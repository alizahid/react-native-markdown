#import "JMDBlockTextView.h"

#import <CoreText/CoreText.h>

@implementation JMDBlockTextView {
  // Owned by the measured block and shared with every view bound to the
  // same cached content (and the layout thread that built it), so it is
  // never mutated here: spoiler hiding is a draw-time clip.
  NSTextStorage *_textStorage;
  NSLayoutManager *_layoutManager;
  NSTextContainer *_textContainer;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

// Hit-test transparent: the host component view owns all touch handling,
// so ancestor scroll views treat markdown content like any React view.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  return nil;
}

- (void)bindTextStorage:(NSTextStorage *)storage {
  if (_textStorage != storage) {
    _textStorage = storage;
    _layoutManager = storage.layoutManagers.firstObject;
    _textContainer = _layoutManager.textContainers.firstObject;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = storage.string;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
  }
  // Spoiler styling and host may change without the storage changing.
  [self setNeedsDisplay];
}

- (NSAttributedString *)attributedText {
  return _textStorage;
}

- (void)drawRect:(CGRect)rect {
  if (_layoutManager == nil || _textStorage.length == 0) {
    return;
  }
  // One engine for everything: the layout manager that measured the block
  // also positions the overlays and draws the glyphs. NSStringDrawing
  // typesets separately and disagrees with NSLayoutManager about font
  // leading under a lineHeight cap (fonts with a nonzero line gap drift
  // ~gap pt per line), which misaligned overlays on wrapped lines.
  const NSRange glyphRange = [_layoutManager glyphRangeForTextContainer:_textContainer];
  [self drawRunBackgrounds];
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGContextSaveGState(context);
  [self clipHiddenSpoilers:context];
  [_layoutManager drawBackgroundForGlyphRange:glyphRange atPoint:CGPointZero];
  [_layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:CGPointZero];
  CGContextRestoreGState(context);
  [self drawSpoilerCovers];
}

// Unrevealed spoiler text is hidden by clipping its line-box slices out of
// the glyph draw (the cover hugs the text, so glyphs would leak around it).
// Purely draw-time, per-view state; the shared storage stays untouched.
- (void)clipHiddenSpoilers:(CGContextRef)context {
  if (self.host == nil) {
    return;
  }
  CGMutablePathRef hidden = CGPathCreateMutable();
  __block BOOL any = NO;
  [_textStorage
      enumerateAttribute:JMDSpoilerIDAttributeName
                 inRange:NSMakeRange(0, _textStorage.length)
                 options:0
              usingBlock:^(NSNumber *spoilerId, NSRange range, BOOL *stop) {
                if (spoilerId == nil ||
                    [self.host isSpoilerRevealed:spoilerId.integerValue]) {
                  return;
                }
                const NSRange glyphs =
                    [self->_layoutManager glyphRangeForCharacterRange:range
                                                 actualCharacterRange:nil];
                [self->_layoutManager
                    enumerateEnclosingRectsForGlyphRange:glyphs
                                withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0)
                                         inTextContainer:self->_textContainer
                                              usingBlock:^(CGRect rect, BOOL *stopInner) {
                                                // Padded past side bearings
                                                // and italic overhang.
                                                CGPathAddRect(hidden, NULL,
                                                              CGRectInset(rect, -2, 0));
                                                any = YES;
                                              }];
              }];
  if (any) {
    CGContextAddRect(context, self.bounds);
    CGContextAddPath(context, hidden);
    CGContextEOClip(context);
  }
  CGPathRelease(hidden);
}

// A chip inside an unrevealed spoiler would peek around the cover.
- (BOOL)isRangeInsideHiddenSpoiler:(NSRange)range {
  if (self.host == nil) {
    return NO;
  }
  __block BOOL hidden = NO;
  [_textStorage
      enumerateAttribute:JMDSpoilerIDAttributeName
                 inRange:range
                 options:0
              usingBlock:^(NSNumber *spoilerId, NSRange subRange, BOOL *stop) {
                if (spoilerId != nil &&
                    ![self.host isSpoilerRevealed:spoilerId.integerValue]) {
                  hidden = YES;
                  *stop = YES;
                }
              }];
  return hidden;
}

// Approximates iOS's continuous ("squircle") corner curve for a single
// rect; falls back to a plain rounded rect when the radius dominates.
static UIBezierPath *JMDChipPath(CGRect rect, CGFloat radius, BOOL continuous) {
  radius = MIN(radius, MIN(rect.size.width, rect.size.height) / 2);
  if (radius <= 0) {
    return [UIBezierPath bezierPathWithRect:rect];
  }
  if (!continuous) {
    return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
  }
  // The standard smooth-corner approximation: control points extend ~1.528x
  // the radius along the edges. Degrades to circular when the rect is too
  // small to fit the extended corners.
  const CGFloat k = 1.528665;
  const CGFloat ext = radius * k;
  if (rect.size.width < 2 * ext || rect.size.height < 2 * ext) {
    return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
  }
  const CGFloat minX = CGRectGetMinX(rect), maxX = CGRectGetMaxX(rect);
  const CGFloat minY = CGRectGetMinY(rect), maxY = CGRectGetMaxY(rect);
  UIBezierPath *path = [UIBezierPath bezierPath];
  [path moveToPoint:CGPointMake(minX + ext, minY)];
  [path addLineToPoint:CGPointMake(maxX - ext, minY)];
  [path addCurveToPoint:CGPointMake(maxX, minY + ext)
          controlPoint1:CGPointMake(maxX - ext + radius, minY)
          controlPoint2:CGPointMake(maxX, minY + ext - radius)];
  [path addLineToPoint:CGPointMake(maxX, maxY - ext)];
  [path addCurveToPoint:CGPointMake(maxX - ext, maxY)
          controlPoint1:CGPointMake(maxX, maxY - ext + radius)
          controlPoint2:CGPointMake(maxX - ext + radius, maxY)];
  [path addLineToPoint:CGPointMake(minX + ext, maxY)];
  [path addCurveToPoint:CGPointMake(minX, maxY - ext)
          controlPoint1:CGPointMake(minX + ext - radius, maxY)
          controlPoint2:CGPointMake(minX, maxY - ext + radius)];
  [path addLineToPoint:CGPointMake(minX, minY + ext)];
  [path addCurveToPoint:CGPointMake(minX + ext, minY)
          controlPoint1:CGPointMake(minX, minY + ext - radius)
          controlPoint2:CGPointMake(minX + ext - radius, minY)];
  [path closePath];
  return path;
}

// Overlays hug the text. lineHeight moves line boxes around the text, so
// any box derived from them inherits that skew; these rects anchor on the
// drawn baseline instead. Horizontal comes from the segment's glyph ink;
// vertical is the FONT's ink envelope (cap height above the baseline,
// descender depth below) so every run of a font renders the same height
// whether or not its particular glyphs have capitals or descenders.
static const CGFloat JMDInkPad = 2;

// Per-line overlay rects for a character range. Whitespace-only segments
// have no ink and produce no rect.
- (NSArray<NSValue *> *)inkRectsForRange:(NSRange)range
                                 padLeft:(CGFloat)padLeft
                                padRight:(CGFloat)padRight {
  CGContextRef context = UIGraphicsGetCurrentContext();
  // CTLineGetImageBounds reports bounds relative to the context's current
  // text position.
  CGContextSetTextPosition(context, 0, 0);
  const CGFloat maxWidth = self.bounds.size.width;
  const CGFloat maxHeight = self.bounds.size.height;
  const NSRange glyphRange =
      [_layoutManager glyphRangeForCharacterRange:range actualCharacterRange:nil];
  NSMutableArray<NSValue *> *lineRects = [NSMutableArray new];
  NSUInteger glyphIndex = glyphRange.location;
  while (glyphIndex < NSMaxRange(glyphRange)) {
    NSRange lineGlyphRange;
    const CGRect fragment =
        [_layoutManager lineFragmentRectForGlyphAtIndex:glyphIndex
                                         effectiveRange:&lineGlyphRange];
    const NSRange lineRange = NSIntersectionRange(lineGlyphRange, glyphRange);
    if (lineRange.length == 0) {
      break;
    }
    const NSRange charRange =
        [_layoutManager characterRangeForGlyphRange:lineRange actualGlyphRange:nil];
    const CGPoint startLocation =
        [_layoutManager locationForGlyphAtIndex:lineRange.location];
    // The typesetter already folds NSBaselineOffset (lineHeight centering,
    // sup/sub shifts) into the glyph location.
    const CGFloat baselineY = fragment.origin.y + startLocation.y;
    const CGFloat penX = fragment.origin.x + startLocation.x;

    CTLineRef line = CTLineCreateWithAttributedString(
        (__bridge CFAttributedStringRef)[_textStorage attributedSubstringFromRange:charRange]);
    const CGRect ink = CTLineGetImageBounds(line, context);
    CFRelease(line);
    if (!CGRectIsNull(ink) && ink.size.width > 0) {
      UIFont *font = [_textStorage attribute:NSFontAttributeName
                                     atIndex:charRange.location
                              effectiveRange:nil]
          ?: [UIFont systemFontOfSize:UIFont.systemFontSize];
      const CGFloat top = MAX(baselineY - font.capHeight - JMDInkPad, 0);
      const CGFloat bottom =
          MIN(baselineY - font.descender + JMDInkPad, maxHeight);
      const CGFloat left = MAX(penX + CGRectGetMinX(ink) - padLeft, 0);
      const CGFloat right = MIN(penX + CGRectGetMaxX(ink) + padRight, maxWidth);
      if (right > left && bottom > top) {
        [lineRects addObject:[NSValue valueWithCGRect:CGRectMake(
                                                          left, top,
                                                          right - left,
                                                          bottom - top)]];
      }
    }
    glyphIndex = NSMaxRange(lineGlyphRange);
  }
  return lineRects;
}

// Run background chips (inlineCode/link/mention and plain highlights),
// drawn UNDER the text; chips hidden with their spoiler don't draw.
- (void)drawRunBackgrounds {
  [_textStorage
      enumerateAttribute:JMDRunBackgroundAttributeName
                 inRange:NSMakeRange(0, _textStorage.length)
                 options:0
              usingBlock:^(JMDRunBackground *chip, NSRange range, BOOL *stop) {
                if (chip == nil || [self isRangeInsideHiddenSpoiler:range]) {
                  return;
                }
                NSArray<NSValue *> *rects = [self
                    inkRectsForRange:range
                             padLeft:chip.padLeft > 0 ? chip.padLeft : JMDInkPad
                            padRight:chip.padRight > 0 ? chip.padRight
                                                       : JMDInkPad];
                [chip.color setFill];
                for (NSValue *value in rects) {
                  [JMDChipPath(value.CGRectValue, chip.radius,
                               chip.continuousCurve) fill];
                }
              }];
}

// Spoiler cover chips, drawn OVER the (clipped-out) text until revealed.
// Same ink geometry as the run backgrounds so covers and backgrounds look
// identical.
- (void)drawSpoilerCovers {
  if (self.host == nil) {
    return;
  }
  [_textStorage
      enumerateAttribute:JMDSpoilerIDAttributeName
                 inRange:NSMakeRange(0, _textStorage.length)
                 options:0
              usingBlock:^(NSNumber *spoilerId, NSRange range, BOOL *stop) {
                if (spoilerId == nil ||
                    [self.host isSpoilerRevealed:spoilerId.integerValue]) {
                  return;
                }
                NSArray<NSValue *> *rects =
                    [self inkRectsForRange:range padLeft:JMDInkPad padRight:JMDInkPad];
                [self.spoilerColor ?: UIColor.darkGrayColor setFill];
                for (NSValue *value in rects) {
                  [JMDChipPath(value.CGRectValue, self.spoilerRadius,
                               self.spoilerContinuous) fill];
                }
              }];
}

- (nullable NSDictionary *)attributesAtPoint:(CGPoint)point {
  if (_layoutManager == nil || _textStorage.length == 0) {
    return nil;
  }
  const NSUInteger glyphIndex = [_layoutManager glyphIndexForPoint:point
                                                   inTextContainer:_textContainer];
  const CGRect glyphRect = [_layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1)
                                                     inTextContainer:_textContainer];
  if (!CGRectContainsPoint(CGRectInset(glyphRect, -8, -4), point)) {
    return nil;
  }
  const NSUInteger charIndex = [_layoutManager characterIndexForGlyphAtIndex:glyphIndex];
  if (charIndex >= _textStorage.length) {
    return nil;
  }
  return [_textStorage attributesAtIndex:charIndex effectiveRange:nil];
}

@end
