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
#import "CGVectorExtensions.h"

typedef IBPUICollectionViewCompositionalLayoutAttributes LayoutAttributes;
NSInteger BoundaryItemIndex = 0;

@interface IBPUICollectionViewCompositionalLayout()<UICollectionViewDelegate> {

    NSMutableArray<IBPCollectionViewHierarchicalSectionSolver *> *sectionSolvers;

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
        [sectionRootSolver solveForContainer:collectionContainer
                             traitCollection:collectionView.traitCollection];
        [sectionSolvers addObject:sectionRootSolver];

        sectionRootSolver.originInParent = sectionOrigin;

        switch (self.scrollDirection) {
            case UICollectionViewScrollDirectionVertical:
                contentFrame.size.height += sectionRootSolver.solvedSize.height;
                break;
            case UICollectionViewScrollDirectionHorizontal:
                contentFrame.size.width += sectionRootSolver.solvedSize.width;
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
                scrollViewFrame.size.height = MIN(sectionRootSolver.solvedSize.height, collectionContainer.contentSize.height);
            }
            if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
                scrollViewFrame.origin.x = sectionOrigin.x + layoutSection.contentInsets.leading;
                scrollViewFrame.size.width = MIN(sectionRootSolver.solvedSize.width, collectionContainer.contentSize.width);
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

        if (!solver.layoutSection.scrollsOrthogonally) {
            [attributes addObjectsFromArray:[solver layoutAttributesForItemInVisibleRect:rect forSectionAtIndex:section]];
        }
    }

    return attributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    abort();
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    abort();
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath {
    abort();
}

- (void)invalidateLayoutWithContext:(UICollectionViewLayoutInvalidationContext *)context {
    _shouldReset = _shouldReset || [context invalidateEverything];

    [super invalidateLayoutWithContext:context];
}

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForPreferredLayoutAttributes:(UICollectionViewLayoutAttributes *)preferredAttributes
                                                                        withOriginalAttributes:(UICollectionViewLayoutAttributes *)originalAttributes {
    UICollectionViewLayoutInvalidationContext *context;
    context = [super invalidationContextForPreferredLayoutAttributes:preferredAttributes
                                              withOriginalAttributes:originalAttributes];

    return context;
}

- (BOOL)shouldInvalidateLayoutForPreferredLayoutAttributes:(LayoutAttributes *)preferredAttributes withOriginalAttributes:(LayoutAttributes *)originalAttributes {
    NSIndexPath *indexPath = preferredAttributes.indexPath;
    CGVector delta = [sectionSolvers[indexPath.section] setPreferredSize:preferredAttributes.size forItemAtIndex:indexPath.item];

    if (!CGVectorEqual(delta, CGVectorZero)) {
        switch (self.scrollDirection) {
            case UICollectionViewScrollDirectionVertical:
                contentFrame.size.height += delta.dy;
                break;
            case UICollectionViewScrollDirectionHorizontal:
                contentFrame.size.width += delta.dx;
                break;
        }

        for (NSInteger i = indexPath.section + 1; i < sectionSolvers.count; i++) {
            IBPCollectionViewHierarchicalSectionSolver *solver = sectionSolvers[i];

            switch (self.scrollDirection) {
                case UICollectionViewScrollDirectionVertical:
                    solver.originInParent = CGPointOffsetY(delta.dy, solver.originInParent);
                    break;
                case UICollectionViewScrollDirectionHorizontal:
                    solver.originInParent = CGPointOffsetX(delta.dx, solver.originInParent);
                    break;
            }
        }

        return YES;
    } else {
        return NO;
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
