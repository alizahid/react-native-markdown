#import <UIKit/UIKit.h>

#import "../style/JMDLayoutStyle.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, JMDBlockKind) {
  JMDBlockKindText,
  JMDBlockKindCode,
  JMDBlockKindQuote,
  JMDBlockKindList,
  JMDBlockKindDivider,
  JMDBlockKindImage,
  JMDBlockKindTable,
};

@class JMDBlock;

/// Custom attributed-string keys carrying interaction data.
FOUNDATION_EXPORT NSAttributedStringKey const JMDLinkURLAttributeName;
FOUNDATION_EXPORT NSAttributedStringKey const JMDSpoilerIDAttributeName;
/// Drawn run background ("chip"): value is an JMDRunBackground. Replaces
/// NSBackgroundColor, whose rect misaligns under custom line heights.
FOUNDATION_EXPORT NSAttributedStringKey const JMDRunBackgroundAttributeName;

/// Geometry + fill for a drawn run background.
@interface JMDRunBackground : NSObject
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) BOOL continuousCurve;
@property (nonatomic, assign) CGFloat padLeft;
@property (nonatomic, assign) CGFloat padRight;
@end

@interface JMDListRow : NSObject
@property (nonatomic, strong) NSAttributedString *marker;
@property (nonatomic, strong) NSArray<JMDBlock *> *content;
@end

@interface JMDTableRow : NSObject
@property (nonatomic, assign) BOOL isHeader;
@property (nonatomic, strong) NSArray<NSAttributedString *> *cells;
@end

/// One renderable block; blocks nest (quote children, list row content).
@interface JMDBlock : NSObject
@property (nonatomic, assign) JMDBlockKind kind;
@property (nonatomic, strong, nullable) NSAttributedString *attributedText;
// Text blocks: spoiler cover styling.
@property (nonatomic, strong, nullable) UIColor *spoilerColor;
@property (nonatomic, assign) CGFloat spoilerRadius;
@property (nonatomic, assign) BOOL spoilerContinuous;
@property (nonatomic, strong, nullable) JMDLayoutStyle *layoutStyle;
@property (nonatomic, strong, nullable) NSArray<JMDBlock *> *children;
@property (nonatomic, strong, nullable) NSArray<JMDListRow *> *rows;
@property (nonatomic, assign) CGFloat listMarginLeft;
@property (nonatomic, assign) CGFloat markerWidth;
@property (nonatomic, assign) CGFloat markerMarginLeft;
@property (nonatomic, strong, nullable) UIColor *dividerColor;
@property (nonatomic, assign) CGFloat dividerThickness;

// Table blocks. Header/body row styles layer tableHeaderRow/tableBodyRow
// over the shared tableRow base; header cells fall back to the body cell
// padding key-by-key.
@property (nonatomic, strong, nullable) NSArray<JMDTableRow *> *tableRows;
@property (nonatomic, strong, nullable) JMDLayoutStyle *headerRowStyle;
@property (nonatomic, strong, nullable) JMDLayoutStyle *bodyRowStyle;
@property (nonatomic, assign) UIEdgeInsets cellPadding;
@property (nonatomic, assign) UIEdgeInsets headerCellPadding;
@property (nonatomic, assign) CGFloat minColumnWidth;
@property (nonatomic, assign) CGFloat maxColumnWidth;

// Image blocks.
@property (nonatomic, copy, nullable) NSString *imageUrl;
@property (nonatomic, strong, nullable) UIColor *imageBackground;
@property (nonatomic, assign) CGFloat imageBorderRadius;
@property (nonatomic, assign) CGFloat imageHeight;
@property (nonatomic, assign) CGFloat imageMaxHeight;
@property (nonatomic, assign) CGFloat imagePlaceholder;
@end

/// Layout results for one block at one width.
@interface JMDMeasuredBlock : NSObject
@property (nonatomic, strong) JMDBlock *block;
@property (nonatomic, assign) CGFloat height;
/// Code: unwrapped content width for the scroller; Text: wrapped text height.
@property (nonatomic, assign) CGFloat contentWidth;
@property (nonatomic, assign) CGFloat textHeight;
@property (nonatomic, strong) NSArray<JMDMeasuredBlock *> *children;
@property (nonatomic, strong) NSArray<NSNumber *> *markerHeights;
@property (nonatomic, strong) NSArray<NSArray<JMDMeasuredBlock *> *> *rowContents;
/// Tables: resolved column widths and per-row heights.
@property (nonatomic, strong) NSArray<NSNumber *> *columnWidths;
@property (nonatomic, strong) NSArray<NSNumber *> *rowHeights;
/// TextKit stacks built at measure time (storage owns the layout manager
/// and container); the views draw with these, so measure and draw never
/// disagree and text is laid out once. Text/Code: textStorage. Lists:
/// one per row. Tables: row-major cells.
@property (nonatomic, strong, nullable) NSTextStorage *textStorage;
@property (nonatomic, strong) NSArray<NSTextStorage *> *markerStorages;
@property (nonatomic, strong) NSArray<NSArray<NSTextStorage *> *> *cellStorages;
@end

NS_ASSUME_NONNULL_END
