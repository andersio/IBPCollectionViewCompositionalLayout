#import "IBPHierarchicalGroupSolver.h"
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
#import "IBPHierarchicalSolver_Private.h"
#import "Misc.h"

@interface IBPHierarchicalGroupSolver (Private)

+(NSArray<IBPHierarchicalSolver *> *)childrenForLayoutGroup:(IBPNSCollectionLayoutGroup *)layoutGroup
                                                        locationInSection:(NSRange)locationInSection;

@end

@implementation IBPHierarchicalGroupSolver {
    NSArray<IBPHierarchicalSolver *> *children;
}

@dynamic layoutItem;

-(instancetype)initWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                 locationInSection:(NSRange)locationInSection {
    NSAssert(layoutItem.isGroup, @"`IBPHierarchicalGroupSolver` can only be used with `IBPNSCollectionLayoutGroup`.");

    self = [super initWithLayoutItem:layoutItem locationInSection:locationInSection];

    if (self) {
        children = [IBPHierarchicalGroupSolver childrenForLayoutGroup:(IBPNSCollectionLayoutGroup *)layoutItem
                                                    locationInSection:locationInSection];
    }

    return self;
}

-(void)solveForContainer:(IBPNSCollectionLayoutContainer *)container traitCollection:(UITraitCollection *)traitCollection {
    CGSize groupEffectiveSize = [[self.layoutItem layoutSize] effectiveSizeForContainer:container];
    IBPNSCollectionLayoutContainer *groupContainer;
    groupContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:groupEffectiveSize
                                                                   contentInsets:IBPNSDirectionalEdgeInsetsZero];

    CGPoint origin = CGPointZero;
    CGRect finalBounds = CGRectZero;

    IBPGroupLayoutDirection layoutDirection = self.layoutItem.layoutDirection;

    for (IBPHierarchicalSolver *solver in children) {
        solver.originInParent = origin;
        [solver solveForContainer:groupContainer traitCollection:traitCollection];

        switch (layoutDirection) {
            case IBPGroupLayoutDirectionVertical:
                origin.y += solver.solvedSize.height;
                break;
            case IBPGroupLayoutDirectionHorizontal:
                origin.x += solver.solvedSize.width;
                break;
            case IBPGroupLayoutDirectionCustom:
                NotImplemented(@"Custom layout group");
        }

        finalBounds = CGRectUnion(finalBounds, solver.frame);
    }

    self.solvedSize = finalBounds.size;
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    CGPoint originInParent = self.originInParent;

    CGRect localVisibleRect = rect;
    localVisibleRect.origin.x -= originInParent.x;
    localVisibleRect.origin.y -= originInParent.y;

    __block NSMutableArray<IBPUICollectionViewCompositionalLayoutAttributes *> *allAttributes;
    allAttributes = [[NSMutableArray alloc] init];

    [children enumerateObjectsUsingBlock:^(IBPHierarchicalSolver * _Nonnull solver, NSUInteger idx, BOOL * _Nonnull stop) {
        if (CGRectIntersectsRect(solver.frame, localVisibleRect)) {
            [allAttributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:localVisibleRect
                                                                               sectionIndex:sectionIndex]];
        }
    }];

    [allAttributes enumerateObjectsUsingBlock:^(IBPUICollectionViewCompositionalLayoutAttributes * _Nonnull attributes, NSUInteger idx, BOOL * _Nonnull stop) {
        CGRect frame = attributes.frame;
        frame.origin = CGPointMake(frame.origin.x + originInParent.x, frame.origin.y + originInParent.y);
        attributes.frame = frame;
    }];

    return allAttributes;
}

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex {
    IBPNSCollectionLayoutGroup *group = (typeof(group)) self.layoutItem;

    CGVector delta = CGVectorZero;
    NSInteger solverIndex = 0;

    for (solverIndex = 0; solverIndex < children.count; solverIndex++) {
        IBPHierarchicalSolver *solver = children[solverIndex];

        if (NSLocationInRange(itemIndex, solver.locationInSection)) {
            delta = [solver setPreferredSize:preferredSize forItemAtIndex:itemIndex];
            break;
        }
    }

    if (!CGVectorEqual(delta, CGVectorZero)) {
        IBPGroupLayoutDirection layoutDirection = self.layoutItem.layoutDirection;

        for (NSInteger i = solverIndex + 1; i < children.count; i++) {
            IBPHierarchicalSolver *solver = children[i];

            switch (layoutDirection) {
                case IBPGroupLayoutDirectionVertical:
                    solver.originInParent = CGPointOffsetY(delta.dy, solver.originInParent);
                    break;
                case IBPGroupLayoutDirectionHorizontal:
                    solver.originInParent = CGPointOffsetX(delta.dx, solver.originInParent);
                    break;
                case IBPGroupLayoutDirectionCustom:
                    NotImplemented(@"Custom layout group");
            }
        }

        // Recompute the bounds.
        CGRect bounds = CGRectZero;

        for (IBPHierarchicalSolver *solver in children) {
            bounds = CGRectUnion(bounds, solver.frame);
        }

        CGSize oldSize = self.solvedSize;
        self.solvedSize = bounds.size;
        CGSize newSize = self.solvedSize;

        return CGVectorMake(newSize.width - oldSize.width, newSize.height - oldSize.height);
    }

    return CGVectorZero;
}

+(NSArray<IBPHierarchicalSolver *> *)childrenForLayoutGroup:(IBPNSCollectionLayoutGroup *)layoutGroup
                                                        locationInSection:(NSRange)locationInSection {
    NSMutableArray *children = [[NSMutableArray alloc] init];
    __block NSInteger cursor = locationInSection.location;
    NSInteger endIndex = NSMaxRange(locationInSection);

    [layoutGroup enumerateItemsWithHandler:^(IBPNSCollectionLayoutItem * _Nonnull item, BOOL * _Nonnull stop) {
        NSInteger leafItemCount = [item leafItemCount];
        NSRange localRange = NSIntersectionRange(NSMakeRange(cursor, leafItemCount), locationInSection);
        cursor += leafItemCount;

        IBPHierarchicalSolver *childSolver;
        childSolver = [IBPHierarchicalSolver solverWithLayoutItem:item
                                                locationInSection:localRange];
        [children addObject:childSolver];

        if (cursor >= endIndex) {
            *stop = YES;
        }
    }];

    return children;
}

@end
