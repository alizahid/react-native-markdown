#import "JMDBoxViews.h"

#import "../render/JMDRenderedContent.h"
#import "JMDBlockStackView.h"
#import "JMDBlockTextView.h"

@implementation JMDNestedScrollView {
  __weak UIControl *_trackingControl;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.delegate = self;
  }
  return self;
}

// As the hit view this scroller consumes the raw touch stream, which starves
// UIControl-based wrappers: react-native-gesture-handler's button fires
// presses from UIControl events, and a control refuses to track touches
// hit-tested to another view. Synthesize the control events instead — press
// down on touch start, press on a clean touch up, cancel when the pan takes
// the touches — so a tap on a code block or table still presses the
// wrapping card while drags scroll without pressing.
- (nullable UIControl *)jmdAncestorControl {
  UIView *view = self.superview;
  while (view != nil) {
    if ([view isKindOfClass:[UIControl class]]) {
      return (UIControl *)view;
    }
    view = view.superview;
  }
  return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesBegan:touches withEvent:event];
  _trackingControl = [self jmdAncestorControl];
  [_trackingControl sendActionsForControlEvents:UIControlEventTouchDown];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesEnded:touches withEvent:event];
  [_trackingControl sendActionsForControlEvents:UIControlEventTouchUpInside];
  _trackingControl = nil;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  [super touchesCancelled:touches withEvent:event];
  [_trackingControl sendActionsForControlEvents:UIControlEventTouchCancel];
  _trackingControl = nil;
}

// This scroller is not a React view, so nothing cancels the JS responder
// (an RN Pressable wrapping the markdown view) when a drag starts here —
// React only cancels for its own scroll views. Kill the surface touch
// handler's active touches the way RCTTouchHandler itself cancels: an
// enabled toggle.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
  UIView *view = self.superview;
  while (view != nil) {
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
      if ([NSStringFromClass(recognizer.class) containsString:@"TouchHandler"]) {
        recognizer.enabled = NO;
        recognizer.enabled = YES;
        return;
      }
    }
    view = view.superview;
  }
}

@end

// Shared background + border painting on a host view's layer tree.
static void JMDApplyBox(UIView *view, JMDLayoutStyle *style) {
  view.backgroundColor = style.backgroundColor ?: UIColor.clearColor;
  view.layer.cornerRadius = style.borderRadius;
  view.layer.cornerCurve =
      style.continuousCorners ? kCACornerCurveContinuous : kCACornerCurveCircular;
  view.layer.masksToBounds = style.borderRadius > 0;
}

@interface JMDBorderView : UIView
@property (nonatomic, strong, nullable) JMDLayoutStyle *boxStyle;
@end

@implementation JMDBorderView

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

- (void)drawRect:(CGRect)rect {
  JMDLayoutStyle *style = self.boxStyle;
  if (style == nil) {
    return;
  }
  CGContextRef context = UIGraphicsGetCurrentContext();
  const CGSize size = self.bounds.size;

  if (style.borderLeftWidth > 0 && style.borderLeftColor != nil) {
    CGContextSetFillColorWithColor(context, style.borderLeftColor.CGColor);
    if (style.borderRadius > 0) {
      UIBezierPath *path = [UIBezierPath
          bezierPathWithRoundedRect:CGRectMake(0, 0, style.borderLeftWidth, size.height)
                       cornerRadius:style.borderRadius / 2];
      [path fill];
    } else {
      CGContextFillRect(context, CGRectMake(0, 0, style.borderLeftWidth, size.height));
    }
  }
  if (style.borderRightWidth > 0 && style.borderRightColor != nil) {
    CGContextSetFillColorWithColor(context, style.borderRightColor.CGColor);
    CGContextFillRect(
        context,
        CGRectMake(size.width - style.borderRightWidth, 0, style.borderRightWidth, size.height));
  }
  if (style.borderTopWidth > 0 && style.borderTopColor != nil) {
    CGContextSetFillColorWithColor(context, style.borderTopColor.CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, size.width, style.borderTopWidth));
  }
  if (style.borderBottomWidth > 0 && style.borderBottomColor != nil) {
    CGContextSetFillColorWithColor(context, style.borderBottomColor.CGColor);
    CGContextFillRect(
        context,
        CGRectMake(0, size.height - style.borderBottomWidth, size.width, style.borderBottomWidth));
  }
}

@end

@implementation JMDQuoteView {
  JMDMeasuredBlock *_measured;
  JMDBlockStackView *_stack;
  JMDBorderView *_borders;
}

- (void)bind:(JMDMeasuredBlock *)measured
         gap:(CGFloat)gap
        host:(nullable id<JMDMarkdownHost>)host {
  _measured = measured;
  if (_stack == nil) {
    _stack = [[JMDBlockStackView alloc] initWithFrame:CGRectZero];
    _borders = [[JMDBorderView alloc] initWithFrame:CGRectZero];
    [self addSubview:_stack];
    [self addSubview:_borders];
  }
  JMDApplyBox(self, measured.block.layoutStyle);
  _borders.boxStyle = measured.block.layoutStyle;
  _stack.host = host;
  [_stack setBlocks:measured.children gap:gap];
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
  const CGFloat left = style.borderLeftWidth + style.paddingLeft;
  const CGFloat top = style.borderTopWidth + style.paddingTop;
  _stack.frame = CGRectMake(
      left,
      top,
      self.bounds.size.width - left - style.borderRightWidth - style.paddingRight,
      self.bounds.size.height - top - style.borderBottomWidth - style.paddingBottom);
  _borders.frame = self.bounds;
  [_borders setNeedsDisplay];
}

@end

@implementation JMDCodeBlockView {
  JMDMeasuredBlock *_measured;
  UIScrollView *_scroller;
  JMDBlockTextView *_text;
}

- (void)bind:(JMDMeasuredBlock *)measured {
  _measured = measured;
  if (_scroller == nil) {
    _scroller = [[JMDNestedScrollView alloc] initWithFrame:CGRectZero];
    _scroller.showsHorizontalScrollIndicator = NO;
    _scroller.showsVerticalScrollIndicator = NO;
    _scroller.alwaysBounceHorizontal = YES;
    _scroller.alwaysBounceVertical = NO;
    _scroller.delaysContentTouches = NO;
    _scroller.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _text = [[JMDBlockTextView alloc] initWithFrame:CGRectZero];
    [_scroller addSubview:_text];
    [self addSubview:_scroller];
  }
  JMDApplyBox(self, measured.block.layoutStyle);
  [_text bindTextStorage:measured.textStorage];
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
  const CGFloat innerWidth =
      self.bounds.size.width - style.paddingLeft - style.paddingRight;
  _scroller.frame = CGRectMake(
      style.paddingLeft, style.paddingTop, innerWidth, _measured.textHeight);
  _text.frame = CGRectMake(0, 0, _measured.contentWidth, _measured.textHeight);
  _scroller.contentSize = CGSizeMake(_measured.contentWidth, _measured.textHeight);
}

@end

@implementation JMDListBlockView {
  JMDMeasuredBlock *_measured;
  CGFloat _gap;
}

- (void)bind:(JMDMeasuredBlock *)measured
         gap:(CGFloat)gap
        host:(nullable id<JMDMarkdownHost>)host {
  _measured = measured;
  _gap = gap;
  // Subviews are (marker, content) pairs; grow/shrink the pair list, then
  // rebind every pair in place.
  const NSUInteger needed = measured.block.rows.count * 2;
  while (self.subviews.count > needed) {
    [self.subviews.lastObject removeFromSuperview];
  }
  while (self.subviews.count < needed) {
    [self addSubview:[[JMDBlockTextView alloc] initWithFrame:CGRectZero]];
    [self addSubview:[[JMDBlockStackView alloc] initWithFrame:CGRectZero]];
  }
  for (NSUInteger i = 0; i < measured.block.rows.count; i++) {
    JMDBlockTextView *marker = (JMDBlockTextView *)self.subviews[i * 2];
    [marker bindTextStorage:measured.markerStorages[i]];
    JMDBlockStackView *content = (JMDBlockStackView *)self.subviews[i * 2 + 1];
    content.host = host;
    [content setBlocks:measured.rowContents[i] gap:gap];
  }
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
  JMDBlock *block = _measured.block;
  const CGFloat markerX = block.listMarginLeft + block.markerMarginLeft;
  const CGFloat contentX = markerX + block.markerWidth;
  const CGFloat contentWidth = _measured.contentWidth;

  CGFloat y = 0;
  for (NSUInteger i = 0; i < block.rows.count; i++) {
    const CGFloat markerHeight = _measured.markerHeights[i].doubleValue;
    const CGFloat contentHeight =
        [JMDRenderedContent stackHeight:_measured.rowContents[i] gap:_gap];
    const CGFloat rowHeight = MAX(markerHeight, contentHeight);

    UIView *markerView = self.subviews[i * 2];
    UIView *contentView = self.subviews[i * 2 + 1];
    markerView.frame = CGRectMake(markerX, y, block.markerWidth, markerHeight);
    contentView.frame = CGRectMake(contentX, y, contentWidth, contentHeight);

    y += rowHeight;
    if (i + 1 < block.rows.count) {
      y += _gap / 2;
    }
  }
}

@end
