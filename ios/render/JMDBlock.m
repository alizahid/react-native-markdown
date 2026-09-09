#import "JMDBlock.h"

@implementation JMDRunBackground
@end

@implementation JMDListRow
@end

@implementation JMDTableRow
@end

@implementation JMDBlock
@end

@implementation JMDMeasuredBlock

- (instancetype)init {
  if (self = [super init]) {
    _children = @[];
    _markerHeights = @[];
    _rowContents = @[];
    _columnWidths = @[];
    _rowHeights = @[];
    _markerStorages = @[];
    _cellStorages = @[];
  }
  return self;
}

@end
