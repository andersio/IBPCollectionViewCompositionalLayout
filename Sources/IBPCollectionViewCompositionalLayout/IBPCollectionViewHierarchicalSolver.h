#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IBPNSCollectionLayoutItem.h"
#import "IBPNSCollectionLayoutContainer.h"
#import "IBPUICollectionViewCompositionalLayoutAttributes.h"

NS_ASSUME_NONNULL_BEGIN

@interface IBPCollectionViewHierarchicalSolver : NSObject

@property (nonatomic, strong) IBPNSCollectionLayoutItem *layoutItem;
@property (nonatomic, strong) NSMutableArray<IBPCollectionViewHierarchicalSolver *> *children;
@property (nonatomic) NSRange locationInSection;

// Frame (in parent coordinate space).
@property (nonatomic) CGSize solvedSize;
@property (nonatomic) CGPoint originInParent;

@property (nonatomic, readonly) CGRect frame;

// Capture the preferred size reported by the UICollectionView.
@property (nonatomic, readonly) BOOL hasPreferredSize;
@property (nonatomic, readonly) CGSize preferredSize;

+(instancetype)solverWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                  locationInSection:(NSRange)locationInSection;

- (void)solveForContainer:(IBPNSCollectionLayoutContainer *)container
             traitCollection:(UITraitCollection *)traitCollection;

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex;

- (IBPUICollectionViewCompositionalLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath;

- (NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                            itemIndex:(NSInteger)itemIndex
                                                                                         sectionIndex:(NSInteger)sectionIndex;

@end

NS_ASSUME_NONNULL_END
