#import "JMDBlockStackView.h"

#import "JMDBlockTextView.h"
#import "JMDBoxViews.h"
#import "JMDImageView.h"
#import "JMDTableView.h"

@implementation JMDBlockStackView {
  NSArray<JMDMeasuredBlock *> *_measured;
  CGFloat _gap;
}

// Rebinds in place: a subview of the right kind at the same index is
// reused, anything else is replaced. List recycling rebinds whole trees, so
// the common case (same block kinds, different content) allocates nothing.
- (void)setBlocks:(NSArray<JMDMeasuredBlock *> *)blocks gap:(CGFloat)gap {
  _measured = blocks;
  _gap = gap;

  NSArray<UIView *> *existing = self.subviews;
  for (NSUInteger i = 0; i < blocks.count; i++) {
    UIView *old = i < existing.count ? existing[i] : nil;
    UIView *view = [self bindView:old to:blocks[i]];
    if (view != old) {
      [old removeFromSuperview];
      [self insertSubview:view atIndex:i];
    }
  }
  for (NSUInteger i = blocks.count; i < existing.count; i++) {
    [existing[i] removeFromSuperview];
  }
  [self setNeedsLayout];
}

- (UIView *)bindView:(nullable UIView *)old to:(JMDMeasuredBlock *)measured {
  switch (measured.block.kind) {
    case JMDBlockKindText: {
      JMDBlockTextView *view = [old isKindOfClass:JMDBlockTextView.class]
          ? (JMDBlockTextView *)old
          : [[JMDBlockTextView alloc] initWithFrame:CGRectZero];
      view.host = self.host;
      view.spoilerColor = measured.block.spoilerColor;
      view.spoilerRadius = measured.block.spoilerRadius;
      view.spoilerContinuous = measured.block.spoilerContinuous;
      [view bindTextStorage:measured.textStorage];
      return view;
    }
    case JMDBlockKindCode: {
      JMDCodeBlockView *view = [old isKindOfClass:JMDCodeBlockView.class]
          ? (JMDCodeBlockView *)old
          : [[JMDCodeBlockView alloc] initWithFrame:CGRectZero];
      [view bind:measured];
      return view;
    }
    case JMDBlockKindQuote: {
      JMDQuoteView *view = [old isKindOfClass:JMDQuoteView.class]
          ? (JMDQuoteView *)old
          : [[JMDQuoteView alloc] initWithFrame:CGRectZero];
      [view bind:measured gap:_gap host:self.host];
      return view;
    }
    case JMDBlockKindList: {
      JMDListBlockView *view = [old isKindOfClass:JMDListBlockView.class]
          ? (JMDListBlockView *)old
          : [[JMDListBlockView alloc] initWithFrame:CGRectZero];
      [view bind:measured gap:_gap host:self.host];
      return view;
    }
    case JMDBlockKindDivider: {
      UIView *view = (old != nil && old.class == UIView.class)
          ? old
          : [[UIView alloc] initWithFrame:CGRectZero];
      view.backgroundColor = measured.block.dividerColor;
      return view;
    }
    case JMDBlockKindImage: {
      JMDImageView *view = [old isKindOfClass:JMDImageView.class]
          ? (JMDImageView *)old
          : [[JMDImageView alloc] initWithFrame:CGRectZero];
      view.host = self.host;
      [view bind:measured.block];
      return view;
    }
    case JMDBlockKindTable: {
      JMDTableView *view = [old isKindOfClass:JMDTableView.class]
          ? (JMDTableView *)old
          : [[JMDTableView alloc] initWithFrame:CGRectZero];
      [view bind:measured host:self.host];
      return view;
    }
  }
  return [[UIView alloc] initWithFrame:CGRectZero];
}

// Never the hit view itself: markdown touches belong to the host component
// view; only nested scrollers (code blocks, tables) claim touches.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  return hit == self ? nil : hit;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  const CGFloat width = self.bounds.size.width;
  CGFloat y = 0;
  for (NSUInteger i = 0; i < _measured.count && i < self.subviews.count; i++) {
    JMDMeasuredBlock *measured = _measured[i];
    const CGFloat childWidth = measured.block.kind == JMDBlockKindImage
        ? MIN(measured.contentWidth, width)
        : width;
    self.subviews[i].frame = CGRectMake(0, y, childWidth, measured.height);
    y += measured.height;
    if (i + 1 < _measured.count) {
      y += _gap;
    }
  }
}

@end
