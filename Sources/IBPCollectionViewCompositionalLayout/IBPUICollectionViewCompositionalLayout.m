#import "IBPUICollectionViewCompositionalLayout.h"
#import "IBPCollectionCompositionalLayoutSolver.h"
#import "IBPCollectionViewOrthogonalScrollerEmbeddedScrollView.h"
#import "IBPCollectionViewOrthogonalScrollerSectionController.h"
#import "IBPNSCollectionLayoutAnchor_Private.h"
#import "IBPNSCollectionLayoutBoundarySupplementaryItem.h"
#import "IBPNSCollectionLayoutContainer.h"
#import "IBPNSCollectionLayoutDecorationItem.h"
#import "IBPNSCollectionLayoutDimension.h"
#import "IBPNSCollectionLayoutEnvironment.h"
#import "IBPNSCollectionLayoutGroup_Private.h"
#import "IBPNSCollectionLayoutItem_Private.h"
#import "IBPNSCollectionLayoutSection_Private.h"
#import "IBPNSCollectionLayoutSize_Private.h"
#import "IBPNSCollectionLayoutSpacing.h"
#import "IBPNSCollectionLayoutSupplementaryItem_Private.h"
#import "IBPUICollectionViewCompositionalLayoutConfiguration_Private.h"
#import "IBPUICollectionViewCompositionalLayoutAttributes.h"
#import <objc/runtime.h>
#import "IBPCollectionViewHierarchicalSolver.h"
#import "IBPCollectionViewHierarchicalSectionSolver.h"

typedef IBPUICollectionViewCompositionalLayoutAttributes LayoutAttributes;
NSInteger BoundaryItemIndex = 0;
CGVector CGVectorAdd(CGVector lhs, CGVector rhs);
CGRect CGRectTranslate(CGRect original, CGVector delta);
NSArray<LayoutAttributes *> * _Nonnull SearchMinEdgeAlignedElements(NSArray<LayoutAttributes *> * _Nonnull attributes, NSInteger index, UICollectionViewScrollDirection direction, NSInteger *outSliceIndex);

@interface IBPUICollectionViewCompositionalLayout()<UICollectionViewDelegate> {

    NSMutableArray<IBPCollectionViewHierarchicalSectionSolver *> *sectionSolvers;
    NSMutableDictionary<NSIndexPath *, LayoutAttributes *> *cachedItemAttributes;
    NSMutableDictionary<NSString *, LayoutAttributes *> *cachedBoundarySupplementaryAttributes;
    NSMutableDictionary<NSString *, LayoutAttributes *> *cachedSupplementaryAttributes;
    NSMutableDictionary<NSString *, LayoutAttributes *> *cachedDecorationAttributes;
    NSMutableArray<IBPNSCollectionLayoutSupplementaryItem *> *globalSupplementaryItems;
    NSMutableArray<LayoutAttributes *> *layoutAttributesForPinnedSupplementaryItems;

    CGRect contentFrame;
    NSMutableDictionary<NSNumber *, IBPCollectionViewOrthogonalScrollerSectionController *> *orthogonalScrollerSectionControllers;
}

@property (nonatomic, copy) IBPNSCollectionLayoutSection *layoutSection;
@property (nonatomic) IBPUICollectionViewCompositionalLayoutSectionProvider layoutSectionProvider;

@property (nonatomic, weak) IBPUICollectionViewCompositionalLayout *parent;
@property (nonatomic, copy) IBPNSCollectionLayoutSection *containerSection;

@property (nonatomic, readonly) UICollectionViewScrollDirection scrollDirection;
@property (nonatomic) BOOL hasPinnedSupplementaryItems;
@property (nonatomic) BOOL shouldReset;

@property (nonatomic, weak) id<UICollectionViewDelegate> collectionViewDelegate;

@end

@implementation IBPUICollectionViewCompositionalLayout

+(void)initialize {
    // Who doesn't love swizzling?

    SEL canonicalSelector = @selector(preferredLayoutAttributesFittingAttributes:);
    SEL newImplSelector = @selector(ibp_configurablePreferredLayoutAttributesFittingAttributes:);
    SEL originalImplSelector = @selector(ibp_originalPreferredLayoutAttributesFittingAttributes:);

    Method method = class_getInstanceMethod([UICollectionReusableView class], canonicalSelector);
    char *types = method_getTypeEncoding(method);
    class_replaceMethod([UICollectionReusableView class], originalImplSelector, method_getImplementation(method), types);

    IMP newImpl = class_getMethodImplementation([UICollectionReusableView class], newImplSelector);
    class_replaceMethod([UICollectionReusableView class], canonicalSelector, newImpl, types);
}

- (instancetype)initWithSection:(IBPNSCollectionLayoutSection *)section {
    if (@available(iOS 13, *)) {
        return [[NSClassFromString(@"UICollectionViewCompositionalLayout") alloc] initWithSection:section];
    } else {
        IBPUICollectionViewCompositionalLayoutConfiguration *configuration = [IBPUICollectionViewCompositionalLayoutConfiguration defaultConfiguration];
        return [self initWithSection:section configuration:configuration];
    }
}

- (instancetype)initWithSection:(IBPNSCollectionLayoutSection *)section
                  configuration:(IBPUICollectionViewCompositionalLayoutConfiguration *)configuration {
    if (@available(iOS 13, *)) {
        return [[NSClassFromString(@"UICollectionViewCompositionalLayout") alloc] initWithSection:section configuration:configuration];
    } else {
        return [self initWithSection:section sectionProvider:nil configuration:configuration];
    }
}

- (instancetype)initWithSectionProvider:(IBPUICollectionViewCompositionalLayoutSectionProvider)sectionProvider {
    if (@available(iOS 13, *)) {
        return [[NSClassFromString(@"UICollectionViewCompositionalLayout") alloc] initWithSectionProvider:sectionProvider];
    } else {
        IBPUICollectionViewCompositionalLayoutConfiguration *configuration = [IBPUICollectionViewCompositionalLayoutConfiguration defaultConfiguration];
        return [self initWithSectionProvider:sectionProvider configuration:configuration];
    }
}

- (instancetype)initWithSectionProvider:(IBPUICollectionViewCompositionalLayoutSectionProvider)sectionProvider
                          configuration:(IBPUICollectionViewCompositionalLayoutConfiguration *)configuration {
    if (@available(iOS 13, *)) {
        return [[NSClassFromString(@"UICollectionViewCompositionalLayout") alloc] initWithSectionProvider:sectionProvider configuration:configuration];
    } else {
        return [self initWithSection:nil sectionProvider:sectionProvider configuration:configuration];
    }
}

- (instancetype)initWithSection:(IBPNSCollectionLayoutSection *)section
                sectionProvider:(IBPUICollectionViewCompositionalLayoutSectionProvider)sectionProvider
                  configuration:(IBPUICollectionViewCompositionalLayoutConfiguration *)configuration {
    self = [super init];
    if (self) {
        self.layoutSection = section;
        self.layoutSectionProvider = sectionProvider;
        self.configuration = configuration;

        self.shouldReset = NO;
        cachedItemAttributes = [[NSMutableDictionary alloc] init];
        cachedSupplementaryAttributes = [[NSMutableDictionary alloc] init];
        cachedBoundarySupplementaryAttributes = [[NSMutableDictionary alloc] init];
        cachedDecorationAttributes = [[NSMutableDictionary alloc] init];
        globalSupplementaryItems = [[NSMutableArray alloc] init];
        layoutAttributesForPinnedSupplementaryItems = [[NSMutableArray alloc] init];
        orthogonalScrollerSectionControllers = [[NSMutableDictionary alloc] init];
        sectionSolvers = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (Class)layoutAttributesClass {
    return [LayoutAttributes class];
}

- (void)setConfiguration:(IBPUICollectionViewCompositionalLayoutConfiguration *)configuration {
    _configuration = configuration;
    [self invalidateLayout];
}

- (UICollectionViewScrollDirection)scrollDirection {
    return self.configuration.scrollDirection;
}

- (void)resetState {
    [cachedItemAttributes removeAllObjects];
    [cachedSupplementaryAttributes removeAllObjects];
    [cachedBoundarySupplementaryAttributes removeAllObjects];
    [cachedDecorationAttributes removeAllObjects];
    [globalSupplementaryItems removeAllObjects];
    [layoutAttributesForPinnedSupplementaryItems removeAllObjects];
    self.hasPinnedSupplementaryItems = NO;

    [[orthogonalScrollerSectionControllers allValues] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [orthogonalScrollerSectionControllers removeAllObjects];

    [sectionSolvers removeAllObjects];
}

- (void)prepareLayout {
    [super prepareLayout];

    if (!self.shouldReset) {
        return;
    }

    self.shouldReset = NO;

    UICollectionView *collectionView = self.collectionView;
    if (!collectionView) {
        return;
    }
    CGRect collectionViewBounds = collectionView.bounds;
    if (CGRectIsEmpty(collectionViewBounds)) {
        return;
    }

    if (!self.collectionViewDelegate && collectionView.delegate != self) {
        self.collectionViewDelegate = collectionView.delegate;
        collectionView.delegate = self;
    }

    [self resetState];

    UIEdgeInsets collectionContentInset = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        if ([collectionView respondsToSelector:@selector(safeAreaInsets)]) {
            collectionContentInset = collectionView.safeAreaInsets;
        }
    }

    IBPNSCollectionLayoutContainer *collectionContainer;
    if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
        IBPNSDirectionalEdgeInsets insets = IBPNSDirectionalEdgeInsetsMake(0, collectionContentInset.left, 0, collectionContentInset.right);
        collectionContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:collectionViewBounds.size contentInsets:insets];
    }
    if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        IBPNSDirectionalEdgeInsets insets = IBPNSDirectionalEdgeInsetsMake(collectionContentInset.top, 0, collectionContentInset.bottom, 0);
        collectionContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:collectionViewBounds.size contentInsets:insets];
    }

    IBPNSCollectionLayoutEnvironment *environment = [[IBPNSCollectionLayoutEnvironment alloc] init];
    environment.container = collectionContainer;
    environment.traitCollection = collectionView.traitCollection;

    contentFrame = CGRectZero;
    contentFrame.origin.x = collectionContainer.effectiveContentInsets.leading;
    contentFrame.origin.y = collectionContainer.effectiveContentInsets.top;

    switch (self.scrollDirection) {
        case UICollectionViewScrollDirectionVertical:
            contentFrame.size.width = collectionViewBounds.size.width;
            break;
        case UICollectionViewScrollDirectionHorizontal:
            contentFrame.size.height = collectionViewBounds.size.height;
            break;
    }

    for (NSInteger sectionIndex = 0; sectionIndex < collectionView.numberOfSections; sectionIndex++) {
        IBPNSCollectionLayoutSection *layoutSection = self.layoutSectionProvider ? self.layoutSectionProvider(sectionIndex, environment) : self.layoutSection;

        CGPoint sectionOrigin = contentFrame.origin;
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            sectionOrigin.y = CGRectGetMaxY(contentFrame);
        }
        if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            sectionOrigin.x = CGRectGetMaxX(contentFrame);
        }

        NSInteger numberOfItems = [collectionView numberOfItemsInSection:sectionIndex];

        IBPCollectionViewHierarchicalSectionSolver *sectionRootSolver;
        sectionRootSolver = [IBPCollectionViewHierarchicalSectionSolver solverWithLayoutSection:layoutSection
                                                                                     layoutAxis:self.scrollDirection
                                                                                  numberOfItems:numberOfItems];
        [sectionRootSolver solveForProposedRect:CGRectMake(sectionOrigin.x, sectionOrigin.y, collectionViewBounds.size.width, collectionViewBounds.size.height)
                                traitCollection:collectionView.traitCollection];
        [sectionSolvers addObject:sectionRootSolver];

        switch (self.scrollDirection) {
            case UICollectionViewScrollDirectionVertical:
                contentFrame.size.height += sectionRootSolver.frame.size.height;
                break;
            case UICollectionViewScrollDirectionHorizontal:
                contentFrame.size.width += sectionRootSolver.frame.size.width;
                break;
        }

        if (layoutSection.scrollsOrthogonally) {
            IBPCollectionViewOrthogonalScrollerSectionController *controller = orthogonalScrollerSectionControllers[@(sectionIndex)];

            UICollectionView *scrollView = [self setupOrthogonalScrollViewForSection:layoutSection];
            if (@available(iOS 11.0, *)) {
                if ([scrollView respondsToSelector:@selector(setContentInsetAdjustmentBehavior:)] && [collectionView respondsToSelector:@selector(contentInsetAdjustmentBehavior)]) {
                    scrollView.contentInsetAdjustmentBehavior = collectionView.contentInsetAdjustmentBehavior;
                }
            }

            CGRect scrollViewFrame = CGRectZero;
            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                scrollViewFrame.origin.y = sectionOrigin.y + layoutSection.contentInsets.top;
                scrollViewFrame.size.width = collectionContainer.contentSize.width;
                scrollViewFrame.size.height = MIN(sectionRootSolver.frame.size.height, collectionContainer.contentSize.height);
            }
            if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
                scrollViewFrame.origin.x = sectionOrigin.x + layoutSection.contentInsets.leading;
                scrollViewFrame.size.width = MIN(sectionRootSolver.frame.size.width, collectionContainer.contentSize.width);
                scrollViewFrame.size.height = collectionContainer.contentSize.height;
            }
            scrollView.frame = scrollViewFrame;

            contentFrame = CGRectUnion(contentFrame, scrollViewFrame);

            if (layoutSection.orthogonalScrollingBehavior == IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered) {
                CGSize groupSize = [layoutSection.group.layoutSize effectiveSizeForContainer:collectionContainer];
                if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                    CGFloat inset = (collectionContainer.contentSize.width - groupSize.width) / 2;
                    scrollView.contentInset = UIEdgeInsetsMake(0, inset, 0, 0);
                }
                if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
                    CGFloat inset = (collectionContainer.contentSize.height - groupSize.height) / 2;
                    scrollView.contentInset = UIEdgeInsetsMake(inset, 0, 0, 0);
                }
            }

            [collectionView addSubview:scrollView];

            controller = [[IBPCollectionViewOrthogonalScrollerSectionController alloc] initWithSectionIndex:sectionIndex collectionView:self.collectionView scrollView:scrollView];
            orthogonalScrollerSectionControllers[@(sectionIndex)] = controller;
        }

//        CGSize extendedBoundary = CGSizeZero;
//        for (IBPNSCollectionLayoutBoundarySupplementaryItem *boundaryItem in layoutSection.boundarySupplementaryItems) {
//            CGRect containerFrame = CGRectZero;
//            containerFrame.size = collectionContainer.contentSize;
//
//            IBPNSDirectionalEdgeInsets boundaryInsets = boundaryItem.contentInsets;
//            if (layoutSection.supplementariesFollowContentInsets) {
//                boundaryInsets.top += layoutSection.contentInsets.top;
//                boundaryInsets.bottom += layoutSection.contentInsets.bottom;
//                boundaryInsets.leading += layoutSection.contentInsets.leading;
//                boundaryInsets.trailing += layoutSection.contentInsets.trailing;
//            }
//
//            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
//                containerFrame.origin.y = contentFrame.origin.y;
//                containerFrame.size.height = contentFrame.size.height;
//
//                boundaryInsets.top = 0;
//                boundaryInsets.bottom = 0;
//            }
//            if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
//                containerFrame.origin.x = contentFrame.origin.x;
//                containerFrame.origin.y = contentFrame.origin.y;
//                containerFrame.size.width = contentFrame.size.width;
//
//                boundaryInsets.leading = 0;
//                boundaryInsets.trailing = 0;
//            }
//
//            containerFrame = UIEdgeInsetsInsetRect(containerFrame, UIEdgeInsetsMake(boundaryInsets.top, boundaryInsets.leading, boundaryInsets.bottom, boundaryInsets.trailing));
//
//            UICollectionViewLayoutAttributes *layoutAttributes = [self prepareLayoutForBoundaryItem:boundaryItem
//                                                                                     containerFrame:containerFrame
//                                                                                       sectionIndex:sectionIndex];
//            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
//                if (boundaryItem.alignment == IBPNSRectAlignmentTop ||
//                    boundaryItem.alignment == IBPNSRectAlignmentTopLeading ||
//                    boundaryItem.alignment == IBPNSRectAlignmentTopTrailing) {
//                    CGRect itemFrame = layoutAttributes.frame;
//                    itemFrame.origin.y += sectionOrigin.y;
//                    layoutAttributes.frame = itemFrame;
//
//                    if (boundaryItem.extendsBoundary && extendedBoundary.height < CGRectGetHeight(itemFrame)) {
//                        CGFloat extendHeight = CGRectGetHeight(itemFrame) - extendedBoundary.height;
//                        for (UICollectionViewLayoutAttributes *attributes in cachedItemAttributes.allValues) {
//                            if (attributes.representedElementCategory == UICollectionElementCategoryCell ||
//                                attributes.representedElementCategory == UICollectionElementCategoryDecorationView) {
//                                CGRect frame = attributes.frame;
//                                if (CGRectGetMinY(frame) >= CGRectGetMinY(itemFrame)) {
//                                    frame.origin.y += extendHeight;
//                                    attributes.frame = frame;
//                                    contentFrame = CGRectUnion(contentFrame, frame);
//                                }
//                            }
//                        }
//                        for (IBPCollectionViewOrthogonalScrollerSectionController *controller in orthogonalScrollerSectionControllers.allValues) {
//                            CGRect frame = controller.scrollView.frame;
//                            if (CGRectGetMinY(frame) >= CGRectGetMinY(itemFrame)) {
//                                frame.origin.y += extendHeight;
//                                controller.scrollView.frame = frame;
//                                contentFrame = CGRectUnion(contentFrame, frame);
//                            }
//                        }
//                        extendedBoundary.height += extendHeight;
//                    }
//                }
//            }
//            if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
//                if (boundaryItem.alignment == IBPNSRectAlignmentLeading ||
//                    boundaryItem.alignment == IBPNSRectAlignmentTopLeading ||
//                    boundaryItem.alignment == IBPNSRectAlignmentBottomLeading) {
//                    CGRect frame = layoutAttributes.frame;
//                    frame.origin.x += sectionOrigin.x;
//                    layoutAttributes.frame = frame;
//                }
//            }
//            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
//                if (boundaryItem.alignment == IBPNSRectAlignmentBottom ||
//                    boundaryItem.alignment == IBPNSRectAlignmentBottomLeading ||
//                    boundaryItem.alignment == IBPNSRectAlignmentBottomTrailing) {
//                    CGRect frame = layoutAttributes.frame;
//                    if (!boundaryItem.extendsBoundary) {
//                        frame.origin.y -= CGRectGetHeight(frame);
//                    }
//                    frame.origin.y += layoutSection.contentInsets.bottom;
//                    layoutAttributes.frame = frame;
//                }
//            }
//            if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
//                if (boundaryItem.alignment == IBPNSRectAlignmentTrailing ||
//                    boundaryItem.alignment == IBPNSRectAlignmentTopTrailing ||
//                    boundaryItem.alignment == IBPNSRectAlignmentBottomTrailing) {
//                    CGRect frame = layoutAttributes.frame;
//                    frame.origin.x += layoutSection.contentInsets.trailing;
//                    layoutAttributes.frame = frame;
//                }
//            }
//
//            contentFrame = CGRectUnion(contentFrame, layoutAttributes.frame);
//            cachedBoundarySupplementaryAttributes[[NSString stringWithFormat:@"%@-%zd-%d", boundaryItem.elementKind, sectionIndex, BoundaryItemIndex]] = layoutAttributes;
//            [globalSupplementaryItems addObject:boundaryItem];
//
//            if (boundaryItem.pinToVisibleBounds) {
//                self.hasPinnedSupplementaryItems = YES;
//                [layoutAttributesForPinnedSupplementaryItems addObject:layoutAttributes];
//            }
//        }

        for (IBPNSCollectionLayoutDecorationItem *decorationItem in layoutSection.decorationItems) {
            LayoutAttributes *layoutAttributes = [LayoutAttributes layoutAttributesForDecorationViewOfKind:decorationItem.elementKind withIndexPath:[NSIndexPath indexPathForItem:0 inSection:sectionIndex]];

            CGRect frame = CGRectZero;
            frame.origin = sectionOrigin;
            frame.size = collectionContainer.effectiveContentSize;

            if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
                frame.size.height = CGRectGetMaxY(contentFrame) - sectionOrigin.y + layoutSection.contentInsets.bottom;
            }
            if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
                frame.size.width = CGRectGetMaxX(contentFrame) - sectionOrigin.x;
            }

            frame.origin.x += decorationItem.contentInsets.leading;
            frame.origin.y += decorationItem.contentInsets.top;
            frame.size.width -= decorationItem.contentInsets.leading + decorationItem.contentInsets.trailing;
            frame.size.height -= decorationItem.contentInsets.top + decorationItem.contentInsets.bottom;

            layoutAttributes.zIndex = decorationItem.zIndex;

            layoutAttributes.frame = frame;
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:sectionIndex];
            cachedDecorationAttributes[indexPath] = layoutAttributes;
        }

        CGRect insetsContentFrame = contentFrame;
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            insetsContentFrame.origin.y += self.containerSection.contentInsets.bottom + layoutSection.contentInsets.bottom;
        }
        if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            insetsContentFrame.origin.x += self.containerSection.contentInsets.trailing + layoutSection.contentInsets.trailing;
        }
        if (!CGRectIsEmpty(contentFrame)) {
            contentFrame = CGRectUnion(contentFrame, insetsContentFrame);
        }

        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            contentFrame.size.height += self.configuration.interSectionSpacing;
        }
        if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            contentFrame.size.width += self.configuration.interSectionSpacing;
        }
    }
}

- (UICollectionView *)setupOrthogonalScrollViewForSection:(IBPNSCollectionLayoutSection *)section {
    IBPUICollectionViewCompositionalLayoutConfiguration *configuration = [IBPUICollectionViewCompositionalLayoutConfiguration defaultConfiguration];
    configuration.scrollDirection = self.scrollDirection == UICollectionViewScrollDirectionVertical ? UICollectionViewScrollDirectionHorizontal : UICollectionViewScrollDirectionVertical;

    IBPNSCollectionLayoutSection *orthogonalSection = section.copy;
    orthogonalSection.contentInsets = IBPNSDirectionalEdgeInsetsZero;
    orthogonalSection.boundarySupplementaryItems = @[];
    orthogonalSection.orthogonalScrollingBehavior = IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorNone;

    IBPNSCollectionLayoutSize *orthogonalGroupSize = section.group.layoutSize;
    IBPNSCollectionLayoutDimension *widthDimension = orthogonalGroupSize.widthDimension;
    IBPNSCollectionLayoutDimension *heightDimension = orthogonalGroupSize.heightDimension;

    if (widthDimension.isFractionalWidth) {
        widthDimension = self.scrollDirection == UICollectionViewScrollDirectionVertical ? widthDimension : [IBPNSCollectionLayoutDimension fractionalWidthDimension:MAX(1, widthDimension.dimension)];
    }
    if (widthDimension.isFractionalHeight) {
        widthDimension = self.scrollDirection == UICollectionViewScrollDirectionVertical ? widthDimension : [IBPNSCollectionLayoutDimension fractionalWidthDimension:MAX(1, widthDimension.dimension)];
    }
    if (widthDimension.isAbsolute) {
        widthDimension = [IBPNSCollectionLayoutDimension absoluteDimension:widthDimension.dimension];
    }

    if (heightDimension.isFractionalWidth) {
        heightDimension = self.scrollDirection == UICollectionViewScrollDirectionVertical ? [IBPNSCollectionLayoutDimension fractionalHeightDimension:MAX(1, heightDimension.dimension)] : heightDimension;
    }
    if (heightDimension.isFractionalHeight) {
        heightDimension = self.scrollDirection == UICollectionViewScrollDirectionVertical ? [IBPNSCollectionLayoutDimension fractionalHeightDimension:MAX(1, heightDimension.dimension)] : heightDimension;
    }
    if (heightDimension.isAbsolute) {
        heightDimension = [IBPNSCollectionLayoutDimension absoluteDimension:heightDimension.dimension];
    }

    orthogonalSection.group.layoutSize = [IBPNSCollectionLayoutSize sizeWithWidthDimension:widthDimension heightDimension:heightDimension];
    IBPUICollectionViewCompositionalLayout *collectionViewLayout = [[IBPUICollectionViewCompositionalLayout alloc] initWithSection:orthogonalSection
                                                                                                                     configuration:configuration];
    collectionViewLayout.parent = self;
    collectionViewLayout.containerSection = section;

    IBPCollectionViewOrthogonalScrollerEmbeddedScrollView *scrollView = [[IBPCollectionViewOrthogonalScrollerEmbeddedScrollView alloc] initWithFrame:CGRectZero
                                                                                                                                collectionViewLayout:collectionViewLayout];
    scrollView.backgroundColor = UIColor.clearColor;
    scrollView.directionalLockEnabled = YES;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;

    switch (section.orthogonalScrollingBehavior) {
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorNone:
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous:
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary:
            scrollView.pagingEnabled = NO;
            break;
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorPaging:
            scrollView.pagingEnabled = YES;
            break;
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPaging:
            scrollView.pagingEnabled = NO;
            scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
            break;
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered:
            scrollView.pagingEnabled = NO;
            scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
            break;
    }

    return scrollView;
}

- (UICollectionViewLayoutAttributes *)prepareLayoutForBoundaryItem:(IBPNSCollectionLayoutBoundarySupplementaryItem *)boundaryItem
                                                    containerFrame:(CGRect)containerFrame
                                                      sectionIndex:(NSInteger)sectionIndex {
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:BoundaryItemIndex inSection:sectionIndex];
    LayoutAttributes *layoutAttributes = [LayoutAttributes layoutAttributesForSupplementaryViewOfKind:boundaryItem.elementKind
                                                                                                                        withIndexPath:indexPath];
    layoutAttributes.layoutSize = boundaryItem.layoutSize;
    IBPNSCollectionLayoutContainer *itemContainer = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:containerFrame.size
                                                                                                  contentInsets:IBPNSDirectionalEdgeInsetsZero];
    CGSize itemSize = [boundaryItem.layoutSize effectiveSizeForContainer:itemContainer];

    IBPNSCollectionLayoutAnchor *containerAnchor;
    switch (boundaryItem.alignment) {
        case IBPNSRectAlignmentNone:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeNone];
            break;
        case IBPNSRectAlignmentTop:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeTop];
            break;
        case IBPNSRectAlignmentTopLeading:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeTop | IBPNSDirectionalRectEdgeLeading];
            break;
        case IBPNSRectAlignmentLeading:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeLeading];
            break;
        case IBPNSRectAlignmentBottomLeading:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeBottom | IBPNSDirectionalRectEdgeLeading];
            break;
        case IBPNSRectAlignmentBottom:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeBottom];
            break;
        case IBPNSRectAlignmentBottomTrailing:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeBottom | IBPNSDirectionalRectEdgeTrailing];
            break;
        case IBPNSRectAlignmentTrailing:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeTrailing];
            break;
        case IBPNSRectAlignmentTopTrailing:
            containerAnchor = [IBPNSCollectionLayoutAnchor layoutAnchorWithEdges:IBPNSDirectionalRectEdgeTop | IBPNSDirectionalRectEdgeTrailing];
            break;
    }

    CGRect itemFrame = [containerAnchor itemFrameForContainerRect:containerFrame itemSize:itemSize itemLayoutAnchor:nil];

    if ((containerAnchor.edges & IBPNSDirectionalRectEdgeTrailing) == IBPNSDirectionalRectEdgeTrailing) {
        itemFrame.origin.x += itemSize.width;
    }
    if ((containerAnchor.edges & IBPNSDirectionalRectEdgeBottom) == IBPNSDirectionalRectEdgeBottom) {
        itemFrame.origin.y += itemSize.height;
    }

    layoutAttributes.frame = itemFrame;
    layoutAttributes.zIndex = boundaryItem.zIndex;

    return layoutAttributes;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray<LayoutAttributes *> *attributes;
    attributes = [[NSMutableArray alloc] init];

    NSInteger section = -1;
    for (IBPCollectionViewHierarchicalSectionSolver *solver in sectionSolvers) {
        section += 1;

        if (!CGRectIntersectsRect(solver.frame, rect)) {
            if (attributes.count == 0)
                continue;
            else
                break;
        }

        [attributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:rect forSectionAtIndex:section]];
    }

    return attributes;

//    NSMutableArray<UICollectionViewLayoutAttributes *> *layoutAttributes = [[NSMutableArray alloc] init];
//
//    NSArray *concerningAttributes;
//
//    @autoreleasepool {
//        NSArray *allBoundaryAttributes = [cachedBoundarySupplementaryAttributes allValues];
//        NSArray *allAttributes = [cachedItemAttributes.allValues arrayByAddingObjectsFromArray:allBoundaryAttributes];
//
//        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(LayoutAttributes *attribute, NSDictionary *bindings) {
//            return attribute.frame.origin.y >= rect.origin.y;
//        }];
//        concerningAttributes = [allAttributes filteredArrayUsingPredicate:predicate];
//    }
//
//    NSArray *itemAttributes = [concerningAttributes sortedArrayUsingComparator:^NSComparisonResult(LayoutAttributes *attrs1, LayoutAttributes *attrs2) {
//        switch (_configuration.scrollDirection) {
//            case UICollectionViewScrollDirectionVertical:
//                return CGRectGetMinY(attrs1.frame) > CGRectGetMinY(attrs2.frame);
//            case UICollectionViewScrollDirectionHorizontal:
//                return CGRectGetMinX(attrs1.frame) > CGRectGetMinX(attrs2.frame);
//        }
//    }];
//
//    NSMutableSet *alreadyUpdatedAttributesPointers = [[NSMutableSet alloc] init];
//    CGVector accumulator = CGVectorMake(0.0, 0.0);
//    BOOL isEarlySkipping = YES;
//
//    for (NSInteger i = 0; i < itemAttributes.count; i++) {
//        LayoutAttributes *attributes = itemAttributes[i];
//
//        if (isEarlySkipping && !CGRectIntersectsRect(attributes.frame, rect)) {
//            // "Early skip" attributes until we hit an attribute that intersects with the requested rect.
//            continue;
//        }
//
//        isEarlySkipping = NO;
//
//        NSValue *attributesPointer = [NSValue valueWithPointer:(void *)attributes];
//        BOOL hasAlreadyBeenUpdated = ![alreadyUpdatedAttributesPointers containsObject:attributesPointer];
//        BOOL needsUpdate = (accumulator.dx >= 0.0 || accumulator.dy >= 0.0) && !hasAlreadyBeenUpdated;
//
//        if (hasAlreadyBeenUpdated) {
//            [alreadyUpdatedAttributesPointers removeObject:attributesPointer];
//        }
//
//        if (needsUpdate) {
//            attributes.frame = CGRectTranslate(attributes.frame, accumulator);
//        }
//
//        if ([attributes isInvalidatingSucceedingElements]) {
//            // Search for adjacent elements that are aligned on the same min edge (with regard to the scroll direction).
//            NSInteger indexInSlice;
//            NSArray *adjacentElements = SearchMinEdgeAlignedElements(itemAttributes, i, _configuration.scrollDirection, &indexInSlice);
//            CGVector localDelta = CGVectorMake(0.0, 0.0);
//
//            for (LayoutAttributes *element in adjacentElements) {
//                if ([element isInvalidatingSucceedingElements]) {
//                    CGVector delta = [element deltaForSucceedingElements];
//                    localDelta = CGVectorMake(fmax(localDelta.dx, delta.dx), fmax(localDelta.dy, delta.dy));
//
//                    element.isInvalidatingSucceedingElements = NO;
//                    element.deltaForSucceedingElements = CGVectorMake(0.0, 0.0);
//                }
//            }
//
//            // Update the current & succeeding elements with the current accumulator value after the current attributes.
//            NSIndexSet *updateRange = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(indexInSlice, adjacentElements.count - indexInSlice)];
//            [adjacentElements enumerateObjectsAtIndexes:updateRange options:nil usingBlock:^(LayoutAttributes *attributes, NSUInteger idx, BOOL * _Nonnull stop) {
//                attributes.frame = CGRectTranslate(attributes.frame, accumulator);
//
//                if (idx > indexInSlice) {
//                    [alreadyUpdatedAttributesPointers addObject:[NSValue valueWithPointer:(void *)attributes]];
//                }
//            }];
//
//            accumulator = CGVectorAdd(accumulator, localDelta);
//            CGRect frame = contentFrame;
//            frame.size.width += localDelta.dx;
//            frame.size.height += localDelta.dy;
//            contentFrame = frame;
//        }
//
//        if (CGRectIntersectsRect(attributes.frame, rect)) {
//            [layoutAttributes addObject:attributes];
//        }
//    }
//
//    for (UICollectionViewLayoutAttributes *attributes in cachedSupplementaryAttributes.allValues) {
//        if (!CGRectIntersectsRect(attributes.frame, rect)) {
//            continue;
//        }
//        [layoutAttributes addObject:attributes];
//    }
//
//    for (UICollectionViewLayoutAttributes *attributes in cachedDecorationAttributes.allValues) {
//        if (!CGRectIntersectsRect(attributes.frame, rect)) {
//            continue;
//        }
//        [layoutAttributes addObject:attributes];
//    }
//
//    for (NSInteger i = 0; i < layoutAttributesForPinnedSupplementaryItems.count; i++) {
//        CGPoint contentOffset = self.collectionView.contentOffset;
//        UICollectionViewLayoutAttributes *attributes = layoutAttributesForPinnedSupplementaryItems[i];
//        if (!CGRectIntersectsRect(attributes.frame, rect)) {
//            continue;
//        }
//
//        if (@available(iOS 11.0, *)) {
//            if ([self.collectionView respondsToSelector:@selector(safeAreaInsets)]) {
//                if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
//                    contentOffset.y += self.collectionView.safeAreaInsets.top;
//                }
//                if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
//                    contentOffset.x += self.collectionView.safeAreaInsets.left;
//                }
//            }
//        }
//
//        CGPoint nextHeaderOrigin = CGPointMake(INFINITY, INFINITY);
//
//        if (i + 1 < layoutAttributesForPinnedSupplementaryItems.count) {
//            UICollectionViewLayoutAttributes *nextHeaderAttributes = layoutAttributesForPinnedSupplementaryItems[i + 1];
//            nextHeaderOrigin = nextHeaderAttributes.frame.origin;
//        }
//
//        CGRect frame = attributes.frame;
//        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
//            frame.origin.y = MIN(MAX(contentOffset.y, frame.origin.y), nextHeaderOrigin.y - CGRectGetHeight(frame));
//        }
//        if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
//            frame.origin.x = MIN(MAX(contentOffset.x, frame.origin.x), nextHeaderOrigin.x - CGRectGetWidth(frame));
//        }
//
//        attributes.frame = frame;
//    }
//
//    return layoutAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return cachedItemAttributes[indexPath];
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    NSString *key = [NSString stringWithFormat:@"%@-%zd-%zd", elementKind, indexPath.section, indexPath.item];

    if (indexPath.item == BoundaryItemIndex) {
        return cachedBoundarySupplementaryAttributes[key];
    }

    return cachedSupplementaryAttributes[key];
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    return cachedDecorationAttributes[[NSString stringWithFormat:@"%@-%zd-%zd", elementKind, indexPath.section, indexPath.item]];
}

- (void)invalidateLayoutWithContext:(UICollectionViewLayoutInvalidationContext *)context {
    _shouldReset = _shouldReset || [context invalidateEverything];

    [super invalidateLayoutWithContext:context];
}

- (BOOL)shouldInvalidateLayoutForPreferredLayoutAttributes:(LayoutAttributes *)preferredAttributes withOriginalAttributes:(LayoutAttributes *)originalAttributes {
    LayoutAttributes *cachedAttributes = [self cachedAttributesFromOriginalAttributes:originalAttributes];

    if (!cachedAttributes) {
        return NO;
    }

    BOOL shouldInvalidate = [cachedAttributes isEstimated]
        && !CGSizeEqualToSize([preferredAttributes size], [cachedAttributes size]);

    if (shouldInvalidate) {
        [cachedAttributes updateLayoutSizeWithPreferredAttributes:preferredAttributes];
        return YES;
    }

    return NO;
}

- (LayoutAttributes *)cachedAttributesFromOriginalAttributes:(LayoutAttributes *)originalAttributes {
    NSIndexPath *indexPath = [originalAttributes indexPath];
    NSUInteger category = [originalAttributes representedElementCategory];

    switch (category) {
        case UICollectionElementCategoryCell:
            return cachedItemAttributes[indexPath];
        case UICollectionElementCategorySupplementaryView:
        {
            if (indexPath.item != BoundaryItemIndex) {
                return nil;
            }

            NSString *elementKind = [originalAttributes representedElementKind];
            NSString *key = [NSString stringWithFormat:@"%@-%zd-%zd", elementKind, indexPath.section, BoundaryItemIndex];
            return cachedBoundarySupplementaryAttributes[key];
        }
        case UICollectionElementCategoryDecorationView:
        default:
            return nil;
    }
}

- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset withScrollingVelocity:(CGPoint)velocity {
    switch (self.containerSection.orthogonalScrollingBehavior) {
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary:
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPaging:
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered:
            return [self orthogonalContentOffsetForProposedContentOffset:proposedContentOffset scrollingVelocity:velocity];
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorNone:
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorContinuous:
        case IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorPaging:
            return [super targetContentOffsetForProposedContentOffset:proposedContentOffset withScrollingVelocity:velocity];
    }
}

- (CGPoint)orthogonalContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset
                                         scrollingVelocity:(CGPoint)velocity {
    IBPCollectionCompositionalLayoutSolver *solver;
    CGPoint contentOffset = CGPointZero;

    CGRect layoutFrame = solver.layoutFrame;
    CGFloat interGroupSpacing = solver.layoutSection.interGroupSpacing;

    CGFloat width = CGRectGetWidth(layoutFrame);
    CGFloat height = CGRectGetHeight(layoutFrame);

    CGSize containerSize = self.collectionView.bounds.size;
    CGPoint translation = [self.collectionView.panGestureRecognizer translationInView:self.collectionView.superview];

    UICollectionViewScrollDirection scrollDirection = self.scrollDirection;
    IBPUICollectionLayoutSectionOrthogonalScrollingBehavior orthogonalScrollingBehavior = self.containerSection.orthogonalScrollingBehavior;

    if (orthogonalScrollingBehavior == IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary) {
        if (scrollDirection == UICollectionViewScrollDirectionVertical) {
            contentOffset.y += height * floor(proposedContentOffset.y / height) + interGroupSpacing * floor(proposedContentOffset.y / height) + height * (translation.y < 0 ? 1 : 0);
            return contentOffset;
        }
        if (scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            contentOffset.x += width * floor(proposedContentOffset.x / width) + interGroupSpacing * floor(proposedContentOffset.x / width) + width * (translation.x < 0 ? 1 : 0);
            return contentOffset;
        }
    }
    if (orthogonalScrollingBehavior == IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPaging) {
        if (fabs(velocity.x) > 0.2) {
            translation.x = width / 2 * (translation.x < 0 ? -1 : 1);
        }
        contentOffset.x += width * round((proposedContentOffset.x + translation.x) / width);
        contentOffset.y += height * round((proposedContentOffset.y + translation.y) / height);

        if (scrollDirection == UICollectionViewScrollDirectionVertical) {
            contentOffset.y += height * round(-translation.y / (height / 2)) + interGroupSpacing * round(-translation.y / (height / 2));
            return contentOffset;
        }
        if (scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            contentOffset.x += width * round(-translation.x / (width / 2)) + interGroupSpacing * round(-translation.x / (width / 2));
            return contentOffset;
        }
    }
    if (orthogonalScrollingBehavior == IBPUICollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered) {
        if (fabs(velocity.x) > 0.2) {
            translation.x = width / 2 * (translation.x < 0 ? -1 : 1);
        }
        contentOffset.x += width * round((proposedContentOffset.x + translation.x) / width);
        contentOffset.y += height * round((proposedContentOffset.y + translation.y) / height);

        if (scrollDirection == UICollectionViewScrollDirectionVertical) {
            contentOffset.y += height * round(-translation.y / (height / 2)) + interGroupSpacing * round(-translation.y / (height / 2)) - (containerSize.height - height) / 2;
            return contentOffset;
        }
        if (scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            contentOffset.x += width * round(-translation.x / (width / 2)) + interGroupSpacing * round(-translation.x / (width / 2)) - (containerSize.width - width) / 2;
            return contentOffset;
        }
    }

    return [super targetContentOffsetForProposedContentOffset:proposedContentOffset withScrollingVelocity:velocity];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    if (!self.collectionView) {
        return NO;
    }
    if (self.hasPinnedSupplementaryItems) {
        return YES;
    }

    return !CGSizeEqualToSize(newBounds.size, self.collectionView.bounds.size);
}

- (CGSize)collectionViewContentSize {
    return contentFrame.size;
}

- (void)scrollViewDidChangeAdjustedContentInset:(UIScrollView *)scrollView API_AVAILABLE(ios(11.0), tvos(11.0)); {
    if (scrollView == self.collectionView) {
        if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
            CGPoint contentOffset = CGPointZero;
            contentOffset.y += -scrollView.adjustedContentInset.top;
            scrollView.contentOffset = contentOffset;
        }
        if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
            CGPoint contentOffset = CGPointZero;
            contentOffset.x += -scrollView.adjustedContentInset.left;
            scrollView.contentOffset = contentOffset;
        }
        scrollView.delegate = self.collectionViewDelegate;
    }
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [self.collectionViewDelegate respondsToSelector:aSelector] || [super respondsToSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [anInvocation invokeWithTarget:self.collectionViewDelegate];
}

@end

//NSIndexPath *indexPath = attributes.indexPath;
//IBPNSCollectionLayoutItem *layoutItem = [solvers[indexPath.section] layoutItemAtIndexPath:indexPath];
//IBPNSCollectionLayoutSize *layoutSize = layoutItem.layoutSize;
//if (layoutSize.widthDimension.isEstimated || layoutSize.heightDimension.isEstimated) {
//    if (cell) {
//        CGSize fitSize = [cell systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
//        CGRect frame = attributes.frame;
//        if (CGRectGetWidth(attributes.frame) != fitSize.width || CGRectGetHeight(attributes.frame) != fitSize.height) {
//            for (NSInteger j = i + 1; j < itemAttributes.count; j++) {
//                UICollectionViewLayoutAttributes *nextAttributes = itemAttributes[j];
//                CGRect nextFrame = nextAttributes.frame;
//
//                switch (self.scrollDirection) {
//                    case UICollectionViewScrollDirectionVertical:
//                        if (CGRectGetMinY(nextFrame) > CGRectGetMinY(frame)) {
//                            nextFrame.origin.y += fitSize.height - CGRectGetHeight(nextFrame);
//                        }
//                        break;
//                    case UICollectionViewScrollDirectionHorizontal:
//                        if (CGRectGetMinX(nextFrame) > CGRectGetMinX(attributes.frame)) {
//                            nextFrame.origin.x += fitSize.width - CGRectGetWidth(nextFrame);
//                        }
//                        break;
//                }
//                nextAttributes.frame = nextFrame;
//            }
//        }
//
//        frame.size = fitSize;
//        attributes.frame = frame;
//        [layoutAttributes addObject:attributes];
//
//        contentFrame = CGRectUnion(contentFrame, frame);
//
//        NSMutableDictionary<NSString *, UICollectionViewLayoutAttributes *> *supplementaryAttributes = cachedSupplementaryAttributes;
//        [layoutItem enumerateSupplementaryItemsWithHandler:^(IBPNSCollectionLayoutSupplementaryItem * _Nonnull supplementaryItem, BOOL * _Nonnull stop) {
//            LayoutAttributes *attributes = [LayoutAttributes layoutAttributesForSupplementaryViewOfKind:supplementaryItem.elementKind withIndexPath:indexPath];
//
//            IBPNSCollectionLayoutContainer *container = [[IBPNSCollectionLayoutContainer alloc] initWithContentSize:frame.size
//                                                                                                      contentInsets:IBPNSDirectionalEdgeInsetsZero];
//            CGSize size = [supplementaryItem.layoutSize effectiveSizeForContainer:container];
//            CGRect supplementaryFrame = [supplementaryItem.containerAnchor itemFrameForContainerRect:frame itemSize:size itemLayoutAnchor:supplementaryItem.itemAnchor];
//            attributes.frame = supplementaryFrame;
//            attributes.zIndex = supplementaryItem.zIndex;
//
//            supplementaryAttributes[[NSString stringWithFormat:@"%@-%zd-%zd", supplementaryItem.elementKind, indexPath.section, indexPath.item]] = attributes;
//
//            [layoutAttributes addObject:attributes];
//        }];
//
//        continue;
//    }
//}

CGVector CGVectorAdd(CGVector lhs, CGVector rhs) {
    CGVector vector; vector.dx = lhs.dx + rhs.dx; vector.dy = lhs.dy + rhs.dy; return vector;
}

NSArray<LayoutAttributes *> * _Nonnull SearchMinEdgeAlignedElements(NSArray<LayoutAttributes *> * _Nonnull attributes, NSInteger index, UICollectionViewScrollDirection direction, NSInteger *outSliceIndex) {
    NSMutableArray *results = [[NSMutableArray alloc] init];
    NSIndexSet *range = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, attributes.count - index)];

    CGRect baseFrame = [[attributes objectAtIndex:index] frame];

    [attributes enumerateObjectsAtIndexes:range options:nil usingBlock:^(LayoutAttributes * _Nonnull attributes, NSUInteger idx, BOOL * _Nonnull stop) {
        BOOL pass = NO;

        switch (direction) {
        case UICollectionViewScrollDirectionHorizontal:
            pass = CGRectGetMinX(attributes.frame) == CGRectGetMinX(baseFrame);
            break;
        case UICollectionViewScrollDirectionVertical:
            pass = CGRectGetMinY(attributes.frame) == CGRectGetMinY(baseFrame);
            break;
        }

        if (pass) {
            if (idx == index) {
                *outSliceIndex = [results count];
            }

            [results addObject:attributes];
        } else {
            stop = YES;
        }
    }];

    return results;
}

CGRect CGRectTranslate(CGRect original, CGVector delta) {
    CGRect frame = original;
    frame.origin.x += delta.dx;
    frame.origin.y += delta.dy;
    return frame;
}
