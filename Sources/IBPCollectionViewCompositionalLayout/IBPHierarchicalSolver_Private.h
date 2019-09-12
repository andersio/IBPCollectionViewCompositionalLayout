#import "IBPHierarchicalSolver.h"
#import "IBPNSCollectionLayoutItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface IBPHierarchicalSolver (Private)

-(instancetype)initWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
locationInSection:(NSRange)locationInSection;

@end

NS_ASSUME_NONNULL_END
