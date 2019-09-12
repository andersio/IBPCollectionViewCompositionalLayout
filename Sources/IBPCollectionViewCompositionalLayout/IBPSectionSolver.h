#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "IBPNSCollectionLayoutSection.h"
#import "IBPNSCollectionLayoutContainer.h"
#import "IBPUICollectionViewCompositionalLayoutAttributes.h"
#import "IBPHierarchicalSolver.h"

NS_ASSUME_NONNULL_BEGIN

@interface IBPSectionSolver : NSObject

@property (nonatomic, strong) IBPNSCollectionLayoutSection *layoutSection;
@property (nonatomic, strong) NSMutableArray<IBPHierarchicalSolver *> *children;

// Frame (in parent coordinate space).
@property (nonatomic) CGSize solvedSize;
@property (nonatomic) CGPoint originInParent;
@property (nonatomic, readonly) CGRect frame;

@property (nonatomic) UICollectionViewScrollDirection layoutAxis;

+(instancetype)solverWithLayoutSection:(IBPNSCollectionLayoutSection *)layoutSection
                            layoutAxis:(UICollectionViewScrollDirection)layoutAxis
                         numberOfItems:(NSInteger)numberOfItems;

- (void)solveForContainer:(IBPNSCollectionLayoutContainer *)container
             traitCollection:(UITraitCollection *)traitCollection;

- (CGVector)setPreferredSize:(CGSize)preferredSize forItemAtIndex:(NSInteger)itemIndex;

- (NSArray<IBPUICollectionViewCompositionalLayoutAttributes *> *)layoutAttributesForItemInVisibleRect:(CGRect)rect forSectionAtIndex:(NSInteger)sectionIndex;

@end

NS_ASSUME_NONNULL_END
