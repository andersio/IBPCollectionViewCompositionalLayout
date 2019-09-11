#import "IBPUICollectionViewCompositionalLayoutAttributes.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutDimension.h"
#import <UIKit/UIKit.h>

@implementation IBPUICollectionViewCompositionalLayoutAttributes
@synthesize layoutSize, isInvalidatingSucceedingElements, deltaForSucceedingElements;

-(instancetype)init {
    self = [super init];

    if (self) {
        layoutSize = nil;
    }

    return self;
}

-(BOOL)isEstimated {
    return [[layoutSize widthDimension] isEstimated] || [[layoutSize heightDimension] isEstimated];
}

-(void)updateLayoutSizeWithPreferredAttributes:(IBPUICollectionViewCompositionalLayoutAttributes *)preferredAttributes {
    CGRect frame = self.frame;
    CGVector delta = CGVectorMake(0.0, 0.0);

    if ([[layoutSize widthDimension] isEstimated]) {
        delta.dx = preferredAttributes.size.width - frame.size.width;
        frame.size.width = preferredAttributes.size.width;
    }

    if ([[layoutSize heightDimension] isEstimated]) {
        delta.dy = preferredAttributes.size.height - frame.size.height;
        frame.size.height = preferredAttributes.size.height;
    }

    self.layoutSize = nil;
    self.isInvalidatingSucceedingElements = delta.dy != 0 || delta.dx != 0;
    self.deltaForSucceedingElements = delta;
    self.frame = frame;
}

-(id)copyWithZone:(NSZone *)zone {
    IBPUICollectionViewCompositionalLayoutAttributes *copy = [super copyWithZone:zone];
    copy.layoutSize = layoutSize;
    return copy;
}

@end
