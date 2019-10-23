#import <UIKit/UIKit.h>
#import "IBPNSCollectionLayoutSize.h"

NS_ASSUME_NONNULL_BEGIN

@interface IBPUICollectionViewCompositionalLayoutAttributes : UICollectionViewLayoutAttributes

@property (strong, nonatomic, nullable) IBPNSCollectionLayoutSize *layoutSize;

-(BOOL) isEstimated;

@end

NS_ASSUME_NONNULL_END
