#import "IBPHierarchicalLeafItemSolver.h"
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

@interface IBPHierarchicalLeafItemSolver (Private)

-(void)updateSolvedSizeIfNeeded;

@end

@implementation IBPHierarchicalLeafItemSolver {
    // Capture the preferred size reported by the UICollectionView.
    BOOL hasPreferredSize;
    CGSize preferredSize;
}

-(instancetype)initWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                locationInSection:(NSRange)locationInSection {
    NSAssert(!layoutItem.isGroup, @"Use `IBPHierarchicalGroupSolver` for groups.");

    self = [super initWithLayoutItem:layoutItem locationInSection:locationInSection];

    if (self) {
        hasPreferredSize = NO;
        preferredSize = CGSizeZero;
    }

    return self;
}

-(void)solveForContainer:(IBPNSCollectionLayoutContainer *)container traitCollection:(UITraitCollection *)traitCollection {
    self.solvedSize = [[self.layoutItem layoutSize] effectiveSizeForContainer:container];
    [self updateSolvedSizeIfNeeded];
}

-(void)updateSolvedSizeIfNeeded {
    if (hasPreferredSize) {
        IBPNSCollectionLayoutSize *layoutSize = self.layoutItem.layoutSize;
        CGSize solvedSize = self.solvedSize;

        if (layoutSize.widthDimension.isEstimated) {
            solvedSize.width = preferredSize.width;
        }

        if (layoutSize.heightDimension.isEstimated) {
            solvedSize.height = preferredSize.height;
        }

        self.solvedSize = solvedSize;
    }
}

-(NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                        sectionIndex:(NSInteger)sectionIndex {
    CGPoint originInParent = self.originInParent;

    CGRect localVisibleRect = rect;
    localVisibleRect.origin.x -= originInParent.x;
    localVisibleRect.origin.y -= originInParent.y;

    IBPUICollectionViewCompositionalLayoutAttributes *attributes;
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:self.locationInSection.location inSection:sectionIndex];
    attributes = [IBPUICollectionViewCompositionalLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
    attributes.frame = self.frame;
    attributes.layoutSize = !hasPreferredSize ? self.layoutItem.layoutSize : nil;

    return [NSArray arrayWithObject:attributes];
}

- (CGVector)setPreferredSize:(CGSize)size forItemAtIndex:(NSInteger)itemIndex {
    if (hasPreferredSize) {
        // Reject a new preferred size if a preferred size has been set & has not been invalidated.
        return CGVectorZero;
    }

    hasPreferredSize = YES;
    preferredSize = size;

    CGSize oldSize = self.solvedSize;
    [self updateSolvedSizeIfNeeded];
    CGSize newSize = self.solvedSize;

    return CGVectorMake(newSize.width - oldSize.width, newSize.height - oldSize.height);
}

@end
