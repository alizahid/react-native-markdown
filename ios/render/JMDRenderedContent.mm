#import "JMDRenderedContent.h"

#include <vector>

@implementation JMDWidthLayout
@end

@implementation JMDRenderedContent {
  NSArray<JMDBlock *> *_blocks;
  CGFloat _topPadding;
  CGFloat _bottomPadding;
  NSMutableDictionary<NSString *, JMDWidthLayout *> *_layoutCache;
}

- (instancetype)initWithBlocks:(NSArray<JMDBlock *> *)blocks
                           gap:(CGFloat)gap
                    topPadding:(CGFloat)topPadding
                 bottomPadding:(CGFloat)bottomPadding {
  if (self = [super init]) {
    _blocks = [blocks copy];
    _gap = gap;
    _topPadding = topPadding;
    _bottomPadding = bottomPadding;
    _layoutCache = [NSMutableDictionary new];
  }
  return self;
}

+ (CGFloat)stackHeight:(NSArray<JMDMeasuredBlock *> *)children gap:(CGFloat)gap {
  CGFloat height = 0;
  for (NSUInteger i = 0; i < children.count; i++) {
    height += children[i].height;
    if (i + 1 < children.count) {
      height += gap;
    }
  }
  return height;
}

// NSDictionary.hash is just the entry COUNT — size changes that keep the
// count would collide. Key on the sorted contents instead.
+ (NSString *)keyForImageSizes:
    (nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)imageSizes {
  if (imageSizes.count == 0) {
    return @"";
  }
  NSMutableString *out = [NSMutableString string];
  for (NSString *url in
       [imageSizes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSArray<NSNumber *> *size = imageSizes[url];
    [out appendFormat:@"%@\x1e%@x%@\x1f", url, size.firstObject, size.lastObject];
  }
  return out;
}

- (JMDWidthLayout *)layoutForWidth:(CGFloat)width
                        imageSizes:(nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)imageSizes {
  NSString *key = [NSString stringWithFormat:@"%.1f|%@",
                                             width,
                                             [JMDRenderedContent keyForImageSizes:imageSizes]];
  @synchronized(self) {
    JMDWidthLayout *cached = _layoutCache[key];
    if (cached != nil) {
      return cached;
    }
  }

  NSMutableArray<JMDMeasuredBlock *> *measured = [NSMutableArray arrayWithCapacity:_blocks.count];
  for (JMDBlock *block in _blocks) {
    [measured addObject:[self measureBlock:block width:width imageSizes:imageSizes]];
  }

  JMDWidthLayout *layout = [JMDWidthLayout new];
  layout.measured = measured;
  layout.totalHeight =
      [JMDRenderedContent stackHeight:measured gap:_gap] + _topPadding + _bottomPadding;

  @synchronized(self) {
    if (_layoutCache.count > 4) {
      [_layoutCache removeAllObjects];
    }
    _layoutCache[key] = layout;
  }
  return layout;
}

// Lays text out with TextKit, not NSStringDrawing: boundingRect stops at
// the last line's drawn descent, dropping the bottom of the final line box
// under a custom lineHeight. The full box keeps overlays (spoiler covers,
// run background chips) from being clipped at the view's bottom edge and
// matches how RN's <Text> and the Android renderer measure. The returned
// storage owns the layout manager; views draw with the same stack.
- (NSTextStorage *)layoutText:(NSAttributedString *)text width:(CGFloat)width {
  NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:text];
  NSLayoutManager *layoutManager = [NSLayoutManager new];
  NSTextContainer *container = [[NSTextContainer alloc]
      initWithSize:CGSizeMake(MIN(width, (CGFloat)1e6), CGFLOAT_MAX)];
  container.lineFragmentPadding = 0;
  [layoutManager addTextContainer:container];
  [storage addLayoutManager:layoutManager];
  [layoutManager ensureLayoutForTextContainer:container];
  return storage;
}

static CGSize JMDUsedSize(NSTextStorage *storage) {
  NSLayoutManager *layoutManager = storage.layoutManagers.firstObject;
  const CGRect used =
      [layoutManager usedRectForTextContainer:layoutManager.textContainers.firstObject];
  return CGSizeMake(ceil(used.size.width), ceil(used.size.height));
}

- (CGSize)textSize:(NSAttributedString *)text width:(CGFloat)width {
  return JMDUsedSize([self layoutText:text width:width]);
}

- (JMDMeasuredBlock *)measureBlock:(JMDBlock *)block
                             width:(CGFloat)width
                        imageSizes:(nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)imageSizes {
  JMDMeasuredBlock *measured = [JMDMeasuredBlock new];
  measured.block = block;
  measured.contentWidth = width;

  switch (block.kind) {
    case JMDBlockKindText: {
      NSTextStorage *storage = [self layoutText:block.attributedText width:width];
      const CGSize size = JMDUsedSize(storage);
      measured.textStorage = storage;
      measured.height = size.height;
      measured.textHeight = size.height;
      break;
    }
    case JMDBlockKindCode: {
      NSTextStorage *storage = [self layoutText:block.attributedText width:CGFLOAT_MAX];
      const CGSize size = JMDUsedSize(storage);
      measured.textStorage = storage;
      measured.contentWidth = size.width;
      measured.textHeight = size.height;
      measured.height =
          size.height + block.layoutStyle.paddingTop + block.layoutStyle.paddingBottom;
      break;
    }
    case JMDBlockKindQuote: {
      const CGFloat innerWidth = MAX(width - block.layoutStyle.horizontalInset, 1);
      NSMutableArray<JMDMeasuredBlock *> *children =
          [NSMutableArray arrayWithCapacity:block.children.count];
      for (JMDBlock *child in block.children) {
        [children addObject:[self measureBlock:child width:innerWidth imageSizes:imageSizes]];
      }
      measured.children = children;
      measured.height = [JMDRenderedContent stackHeight:children gap:_gap] +
          block.layoutStyle.verticalInset;
      break;
    }
    case JMDBlockKindList: {
      const CGFloat contentX =
          block.listMarginLeft + block.markerMarginLeft + block.markerWidth;
      const CGFloat contentWidth = MAX(width - contentX, 1);
      measured.contentWidth = contentWidth;
      NSMutableArray<NSNumber *> *markerHeights = [NSMutableArray new];
      NSMutableArray<NSTextStorage *> *markerStorages = [NSMutableArray new];
      NSMutableArray<NSArray<JMDMeasuredBlock *> *> *rowContents = [NSMutableArray new];
      CGFloat height = 0;
      for (NSUInteger i = 0; i < block.rows.count; i++) {
        JMDListRow *row = block.rows[i];
        NSTextStorage *markerStorage = [self layoutText:row.marker width:block.markerWidth];
        [markerStorages addObject:markerStorage];
        const CGSize markerSize = JMDUsedSize(markerStorage);
        NSMutableArray<JMDMeasuredBlock *> *content = [NSMutableArray new];
        for (JMDBlock *child in row.content) {
          [content addObject:[self measureBlock:child width:contentWidth imageSizes:imageSizes]];
        }
        [markerHeights addObject:@(markerSize.height)];
        [rowContents addObject:content];
        height += MAX(markerSize.height, [JMDRenderedContent stackHeight:content gap:_gap]);
        if (i + 1 < block.rows.count) {
          height += _gap / 2;
        }
      }
      measured.markerHeights = markerHeights;
      measured.markerStorages = markerStorages;
      measured.rowContents = rowContents;
      measured.height = height;
      break;
    }
    case JMDBlockKindDivider:
      measured.height = block.dividerThickness;
      break;
    case JMDBlockKindTable: {
      // Intelligent column widths: natural (unwrapped) width per column,
      // clamped to [min, max]; surplus distributed proportionally when the
      // table fits, horizontal scroll when it does not.
      NSUInteger columnCount = 0;
      for (JMDTableRow *row in block.tableRows) {
        columnCount = MAX(columnCount, row.cells.count);
      }
      if (columnCount == 0) {
        measured.height = 0;
        break;
      }

      std::vector<CGFloat> natural(columnCount, 0);
      for (JMDTableRow *row in block.tableRows) {
        const UIEdgeInsets pad = row.isHeader ? block.headerCellPadding : block.cellPadding;
        const CGFloat cellPadH = pad.left + pad.right;
        for (NSUInteger column = 0; column < row.cells.count; column++) {
          const CGFloat desired =
              [self textSize:row.cells[column] width:CGFLOAT_MAX].width + cellPadH;
          natural[column] = MAX(natural[column], desired);
        }
      }

      std::vector<CGFloat> columnWidths(columnCount, 0);
      CGFloat total = 0;
      CGFloat naturalTotal = 0;
      const CGFloat maxColumnWidth =
          block.maxColumnWidth > 0 ? block.maxColumnWidth : CGFLOAT_MAX;
      for (NSUInteger i = 0; i < columnCount; i++) {
        columnWidths[i] = MIN(MAX(natural[i], block.minColumnWidth), maxColumnWidth);
        total += columnWidths[i];
        naturalTotal += natural[i];
      }
      const CGFloat availableWidth = width - block.layoutStyle.horizontalInset;
      if (total < availableWidth && naturalTotal > 0) {
        const CGFloat surplus = availableWidth - total;
        for (NSUInteger i = 0; i < columnCount; i++) {
          columnWidths[i] += surplus * (natural[i] / naturalTotal);
        }
      }

      NSMutableArray<NSNumber *> *rowHeights = [NSMutableArray new];
      NSMutableArray<NSArray<NSTextStorage *> *> *cellStorages = [NSMutableArray new];
      CGFloat contentHeight = 0;
      for (JMDTableRow *row in block.tableRows) {
        JMDLayoutStyle *rowStyle = row.isHeader ? block.headerRowStyle : block.bodyRowStyle;
        const UIEdgeInsets pad = row.isHeader ? block.headerCellPadding : block.cellPadding;
        const CGFloat cellPadH = pad.left + pad.right;
        const CGFloat cellPadV = pad.top + pad.bottom;
        const CGFloat rowExtra = rowStyle.borderTopWidth + rowStyle.borderBottomWidth;
        CGFloat rowHeight = 0;
        NSMutableArray<NSTextStorage *> *rowStorages = [NSMutableArray new];
        for (NSUInteger column = 0; column < row.cells.count; column++) {
          const CGFloat cellWidth = MAX(columnWidths[column] - cellPadH, 1);
          NSTextStorage *storage = [self layoutText:row.cells[column] width:cellWidth];
          [rowStorages addObject:storage];
          rowHeight = MAX(rowHeight, JMDUsedSize(storage).height);
        }
        [cellStorages addObject:rowStorages];
        rowHeight += cellPadV + rowExtra;
        [rowHeights addObject:@(rowHeight)];
        contentHeight += rowHeight;
      }

      NSMutableArray<NSNumber *> *widths = [NSMutableArray new];
      CGFloat contentWidth = 0;
      for (NSUInteger i = 0; i < columnCount; i++) {
        [widths addObject:@(columnWidths[i])];
        contentWidth += columnWidths[i];
      }

      measured.columnWidths = widths;
      measured.rowHeights = rowHeights;
      measured.cellStorages = cellStorages;
      measured.contentWidth = contentWidth;
      measured.height = contentHeight + block.layoutStyle.verticalInset;
      break;
    }
    case JMDBlockKindImage: {
      NSArray<NSNumber *> *known = block.imageUrl != nil ? imageSizes[block.imageUrl] : nil;
      CGFloat displayH;
      CGFloat displayW;
      if (known.count == 2 && known[0].doubleValue > 0 && known[1].doubleValue > 0) {
        const CGFloat intrinsicW = known[0].doubleValue;
        const CGFloat intrinsicH = known[1].doubleValue;
        const CGFloat scale = MIN(width / intrinsicW, 1.0);
        displayH = intrinsicH * scale;
        if (block.imageHeight > 0) {
          displayH = block.imageHeight;
        }
        if (block.imageMaxHeight > 0) {
          displayH = MIN(displayH, block.imageMaxHeight);
        }
        displayW = MIN(intrinsicW * displayH / intrinsicH, width);
      } else {
        // Full-width placeholder until the intrinsic size is known.
        displayH = block.imageHeight > 0 ? block.imageHeight : block.imagePlaceholder;
        if (block.imageMaxHeight > 0) {
          displayH = MIN(displayH, block.imageMaxHeight);
        }
        displayW = width;
      }
      measured.height = displayH;
      measured.contentWidth = displayW;
      break;
    }
  }
  return measured;
}

@end
