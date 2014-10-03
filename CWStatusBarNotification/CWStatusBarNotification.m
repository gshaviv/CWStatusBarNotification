//
//  CWStatusBarNotification.m
//  CWNotificationDemo
//
//  Created by Cezary Wojcik on 11/15/13.
//  Copyright (c) 2013 Cezary Wojcik. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "CWStatusBarNotification.h"
#import "UIDevice-hardware.h"

#define STATUS_BAR_ANIMATION_LENGTH 0.25f
#define FONT_SIZE 12.0f
#define PADDING 10.0f
#define SCROLL_SPEED 40.0f
#define SCROLL_DELAY 1.0f

@interface StupidViewController : UIViewController

@end

@implementation CWWindowContainer

- (UIView*) hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint([[UIApplication sharedApplication] statusBarFrame], point)) {
        return [super hitTest:point withEvent:event];
    }

    return nil;
}

@end

# pragma mark - dispatch after with cancellation
// adapted from: https://github.com/Spaceman-Labs/Dispatch-Cancel

typedef void(^CWDelayedBlockHandle)(BOOL cancel);

@interface NotificationWindow : UIWindow

@end

@implementation NotificationWindow

- (UIView*) hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (CGRectContainsPoint([[UIApplication sharedApplication] statusBarFrame], point)) {
        return [super hitTest:point withEvent:event];
    }

    return nil;
}

@end

static CWDelayedBlockHandle perform_block_after_delay(CGFloat seconds, dispatch_block_t block)
{
	if (block == nil) {
		return nil;
	}

	__block dispatch_block_t blockToExecute = [block copy];
	__block CWDelayedBlockHandle delayHandleCopy = nil;

	CWDelayedBlockHandle delayHandle = ^(BOOL cancel){
		if (NO == cancel && nil != blockToExecute) {
			dispatch_async(dispatch_get_main_queue(), blockToExecute);
		}
        
		blockToExecute = nil;
		delayHandleCopy = nil;
	};

	delayHandleCopy = [delayHandle copy];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (nil != delayHandleCopy) {
			delayHandleCopy(NO);
		}
	});

	return delayHandleCopy;
};

static void cancel_delayed_block(CWDelayedBlockHandle delayedHandle)
{
	if (delayedHandle == nil) {
		return;
	}

	delayedHandle(YES);
}

# pragma mark - ScrollLabel

@implementation ScrollLabel
{
    UIImageView *textImage;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        textImage = [[UIImageView alloc] init];
        [self addSubview:textImage];
    }
    return self;
}

- (CGFloat)fullWidth
{
    return [self.text sizeWithAttributes:@{NSFontAttributeName: self.font}].width;
}

- (CGFloat)scrollOffset
{
    if (self.numberOfLines != 1) return 0;

    CGRect insetRect = CGRectInset(self.bounds, PADDING, 0);
    return MAX(0, [self fullWidth] - insetRect.size.width);
}

- (CGFloat)scrollTime
{
    return ([self scrollOffset] > 0) ? [self scrollOffset] / SCROLL_SPEED + SCROLL_DELAY : 0;
}

- (void)drawTextInRect:(CGRect)rect
{
    if ([self scrollOffset] > 0) {
        rect.size.width = [self fullWidth] + PADDING * 2;
        UIGraphicsBeginImageContextWithOptions(rect.size, NO, [UIScreen mainScreen].scale);
        [super drawTextInRect:rect];
        textImage.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [textImage sizeToFit];
        [UIView animateWithDuration:[self scrollTime] - SCROLL_DELAY
                              delay:SCROLL_DELAY
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             textImage.transform = CGAffineTransformMakeTranslation(-[self scrollOffset], 0);
                         } completion:^(BOOL finished) {
                         }];
    } else {
        textImage.image = nil;
        [super drawTextInRect:CGRectInset(rect, PADDING, 0)];
    }
}

@end

# pragma mark - CWStatusBarNotification

@interface CWStatusBarNotification()

@property (strong, nonatomic) UITapGestureRecognizer *tapGestureRecognizer;
@property (strong, nonatomic) CWDelayedBlockHandle dismissHandle;

@end

@implementation CWStatusBarNotification

@synthesize notificationLabel, notificationLabelBackgroundColor, notificationLabelTextColor, notificationWindow;

@synthesize statusBarView;

@synthesize notificationStyle, notificationIsShowing;

- (CWStatusBarNotification *)init
{
    self = [super init];
    if (self) {
        // set defaults
        self.notificationLabelBackgroundColor = [[UIApplication sharedApplication] delegate].window.tintColor;
        self.notificationLabelTextColor = [UIColor whiteColor];
        self.notificationStyle = CWNotificationStyleStatusBarNotification;
        self.notificationAnimationInStyle = CWNotificationAnimationStyleBottom;
        self.notificationAnimationOutStyle = CWNotificationAnimationStyleBottom;
        self.notificationAnimationType = CWNotificationAnimationTypeReplace;
        self.notificationIsDismissing = NO;

        // create tap recognizer
        self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(notificationTapped:)];
        self.tapGestureRecognizer.numberOfTapsRequired = 1;

        // create default tap block
        @weaken(self);
        self.notificationTappedBlock = ^(void) {
            if (!weak_self.notificationIsDismissing) {
                [weak_self dismissNotification];
            }
        };
    }
    return self;
}

# pragma mark - dimensions

- (CGFloat)getStatusBarHeight
{
    if (self.notificationLabelHeight > 0) {
        return self.notificationLabelHeight;
    }
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
#ifdef __IPHONE_8_0
    if ([UIDevice currentSystemVersionIsLessThan:8 :0 :0]) {
#endif
        if (UIDeviceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
            statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.width;
        }
#ifdef __IPHONE_8_0
    }
#endif

    return statusBarHeight > 0 ? statusBarHeight : 20;
}

- (CGFloat)getStatusBarWidth
{
#ifdef __IPHONE_8_0
    if ([UIDevice currentSystemVersionIsLessThan:8 :0 :0]) {
#endif
        if (UIDeviceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation)) {
            return [UIScreen mainScreen].bounds.size.width;
        }
        return [UIScreen mainScreen].bounds.size.height;
#ifdef __IPHONE_8_0
    } else {
        return notificationWindow.bounds.size.width;
    }
#endif
}

- (CGFloat)getStatusBarOffset
{
    if ([self getStatusBarHeight] == 40.0f) {
        return -20.0f;
    }
    return 0.0f;
}

- (CGRect)getNotificationLabelTopFrame
{
    return CGRectMake(0, [self getStatusBarOffset] + -1*[self getNotificationLabelHeight], [self getStatusBarWidth], [self getNotificationLabelHeight]);
}

- (CGRect)getNotificationLabelLeftFrame
{
    return CGRectMake(-1*[self getStatusBarWidth], [self getStatusBarOffset], [self getStatusBarWidth], [self getNotificationLabelHeight]);
}

- (CGRect)getNotificationLabelRightFrame
{
    return CGRectMake([self getStatusBarWidth], [self getStatusBarOffset], [self getStatusBarWidth], [self getNotificationLabelHeight]);
}

- (CGRect)getNotificationLabelBottomFrame
{
    return CGRectMake(0, [self getStatusBarOffset] + [self getNotificationLabelHeight], [self getStatusBarWidth], 0);
}

- (CGRect)getNotificationLabelFrame
{
    return CGRectMake(0, [self getStatusBarOffset], [self getStatusBarWidth], [self getNotificationLabelHeight]);
}

- (CGFloat)getNavigationBarHeight
{
    if (UIDeviceOrientationIsPortrait([UIApplication sharedApplication].statusBarOrientation) ||
        UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return 44.0f;
    }
    return 30.0f;
}

- (CGFloat)getNotificationLabelHeight
{
    switch (self.notificationStyle) {
        case CWNotificationStyleStatusBarNotification:
            return [self getStatusBarHeight];
        case CWNotificationStyleNavigationBarNotification:
            return [self getStatusBarHeight] + [self getNavigationBarHeight];
        default:
            return [self getStatusBarHeight];
    }
}

# pragma mark - screen orientation change

- (void)updateStatusBarFrame
{
    self.notificationLabel.frame = [self getNotificationLabelFrame];
    self.statusBarView.hidden = YES;
}

# pragma mark - on tap

- (void)notificationTapped:(UITapGestureRecognizer*)recognizer
{
    [self.notificationTappedBlock invoke];
}

# pragma mark - display helpers


- (void)createNotificationLabelWithMessage:(NSString *)message
{
    self.notificationLabel = [ScrollLabel new];
    self.notificationLabel.numberOfLines = self.multiline ? 0 : 1;
    self.notificationLabel.text = message;
    self.notificationLabel.textAlignment = NSTextAlignmentCenter;
    self.notificationLabel.adjustsFontSizeToFitWidth = NO;
    self.notificationLabel.font = [UIFont systemFontOfSize:FONT_SIZE];
    self.notificationLabel.backgroundColor = self.notificationLabelBackgroundColor;
    self.notificationLabel.textColor = self.notificationLabelTextColor;
    self.notificationLabel.clipsToBounds = YES;
    self.notificationLabel.userInteractionEnabled = YES;
    [self.notificationLabel addGestureRecognizer:self.tapGestureRecognizer];
    switch (self.notificationAnimationInStyle) {
        case CWNotificationAnimationStyleTop:
            self.notificationLabel.frame = [self getNotificationLabelTopFrame];
            break;
        case CWNotificationAnimationStyleBottom:
            self.notificationLabel.frame = [self getNotificationLabelBottomFrame];
            break;
        case CWNotificationAnimationStyleLeft:
            self.notificationLabel.frame = [self getNotificationLabelLeftFrame];
            break;
        case CWNotificationAnimationStyleRight:
            self.notificationLabel.frame = [self getNotificationLabelRightFrame];
            break;
    }
}

- (void)createNotificationWindow
{
    self.notificationWindow = [[CWWindowContainer alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.notificationWindow.backgroundColor = [UIColor clearColor];
    self.notificationWindow.userInteractionEnabled = YES;
    self.notificationWindow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.notificationWindow.windowLevel = UIWindowLevelStatusBar;
    UIViewController *vc = [StupidViewController new];
    self.notificationWindow.rootViewController = vc;
}

- (void)createStatusBarView
{
    self.statusBarView = [[UIView alloc] initWithFrame:[self getNotificationLabelFrame]];
    self.statusBarView.clipsToBounds = YES;
    if (self.notificationAnimationType == CWNotificationAnimationTypeReplace) {
        UIView *statusBarImageView = [[UIScreen mainScreen] snapshotViewAfterScreenUpdates:YES];
        [self.statusBarView addSubview:statusBarImageView];
    }
    [self.notificationWindow.rootViewController.view addSubview:self.statusBarView];
    [self.notificationWindow.rootViewController.view sendSubviewToBack:self.statusBarView];
}

# pragma mark - frame changing

- (void)firstFrameChange
{
    self.notificationLabel.frame = [self getNotificationLabelFrame];
    switch (self.notificationAnimationInStyle) {
        case CWNotificationAnimationStyleTop:
            self.statusBarView.frame = [self getNotificationLabelBottomFrame];
            break;
        case CWNotificationAnimationStyleBottom:
            self.statusBarView.frame = [self getNotificationLabelTopFrame];
            break;
        case CWNotificationAnimationStyleLeft:
            self.statusBarView.frame = [self getNotificationLabelRightFrame];
            break;
        case CWNotificationAnimationStyleRight:
            self.statusBarView.frame = [self getNotificationLabelLeftFrame];
            break;
    }
}

- (void)secondFrameChange
{
    switch (self.notificationAnimationOutStyle) {
        case CWNotificationAnimationStyleTop:
            self.statusBarView.frame = [self getNotificationLabelBottomFrame];
            break;
        case CWNotificationAnimationStyleBottom:
            self.statusBarView.frame = [self getNotificationLabelTopFrame];
            self.notificationLabel.layer.anchorPoint = CGPointMake(0.5f, 1.0f);
            self.notificationLabel.center = CGPointMake(self.notificationLabel.center.x, [self getStatusBarOffset] + [self getNotificationLabelHeight]);
            break;
        case CWNotificationAnimationStyleLeft:
            self.statusBarView.frame = [self getNotificationLabelRightFrame];
            break;
        case CWNotificationAnimationStyleRight:
            self.statusBarView.frame = [self getNotificationLabelLeftFrame];
            break;
    }
}

- (void)thirdFrameChange
{
    self.statusBarView.frame = [self getNotificationLabelFrame];
    switch (self.notificationAnimationOutStyle) {
        case CWNotificationAnimationStyleTop:
            self.notificationLabel.frame = [self getNotificationLabelTopFrame];
            break;
        case CWNotificationAnimationStyleBottom:
            self.notificationLabel.transform = CGAffineTransformMakeScale(1.0f, 0.0f);
            break;
        case CWNotificationAnimationStyleLeft:
            self.notificationLabel.frame = [self getNotificationLabelLeftFrame];
            break;
        case CWNotificationAnimationStyleRight:
            self.notificationLabel.frame = [self getNotificationLabelRightFrame];
            break;
    }
}

# pragma mark - display notification

- (void)displayNotificationWithMessage:(NSString *)message completion:(void (^)(void))completion
{
    if (!self.notificationIsShowing) {
        self.notificationIsShowing = YES;

        // create UIWindow
        [self createNotificationWindow];

        // create ScrollLabel
        [self createNotificationLabelWithMessage:message];

        // create status bar view
        [self createStatusBarView];

        // add label to window
        [self.notificationWindow.rootViewController.view addSubview:self.notificationLabel];
        [self.notificationWindow.rootViewController.view bringSubviewToFront:self.notificationLabel];
        [self.notificationWindow setHidden:NO];

        // checking for screen orientation change
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatusBarFrame) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
        
        // checking for status bar change
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatusBarFrame) name:UIApplicationWillChangeStatusBarFrameNotification object:nil];

        // animate
        [UIView animateWithDuration:STATUS_BAR_ANIMATION_LENGTH animations:^{
            [self firstFrameChange];
        } completion:^(BOOL finished) {
            double delayInSeconds = [self.notificationLabel scrollTime];
            perform_block_after_delay(delayInSeconds, ^{
                [completion invoke];
            });
        }];
    }
}

- (void)dismissNotification
{
    if (self.notificationIsShowing) {
        cancel_delayed_block(self.dismissHandle);
        self.notificationIsDismissing = YES;
        [self secondFrameChange];
        [UIView animateWithDuration:STATUS_BAR_ANIMATION_LENGTH animations:^{
            [self thirdFrameChange];
        } completion:^(BOOL finished) {
            [self.notificationLabel removeFromSuperview];
            [self.statusBarView removeFromSuperview];
            [self.notificationWindow setHidden:YES];
            self.notificationWindow = nil;
            self.notificationLabel = nil;
            self.notificationIsShowing = NO;
            self.notificationIsDismissing = NO;
            [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillChangeStatusBarFrameNotification object:nil];
        }];
    }
}

- (void)displayNotificationWithMessage:(NSString *)message forDuration:(CGFloat)duration
{
    [self displayNotificationWithMessage:message completion:^{
        self.dismissHandle = perform_block_after_delay(duration, ^{
            [self dismissNotification];
        });
    }];
}

@end

@implementation StupidViewController

- (BOOL) shouldAutorotate {
    return YES;
}

- (NSUInteger) supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end
