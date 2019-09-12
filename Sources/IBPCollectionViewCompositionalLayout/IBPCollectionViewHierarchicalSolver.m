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
#import "CGVectorExtensions.h"

@interface IBPCollectionViewHierarchicalSolver (Private)

-(void)createChildren;
-(void)solveItemForProposedRect:(CGSize)proposedSize traitCollection:(UITraitCollection *)traitCollection;
-(void)solveGroup:(IBPNSCollectionLayoutGroup*)group forProposedRect:(CGSize)proposedSize traitCollection:(UITraitCollection *)traitCollection;
-(void)updateSolvedSizeIfNeeded;

@end

@implementation IBPCollectionViewHierarchicalSolver

+(instancetype)solverWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                  locationInSection:(NSRange)locationInSection {
    IBPCollectionViewHierarchicalSolver *solver = [[self alloc] init];

    if (solver) {
        solver->_hasPreferredSize = NO;
        solver->_preferredSize = CGSizeZero;
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
    _solvedSize = [[_layoutItem layoutSize] effectiveSizeForContainer:container];
    [self updateSolvedSizeIfNeeded];
}

-(void)updateSolvedSizeIfNeeded {
    assert(!_layoutItem.isGroup);

    if (_hasPreferredSize) {
        if (_layoutItem.layoutSize.widthDimension.isEstimated) {
            _solvedSize.width = _preferredSize.width;
        }

        if (_layoutItem.layoutSize.heightDimension.isEstimated) {
            _solvedSize.height = _preferredSize.height;
        }
    }
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    CGRect localVisibleRect = rect;
    localVisibleRect.origin.x -= _originInParent.x;
    localVisibleRect.origin.y -= _originInParent.y;

    __block NSMutableArray<IBPUICollectionViewCompositionalLayoutAttributes *> *allAttributes;
    allAttributes = [[NSMutableArray alloc] init];

    if (_layoutItem.isGroup) {
        [_children enumerateObjectsUsingBlock:^(IBPCollectionViewHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
            if (CGRectIntersectsRect(solver.frame, localVisibleRect)) {
                [allAttributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:localVisibleRect
                                                                                   sectionIndex:sectionIndex]];
            }
        }];

        [allAttributes enumerateObjectsUsingBlock:^(IBPUICollectionViewCompositionalLayoutAttributes * _Nonnull attributes, NSUInteger idx, BOOL * _Nonnull stop) {
            CGRect frame = attributes.frame;
            frame.origin = CGPointMake(frame.origin.x + _originInParent.x, frame.origin.y + _originInParent.y);
            attributes.frame = frame;
        }];
    } else {
        IBPUICollectionViewCompositionalLayoutAttributes *attributes;
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:_locationInSection.location inSection:sectionIndex];
        attributes = [IBPUICollectionViewCompositionalLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        attributes.frame = self.frame;
        attributes.layoutSize = !_hasPreferredSize ? self.layoutItem.layoutSize : nil;

        [allAttributes addObject:attributes];
    }

    return allAttributes;
}

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex {
    if (![_layoutItem isGroup]) {
        if (self.hasPreferredSize) {
            // Reject a new preferred size if a preferred size has been set & has not been invalidated.
            return CGVectorZero;
        }

        self->_hasPreferredSize = YES;
        self->_preferredSize = preferredSize;

        CGSize oldSize = _solvedSize;
        [self updateSolvedSizeIfNeeded];
        CGSize newSize = _solvedSize;

        return CGVectorMake(newSize.width - oldSize.width, newSize.height - oldSize.height);
    }

    IBPNSCollectionLayoutGroup *group = (typeof(group)) _layoutItem;

    CGVector delta = CGVectorZero;
    NSInteger solverIndex = 0;

    for (solverIndex = 0; solverIndex < _children.count; solverIndex++) {
        IBPCollectionViewHierarchicalSolver *solver = _children[solverIndex];

        if (NSLocationInRange(itemIndex, solver.locationInSection)) {
            delta = [solver setPreferredSize:preferredSize forItemAtIndex:itemIndex];
            break;
        }
    }

    if (!CGVectorEqual(delta, CGVectorZero)) {
        for (NSInteger i = solverIndex + 1; i < _children.count; i++) {
            IBPCollectionViewHierarchicalSolver *solver = _children[i];

            if ([group isHorizontalGroup]) {
                solver.originInParent = CGPointOffsetX(delta.dx, solver.originInParent);
            }

            if ([group isVerticalGroup]) {
                solver.originInParent = CGPointOffsetY(delta.dy, solver.originInParent);
            }
        }

        // Recompute the bounds.
        CGRect bounds = CGRectZero;

        for (IBPCollectionViewHierarchicalSolver *solver in _children) {
            bounds = CGRectUnion(bounds, solver.frame);
        }

        CGSize oldSize = _solvedSize;
        _solvedSize = bounds.size;
        return CGVectorMake(_solvedSize.width - oldSize.width, _solvedSize.height - oldSize.height);
    }

    return CGVectorZero;
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
