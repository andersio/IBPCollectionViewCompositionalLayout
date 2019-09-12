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
-(void)solveItemForProposedRect:(CGSize)proposedSize traitCollection:(UITraitCollection *)traitCollection;
-(void)solveGroup:(IBPNSCollectionLayoutGroup*)group forProposedRect:(CGSize)proposedSize traitCollection:(UITraitCollection *)traitCollection;

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

-(CGRect)frame {
    return CGRectMake(_originInParent.x, _originInParent.y, _solvedSize.width, _solvedSize.height);
}

-(void)solveForContainer:(IBPNSCollectionLayoutContainer *)container traitCollection:(UITraitCollection *)traitCollection {
    if (_layoutItem.isGroup) {
        [self solveGroup:(IBPNSCollectionLayoutGroup *)_layoutItem
         forContainer:container
         traitCollection:traitCollection];
    } else {
        [self solveItemForContainer:container traitCollection:traitCollection];
    }
}

-(void)solveGroup:(IBPNSCollectionLayoutGroup *)group
     forContainer:(IBPNSCollectionLayoutContainer *)container
  traitCollection:(UITraitCollection *)traitCollection {
    CGSize groupEffectiveSize = [[_layoutItem layoutSize] effectiveSizeForContainer:container];
    IBPNSCollectionLayoutContainer *groupContainer;
    groupContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:groupEffectiveSize
                                                                   contentInsets:IBPNSDirectionalEdgeInsetsZero];

    CGPoint origin = CGPointZero;
    CGRect finalBounds = CGRectZero;

    for (IBPCollectionViewHierarchicalSolver *solver in _children) {
        CGRect childRect = CGRectMake(origin.x, origin.y, groupEffectiveSize.width, groupEffectiveSize.height);

        solver.originInParent = origin;
        [solver solveForContainer:groupContainer traitCollection:traitCollection];

        if (group.isVerticalGroup) {
            origin.y += solver.solvedSize.height;
        }

        if (group.isHorizontalGroup) {
            origin.x += solver.solvedSize.width;
        }

        finalBounds = CGRectUnion(finalBounds, solver.frame);
    }

    _solvedSize = finalBounds.size;
}

-(void)solveItemForContainer:(IBPNSCollectionLayoutContainer *)container
             traitCollection:(UITraitCollection *)traitCollection {
    CGSize effectiveSize = [[_layoutItem layoutSize] effectiveSizeForContainer:container];

    if (_hasPreferredSize) {
        if (_layoutItem.layoutSize.widthDimension.isEstimated) {
            effectiveSize.width = _preferredSize.width;
        }

        if (_layoutItem.layoutSize.heightDimension.isEstimated) {
            effectiveSize.height = _preferredSize.height;
        }
    }

    _solvedSize = effectiveSize;
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                           itemIndex:(NSInteger)itemIndex
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    CGRect localVisibleRect = rect;
    localVisibleRect.origin.x -= _originInParent.x;
    localVisibleRect.origin.y -= _originInParent.y;

    __block NSMutableArray<IBPUICollectionViewCompositionalLayoutAttributes *> *allAttributes;
    allAttributes = [[NSMutableArray alloc] init];

    if (_layoutItem.isGroup) {
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
    } else {
        IBPUICollectionViewCompositionalLayoutAttributes *attributes;
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:itemIndex inSection:sectionIndex];
        attributes = [IBPUICollectionViewCompositionalLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attributes.frame = self.frame;

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
        attributes.frame = self.frame;
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

-(NSString *)description {
    return [NSString stringWithFormat:@"solver for %@ <frame = %@>",
            NSStringFromClass([_layoutItem class]),
            [NSValue valueWithCGRect:self.frame]];
}

@end
