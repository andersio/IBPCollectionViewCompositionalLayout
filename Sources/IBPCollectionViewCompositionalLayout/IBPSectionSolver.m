#import "IBPSectionSolver.h"
#import "IBPHierarchicalSolver.h"
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
#import "CGVectorExtensions.h"

@interface IBPSectionSolver (Private)

-(void)createChildrenForCount:(NSInteger)count;

@end

@implementation IBPSectionSolver

+(instancetype)solverWithLayoutSection:(IBPNSCollectionLayoutSection *)layoutSection
                            layoutAxis:(UICollectionViewScrollDirection)layoutAxis
                         numberOfItems:(NSInteger)numberOfItems {
    IBPSectionSolver *solver = [[self alloc] init];

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
    IBPNSCollectionLayoutContainer *childContainer;
    childContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:container.effectiveContentSize contentInsets:IBPNSDirectionalEdgeInsetsZero];

    CGPoint layoutOrigin = CGPointZero;
    CGRect finalBounds = CGRectZero;

    for (IBPHierarchicalSolver *solver in _children) {
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

    [_children enumerateObjectsUsingBlock:^(IBPHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
        if (CGRectIntersectsRect(solver.frame, localVisibleRect)) {
            [allAttributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:localVisibleRect
                                                                               sectionIndex:sectionIndex]];
        }
    }];

    [allAttributes enumerateObjectsUsingBlock:^(IBPUICollectionViewCompositionalLayoutAttributes * _Nonnull attributes, NSUInteger idx, BOOL * _Nonnull stop) {
        CGRect frame = attributes.frame;
        frame.origin = CGPointMake(frame.origin.x + self->_originInParent.x, frame.origin.y + self->_originInParent.y);
        attributes.frame = frame;
    }];

    return allAttributes;
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect forSectionAtIndex:(NSInteger)sectionIndex {
    return [self layoutAttributesForItemInVisibleRect:rect itemIndex:0 sectionIndex:sectionIndex];
}

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex {
    CGVector delta = CGVectorZero;
    NSInteger solverIndex = 0;

    for (solverIndex = 0; solverIndex < _children.count; solverIndex++) {
        IBPHierarchicalSolver *solver = _children[solverIndex];

        if (NSLocationInRange(itemIndex, solver.locationInSection)) {
            delta = [solver setPreferredSize:preferredSize forItemAtIndex:itemIndex];
            break;
        }
    }

    if (!CGVectorEqual(delta, CGVectorZero)) {
        for (NSInteger i = solverIndex + 1; i < _children.count; i++) {
            IBPHierarchicalSolver *solver = _children[i];

            switch (_layoutAxis) {
                case UICollectionViewScrollDirectionHorizontal:
                    solver.originInParent = CGPointOffsetX(delta.dx, solver.originInParent);
                    break;
                case UICollectionViewScrollDirectionVertical:
                    solver.originInParent = CGPointOffsetY(delta.dy, solver.originInParent);
                    break;
            }
        }

        // Recompute the bounds.
        CGRect bounds = CGRectZero;

        for (IBPHierarchicalSolver *solver in _children) {
            bounds = CGRectUnion(bounds, solver.frame);
        }

        CGSize oldSize = _solvedSize;
        _solvedSize = bounds.size;
        return CGVectorMake(_solvedSize.width - oldSize.width, _solvedSize.height - oldSize.height);
    }

    return CGVectorZero;
}

- (void)createChildrenForCount:(NSInteger)count {
    NSMutableArray *children = [[NSMutableArray alloc] init];

    IBPNSCollectionLayoutGroup *group = [_layoutSection group];
    NSInteger leafItemCount = [group leafItemCount];
    NSInteger numberOfMateralizedGroups = (NSInteger) ceil((double) count / (double) leafItemCount);

    for (NSInteger i = 0; i < numberOfMateralizedGroups; i++) {
        NSRange localRange = NSIntersectionRange(NSMakeRange(i * leafItemCount, leafItemCount), NSMakeRange(0, count));

        IBPHierarchicalSolver *childSolver;
        childSolver = [IBPHierarchicalSolver solverWithLayoutItem:group
                                                              locationInSection:localRange];
        [children addObject:childSolver];
    }

    _children = children;
}

@end
