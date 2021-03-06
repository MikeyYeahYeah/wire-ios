// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import MobileCoreServices;

#import "ImageMessageCell+Internal.h"
@import PureLayout;
#import <WireSyncEngine/WireSyncEngine.h>

#import "Constants.h"
#import "UIColor+WAZExtensions.h"
@import FLAnimatedImage;
#import "UIImage+ImageUtilities.h"
#import "MediaAsset.h"
#import "Analytics.h"
#import "Wire-Swift.h"
#import "UIImage+ZetaIconsNeue.h"
#import "ConversationCell+Private.h"

static NSString* ZMLogTag ZM_UNUSED = @"UI";

@protocol MediaAsset;

@interface ImageMessageCell ()

@property (nonatomic, strong) ImageResourceView *fullImageView;
@property (nonatomic, strong) ImageToolbarView *imageToolbarView;
@property (nonatomic, strong) ObfuscationView *obfuscationView;
@property (nonatomic) UITapGestureRecognizer *imageTapRecognizer;

/// Can either be UIImage or FLAnimatedImage
@property (nonatomic, strong) id<MediaAsset> image;

@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageAspectConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageTopInsetConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageRightConstraint;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *imageToolbarInsideConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *imageToolbarOutsideConstraints;

@property (nonatomic) CGSize originalImageSize;
@property (nonatomic) CGSize imageSize;

@end

@implementation ImageMessageCell

static const CGFloat ImageToolbarMinimumSize = 192;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.variant = [ColorScheme defaultColorScheme].variant;
        _autoStretchVertically = YES;
        [self createImageMessageViews];
        [self createConstraints];

        self.defaultLayoutMargins = UIView.directionAwareConversationLayoutMargins;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:[UIApplication sharedApplication]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:[UIApplication sharedApplication]];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidEnterBackgroundNotification
                                                  object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationWillEnterForegroundNotification
                                                  object:[UIApplication sharedApplication]];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    FLAnimatedImage *image = self.fullImageView.animatedImage;
    if (image) {
        image.frameCacheSizeMax = 1;
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    FLAnimatedImage *image = self.fullImageView.animatedImage;
    if (image) {
        image.frameCacheSizeMax = 0; // not limited
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.originalImageSize = CGSizeZero;
    self.imageSize = CGSizeZero;
    self.obfuscationView.hidden = YES;
    self.imageToolbarView.hidden = NO;
    self.image = nil;
    
    [self setImageResource:nil];

    if (self.imageAspectConstraint) {
        [self.imageViewContainer removeConstraint:self.imageAspectConstraint];
        self.imageAspectConstraint = nil;
    }
}

- (void)didEndDisplayingInTableView
{
    [super didEndDisplayingInTableView];
    [self recycleImage];
}

- (void)createImageMessageViews
{
    self.imageViewContainer = [[UIView alloc] init];
    self.imageViewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageViewContainer.isAccessibilityElement = YES;
    self.imageViewContainer.accessibilityTraits = UIAccessibilityTraitImage;
    [self.messageContentView addSubview:self.imageViewContainer];
        
    self.fullImageView = [[ImageResourceView alloc] init];
    self.fullImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.fullImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.fullImageView.clipsToBounds = YES;
    [self.imageViewContainer addSubview:self.fullImageView];

    self.obfuscationView = [[ObfuscationView alloc] initWithIcon:ZetaIconTypePhoto];
    [self.imageViewContainer addSubview:self.obfuscationView];

    self.imageTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageTapped:)];
    [self.imageViewContainer addGestureRecognizer:self.imageTapRecognizer];
    [self.imageTapRecognizer requireGestureRecognizerToFail:self.doubleTapGestureRecognizer];
    self.obfuscationView.hidden = YES;
  
    self.accessibilityIdentifier = @"ImageCell";
    
    self.imageToolbarView = [[ImageToolbarView alloc] initWithConfiguraton:ImageToolbarConfigurationCell];
    self.imageToolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.imageToolbarView.sketchButton addTarget:self action:@selector(onDrawSketchPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.imageToolbarView.emojiButton addTarget:self action:@selector(onEmojiSketchPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.imageToolbarView.textButton addTarget:self action:@selector(onTextSketchPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.imageToolbarView.expandButton addTarget:self action:@selector(onFullScreenPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.messageContentView addSubview:_imageToolbarView];
}

- (void)createConstraints
{
    [self.fullImageView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero];

    self.imageTopInsetConstraint = [self.imageViewContainer autoPinEdgeToSuperviewEdge:ALEdgeTop];
    
    [self.imageViewContainer autoPinEdgeToSuperviewMargin:ALEdgeLeft relation:NSLayoutRelationLessThanOrEqual];
    self.imageRightConstraint = [self.imageViewContainer autoPinEdgeToSuperviewMargin:ALEdgeRight];
    self.imageRightConstraint.active = NO;
    
    NSLayoutRelation rightRelation = self.showsPreview ? NSLayoutRelationEqual : NSLayoutRelationGreaterThanOrEqual;
    [self.imageViewContainer autoPinEdgeToSuperviewMargin:ALEdgeRight relation: rightRelation];
    [self.imageViewContainer autoPinEdgeToSuperviewMargin:ALEdgeLeft];
    [NSLayoutConstraint autoSetPriority:ALLayoutPriorityDefaultHigh + 1 forConstraints:^{
        [self.imageViewContainer autoPinEdgeToSuperviewEdge:ALEdgeBottom];
        self.imageWidthConstraint = [self.imageViewContainer autoSetDimension:ALDimensionWidth toSize:0];
    }];
    
    NSMutableArray<NSLayoutConstraint *> *insideConstraints = [NSMutableArray array];
    [insideConstraints addObject:[self.imageToolbarView autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:self.imageViewContainer]];
    [insideConstraints addObject:[self.imageToolbarView autoPinEdge:ALEdgeRight toEdge:ALEdgeRight ofView:self.imageViewContainer]];
    [NSLayoutConstraint deactivateConstraints:insideConstraints];
    self.imageToolbarInsideConstraints = insideConstraints;
    
    NSMutableArray<NSLayoutConstraint *> *outsideConstraints = [NSMutableArray array];
    [outsideConstraints addObject:[self.imageToolbarView autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:self.imageViewContainer]];
    [NSLayoutConstraint deactivateConstraints:outsideConstraints];
    self.imageToolbarOutsideConstraints = outsideConstraints;
    
    [self.imageToolbarView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.imageViewContainer];
    [self.imageToolbarView autoSetDimension:ALDimensionHeight toSize:48];
    
    [self.obfuscationView autoPinEdgesToSuperviewEdges];
}

 - (void)updateImageMessageConstraintConstants
{
    self.imageTopInsetConstraint.constant = self.layoutProperties.showSender ? 12 : 0;
    
    if (! CGSizeEqualToSize(self.originalImageSize, CGSizeZero)) {
        
        if (self.autoStretchVertically) {
            self.imageRightConstraint.active = NO;
            self.messageContentView.layoutMargins = self.defaultLayoutMargins;
            self.imageWidthConstraint.constant = self.imageSize.width;
            
            if (! self.imageAspectConstraint) {
                CGFloat aspectRatio = self.imageSize.height / self.imageSize.width;
                [NSLayoutConstraint autoSetPriority:ALLayoutPriorityRequired forConstraints:^{
                    self.imageAspectConstraint = [self.imageViewContainer autoMatchDimension:ALDimensionHeight
                                                                                 toDimension:ALDimensionWidth
                                                                                      ofView:self.imageViewContainer
                                                                              withMultiplier:aspectRatio];
                }];
            }
        }
        else {
            self.messageContentView.layoutMargins = UIEdgeInsetsZero;
            self.imageRightConstraint.active = YES;
            [self.messageContentView autoPinEdgesToSuperviewEdges];
        }
        
        [NSLayoutConstraint deactivateConstraints:self.imageToolbarOutsideConstraints];
        [NSLayoutConstraint deactivateConstraints:self.imageToolbarInsideConstraints];
        
        if ([self imageToolbarFitsInsideImage]) {
            [NSLayoutConstraint activateConstraints:self.imageToolbarInsideConstraints];
        } else {
            [NSLayoutConstraint activateConstraints:self.imageToolbarOutsideConstraints];
        }
    }
}

- (BOOL)imageToolbarFitsInsideImage
{
    return self.imageSize.width > ImageToolbarMinimumSize;
}

- (BOOL)imageToolbarNeedsToBeCompact
{
    return ![self imageToolbarFitsInsideImage] && (self.bounds.size.width - self.imageSize.width - self.defaultLayoutMargins.left - self.defaultLayoutMargins.right) < ImageToolbarMinimumSize;
}

- (BOOL)imageSmallerThanMinimumSize
{
    return self.originalImageSize.width < self.imageSize.width || self.originalImageSize.height < self.imageSize.height;
}

- (CGSize)sizeForMessage:(id<ZMImageMessageData>)messageData
{
    CGFloat scaleFactor = [messageData isAnimatedGIF] ? 1 : 0.5;
    return CGSizeApplyAffineTransform(messageData.originalSize, CGAffineTransformMakeScale(scaleFactor, scaleFactor));
}

- (void)configureForMessage:(id<ZMConversationMessage>)convMessage layoutProperties:(ConversationCellLayoutProperties *)layoutProperties
{
    if (! [Message isImageMessage:convMessage]) {
        return;
    }

    [super configureForMessage:convMessage layoutProperties:layoutProperties];

    id<ZMImageMessageData> imageMessageData = convMessage.imageMessageData;
    
    CGFloat minimumMediaSize = 48.0;
    
    self.originalImageSize = [self sizeForMessage:imageMessageData];
    self.imageSize = CGSizeMake(MAX(minimumMediaSize, self.originalImageSize.width),
                                MAX(minimumMediaSize, self.originalImageSize.height));
    
    if (self.autoStretchVertically) {
        self.fullImageView.contentMode = [self imageSmallerThanMinimumSize] ? UIViewContentModeLeft : UIViewContentModeScaleAspectFill;
    } else if (self.showsPreview) {
        BOOL isSmall = self.imageSize.height < [PreviewHeightCalculator standardCellHeight];
        self.fullImageView.contentMode = isSmall ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    } else {
        self.fullImageView.contentMode = UIViewContentModeScaleAspectFill;
    }

    [self updateImageBorder];

    self.imageToolbarView.showsSketchButton = !imageMessageData.isAnimatedGIF;
    self.imageToolbarView.imageIsEphemeral = convMessage.isEphemeral;
    self.imageToolbarView.isPlacedOnImage = [self imageToolbarFitsInsideImage];
    self.imageToolbarView.configuration = [self imageToolbarNeedsToBeCompact] ? ImageToolbarConfigurationCompactCell : ImageToolbarConfigurationCell;
    
    [self updateImageMessageConstraintConstants];
    
    if (convMessage.isObfuscated) {
        self.obfuscationView.hidden = NO;
        self.imageToolbarView.hidden = YES;
        self.imageViewContainer.backgroundColor = [UIColor clearColor];
    } else {
        [self updateBackgroundColor];
    }
    
    [self setImageResource:self.message.imageMessageData];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    [self updateAccessibilityElements];

    dispatch_block_t changeBlock = ^{
        self.imageToolbarView.alpha = self.selected ? 1 : 0;
    };
    
    if (animated) {
        [UIView animateWithDuration:0.15 animations:changeBlock completion:nil];
    }
    else {
        changeBlock();
    }
    
}

- (void)setAutoStretchVertically:(BOOL)autoStretchVertically
{
    _autoStretchVertically = autoStretchVertically;
    
    [self updateImageMessageConstraintConstants];
}

- (void)recycleImage
{
    self.image = nil;
}

- (void)updateAccessibilityElements
{
    
    NSMutableArray *elements = self.accessibilityElements.mutableCopy;
    [elements addObject:self.imageViewContainer];
    
    if (self.selected) {
        [elements addObjectsFromArray:@[self.imageToolbarView, self.imageViewContainer]];
    }

    self.accessibilityElements = elements;
}

#pragma mark - Actions

- (void)onFullScreenPressed:(id)sender {
    [self.delegate conversationCell:self didSelectAction:MessageActionPresent];
}

- (void)onDrawSketchPressed:(id)sender {
    [self.delegate conversationCell:self didSelectAction:MessageActionSketchDraw];
}

- (void)onEmojiSketchPressed:(id)sender {
    [self.delegate conversationCell:self didSelectAction:MessageActionSketchEmoji];
}

- (void)onTextSketchPressed:(id)sender {
    [self.delegate conversationCell:self didSelectAction:MessageActionSketchText];
}

- (void)imageTapped:(id)sender {
    if (!self.message.isObfuscated) {
        [self.delegate conversationCell:self didSelectAction:MessageActionPresent];
    }
}

#pragma mark - Message updates

/// Overriden from the super class cell
- (BOOL)updateForMessage:(MessageChangeInfo *)change
{
    BOOL needsLayout = [super updateForMessage:change];
    if (change.imageChanged || change.transferStateChanged || change.isObfuscatedChanged) {
        [self configureForMessage:self.message layoutProperties:self.layoutProperties];
    }
    
    return needsLayout;
}

#pragma mark - Copy/Paste

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action
              withSender:(id)sender
{
    
    if (action == @selector(cut:)) {
        return NO;
    }
    else if (action == @selector(copy:) || action == @selector(saveImage) || action == @selector(forward:)) {
        return !self.message.isEphemeral && self.fullImageView.image != nil;
    }
    else if (action == @selector(paste:)) {
        return NO;
    }
    else if (action == @selector(select:) || action == @selector(selectAll:)) {
        return NO;
    }
    
    return [super canPerformAction:action withSender:sender];
}

- (void)copy:(id)sender
{
    [[UIPasteboard generalPasteboard] setMediaAsset:[self.fullImageView mediaAsset]];
}

- (void)setSelectedByMenu:(BOOL)selected animated:(BOOL)animated
{
    ZMLogDebug(@"Setting selected: %@ animated: %@", @(selected), @(animated));
    
    dispatch_block_t animations = ^{
        self.fullImageView.alpha = selected ? ConversationCellSelectedOpacity : 1.0f;
    };
    
    if (animated) {
        [UIView animateWithDuration:ConversationCellSelectionAnimationDuration animations:animations];
    } else {
        animations();
    }
}

- (CGRect)selectionRect
{
    return self.imageViewContainer.bounds;
}

- (UIView *)selectionView
{
    return self.imageViewContainer;
}

- (MenuConfigurationProperties *)menuConfigurationProperties;
{
    MenuConfigurationProperties *properties = [[MenuConfigurationProperties alloc] init];
    properties.targetRect = self.selectionRect;
    properties.targetView = self.selectionView;
    UIMenuItem *saveItem = [UIMenuItem saveItemWithAction:@selector(saveImage)];
    UIMenuItem *forwardItem = [UIMenuItem forwardItemWithAction:@selector(forward:)];
    properties.additionalItems = @[
                                   [AdditionalMenuItem forbiddenInEphemeral:saveItem],
                                   [AdditionalMenuItem forbiddenInEphemeral:forwardItem]
                                   ];
    properties.selectedMenuBlock = ^(BOOL selected, BOOL animated) {
        [self setSelectedByMenu:selected animated:animated];
    };
    return properties;
}

- (void)saveImage
{
    if ([self.delegate respondsToSelector:@selector(conversationCell:didSelectAction:)]) {
        [self.delegate conversationCell:self didSelectAction:MessageActionSave];
    }
}

- (MessageType)messageType;
{
    return MessageTypeImage;
}

#pragma mark - Preview Provider delegate

- (CGFloat)prepareLayoutForPreviewWithMessage:(id <ZMConversationMessage>)message
{
    NOT_USED([super prepareLayoutForPreviewWithMessage:message]);
    self.autoStretchVertically = NO;
    self.defaultLayoutMargins = UIEdgeInsetsZero;
    return [PreviewHeightCalculator heightForImage:self.fullImageView.image];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    self.defaultLayoutMargins = UIView.directionAwareConversationLayoutMargins;
    [self updateImageMessageConstraintConstants];
}

@end
