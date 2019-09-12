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
-(void)solveItemForProposedRect:(CGSize)proposedSize traitCollection:(UITraitCollection *)traitCollection;
-(void)solveGroup:(IBPNSCollectionLayoutGroup*)group forProposedRect:(CGSize)proposedSize traitCollection:(UITraitCollection *)traitCollection;

@end

@implementation IBPCollectionViewHierarchicalSectionSolver

+(instancetype)solverWithLayoutSection:(IBPNSCollectionLayoutSection *)layoutSection
                            layoutAxis:(UICollectionViewScrollDirection)layoutAxis
                         numberOfItems:(NSInteger)numberOfItems {
    IBPCollectionViewHierarchicalSectionSolver *solver = [[self alloc] init];

    if (solver) {
        solver.layoutSection = layoutSection;

        if (layoutSection.scrollsOrthogonally) {
            switch (layoutAxis) {
                case UICollectionViewScrollDirectionVertical:
                    solver->_layoutAxis = UICollectionViewScrollDirectionHorizontal;
                    break;
                case UICollectionViewScrollDirectionHorizontal:
                    solver->_layoutAxis = UICollectionViewScrollDirectionVertical;
                    break;
            }
        } else {
            solver->_layoutAxis = layoutAxis;
        }

        [solver createChildrenForCount:numberOfItems];
    }

    return solver;
}

-(CGRect)frame {
    return CGRectMake(_originInParent.x, _originInParent.y, _solvedSize.width, _solvedSize.height);
}

-(void)solveForContainer:(IBPNSCollectionLayoutContainer *)container traitCollection:(UITraitCollection *)traitCollection {
    CGSize containerSize = container.effectiveContentSize;

    IBPNSCollectionLayoutContainer *childContainer;
    childContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:container.effectiveContentSize contentInsets:IBPNSDirectionalEdgeInsetsZero];

    CGPoint layoutOrigin = CGPointZero;
    CGRect finalBounds = CGRectZero;

    for (IBPCollectionViewHierarchicalSolver *solver in _children) {
        [solver solveForContainer:childContainer traitCollection:traitCollection];
        solver.originInParent = layoutOrigin;

        CGSize solvedSize = solver.solvedSize;

        switch (_layoutAxis) {
            case UICollectionViewScrollDirectionVertical:
                layoutOrigin.y += solvedSize.height;
                break;
            case UICollectionViewScrollDirectionHorizontal:
                layoutOrigin.x += solvedSize.width;
                break;
        }

        finalBounds = CGRectUnion(finalBounds, solver.frame);
    }

    _solvedSize = finalBounds.size;
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                           itemIndex:(NSInteger)itemIndex
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    CGRect localVisibleRect = rect;
    localVisibleRect.origin.x -= _originInParent.x;
    localVisibleRect.origin.y -= _originInParent.y;

    __block NSMutableArray<IBPUICollectionViewCompositionalLayoutAttributes *> *allAttributes;
    allAttributes = [[NSMutableArray alloc] init];

    __block NSInteger itemCursor = itemIndex;

    [_children enumerateObjectsUsingBlock:^(IBPCollectionViewHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
        if (CGRectIntersectsRect(solver.frame, localVisibleRect)) {
            [allAttributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:localVisibleRect
                                                                                  itemIndex:itemCursor
                                                                               sectionIndex:sectionIndex]];
            itemCursor += solver.layoutItem.leafItemCount;
        }
    }];

    [allAttributes enumerateObjectsUsingBlock:^(IBPUICollectionViewCompositionalLayoutAttributes * _Nonnull attributes, NSUInteger idx, BOOL * _Nonnull stop) {
        CGRect frame = attributes.frame;
        frame.origin = CGPointMake(frame.origin.x + _originInParent.x, frame.origin.y + _originInParent.y);
        attributes.frame = frame;
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
