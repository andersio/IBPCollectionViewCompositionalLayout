#import <UIKit/UIKit.h>
#import "UICollectionReusableView+UICollectionViewReusableView.h"
#import "IBPUICollectionViewCompositionalLayoutAttributes.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutDimension.h"

typedef IBPUICollectionViewCompositionalLayoutAttributes LayoutAttributes;

@implementation UICollectionReusableView (UICollectionViewReusableView)

- (UICollectionViewLayoutAttributes *)ibp_configurablePreferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes {
    UICollectionViewLayoutAttributes *preferred = [self ibp_originalPreferredLayoutAttributesFittingAttributes:layoutAttributes];

    if ([preferred isKindOfClass:[LayoutAttributes class]]) {
        [self updateLayoutAttributes:(LayoutAttributes *) layoutAttributes];
    }

    return preferred;
}

- (void)updateLayoutAttributes:(LayoutAttributes *)attributes {
    if (![attributes isEstimated]) {
        return;
    }

    IBPNSCollectionLayoutSize *layoutSize = [attributes layoutSize];

    UIView *sizingView = ([self isKindOfClass:[UICollectionViewCell class]] ? [(UICollectionViewCell *)self contentView] : self);
    CGRect frame = attributes.frame;
    CGSize querySize = frame.size;
    UILayoutPriority horizontalFittingPriority = UILayoutPriorityRequired;
    UILayoutPriority verticalFittingPriority = UILayoutPriorityRequired;

    if ([[layoutSize widthDimension] isEstimated]) {
        querySize.width = UILayoutFittingCompressedSize.width;
        horizontalFittingPriority = UILayoutPriorityFittingSizeLevel;
    }

    if ([[layoutSize heightDimension] isEstimated]) {
        querySize.height = UILayoutFittingCompressedSize.height;
        verticalFittingPriority = UILayoutPriorityFittingSizeLevel;
    }

    frame.size = [sizingView systemLayoutSizeFittingSize:querySize
                           withHorizontalFittingPriority:horizontalFittingPriority
                                 verticalFittingPriority:verticalFittingPriority];

    attributes.frame = frame;
}

@end
