#import "IBPHierarchicalSolver.h"
#import "IBPNSCollectionLayoutItem.h"
#import "IBPNSCollectionLayoutItem_Private.h"
#import "IBPNSCollectionLayoutGroup.h"
#import "IBPNSCollectionLayoutGroup_Private.h"
#import "IBPNSCollectionLayoutEnvironment.h"
#import "IBPNSCollectionLayoutSpacing.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutSize_Private.h"
#import "IBPNSCollectionLayoutDimension.h"
#import "CGVectorExtensions.h"
#import "IBPHierarchicalGroupSolver.h"
#import "IBPHierarchicalLeafItemSolver.h"
#import "Misc.h"

@implementation IBPHierarchicalSolver

+(IBPHierarchicalSolver *)solverWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                                           locationInSection:(NSRange)locationInSection {
    if (layoutItem.isGroup) {
        return [[IBPHierarchicalGroupSolver alloc] initWithLayoutItem:(IBPNSCollectionLayoutGroup *)layoutItem
                                                                  locationInSection:locationInSection];
    }

    return [[IBPHierarchicalLeafItemSolver alloc] initWithLayoutItem:layoutItem
                                                             locationInSection:locationInSection];
}

-(instancetype)initWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem locationInSection:(NSRange)locationInSection {
    self = [super init];

    if (self) {
        _locationInSection = locationInSection;
        _layoutItem = layoutItem;
    }

    return self;
}

-(CGRect)frame {
    return CGRectMake(_originInParent.x, _originInParent.y, _solvedSize.width, _solvedSize.height);
}

-(void)solveForContainer:(IBPNSCollectionLayoutContainer *)container traitCollection:(UITraitCollection *)traitCollection {
    SubclassMustOverride(_cmd);
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    SubclassMustOverride(_cmd);
}

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex {
    SubclassMustOverride(_cmd);
}

-(NSString *)description {
    return [NSString stringWithFormat:@"solver for %@ <frame = %@>",
            NSStringFromClass([_layoutItem class]),
            [NSValue valueWithCGRect:self.frame]];
}

@end
