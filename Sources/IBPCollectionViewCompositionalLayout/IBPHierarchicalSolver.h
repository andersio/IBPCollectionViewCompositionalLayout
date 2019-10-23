#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IBPNSCollectionLayoutItem.h"
#import "IBPNSCollectionLayoutContainer.h"
#import "IBPUICollectionViewCompositionalLayoutAttributes.h"

NS_ASSUME_NONNULL_BEGIN

@interface IBPHierarchicalSolver : NSObject

@property (nonatomic, strong) IBPNSCollectionLayoutItem *layoutItem;
@property (nonatomic) NSRange locationInSection;

// Frame (in parent coordinate space).
@property (nonatomic) CGSize solvedSize;
@property (nonatomic) CGPoint originInParent;

@property (nonatomic, readonly) CGRect frame;

+(IBPHierarchicalSolver *)solverWithLayoutItem:(IBPNSCollectionLayoutItem *)layoutItem
                                           locationInSection:(NSRange)locationInSection;

- (void)solveForContainer:(IBPNSCollectionLayoutContainer *)container
             traitCollection:(UITraitCollection *)traitCollection;

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex;

- (NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect
                                                                                         sectionIndex:(NSInteger)sectionIndex;

@end

NS_ASSUME_NONNULL_END
