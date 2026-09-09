#import "JMDBlockRenderer.h"

#import <CoreText/CoreText.h>

#import "core/Parser.h"

using jetmarkdown::Node;
using jetmarkdown::NodeType;

NSAttributedStringKey const JMDLinkURLAttributeName = @"JMDLinkURL";
NSAttributedStringKey const JMDRunBackgroundAttributeName = @"JMDRunBackground";
NSAttributedStringKey const JMDSpoilerIDAttributeName = @"JMDSpoilerID";

namespace {

NSString *toNSString(const std::string &value) {
  NSString *result = [[NSString alloc] initWithBytes:value.data()
                                              length:value.size()
                                            encoding:NSUTF8StringEncoding];
  return result != nil ? result : @"";
}

bool isInlineType(NodeType type) {
  switch (type) {
    case NodeType::Text:
    case NodeType::SoftBreak:
    case NodeType::HardBreak:
    case NodeType::Bold:
    case NodeType::Italic:
    case NodeType::Strikethrough:
    case NodeType::Link:
    case NodeType::InlineCode:
    case NodeType::Spoiler:
    case NodeType::Superscript:
    case NodeType::Subscript:
    case NodeType::Image:
      return true;
    default:
      return false;
  }
}

// codeBlock/blockQuote merge text + layout keys in one section; their
// backgroundColor is the box fill, not an inline-run background, so it must
// not reach the text-attribute path.
JMDTextStyle *JMDTextStyleWithoutBackground(JMDStyleConfig *styles, NSString *key) {
  NSDictionary *section = [styles rawSectionFor:key];
  if (section == nil) {
    return nil;
  }
  if (section[@"backgroundColor"] == nil) {
    return [JMDTextStyle fromJson:section];
  }
  NSMutableDictionary *copy = [section mutableCopy];
  [copy removeObjectForKey:@"backgroundColor"];
  return [JMDTextStyle fromJson:copy];
}

// Fully-resolved text attributes at one point of the inline tree walk.
struct ResolvedAttrs {
  CGFloat fontSize = 16;
  CGFloat lineHeight = 0; // 0 = natural
  NSInteger weight = 400;
  bool italic = false;
  NSString *__strong family = nil;
  UIColor *__strong color = nil;
  NSArray<NSString *> *__strong variants = nil;
  bool underline = false;
  bool strikethrough = false;
  UIColor *__strong decorationColor = nil;
  NSString *__strong decorationStyle = nil;
  CGFloat baselineOffset = 0;
  // lineHeight-centering raise, computed ONCE from the block's base font so
  // every run on a line shares the same shift (per-run deltas cancel sub/sup
  // offsets and split mixed-font runs onto different visual baselines).
  CGFloat centeringOffset = 0;
  UIColor *__strong backgroundColor = nil;
  // Chip geometry for drawn run backgrounds (inlineCode/link/mention).
  CGFloat chipRadius = 0;
  bool chipContinuous = false;
  CGFloat chipPadLeft = 0;
  CGFloat chipPadRight = 0;
  // One chip object per link/mention node, shared by its child runs so
  // enumerateAttribute coalesces them into ONE chip — per-run instances
  // fragment a mixed-styling link into seamed per-run rects.
  JMDRunBackground *__strong chipInstance = nil;
  NSString *__strong linkUrl = nil;
  NSInteger spoilerId = -1;
};

void applyStyle(ResolvedAttrs &attrs, JMDTextStyle *style, CGFloat fontScale) {
  if (style == nil) {
    return;
  }
  if (style.fontSize != nil) {
    attrs.fontSize = style.fontSize.doubleValue * fontScale;
  }
  if (style.fontWeight != nil) {
    attrs.weight = style.fontWeight.integerValue;
  }
  if (style.fontFamily != nil) {
    attrs.family = style.fontFamily;
  }
  if (style.lineHeight != nil) {
    attrs.lineHeight = style.lineHeight.doubleValue * fontScale;
  }
  if (style.color != nil) {
    attrs.color = style.color;
  }
  if (style.fontVariant != nil) {
    attrs.variants = style.fontVariant;
  }
  if (style.textDecorationColor != nil) {
    attrs.decorationColor = style.textDecorationColor;
  }
  if (style.textDecorationStyle != nil) {
    attrs.decorationStyle = style.textDecorationStyle;
  }
  if (style.textDecorationLine != nil) {
    attrs.underline = [style.textDecorationLine containsString:@"underline"];
    attrs.strikethrough = [style.textDecorationLine containsString:@"line-through"];
  }
  if (style.backgroundColor != nil) {
    attrs.backgroundColor = style.backgroundColor;
  }
}

void applyChipStyle(ResolvedAttrs &attrs, NSDictionary *section) {
  if (section == nil) {
    return;
  }
  if ([section[@"borderRadius"] isKindOfClass:[NSNumber class]]) {
    attrs.chipRadius = [section[@"borderRadius"] doubleValue];
  }
  attrs.chipContinuous = [section[@"borderCurve"] isEqual:@"continuous"];
  if ([section[@"paddingLeft"] isKindOfClass:[NSNumber class]]) {
    attrs.chipPadLeft = [section[@"paddingLeft"] doubleValue];
  }
  if ([section[@"paddingRight"] isKindOfClass:[NSNumber class]]) {
    attrs.chipPadRight = [section[@"paddingRight"] doubleValue];
  }
}

UIFontWeight uiWeight(NSInteger weight) {
  switch (weight) {
    case 100: return UIFontWeightUltraLight;
    case 200: return UIFontWeightThin;
    case 300: return UIFontWeightLight;
    case 400: return UIFontWeightRegular;
    case 500: return UIFontWeightMedium;
    case 600: return UIFontWeightSemibold;
    case 700: return UIFontWeightBold;
    case 800: return UIFontWeightHeavy;
    default: return weight >= 900 ? UIFontWeightBlack : UIFontWeightRegular;
  }
}

NSArray<NSDictionary *> *featureSettings(NSArray<NSString *> *variants) {
  NSMutableArray *features = [NSMutableArray new];
  for (NSString *variant in variants) {
    int type = -1;
    int selector = -1;
    if ([variant isEqualToString:@"tabular-nums"]) {
      type = kNumberSpacingType;
      selector = kMonospacedNumbersSelector;
    } else if ([variant isEqualToString:@"proportional-nums"]) {
      type = kNumberSpacingType;
      selector = kProportionalNumbersSelector;
    } else if ([variant isEqualToString:@"oldstyle-nums"]) {
      type = kNumberCaseType;
      selector = kLowerCaseNumbersSelector;
    } else if ([variant isEqualToString:@"lining-nums"]) {
      type = kNumberCaseType;
      selector = kUpperCaseNumbersSelector;
    } else if ([variant isEqualToString:@"small-caps"]) {
      type = kLowerCaseType;
      selector = kLowerCaseSmallCapsSelector;
    }
    if (type >= 0) {
      [features addObject:@{
        UIFontFeatureTypeIdentifierKey : @(type),
        UIFontFeatureSelectorIdentifierKey : @(selector),
      }];
    }
  }
  return features;
}

UIFont *buildFontUncached(const ResolvedAttrs &attrs) {
  UIFont *base;
  if (attrs.family.length > 0) {
    UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
      UIFontDescriptorFamilyAttribute : attrs.family,
      UIFontDescriptorTraitsAttribute : @{
        UIFontWeightTrait : @((uiWeight(attrs.weight) - UIFontWeightRegular)),
      },
    }];
    base = [UIFont fontWithDescriptor:descriptor size:attrs.fontSize];
    if (base == nil) {
      base = [UIFont systemFontOfSize:attrs.fontSize weight:uiWeight(attrs.weight)];
    }
  } else {
    base = [UIFont systemFontOfSize:attrs.fontSize weight:uiWeight(attrs.weight)];
  }

  UIFontDescriptorSymbolicTraits traits = base.fontDescriptor.symbolicTraits;
  if (attrs.italic) {
    traits |= UIFontDescriptorTraitItalic;
  }

  NSMutableDictionary *descriptorAttributes = [NSMutableDictionary new];
  NSArray *features = attrs.variants != nil ? featureSettings(attrs.variants) : @[];
  if (features.count > 0) {
    descriptorAttributes[UIFontDescriptorFeatureSettingsAttribute] = features;
  }

  UIFontDescriptor *descriptor = base.fontDescriptor;
  if (descriptorAttributes.count > 0) {
    descriptor = [descriptor fontDescriptorByAddingAttributes:descriptorAttributes];
  }
  if (attrs.italic) {
    UIFontDescriptor *italicDescriptor = [descriptor fontDescriptorWithSymbolicTraits:traits];
    if (italicDescriptor != nil) {
      descriptor = italicDescriptor;
    }
  }
  UIFont *font = [UIFont fontWithDescriptor:descriptor size:attrs.fontSize];
  return font ?: base;
}

// Descriptor matching (family + weight trait, especially for custom
// families) costs real time and runs once per text run otherwise. UIFont is
// immutable, NSCache is thread-safe: the layout thread and main thread share
// one cache.
UIFont *buildFont(const ResolvedAttrs &attrs) {
  static NSCache<NSString *, UIFont *> *cache;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [NSCache new];
    cache.countLimit = 256;
  });
  NSString *key = [NSString stringWithFormat:@"%@\x1f%.2f\x1f%ld\x1f%d\x1f%@",
                                             attrs.family ?: @"",
                                             attrs.fontSize,
                                             (long)attrs.weight,
                                             attrs.italic ? 1 : 0,
                                             [attrs.variants componentsJoinedByString:@","] ?: @""];
  UIFont *cached = [cache objectForKey:key];
  if (cached != nil) {
    return cached;
  }
  UIFont *font = buildFontUncached(attrs);
  [cache setObject:font forKey:key];
  return font;
}

NSUnderlineStyle decorationMask(NSString *style) {
  if ([style isEqualToString:@"double"]) {
    return NSUnderlineStyleDouble;
  }
  if ([style isEqualToString:@"dotted"]) {
    return NSUnderlineStyleSingle | NSUnderlineStylePatternDot;
  }
  if ([style isEqualToString:@"dashed"]) {
    return NSUnderlineStyleSingle | NSUnderlineStylePatternDash;
  }
  return NSUnderlineStyleSingle;
}

// RN semantics: the line box is exactly lineHeight tall and glyphs center
// vertically inside it. The raise derives from the BLOCK's base font; call
// once wherever block-level attrs are finalized.
void applyCenteringOffset(ResolvedAttrs &attrs) {
  attrs.centeringOffset = 0;
  if (attrs.lineHeight <= 0) {
    return;
  }
  UIFont *font = buildFont(attrs);
  const CGFloat delta = attrs.lineHeight - font.lineHeight;
  if (delta > 0) {
    attrs.centeringOffset = delta / 2;
  }
}

NSDictionary *attributesDictionary(const ResolvedAttrs &attrs) {
  NSMutableDictionary *attributes = [NSMutableDictionary new];
  UIFont *font = buildFont(attrs);
  attributes[NSFontAttributeName] = font;
  attributes[NSForegroundColorAttributeName] = attrs.color ?: UIColor.blackColor;
  CGFloat baselineOffset = attrs.baselineOffset + attrs.centeringOffset;
  if (attrs.lineHeight > 0) {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.minimumLineHeight = attrs.lineHeight;
    paragraph.maximumLineHeight = attrs.lineHeight;
    attributes[NSParagraphStyleAttributeName] = paragraph;
  }
  if (attrs.underline) {
    attributes[NSUnderlineStyleAttributeName] = @(decorationMask(attrs.decorationStyle));
    if (attrs.decorationColor != nil) {
      attributes[NSUnderlineColorAttributeName] = attrs.decorationColor;
    }
  }
  if (attrs.strikethrough) {
    attributes[NSStrikethroughStyleAttributeName] = @(decorationMask(attrs.decorationStyle));
    if (attrs.decorationColor != nil) {
      attributes[NSStrikethroughColorAttributeName] = attrs.decorationColor;
    }
  }
  if (baselineOffset != 0) {
    attributes[NSBaselineOffsetAttributeName] = @(baselineOffset);
  }
  if (attrs.chipInstance != nil) {
    attributes[JMDRunBackgroundAttributeName] = attrs.chipInstance;
  } else if (attrs.backgroundColor != nil) {
    JMDRunBackground *chip = [JMDRunBackground new];
    chip.color = attrs.backgroundColor;
    chip.radius = attrs.chipRadius;
    chip.continuousCurve = attrs.chipContinuous;
    chip.padLeft = attrs.chipPadLeft;
    chip.padRight = attrs.chipPadRight;
    attributes[JMDRunBackgroundAttributeName] = chip;
  }
  if (attrs.linkUrl != nil) {
    attributes[JMDLinkURLAttributeName] = attrs.linkUrl;
  }
  if (attrs.spoilerId >= 0) {
    attributes[JMDSpoilerIDAttributeName] = @(attrs.spoilerId);
  }
  return attributes;
}

class BlockBuilder {
 public:
  BlockBuilder(JMDStyleConfig *styles, CGFloat fontScale)
      : styles_(styles), fontScale_(fontScale) {}

  NSArray<JMDBlock *> *renderBlocks(
      const std::vector<Node *> &children,
      NSArray<JMDTextStyle *> *inherited) {
    NSMutableArray<JMDBlock *> *out = [NSMutableArray new];
    std::vector<const Node *> inlineRun;

    auto flushInline = [&]() {
      if (!inlineRun.empty()) {
        Node synthetic;
        synthetic.type = NodeType::Paragraph;
        for (const Node *node : inlineRun) {
          synthetic.children.push_back(const_cast<Node *>(node));
        }
        [out addObject:textBlock(&synthetic, inherited)];
        inlineRun.clear();
      }
    };

    for (const Node *child : children) {
      if (isInlineType(child->type)) {
        inlineRun.push_back(child);
      } else {
        flushInline();
        renderBlock(child, inherited, out);
      }
    }
    flushInline();
    return out;
  }

  // -- block level ---------------------------------------------------------

  void renderBlock(
      const Node *node,
      NSArray<JMDTextStyle *> *inherited,
      NSMutableArray<JMDBlock *> *out) {
    switch (node->type) {
      case NodeType::Paragraph:
      case NodeType::Heading: {
        const Node *image = singleImageChild(node);
        if (image != nullptr) {
          [out addObject:imageBlock(image)];
        } else {
          [out addObject:textBlock(node, inherited)];
        }
        break;
      }

      case NodeType::BlockQuote: {
        JMDLayoutStyle *defaults = [JMDLayoutStyle
            defaultsWithBackground:nil
                           padding:UIEdgeInsetsZero
                      borderRadius:0
                   borderLeftColor:nil
                   borderLeftWidth:0];
        JMDLayoutStyle *layout =
            [JMDLayoutStyle fromJson:[styles_ rawSectionFor:@"blockQuote"] defaults:defaults];
        NSArray<JMDTextStyle *> *quoteInherited =
            appendStyle(inherited, JMDTextStyleWithoutBackground(styles_, @"blockQuote"));
        JMDBlock *block = [JMDBlock new];
        block.kind = JMDBlockKindQuote;
        block.layoutStyle = layout;
        block.children = renderBlocks(node->children, quoteInherited);
        [out addObject:block];
        break;
      }

      case NodeType::CodeBlock: {
        JMDLayoutStyle *defaults = [JMDLayoutStyle
            defaultsWithBackground:nil
                           padding:UIEdgeInsetsZero
                      borderRadius:0
                   borderLeftColor:nil
                   borderLeftWidth:0];
        JMDLayoutStyle *layout =
            [JMDLayoutStyle fromJson:[styles_ rawSectionFor:@"codeBlock"] defaults:defaults];

        ResolvedAttrs attrs;
        attrs.fontSize = 16 * fontScale_;
        // Base cascades into code; the monospace family is semantic and
        // only styles.codeBlock overrides it.
        applyStyle(attrs, [styles_ textStyleFor:@"base"], fontScale_);
        attrs.family = @"Menlo";
        if (attrs.color == nil) {
          attrs.color = UIColor.blackColor;
        }
        for (JMDTextStyle *style in inherited) {
          applyStyle(attrs, style, fontScale_);
        }
        applyStyle(attrs, JMDTextStyleWithoutBackground(styles_, @"codeBlock"), fontScale_);
        applyCenteringOffset(attrs);

        std::string text = node->text;
        while (!text.empty() && text.back() == '\n') {
          text.pop_back();
        }
        JMDBlock *block = [JMDBlock new];
        block.kind = JMDBlockKindCode;
        block.layoutStyle = layout;
        block.attributedText =
            [[NSAttributedString alloc] initWithString:toNSString(text)
                                            attributes:attributesDictionary(attrs)];
        [out addObject:block];
        break;
      }

      case NodeType::List:
        [out addObject:listBlock(node, inherited)];
        break;

      case NodeType::Table:
        [out addObject:tableBlock(node, inherited)];
        break;

      case NodeType::ThematicBreak: {
        NSDictionary *section = [styles_ rawSectionFor:@"divider"];
        NSNumber *height = [section[@"height"] isKindOfClass:[NSNumber class]]
            ? section[@"height"]
            : @1;
        JMDBlock *block = [JMDBlock new];
        block.kind = JMDBlockKindDivider;
        // Neutral functional floor — a divider is content, so it stays
        // visible even unstyled; defaultStyles provides the subtle hairline.
        block.dividerColor = [JMDTextStyle colorFromJson:section[@"color"]]
            ?: UIColor.blackColor;
        block.dividerThickness = height.doubleValue;
        [out addObject:block];
        break;
      }

      default: {
        if (!node->children.empty()) {
          [out addObjectsFromArray:renderBlocks(node->children, inherited)];
        } else if (!node->text.empty()) {
          Node text;
          text.type = NodeType::Text;
          text.text = node->text;
          Node wrapper;
          wrapper.type = NodeType::Paragraph;
          wrapper.children.push_back(&text);
          [out addObject:textBlock(&wrapper, inherited)];
        }
        break;
      }
    }
  }

  // A paragraph whose only meaningful child is one image renders as an
  // image block (markdown images are inline; block display matches usage).
  static const Node *singleImageChild(const Node *node) {
    if (node->type != NodeType::Paragraph) {
      return nullptr;
    }
    const Node *image = nullptr;
    for (const Node *child : node->children) {
      switch (child->type) {
        case NodeType::Image:
          if (image != nullptr) {
            return nullptr;
          }
          image = child;
          break;
        case NodeType::Text: {
          for (char c : child->text) {
            if (c != ' ' && c != '\t') {
              return nullptr;
            }
          }
          break;
        }
        case NodeType::SoftBreak:
        case NodeType::HardBreak:
          break;
        default:
          return nullptr;
      }
    }
    return image;
  }

  JMDBlock *imageBlock(const Node *node) {
    NSDictionary *section = [styles_ rawSectionFor:@"image"];
    auto number = [](NSDictionary *dict, NSString *key, CGFloat fallback) -> CGFloat {
      NSNumber *value = [dict[key] isKindOfClass:[NSNumber class]] ? dict[key] : nil;
      return value != nil ? value.doubleValue : fallback;
    };
    JMDBlock *block = [JMDBlock new];
    block.kind = JMDBlockKindImage;
    block.imageUrl = toNSString(node->url);
    block.imageBackground = [JMDTextStyle colorFromJson:section[@"backgroundColor"]];
    block.imageBorderRadius = number(section, @"borderRadius", 0);
    block.imageHeight = number(section, @"height", 0);
    block.imageMaxHeight = number(section, @"maxHeight", 0);
    block.imagePlaceholder = 200;
    return block;
  }

  JMDBlock *listBlock(const Node *node, NSArray<JMDTextStyle *> *inherited) {
    NSDictionary *listSection = [styles_ rawSectionFor:@"list"];
    NSDictionary *markerSection = [styles_ rawSectionFor:@"listMarker"];

    auto number = [](NSDictionary *dict, NSString *key, CGFloat fallback) -> CGFloat {
      NSNumber *value = [dict[key] isKindOfClass:[NSNumber class]] ? dict[key] : nil;
      return value != nil ? value.doubleValue : fallback;
    };

    JMDBlock *block = [JMDBlock new];
    block.kind = JMDBlockKindList;
    block.listMarginLeft = number(listSection, @"marginLeft", 0);
    block.markerMarginLeft = number(markerSection, @"marginLeft", 0);

    NSArray<JMDTextStyle *> *itemInherited =
        appendStyle(inherited, [styles_ textStyleFor:@"listItem"]);

    ResolvedAttrs markerAttrs;
    markerAttrs.fontSize = 16 * fontScale_;
    markerAttrs.color = UIColor.blackColor;
    applyStyle(markerAttrs, [styles_ textStyleFor:@"base"], fontScale_);
    applyStyle(markerAttrs, [styles_ textStyleFor:@"paragraph"], fontScale_);
    for (JMDTextStyle *style in itemInherited) {
      applyStyle(markerAttrs, style, fontScale_);
    }
    UIColor *markerColor = [JMDTextStyle colorFromJson:markerSection[@"color"]];
    if (markerColor != nil) {
      markerAttrs.color = markerColor;
    }
    applyCenteringOffset(markerAttrs);

    NSMutableArray<JMDListRow *> *rows = [NSMutableArray new];
    int index = node->startIndex;
    CGFloat naturalMarkerWidth = 0;
    for (const Node *item : node->children) {
      if (item->type != NodeType::ListItem) {
        continue;
      }
      NSString *markerText =
          node->ordered ? [NSString stringWithFormat:@"%d.", index] : @"•";
      JMDListRow *row = [JMDListRow new];
      row.marker = [[NSAttributedString alloc] initWithString:markerText
                                                    attributes:attributesDictionary(markerAttrs)];
      naturalMarkerWidth = MAX(naturalMarkerWidth, ceil(row.marker.size.width));
      row.content = renderBlocks(item->children, itemInherited);
      [rows addObject:row];
      index++;
    }
    // Unstyled marker column is content-driven (widest marker); defaultStyles
    // provides the classic fixed width.
    const CGFloat styledWidth = number(markerSection, @"width", -1);
    block.markerWidth = styledWidth >= 0 ? styledWidth : naturalMarkerWidth;
    block.rows = rows;
    return block;
  }

  JMDBlock *tableBlock(const Node *node, NSArray<JMDTextStyle *> *inherited) {
    NSDictionary *tableSection = [styles_ rawSectionFor:@"table"];
    NSDictionary *cellSection = [styles_ rawSectionFor:@"tableCell"];
    auto number = [](NSDictionary *dict, NSString *key, CGFloat fallback) -> CGFloat {
      NSNumber *value = [dict[key] isKindOfClass:[NSNumber class]] ? dict[key] : nil;
      return value != nil ? value.doubleValue : fallback;
    };

    JMDLayoutStyle *rowDefaults = [JMDLayoutStyle
        defaultsWithBackground:nil
                       padding:UIEdgeInsetsZero
                  borderRadius:0
               borderLeftColor:nil
               borderLeftWidth:0];
    JMDLayoutStyle *rowBase =
        [JMDLayoutStyle fromJson:[styles_ rawSectionFor:@"tableRow"] defaults:rowDefaults];
    JMDLayoutStyle *headerRowStyle =
        [JMDLayoutStyle fromJson:[styles_ rawSectionFor:@"tableHeaderRow"] defaults:rowBase];
    JMDLayoutStyle *bodyRowStyle =
        [JMDLayoutStyle fromJson:[styles_ rawSectionFor:@"tableBodyRow"] defaults:rowBase];

    ResolvedAttrs cellAttrs;
    cellAttrs.fontSize = 16 * fontScale_;
    cellAttrs.color = UIColor.blackColor;
    applyStyle(cellAttrs, [styles_ textStyleFor:@"base"], fontScale_);
    applyStyle(cellAttrs, [styles_ textStyleFor:@"paragraph"], fontScale_);
    for (JMDTextStyle *style in inherited) {
      applyStyle(cellAttrs, style, fontScale_);
    }
    applyStyle(cellAttrs, [styles_ textStyleFor:@"tableCell"], fontScale_);

    NSMutableArray<JMDTableRow *> *rows = [NSMutableArray new];
    for (const Node *rowNode : node->children) {
      if (rowNode->type != NodeType::TableRow) {
        continue;
      }
      JMDTableRow *row = [JMDTableRow new];
      row.isHeader = rowNode->level == 1;
      NSMutableArray<NSAttributedString *> *cells = [NSMutableArray new];
      for (const Node *cellNode : rowNode->children) {
        if (cellNode->type != NodeType::TableCell) {
          continue;
        }
        ResolvedAttrs attrs = cellAttrs;
        if (row.isHeader) {
          attrs.weight = 700;
          applyStyle(attrs, [styles_ textStyleFor:@"tableCell"], fontScale_);
          applyStyle(attrs, [styles_ textStyleFor:@"tableHeaderCell"], fontScale_);
        }
        applyCenteringOffset(attrs);
        NSMutableAttributedString *cell = [NSMutableAttributedString new];
        walk(cell, cellNode, attrs);
        [cells addObject:cell];
      }
      row.cells = cells;
      [rows addObject:row];
    }

    JMDBlock *block = [JMDBlock new];
    block.kind = JMDBlockKindTable;
    block.tableRows = rows;
    block.layoutStyle = [JMDLayoutStyle fromJson:tableSection defaults:nil];
    block.headerRowStyle = headerRowStyle;
    block.bodyRowStyle = bodyRowStyle;
    block.cellPadding = UIEdgeInsetsMake(
        number(cellSection, @"paddingTop", 0),
        number(cellSection, @"paddingLeft", 0),
        number(cellSection, @"paddingBottom", 0),
        number(cellSection, @"paddingRight", 0));
    // Header cells fall back to the body cell padding key-by-key.
    NSDictionary *headerCellSection = [styles_ rawSectionFor:@"tableHeaderCell"];
    const auto headerNumber = [&](NSString *key) {
      NSNumber *value = [headerCellSection[key] isKindOfClass:[NSNumber class]]
          ? headerCellSection[key]
          : nil;
      return value != nil ? value.doubleValue : number(cellSection, key, 0);
    };
    block.headerCellPadding = UIEdgeInsetsMake(
        headerNumber(@"paddingTop"),
        headerNumber(@"paddingLeft"),
        headerNumber(@"paddingBottom"),
        headerNumber(@"paddingRight"));
    // Unstyled columns take their natural widths; defaultStyles provides the
    // classic [44, 320] clamps.
    block.minColumnWidth = number(tableSection, @"minColumnWidth", 0);
    block.maxColumnWidth = number(tableSection, @"maxColumnWidth", 0);
    return block;
  }

  JMDBlock *textBlock(const Node *node, NSArray<JMDTextStyle *> *inherited) {
    NSMutableAttributedString *output = [NSMutableAttributedString new];

    ResolvedAttrs base;
    base.fontSize = 16 * fontScale_;
    base.color = UIColor.blackColor;
    // Unstyled output is fully plain: heading sizes/weights come from the
    // hN sections (defaultStyles on the JS side), not builtins.
    if (node->type == NodeType::Heading) {
      applyStyle(base, [styles_ textStyleFor:@"base"], fontScale_);
      for (JMDTextStyle *style in inherited) {
        applyStyle(base, style, fontScale_);
      }
      // Headings shed the inherited lineHeight like they shed paragraph
      // styles: a body lineHeight would cap the taller heading's line box
      // and clip its ascenders. hN.lineHeight still applies.
      base.lineHeight = 0;
      applyStyle(
          base,
          [styles_ textStyleFor:[NSString stringWithFormat:@"h%d", (int)node->level]],
          fontScale_);
    } else {
      applyStyle(base, [styles_ textStyleFor:@"base"], fontScale_);
      applyStyle(base, [styles_ textStyleFor:@"paragraph"], fontScale_);
      for (JMDTextStyle *style in inherited) {
        applyStyle(base, style, fontScale_);
      }
    }

    applyCenteringOffset(base);
    walk(output, node, base);

    NSDictionary *spoilerSection = [styles_ rawSectionFor:@"spoiler"];
    NSNumber *spoilerRadius =
        [spoilerSection[@"borderRadius"] isKindOfClass:[NSNumber class]]
            ? spoilerSection[@"borderRadius"]
            : @0;

    JMDBlock *block = [JMDBlock new];
    block.kind = JMDBlockKindText;
    block.attributedText = output;
    // Neutral functional floor — the cover must hide text even unstyled;
    // defaultStyles provides the styled cover.
    block.spoilerColor = [JMDTextStyle colorFromJson:spoilerSection[@"backgroundColor"]]
        ?: UIColor.blackColor;
    block.spoilerRadius = spoilerRadius.doubleValue;
    block.spoilerContinuous =
        [spoilerSection[@"borderCurve"] isEqual:@"continuous"];
    return block;
  }

 private:
  static NSArray<JMDTextStyle *> *appendStyle(
      NSArray<JMDTextStyle *> *chain, JMDTextStyle *style) {
    if (style == nil) {
      return chain;
    }
    return [chain arrayByAddingObject:style];
  }

  void append(NSMutableAttributedString *output, NSString *text, const ResolvedAttrs &attrs) {
    if (text.length == 0) {
      return;
    }
    [output appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:text
                                           attributes:attributesDictionary(attrs)]];
  }

  void walk(NSMutableAttributedString *output, const Node *parent, const ResolvedAttrs &attrs) {
    for (const Node *node : parent->children) {
      switch (node->type) {
        case NodeType::Text:
          append(output, toNSString(node->text), attrs);
          break;
        case NodeType::SoftBreak:
          append(output, @" ", attrs);
          break;
        case NodeType::HardBreak:
          append(output, @"\n", attrs);
          break;
        case NodeType::Bold: {
          ResolvedAttrs next = attrs;
          next.weight = 700;
          applyStyle(next, [styles_ textStyleFor:@"bold"], fontScale_);
          walk(output, node, next);
          break;
        }
        case NodeType::Italic: {
          ResolvedAttrs next = attrs;
          next.italic = true;
          applyStyle(next, [styles_ textStyleFor:@"italic"], fontScale_);
          walk(output, node, next);
          break;
        }
        case NodeType::Strikethrough: {
          ResolvedAttrs next = attrs;
          next.strikethrough = true;
          applyStyle(next, [styles_ textStyleFor:@"strikethrough"], fontScale_);
          walk(output, node, next);
          break;
        }
        case NodeType::Link: {
          ResolvedAttrs next = attrs;
          NSString *url = toNSString(node->url);
          next.linkUrl = url;
          JMDTextStyle *variantStyle = nil;
          bool isMention = false;
          for (JMDMentionVariant *variant in styles_.mentionVariants) {
            if ([variant.pattern firstMatchInString:url
                                            options:0
                                              range:NSMakeRange(0, url.length)] != nil) {
              isMention = true;
              variantStyle = variant.style;
              break;
            }
          }
          if (isMention) {
            applyStyle(next, [styles_ textStyleFor:@"mention"], fontScale_);
            applyStyle(next, variantStyle, fontScale_);
            applyChipStyle(next, [styles_ rawSectionFor:@"mention"]);
          } else {
            applyStyle(next, [styles_ textStyleFor:@"link"], fontScale_);
            applyChipStyle(next, [styles_ rawSectionFor:@"link"]);
          }
          if (next.backgroundColor != nil) {
            JMDRunBackground *chip = [JMDRunBackground new];
            chip.color = next.backgroundColor;
            chip.radius = next.chipRadius;
            chip.continuousCurve = next.chipContinuous;
            chip.padLeft = next.chipPadLeft;
            chip.padRight = next.chipPadRight;
            next.chipInstance = chip;
          }
          walk(output, node, next);
          break;
        }
        case NodeType::InlineCode: {
          ResolvedAttrs next = attrs;
          next.family = @"Menlo";
          applyStyle(next, [styles_ textStyleFor:@"inlineCode"], fontScale_);
          applyChipStyle(next, [styles_ rawSectionFor:@"inlineCode"]);
          append(output, toNSString(node->text), next);
          break;
        }
        case NodeType::Superscript: {
          ResolvedAttrs next = attrs;
          next.fontSize = attrs.fontSize * 0.7;
          next.baselineOffset = attrs.fontSize * 0.35;
          applyStyle(next, [styles_ textStyleFor:@"superscript"], fontScale_);
          walk(output, node, next);
          break;
        }
        case NodeType::Subscript: {
          ResolvedAttrs next = attrs;
          next.fontSize = attrs.fontSize * 0.7;
          next.baselineOffset = -attrs.fontSize * 0.18;
          applyStyle(next, [styles_ textStyleFor:@"subscript"], fontScale_);
          walk(output, node, next);
          break;
        }
        case NodeType::Spoiler: {
          ResolvedAttrs next = attrs;
          next.spoilerId = spoilerCounter_++;
          walk(output, node, next);
          break;
        }
        case NodeType::Image:
          append(output, toNSString(node->text), attrs);
          break;
        default:
          walk(output, node, attrs);
          break;
      }
    }
  }

  JMDStyleConfig *styles_;
  CGFloat fontScale_;
  NSInteger spoilerCounter_ = 0;
};

} // namespace

@implementation JMDBlockRenderer

+ (NSArray<JMDBlock *> *)renderMarkdown:(NSString *)markdown
                                 styles:(JMDStyleConfig *)styles
                              fontScale:(CGFloat)fontScale {
  const auto document =
      jetmarkdown::parseMarkdown(std::string([markdown UTF8String] ?: ""));

  BlockBuilder builder(styles, fontScale);
  if (document->root == nullptr) {
    return @[];
  }
  return builder.renderBlocks(document->root->children, @[]);
}

@end
