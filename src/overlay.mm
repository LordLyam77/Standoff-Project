#import "overlay.h"
#import "esp.h"
#import "aimbot.h"
#import "recoil.h"
#import <QuartzCore/QuartzCore.h>
#import "tracelog.h"

static UIWindow* g_overlayWindow = nil;
static ESPOverlayView* g_overlayView = nil;
static CADisplayLink* g_displayLink = nil;

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
    if (!g_config.initialized) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetShouldAntialias(ctx, true);

    // Points, not pixels. drawRect's context is in UIKit points; the previous
    // version multiplied by UIScreen.scale and drew at 2x/3x offsets.
    GetESP()->Render(ctx, self.bounds.size.width, self.bounds.size.height);
}

- (void)displayLinkTick:(CADisplayLink*)link {
    static CFTimeInterval last = 0;
    CFTimeInterval now = link.timestamp;
    float dt = (last > 0.0) ? (float)(now - last) : 0.016f;
    if (dt > 0.1f) dt = 0.1f;
    if (dt < 0.001f) dt = 0.001f;
    last = now;

    static long tick = 0;
    if ((tick++ % 600) == 0) {
        CHEAT_LOG("m: tick esp=%d init=%d aim=%d rec=%d",
                  g_config.espEnabled, g_config.initialized,
                  g_config.aimbotEnabled, g_config.recoilEnabled);
    }

    if (!g_config.initialized) return;

    // Everything IL2CPP-touching now runs on the main thread, in step with the
    // engine. The old build called FindObjectsOfType and WorldToScreenPoint from
    // a 16ms background thread, which is how you get stale/torn scene data.
    GetESP()->Update();

    if (g_config.aimbotEnabled) {
        GetAimbot()->SetPlayerList(&g_players);
        GetAimbot()->Update(dt);
    }
    GetRecoilControl()->Update();

    [self setNeedsDisplay];
}

@end

@interface ESPOverlayViewController : UIViewController
@end

@implementation ESPOverlayViewController
- (BOOL)_canShowWhileLocked { return YES; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }
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

            g_displayLink = [CADisplayLink displayLinkWithTarget:g_overlayView selector:@selector(displayLinkTick:)];
            [g_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

            CHEAT_LOG("m: overlay window ready");
        } @catch (NSException* e) {
            CHEAT_LOG("m: SetupOverlayWindow exception: %s", e.reason ? e.reason.UTF8String : "unknown");
        }
    });
}
