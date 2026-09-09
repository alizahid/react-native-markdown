#import "JMDTableView.h"

#import "JMDBlockTextView.h"
#import "JMDBoxViews.h"

/// The unclipped grid inside the scroller: row boxes + cell text.
@interface JMDTableGridView : UIView
- (void)bind:(JMDMeasuredBlock *)measured host:(nullable id<JMDMarkdownHost>)host;
@end

@implementation JMDTableGridView {
  JMDMeasuredBlock *_measured;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

- (void)bind:(JMDMeasuredBlock *)measured host:(nullable id<JMDMarkdownHost>)host {
  _measured = measured;
  // One text view per cell, row-major; grow/shrink then rebind in place.
  NSUInteger needed = 0;
  for (NSArray<NSTextStorage *> *row in measured.cellStorages) {
    needed += row.count;
  }
  while (self.subviews.count > needed) {
    [self.subviews.lastObject removeFromSuperview];
  }
  while (self.subviews.count < needed) {
    [self addSubview:[[JMDBlockTextView alloc] initWithFrame:CGRectZero]];
  }
  NSUInteger index = 0;
  for (NSArray<NSTextStorage *> *row in measured.cellStorages) {
    for (NSTextStorage *cell in row) {
      JMDBlockTextView *view = (JMDBlockTextView *)self.subviews[index++];
      view.host = host;
      [view bindTextStorage:cell];
    }
  }
  [self setNeedsDisplay];
  [self setNeedsLayout];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  // Touches inside the grid belong to the horizontal scroller.
  UIView *hit = [super hitTest:point withEvent:event];
  return hit == self ? nil : hit;
}

- (void)drawRect:(CGRect)rect {
  JMDBlock *block = _measured.block;
  CGContextRef context = UIGraphicsGetCurrentContext();
  const CGFloat width = _measured.contentWidth;

  CGFloat y = 0;
  NSUInteger rowIndex = 0;
  for (NSNumber *rowHeight in _measured.rowHeights) {
    const BOOL isHeader =
        rowIndex < block.tableRows.count && block.tableRows[rowIndex].isHeader;
    JMDLayoutStyle *rowStyle = isHeader ? block.headerRowStyle : block.bodyRowStyle;
    rowIndex++;
    if (rowStyle.backgroundColor != nil) {
      CGContextSetFillColorWithColor(context, rowStyle.backgroundColor.CGColor);
      CGContextFillRect(context, CGRectMake(0, y, width, rowHeight.doubleValue));
    }
    if (rowStyle.borderBottomWidth > 0 && rowStyle.borderBottomColor != nil) {
      CGContextSetFillColorWithColor(context, rowStyle.borderBottomColor.CGColor);
      CGContextFillRect(
          context,
          CGRectMake(
              0,
              y + rowHeight.doubleValue - rowStyle.borderBottomWidth,
              width,
              rowStyle.borderBottomWidth));
    }
    if (rowStyle.borderTopWidth > 0 && rowStyle.borderTopColor != nil) {
      CGContextSetFillColorWithColor(context, rowStyle.borderTopColor.CGColor);
      CGContextFillRect(context, CGRectMake(0, y, width, rowStyle.borderTopWidth));
    }
    y += rowHeight.doubleValue;
  }
}

- (void)layoutSubviews {
  [super layoutSubviews];
  JMDBlock *block = _measured.block;

  NSUInteger index = 0;
  CGFloat y = 0;
  for (NSUInteger rowIndex = 0; rowIndex < block.tableRows.count; rowIndex++) {
    JMDTableRow *row = block.tableRows[rowIndex];
    JMDLayoutStyle *rowStyle = row.isHeader ? block.headerRowStyle : block.bodyRowStyle;
    const UIEdgeInsets pad = row.isHeader ? block.headerCellPadding : block.cellPadding;
    const CGFloat cellPadH = pad.left + pad.right;
    CGFloat x = 0;
    for (NSUInteger column = 0; column < row.cells.count; column++) {
      if (index >= self.subviews.count) {
        break;
      }
      const CGFloat columnWidth = _measured.columnWidths[column].doubleValue;
      const CGFloat cellHeight = _measured.rowHeights[rowIndex].doubleValue -
          pad.top - pad.bottom -
          rowStyle.borderTopWidth - rowStyle.borderBottomWidth;
      self.subviews[index].frame = CGRectMake(
          x + pad.left,
          y + pad.top + rowStyle.borderTopWidth,
          MAX(columnWidth - cellPadH, 1),
          MAX(cellHeight, 0));
      index++;
      x += columnWidth;
    }
    y += _measured.rowHeights[rowIndex].doubleValue;
  }
}

@end

@implementation JMDTableView {
  JMDMeasuredBlock *_measured;
  UIScrollView *_scroller;
  JMDTableGridView *_grid;
}

- (void)bind:(JMDMeasuredBlock *)measured host:(nullable id<JMDMarkdownHost>)host {
  _measured = measured;
  if (_scroller == nil) {
    _scroller = [[JMDNestedScrollView alloc] initWithFrame:CGRectZero];
    _scroller.showsHorizontalScrollIndicator = NO;
    _scroller.showsVerticalScrollIndicator = NO;
    _scroller.alwaysBounceVertical = NO;
    _scroller.delaysContentTouches = NO;
    _scroller.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _grid = [[JMDTableGridView alloc] initWithFrame:CGRectZero];
    [_scroller addSubview:_grid];
    [self addSubview:_scroller];
  }

  JMDLayoutStyle *style = measured.block.layoutStyle;
  self.backgroundColor = style.backgroundColor ?: UIColor.clearColor;
  self.layer.cornerRadius = style.borderRadius;
  self.layer.cornerCurve =
      style.continuousCorners ? kCACornerCurveContinuous : kCACornerCurveCircular;
  self.layer.masksToBounds = style.borderRadius > 0;

  [_grid bind:measured host:host];
  [self setNeedsLayout];
}


// Never the hit view itself: markdown touches belong to the host component
// view; only nested scrollers (code blocks, tables) claim touches.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  return hit == self ? nil : hit;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  JMDLayoutStyle *style = _measured.block.layoutStyle;
  CGFloat gridHeight = 0;
  for (NSNumber *rowHeight in _measured.rowHeights) {
    gridHeight += rowHeight.doubleValue;
  }
  const CGFloat left = style.borderLeftWidth + style.paddingLeft;
  const CGFloat top = style.borderTopWidth + style.paddingTop;
  _scroller.frame = CGRectMake(
      left,
      top,
      self.bounds.size.width - left - style.borderRightWidth - style.paddingRight,
      gridHeight);
  _grid.frame = CGRectMake(0, 0, _measured.contentWidth, gridHeight);
  _scroller.contentSize = CGSizeMake(_measured.contentWidth, gridHeight);
}

@end
