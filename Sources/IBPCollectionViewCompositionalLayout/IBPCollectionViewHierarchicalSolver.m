#import "IBPCollectionViewHierarchicalSolver.h"
#import "IBPNSCollectionLayoutItem.h"
#import "IBPNSCollectionLayoutItem_Private.h"
#import "IBPNSCollectionLayoutGroup.h"
#import "IBPNSCollectionLayoutGroup_Private.h"
#import "IBPNSCollectionLayoutEnvironment.h"
#import "IBPNSCollectionLayoutSpacing.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutSize_Private.h"
#import "IBPNSCollectionLayoutDimension.h"

@interface IBPCollectionViewHierarchicalSolver (Private)

-(void)createChildren;
-(void)solveItemForProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection;
-(void)solveGroup:(IBPNSCollectionLayoutGroup*)group forProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection;

@end

@implementation IBPCollectionViewHierarchicalSolver

+(instancetype)solverWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                         layoutAxis:(UICollectionViewScrollDirection)layoutAxis
                  locationInSection:(NSRange)locationInSection {
    IBPCollectionViewHierarchicalSolver *solver = [[self alloc] init];

    if (solver) {
        solver->_hasPreferredSize = NO;
        solver->_preferredSize = CGSizeZero;
        solver->_layoutAxis = layoutAxis;
        solver->_locationInSection = locationInSection;
        solver.layoutItem = layoutItem;

        [solver createChildren];
    }

    return solver;
}

-(void)solveForProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection {
    if (_layoutItem.isGroup) {
        [self solveGroup:(IBPNSCollectionLayoutGroup *)_layoutItem
         forProposedRect:proposedRect
         traitCollection:traitCollection];
    } else {
        [self solveItemForProposedRect:proposedRect traitCollection:traitCollection];
    }
}

-(void)solveGroup:(IBPNSCollectionLayoutGroup *)group forProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection {
    IBPNSCollectionLayoutContainer *container = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:proposedRect.size contentInsets:IBPNSDirectionalEdgeInsetsZero];
    CGSize groupEffectiveSize = [[_layoutItem layoutSize] effectiveSizeForContainer:container];

    CGPoint origin = proposedRect.origin;
    CGRect finalFrame = CGRectMake(origin.x, origin.y, 0.0, 0.0);

    for (IBPCollectionViewHierarchicalSolver *solver in _children) {
        CGRect childRect = CGRectMake(origin.x, origin.y, groupEffectiveSize.width, groupEffectiveSize.height);
        [solver solveForProposedRect:childRect traitCollection:traitCollection];

        if (group.isVerticalGroup) {
            origin.y += solver.frame.size.height;
        }

        if (group.isHorizontalGroup) {
            origin.x += solver.frame.size.width;
        }

        finalFrame = CGRectUnion(finalFrame, solver.frame);
    }

    _frame = finalFrame;
}

-(void)solveItemForProposedRect:(CGRect)proposedRect traitCollection:(UITraitCollection *)traitCollection {
    IBPNSCollectionLayoutContainer *container = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:proposedRect.size contentInsets:IBPNSDirectionalEdgeInsetsZero];
    CGSize effectiveSize = [[_layoutItem layoutSize] effectiveSizeForContainer:container];

    if (_hasPreferredSize) {
        if (_layoutItem.layoutSize.widthDimension.isEstimated) {
            effectiveSize.width = _preferredSize.width;
        }

        if (_layoutItem.layoutSize.heightDimension.isEstimated) {
            effectiveSize.height = _preferredSize.height;
        }
    }

    _frame = CGRectMake(proposedRect.origin.x, proposedRect.origin.y, effectiveSize.width, effectiveSize.height);
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                           itemIndex:(NSInteger)itemIndex
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    __block NSMutableArray<IBPUICollectionViewCompositionalLayoutAttributes *> *allAttributes;
    allAttributes = [[NSMutableArray alloc] init];

    if (_layoutItem.isGroup) {
        __block NSInteger itemCursor = itemIndex;

        [_children enumerateObjectsUsingBlock:^(IBPCollectionViewHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
            if (CGRectIntersectsRect(solver.frame, rect)) {
                [allAttributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:rect
                                                                                      itemIndex:itemCursor
                                                                                   sectionIndex:sectionIndex]];
                itemCursor += solver.layoutItem.leafItemCount;
            }
        }];
    } else {
        IBPUICollectionViewCompositionalLayoutAttributes *attributes;
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:itemIndex inSection:sectionIndex];
        attributes = [IBPUICollectionViewCompositionalLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attributes.frame = _frame;

        [allAttributes addObject:attributes];
    }

    return allAttributes;
}

-(IBPUICollectionViewCompositionalLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    assert(NSLocationInRange(indexPath.item, _locationInSection));
    __block IBPUICollectionViewCompositionalLayoutAttributes *attributes;

    if (_layoutItem.isGroup) {
        [_children enumerateObjectsUsingBlock:^(IBPCollectionViewHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
            if (NSLocationInRange(indexPath.item, solver.locationInSection)) {
                attributes = [solver layoutAttributesForItemAtIndexPath:indexPath];
                *stop = YES;
            }
        }];
    } else {
        attributes = [IBPUICollectionViewCompositionalLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attributes.frame = _frame;
    }

    if (!attributes) {
        abort();
    }

    return attributes;
}

- (void)setPreferredSize:(CGRect)preferredSize forItemAtIndex:(NSInteger)itemIndex {
    
}

- (void)createChildren {
    NSMutableArray *children = [[NSMutableArray alloc] init];

    if (_layoutItem.isGroup) {
        __block NSInteger cursor = _locationInSection.location;
        NSInteger endIndex = NSMaxRange(_locationInSection);

        [_layoutItem enumerateItemsWithHandler:^(IBPNSCollectionLayoutItem * _Nonnull item, BOOL * _Nonnull stop) {
            NSInteger leafItemCount = [item leafItemCount];
            NSRange localRange = NSIntersectionRange(NSMakeRange(cursor, leafItemCount), self->_locationInSection);
            cursor += leafItemCount;

            IBPCollectionViewHierarchicalSolver *childSolver = [IBPCollectionViewHierarchicalSolver solverWithLayoutItem:item
                                                                                                              layoutAxis:self->_layoutAxis
                                                                                                       locationInSection:localRange];
            [children addObject:childSolver];

            if (cursor >= endIndex) {
                *stop = YES;
            }
        }];
    } else {
        assert(_locationInSection.length == 1);
    }

    _children = children;
}

@end
