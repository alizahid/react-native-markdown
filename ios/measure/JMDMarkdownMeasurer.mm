#import "JMDMarkdownMeasurer.h"

#import "../render/JMDContentCache.h"
#import "../style/JMDStyleConfig.h"

@implementation JMDMarkdownMeasurer

+ (CGFloat)measureMarkdown:(NSString *)markdown
                stylesJson:(NSString *)stylesJson
                imagesJson:(NSString *)imagesJson
                  maxWidth:(CGFloat)maxWidth
                 fontScale:(CGFloat)fontScale {
  JMDStyleConfig *styles = [JMDStyleConfig configWithJson:stylesJson];
  const CGFloat contentWidth = maxWidth - styles.paddingLeft - styles.paddingRight;
  if (contentWidth <= 0) {
    return 0;
  }

  JMDRenderedContent *content = [JMDContentCache contentForMarkdown:markdown
                                                         stylesJson:stylesJson
                                                          fontScale:fontScale];
  return [content layoutForWidth:contentWidth
                      imageSizes:[self parseImageSizes:imagesJson]].totalHeight;
}

+ (nullable NSDictionary<NSString *, NSArray<NSNumber *> *> *)parseImageSizes:(NSString *)json {
  if (json.length == 0 || [json isEqualToString:@"{}"]) {
    return nil;
  }
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return nil;
  }
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [parsed isKindOfClass:[NSDictionary class]] ? parsed : nil;
}

@end
