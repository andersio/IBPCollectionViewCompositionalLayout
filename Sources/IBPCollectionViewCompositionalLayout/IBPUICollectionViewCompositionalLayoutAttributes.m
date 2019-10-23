#import "IBPUICollectionViewCompositionalLayoutAttributes.h"
#import "IBPNSCollectionLayoutSize.h"
#import "IBPNSCollectionLayoutDimension.h"
#import <UIKit/UIKit.h>

@implementation IBPUICollectionViewCompositionalLayoutAttributes
@synthesize layoutSize;

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

-(id)copyWithZone:(NSZone *)zone {
    IBPUICollectionViewCompositionalLayoutAttributes *copy = [super copyWithZone:zone];
    copy.layoutSize = layoutSize;
    return copy;
}

@end
