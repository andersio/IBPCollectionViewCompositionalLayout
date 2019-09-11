#import <UIKit/UIKit.h>
#import "IBPNSCollectionLayoutSize.h"

NS_ASSUME_NONNULL_BEGIN

@interface IBPUICollectionViewCompositionalLayoutAttributes : UICollectionViewLayoutAttributes

@property (strong, nonatomic, nullable) IBPNSCollectionLayoutSize *layoutSize;
@property (nonatomic) BOOL isInvalidatingSucceedingElements;
@property (nonatomic) CGVector deltaForSucceedingElements;

-(BOOL) isEstimated;
-(void)updateLayoutSizeWithPreferredAttributes:(IBPUICollectionViewCompositionalLayoutAttributes *)preferredAttributes;

@end

NS_ASSUME_NONNULL_END
