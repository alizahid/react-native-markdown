#import "JetMarkdownView.h"

#import <React/RCTConversions.h>

#import <react/renderer/components/JetMarkdownViewSpec/EventEmitters.h>
#import <react/renderer/components/JetMarkdownViewSpec/Props.h>
#import <react/renderer/core/ConcreteComponentDescriptor.h>

// Imported directly (not via the override ComponentDescriptors.h) so the
// custom measurable shadow node is used regardless of header search order.
#import "react/JetMarkdownShadowNode.h"

namespace facebook::react {
using JMDComponentDescriptor = ConcreteComponentDescriptor<JetMarkdownShadowNode>;
} // namespace facebook::react

#import "RCTFabricComponentsPlugins.h"

#import "measure/JMDMarkdownMeasurer.h"
#import "render/JMDContentCache.h"
#import "style/JMDFontScale.h"
#import "style/JMDStyleConfig.h"
#import "views/JMDBlockStackView.h"
#import "views/JMDBlockTextView.h"
#import "views/JMDImageView.h"
#import "views/JMDMarkdownHost.h"

#import "react/JetMarkdownMeasurer.h"

using namespace facebook::react;

@interface JetMarkdownView () <JMDMarkdownHost, UIGestureRecognizerDelegate>
@end

static void JMDSetNeedsDisplayDeep(UIView *view);
static CGRect JMDScreenFrameOfView(UIView *view);
static BOOL JMDIsScrollInProgress(UIView *view);

@implementation JetMarkdownView {
  NSString *_markdown;
  NSString *_stylesJson;
  BOOL _allowFontScaling;
  JMDBlockStackView *_stack;
  // Layout objects are cached per (content, width, image sizes, font
  // scale), so identity says whether the bound view tree is still current.
  JMDWidthLayout *_boundLayout;
  // url -> @[w, h] points: from the images prop (wins) and loaded bitmaps.
  NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *_propImageSizes;
  NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *_loadedImageSizes;
  NSMutableSet<NSNumber *> *_revealedSpoilers;
  JetMarkdownShadowNode::ConcreteState::Shared _state;
}

+ (void)load {
  jetmarkdown::JetMarkdownMeasurer::shared().install(
      [](const std::string &markdown,
         const std::string &stylesJson,
         const std::string &imagesJson,
         float maxWidth,
         float fontScale) -> float {
        NSString *markdownString =
            [[NSString alloc] initWithBytes:markdown.data()
                                     length:markdown.size()
                                   encoding:NSUTF8StringEncoding];
        NSString *stylesString =
            [[NSString alloc] initWithBytes:stylesJson.data()
                                     length:stylesJson.size()
                                   encoding:NSUTF8StringEncoding];
        NSString *imagesString =
            [[NSString alloc] initWithBytes:imagesJson.data()
                                     length:imagesJson.size()
                                   encoding:NSUTF8StringEncoding];
        return [JMDMarkdownMeasurer measureMarkdown:markdownString ?: @""
                                         stylesJson:stylesString ?: @""
                                         imagesJson:imagesString ?: @""
                                           maxWidth:maxWidth
                                          fontScale:fontScale];
      });
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<JMDComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const JetMarkdownViewProps>();
    _props = defaultProps;
    _markdown = @"";
    _stylesJson = @"";
    _allowFontScaling = YES;

    // Dynamic Type changes re-render in place; RN relayouts the shadow
    // tree with the new multiplier on its own.
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(jmdContentSizeCategoryDidChange)
               name:UIContentSizeCategoryDidChangeNotification
             object:nil];
    _stack = [[JMDBlockStackView alloc] initWithFrame:CGRectZero];
    _propImageSizes = [NSMutableDictionary new];
    _loadedImageSizes = [NSMutableDictionary new];
    _revealedSpoilers = [NSMutableSet new];
    _stack.host = self;
    [self addSubview:_stack];

    // The internal tree is hit-test transparent; the component view owns
    // link/mention/spoiler/image touch handling (like React Native's Text).
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(jmdHandleTap:)];
    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(jmdHandleLongPress:)];
    tap.delegate = self;
    longPress.delegate = self;
    [self addGestureRecognizer:tap];
    [self addGestureRecognizer:longPress];
  }
  return self;
}

#pragma mark - Interaction resolution

// Deepest content view at a host-space point (internal views are hit-test
// transparent, so this walks frames directly). Views that opt out of user
// interaction (border overlays) are skipped.
- (UIView *)jmdContentViewAtPoint:(CGPoint)point inView:(UIView *)view {
  for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
    if (subview.hidden || subview.alpha < 0.01 || !subview.userInteractionEnabled) {
      continue;
    }
    const CGPoint local = [view convertPoint:point toView:subview];
    if ([subview pointInside:local withEvent:nil]) {
      return [self jmdContentViewAtPoint:local inView:subview];
    }
  }
  return view;
}

- (nullable UIView *)jmdInteractiveViewAtPoint:(CGPoint)point
                                    localPoint:(CGPoint *)localPoint {
  UIView *view = [self jmdContentViewAtPoint:point inView:self];
  while (view != nil && view != self) {
    if ([view isKindOfClass:[JMDBlockTextView class]] ||
        [view isKindOfClass:[JMDImageView class]]) {
      if (localPoint != nil) {
        *localPoint = [self convertPoint:point toView:view];
      }
      return view;
    }
    view = view.superview;
  }
  return nil;
}

- (BOOL)jmdIsInteractiveAtPoint:(CGPoint)point {
  CGPoint local;
  UIView *view = [self jmdInteractiveViewAtPoint:point localPoint:&local];
  if ([view isKindOfClass:[JMDImageView class]]) {
    return ((JMDImageView *)view).imageUrl != nil;
  }
  if ([view isKindOfClass:[JMDBlockTextView class]]) {
    NSDictionary *attributes = [(JMDBlockTextView *)view attributesAtPoint:local];
    return attributes[JMDLinkURLAttributeName] != nil ||
        attributes[JMDSpoilerIDAttributeName] != nil;
  }
  return NO;
}

// Touches that do not start on an interactive range are never tracked, so
// they cannot interfere with an ancestor scroll view's pan. A touch that
// lands mid-scroll is a scroll-stopper, not a press (Pressable semantics) —
// checked from the deepest content view so nested code/table scrollers and
// the outer list both count.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
       shouldReceiveTouch:(UITouch *)touch {
  const CGPoint point = [touch locationInView:self];
  if (![self jmdIsInteractiveAtPoint:point]) {
    return NO;
  }
  return !JMDIsScrollInProgress([self jmdContentViewAtPoint:point inView:self]);
}

// Non-interactive points fall through to ancestors so a wrapping pressable
// becomes the hit view. UIControl-based wrappers (react-native-gesture-handler's
// button) need the touch delivered to them directly and never fire while this
// view claims every point. Interactive points stay claimed for the host
// recognizers; nested code/table scroll views are returned by super unchanged.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *result = [super hitTest:point withEvent:event];
  if (result == self && ![self jmdIsInteractiveAtPoint:point]) {
    return nil;
  }
  // Mid-scroll, an interactive point is not claimed either: hit-testing runs
  // before the touch is delivered, so isDecelerating is still reliable here
  // (by shouldReceiveTouch: time the same touch may have already stopped the
  // scroll). Falling through lets the ancestor scroll view take the touch
  // and stop, exactly like tapping a Pressable during momentum.
  if (result == self && JMDIsScrollInProgress(self)) {
    return nil;
  }
  return result;
}

// YES when any scroll view on the path from `view` up through the window is
// being dragged or is decelerating — a press landing then must only stop
// the scroll, never fire.
static BOOL JMDIsScrollInProgress(UIView *view) {
  for (UIView *ancestor = view; ancestor != nil; ancestor = ancestor.superview) {
    if ([ancestor isKindOfClass:UIScrollView.class]) {
      UIScrollView *scroll = (UIScrollView *)ancestor;
      if (scroll.isDecelerating || scroll.isDragging) {
        return YES;
      }
    }
  }
  return NO;
}

// Scrolling always wins: a drag that begins on a link still pans the list
// (the tap/long-press simply fail on movement).
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
  return [other.view isKindOfClass:[UIScrollView class]];
}

- (void)jmdHandleTap:(UITapGestureRecognizer *)recognizer {
  CGPoint local;
  UIView *view = [self jmdInteractiveViewAtPoint:[recognizer locationInView:self]
                                      localPoint:&local];
  if ([view isKindOfClass:[JMDImageView class]]) {
    NSString *url = ((JMDImageView *)view).imageUrl;
    if (url != nil) {
      [self imagePressed:url frame:JMDScreenFrameOfView(view)];
    }
    return;
  }
  if (![view isKindOfClass:[JMDBlockTextView class]]) {
    return;
  }
  NSDictionary *attributes = [(JMDBlockTextView *)view attributesAtPoint:local];
  NSNumber *spoilerId = attributes[JMDSpoilerIDAttributeName];
  NSString *url = attributes[JMDLinkURLAttributeName];

  if (spoilerId != nil && ![self isSpoilerRevealed:spoilerId.integerValue]) {
    // First tap reveals; links inside come alive afterwards.
    [self toggleSpoiler:spoilerId.integerValue];
  } else if (url != nil) {
    [self linkPressed:url];
  } else if (spoilerId != nil) {
    [self toggleSpoiler:spoilerId.integerValue];
  }
}

- (void)jmdHandleLongPress:(UILongPressGestureRecognizer *)recognizer {
  if (recognizer.state != UIGestureRecognizerStateBegan) {
    return;
  }
  CGPoint local;
  UIView *view = [self jmdInteractiveViewAtPoint:[recognizer locationInView:self]
                                      localPoint:&local];
  if (![view isKindOfClass:[JMDBlockTextView class]]) {
    return;
  }
  NSDictionary *attributes = [(JMDBlockTextView *)view attributesAtPoint:local];
  NSNumber *spoilerId = attributes[JMDSpoilerIDAttributeName];
  NSString *url = attributes[JMDLinkURLAttributeName];
  if (url != nil && (spoilerId == nil || [self isSpoilerRevealed:spoilerId.integerValue])) {
    [self linkLongPressed:url];
  }
}

#pragma mark - JMDMarkdownHost

- (void)imageIntrinsicSize:(CGSize)size forUrl:(NSString *)url {
  [self noteIntrinsicSize:size forUrl:url];
}

- (BOOL)isSpoilerRevealed:(NSInteger)spoilerId {
  return [_revealedSpoilers containsObject:@(spoilerId)];
}

- (void)toggleSpoiler:(NSInteger)spoilerId {
  if ([_revealedSpoilers containsObject:@(spoilerId)]) {
    [_revealedSpoilers removeObject:@(spoilerId)];
  } else {
    [_revealedSpoilers addObject:@(spoilerId)];
  }
  JMDSetNeedsDisplayDeep(self);
}

- (const JetMarkdownViewEventEmitter *)markdownEventEmitter {
  if (!_eventEmitter) {
    return nullptr;
  }
  return static_cast<const JetMarkdownViewEventEmitter *>(_eventEmitter.get());
}

- (void)linkPressed:(NSString *)url {
  if (const auto *emitter = [self markdownEventEmitter]) {
    emitter->onLinkPress({.url = std::string(url.UTF8String ?: "")});
  }
}

- (void)linkLongPressed:(NSString *)url {
  if (const auto *emitter = [self markdownEventEmitter]) {
    emitter->onLinkLongPress({.url = std::string(url.UTF8String ?: "")});
  }
}

- (void)imagePressed:(NSString *)url frame:(CGRect)frame {
  if (const auto *emitter = [self markdownEventEmitter]) {
    emitter->onImagePress({
        .height = frame.size.height,
        .url = std::string(url.UTF8String ?: ""),
        .width = frame.size.width,
        .x = frame.origin.x,
        .y = frame.origin.y,
    });
  }
}

static CGRect JMDScreenFrameOfView(UIView *view) {
  CGRect frame = [view convertRect:view.bounds toView:nil];
  UIWindow *window = view.window;
  if (window != nil) {
    frame = [window convertRect:frame toCoordinateSpace:window.screen.coordinateSpace];
  }
  return frame;
}

static void JMDSetNeedsDisplayDeep(UIView *view) {
  // Spoiler covers are drawn by the text views only; invalidating images
  // and scrollers too would double the redraw work.
  if ([view isKindOfClass:JMDBlockTextView.class]) {
    [view setNeedsDisplay];
  }
  for (UIView *subview in view.subviews) {
    JMDSetNeedsDisplayDeep(subview);
  }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  if ([self.traitCollection
          hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
    // Dynamic (platform) colors resolve at draw time for text, but border
    // and background colors snapshot into CGColors when blocks bind; rebind
    // so they re-resolve under the new appearance.
    _boundLayout = nil;
    [self setNeedsLayout];
    JMDSetNeedsDisplayDeep(self);
  }
}

- (void)noteIntrinsicSize:(CGSize)size forUrl:(NSString *)url {
  if (_propImageSizes[url] != nil || _loadedImageSizes[url] != nil) {
    return;
  }
  _loadedImageSizes[url] = @[ @(size.width), @(size.height) ];

  // Publish into the shadow-node state so measure() grows the component.
  if (_state != nullptr) {
    std::map<std::string, JetMarkdownState::ImageSize> sizes;
    for (NSString *key in _loadedImageSizes) {
      NSArray<NSNumber *> *value = _loadedImageSizes[key];
      sizes[std::string(key.UTF8String ?: "")] = JetMarkdownState::ImageSize{
          value[0].doubleValue, value[1].doubleValue};
    }
    _state->updateState(JetMarkdownState(std::move(sizes)));
  }
  [self setNeedsLayout];
}

- (void)updateState:(const State::Shared &)state oldState:(const State::Shared &)oldState {
  _state = std::static_pointer_cast<const JetMarkdownShadowNode::ConcreteState>(state);
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)jmdContentSizeCategoryDidChange {
  if (_allowFontScaling) {
    [self setNeedsLayout];
  }
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps {
  const auto &newViewProps = *std::static_pointer_cast<JetMarkdownViewProps const>(props);

  NSString *markdown =
      [[NSString alloc] initWithBytes:newViewProps.markdown.data()
                               length:newViewProps.markdown.size()
                             encoding:NSUTF8StringEncoding] ?: @"";
  NSString *stylesJson =
      [[NSString alloc] initWithBytes:newViewProps.stylesJson.data()
                               length:newViewProps.stylesJson.size()
                             encoding:NSUTF8StringEncoding] ?: @"";

  if (![markdown isEqualToString:_markdown]) {
    // Spoiler ids are render-order counters and learned image sizes belong
    // to the old document; both must not survive a content change.
    [_revealedSpoilers removeAllObjects];
    [_loadedImageSizes removeAllObjects];
  }
  if (![markdown isEqualToString:_markdown] || ![stylesJson isEqualToString:_stylesJson] ||
      newViewProps.allowFontScaling != _allowFontScaling) {
    _markdown = markdown;
    _stylesJson = stylesJson;
    _allowFontScaling = newViewProps.allowFontScaling;
    [self setNeedsLayout];
  }

  NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *nextPropSizes =
      [NSMutableDictionary dictionaryWithCapacity:newViewProps.images.size()];
  for (const auto &image : newViewProps.images) {
    NSString *url = [[NSString alloc] initWithBytes:image.url.data()
                                             length:image.url.size()
                                           encoding:NSUTF8StringEncoding];
    if (url != nil) {
      nextPropSizes[url] = @[ @(image.width), @(image.height) ];
    }
  }
  if (![nextPropSizes isEqualToDictionary:_propImageSizes]) {
    _propImageSizes = nextPropSizes;
    // The pre-size data changed: cached layouts for the old sizes must not
    // be reused even when the measured height happens to match.
    [self setNeedsLayout];
  }

  [super updateProps:props oldProps:oldProps];
}

- (NSDictionary<NSString *, NSArray<NSNumber *> *> *)mergedImageSizes {
  if (_loadedImageSizes.count == 0 && _propImageSizes.count == 0) {
    return @{};
  }
  NSMutableDictionary *merged = [_loadedImageSizes mutableCopy];
  [merged addEntriesFromDictionary:_propImageSizes];
  return merged;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self rebuildBlocks];
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  _markdown = @"";
  _stylesJson = @"";
  _boundLayout = nil;
  _state = nullptr;
  [_propImageSizes removeAllObjects];
  [_loadedImageSizes removeAllObjects];
  [_revealedSpoilers removeAllObjects];
  [_stack setBlocks:@[] gap:0];
}

- (void)rebuildBlocks {
  JMDStyleConfig *styles = [JMDStyleConfig configWithJson:_stylesJson];
  self.backgroundColor = styles.backgroundColor ?: UIColor.clearColor;

  const CGFloat contentWidth =
      self.bounds.size.width - styles.paddingLeft - styles.paddingRight;
  if (contentWidth <= 0) {
    [_stack setBlocks:@[] gap:0];
    _boundLayout = nil;
    return;
  }

  // Must match the shadow node's LayoutContext::fontSizeMultiplier.
  const CGFloat fontScale = _allowFontScaling ? JMDFontSizeMultiplier() : 1.0;
  JMDRenderedContent *content = [JMDContentCache contentForMarkdown:_markdown
                                                         stylesJson:_stylesJson
                                                          fontScale:fontScale];
  NSDictionary *imageSizes = [self mergedImageSizes];
  JMDWidthLayout *layout = [content layoutForWidth:contentWidth imageSizes:imageSizes];

  if (layout != _boundLayout) {
    _boundLayout = layout;
    [_stack setBlocks:layout.measured gap:content.gap];
  }

  const CGFloat contentHeight =
      layout.totalHeight - styles.paddingTop - styles.paddingBottom;
  _stack.frame =
      CGRectMake(styles.paddingLeft, styles.paddingTop, contentWidth, contentHeight);
}

@end
