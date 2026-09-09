#import <UIKit/UIKit.h>

#import "../render/JMDBlock.h"
#import "JMDMarkdownHost.h"

NS_ASSUME_NONNULL_BEGIN

/// Draws one block's attributed string (TextKit) plus spoiler covers, and
/// hit-tests links, mentions, and spoilers by character range.
@interface JMDBlockTextView : UIView

/// The bound storage's contents (nil before bind).
@property (nonatomic, readonly, nullable) NSAttributedString *attributedText;
@property (nonatomic, weak, nullable) id<JMDMarkdownHost> host;
@property (nonatomic, strong, nullable) UIColor *spoilerColor;
@property (nonatomic, assign) CGFloat spoilerRadius;
@property (nonatomic, assign) BOOL spoilerContinuous;

/// Binds a measure-time TextKit stack (see JMDMeasuredBlock); the view
/// draws with it and never lays text out itself.
- (void)bindTextStorage:(NSTextStorage *)storage;

/// Attributed-string attributes at a point in this view's coordinates;
/// nil when the point is not on a glyph. Used by the host for hit testing.
- (nullable NSDictionary *)attributesAtPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
