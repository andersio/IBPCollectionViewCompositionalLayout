#import <UIKit/UIKit.h>
#import "UICollectionReusableView+Swizzing.h"
#import "IBPUICollectionViewCompositionalLayoutAttributes.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutDimension.h"
#import <objc/runtime.h>

typedef IBPUICollectionViewCompositionalLayoutAttributes LayoutAttributes;

@interface UICollectionReusableView (Private)

- (UICollectionViewLayoutAttributes *)ibp_configurablePreferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes;
- (UICollectionViewLayoutAttributes *)ibp_originalPreferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes;

@end

@implementation UICollectionReusableView (UICollectionViewReusableView)

+(void)ibp_swizzle {
    SEL canonicalSelector = @selector(preferredLayoutAttributesFittingAttributes:);
    SEL newImplSelector = @selector(ibp_configurablePreferredLayoutAttributesFittingAttributes:);
    SEL originalImplSelector = @selector(ibp_originalPreferredLayoutAttributesFittingAttributes:);

    Method method = class_getInstanceMethod([UICollectionReusableView class], canonicalSelector);
    const char *types = method_getTypeEncoding(method);
    class_replaceMethod([UICollectionReusableView class], originalImplSelector, method_getImplementation(method), types);

    IMP newImpl = class_getMethodImplementation([UICollectionReusableView class], newImplSelector);
    class_replaceMethod([UICollectionReusableView class], canonicalSelector, newImpl, types);
}

- (UICollectionViewLayoutAttributes *)ibp_configurablePreferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes {
    UICollectionViewLayoutAttributes *preferred = [self ibp_originalPreferredLayoutAttributesFittingAttributes:layoutAttributes];

    if ([preferred isKindOfClass:[LayoutAttributes class]]) {
        [self updateLayoutAttributes:(LayoutAttributes *)preferred withOriginalAttributes:(LayoutAttributes *)layoutAttributes];
    }

    return preferred;
}

- (void)updateLayoutAttributes:(LayoutAttributes *)attributes withOriginalAttributes:(LayoutAttributes *)originalAttributes {
    if (![attributes isEstimated]) {
        return;
    }

    IBPNSCollectionLayoutSize *layoutSize = [attributes layoutSize];

    UIView *sizingView = ([self isKindOfClass:[UICollectionViewCell class]] ? [(UICollectionViewCell *)self contentView] : self);
    CGRect frame = originalAttributes.frame;
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
