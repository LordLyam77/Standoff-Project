#import "overlay.h"
#import <QuartzCore/QuartzCore.h>
#import "tracelog.h"

static UIWindow* g_overlayWindow = nil;
static ESPOverlayView* g_overlayView = nil;
static CADisplayLink* g_displayLink = nil;
static ESP* g_espPtr = nullptr;

@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event {
    return NO;
}

- (void)drawRect:(CGRect)rect {
    if (!g_espPtr || !g_config.initialized) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetShouldAntialias(ctx, true);

    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat width = self.bounds.size.width * scale;
    CGFloat height = self.bounds.size.height * scale;

    g_espPtr->Render(ctx, width, height);
}

- (void)displayLinkTick:(CADisplayLink*)link {
    static long tick = 0;
    if ((tick++ % 300) == 0) {
        CHEAT_LOG("m: display alive tick=%ld esp=%d initialized=%d", tick, g_espPtr != nullptr, g_config.initialized);
    }
    if (g_espPtr && g_config.initialized) [self setNeedsDisplay];
}

@end

@interface ESPOverlayViewController : UIViewController
@end

@implementation ESPOverlayViewController
- (BOOL)_canShowWhileLocked { return YES; }

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}
@end

void SetupOverlayWindow() {
    if (g_overlayWindow) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_overlayWindow) return;
        @try {
            CGRect bounds = [UIScreen mainScreen].bounds;
            g_overlayWindow = [[UIWindow alloc] initWithFrame:bounds];
            g_overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
            g_overlayWindow.userInteractionEnabled = NO;
            g_overlayWindow.backgroundColor = [UIColor clearColor];

            ESPOverlayViewController* rootVC = [[ESPOverlayViewController alloc] init];
            rootVC.view.backgroundColor = [UIColor clearColor];
            rootVC.view.userInteractionEnabled = NO;

            g_overlayView = [[ESPOverlayView alloc] initWithFrame:bounds];
            g_overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [rootVC.view addSubview:g_overlayView];

            g_overlayWindow.rootViewController = rootVC;
            if (@available(iOS 13.0, *)) {
                UIWindow* keyWin = [UIApplication sharedApplication].keyWindow;
                if (keyWin && keyWin.windowScene) {
                    g_overlayWindow.windowScene = keyWin.windowScene;
                } else {
                    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
                        if ([scene isKindOfClass:[UIWindowScene class]]) {
                            g_overlayWindow.windowScene = (UIWindowScene*)scene;
                            break;
                        }
                    }
                }
            }
            g_overlayWindow.hidden = NO;

            g_espPtr = (ESP*)GetESP();

            g_displayLink = [CADisplayLink displayLinkWithTarget:g_overlayView selector:@selector(displayLinkTick:)];
            [g_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        } @catch (NSException* e) {
            CHEAT_LOG("m: SetupOverlayWindow exception: %s", e.reason ? e.reason.UTF8String : "unknown");
        }
    });
}