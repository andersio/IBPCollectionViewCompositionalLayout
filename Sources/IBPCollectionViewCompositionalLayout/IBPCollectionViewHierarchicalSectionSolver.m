#import "IBPCollectionViewHierarchicalSectionSolver.h"
#import "IBPCollectionViewHierarchicalSolver.h"
#import "IBPNSCollectionLayoutItem.h"
#import "IBPNSCollectionLayoutItem_Private.h"
#import "IBPNSCollectionLayoutSection.h"
#import "IBPNSCollectionLayoutSection_Private.h"
#import "IBPNSCollectionLayoutGroup.h"
#import "IBPNSCollectionLayoutGroup_Private.h"
#import "IBPNSCollectionLayoutEnvironment.h"
#import "IBPNSCollectionLayoutSpacing.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutSize_Private.h"
#import "IBPNSCollectionLayoutDimension.h"

@interface IBPCollectionViewHierarchicalSectionSolver (Private)

-(void)createChildrenForCount:(NSInteger)count;
-(void)solveItemForProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection;
-(void)solveGroup:(IBPNSCollectionLayoutGroup*)group forProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection;

@end

@implementation IBPCollectionViewHierarchicalSectionSolver

+(instancetype)solverWithLayoutSection:(IBPNSCollectionLayoutSection *)layoutSection
                            layoutAxis:(UICollectionViewScrollDirection)layoutAxis
                         numberOfItems:(NSInteger)numberOfItems {
    IBPCollectionViewHierarchicalSectionSolver *solver = [[self alloc] init];

    if (solver) {
        solver->_layoutAxis = layoutAxis;
        solver.layoutSection = layoutSection;

        [solver createChildrenForCount:numberOfItems];
    }

    return solver;
}

-(void)solveForProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection {
    CGPoint origin = proposedRect.origin;
    CGRect finalFrame = CGRectMake(origin.x, origin.y, 0.0, 0.0);

    for (IBPCollectionViewHierarchicalSolver *solver in _children) {
        CGRect childRect = CGRectMake(origin.x, origin.y, proposedRect.size.width, proposedRect.size.height);
        [solver solveForProposedRect:childRect traitCollection:traitCollection];

        switch (_layoutAxis) {
            case UICollectionViewScrollDirectionVertical:
                origin.y += solver.frame.size.height;
                break;
            case UICollectionViewScrollDirectionHorizontal:
                origin.x += solver.frame.size.width;
                break;
        }

        finalFrame = CGRectUnion(finalFrame, solver.frame);
    }

    _frame = finalFrame;
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                           itemIndex:(NSInteger)itemIndex
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    __block NSMutableArray<IBPUICollectionViewCompositionalLayoutAttributes *> *allAttributes;
    allAttributes = [[NSMutableArray alloc] init];

    __block NSInteger itemCursor = itemIndex;

    [_children enumerateObjectsUsingBlock:^(IBPCollectionViewHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
        if (CGRectIntersectsRect(solver.frame, rect)) {
            [allAttributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:rect
                                                                                  itemIndex:itemCursor
                                                                               sectionIndex:sectionIndex]];
            itemCursor += solver.layoutItem.leafItemCount;
        }
    }];

    return allAttributes;
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect forSectionAtIndex:(NSInteger)sectionIndex {
    return [self layoutAttributesForItemInVisibleRect:rect itemIndex:0 sectionIndex:sectionIndex];
}

-(IBPUICollectionViewCompositionalLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    __block IBPUICollectionViewCompositionalLayoutAttributes *attributes;
    return nil;
}

- (void)setPreferredSize:(CGRect)preferredSize forItemAtIndex:(NSInteger)itemIndex {

}

- (void)createChildrenForCount:(NSInteger)count {
    NSMutableArray *children = [[NSMutableArray alloc] init];

    IBPNSCollectionLayoutGroup *group = [_layoutSection group];
    NSInteger leafItemCount = [group leafItemCount];
    NSInteger numberOfMateralizedGroups = (NSInteger) ceil((double) count / (double) leafItemCount);

    for (NSInteger i = 0; i < numberOfMateralizedGroups; i++) {
        NSRange localRange = NSIntersectionRange(NSMakeRange(i * leafItemCount, leafItemCount), NSMakeRange(0, count));

        IBPCollectionViewHierarchicalSolver *childSolver;
        childSolver = [IBPCollectionViewHierarchicalSolver solverWithLayoutItem:group
                                                                     layoutAxis:self->_layoutAxis
                                                              locationInSection:localRange];
        [children addObject:childSolver];
    }

    _children = children;
}

@end
