// Baseline: how fast does a plain OpenGL window (NSOpenGLContext, vsync on) present on this Mac?
// Compared with build/window (CAMetalLayer on the shim) to tell the system's limit from the shim's.
#import <Cocoa/Cocoa.h>
#define GL_SILENCE_DEPRECATION 1
#import <OpenGL/gl3.h>
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    int w = argc > 1 ? atoi(argv[1]) : 1024, h = argc > 2 ? atoi(argv[2]) : 768;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, w, h) styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered defer:NO];
    NSOpenGLPixelFormatAttribute a[] = { NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion4_1Core, NSOpenGLPFADoubleBuffer, NSOpenGLPFAAccelerated, 0 };
    NSOpenGLView *v = [[NSOpenGLView alloc] initWithFrame:NSMakeRect(0, 0, w, h) pixelFormat:[[NSOpenGLPixelFormat alloc] initWithAttributes:a]];
    v.wantsLayer = YES;
    win.contentView = v;
    [win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenGLContext *ctx = v.openGLContext;
    [ctx makeCurrentContext];
    GLint one = 1; [ctx setValues:&one forParameter:NSOpenGLContextParameterSwapInterval];
    // let the window appear
    for (int i = 0; i < 30; i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    int frames = 0;
    while (CFAbsoluteTimeGetCurrent() - t0 < 3) {
        glClearColor(0.1, 0.2 + 0.1 * (frames & 1), 0.3, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        [ctx flushBuffer];
        frames++;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
    }
    printf("plain GL %dx%d: %.1f fps\n", w, h, frames / (CFAbsoluteTimeGetCurrent() - t0));
} return 0; }
