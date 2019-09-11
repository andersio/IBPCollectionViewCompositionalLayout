#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UICollectionReusableView (IBPUICollectionViewCompositionalLayout)

- (UICollectionViewLayoutAttributes *)ibp_configurablePreferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes;
- (UICollectionViewLayoutAttributes *)ibp_originalPreferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes;

@end

NS_ASSUME_NONNULL_END
