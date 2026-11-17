// Is IOSurfaceIncrementUseCount in one process visible to IOSurfaceIsInUse in another?
// usecount owner: creates a surface, prints its mach-port-free id, increments, waits; usecount check <id>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
int main(int argc, char **argv) { @autoreleasepool {
    if (argc > 2 && !strcmp(argv[1], "check")) {
        // IOSurfaceLookup needs a global surface (deprecated flag, still honoured)
        IOSurfaceRef s = IOSurfaceLookup((IOSurfaceID)atoi(argv[2]));
        if (!s) { printf("lookup failed\n"); return 1; }
        printf("other process: IsInUse=%d\n", IOSurfaceIsInUse(s));
        return 0;
    }
    NSDictionary *p = @{ (id)kIOSurfaceWidth: @256, (id)kIOSurfaceHeight: @256, (id)kIOSurfaceBytesPerElement: @4,
                         (id)kIOSurfacePixelFormat: @('BGRA'), @"IOSurfaceIsGlobal": @YES };
    IOSurfaceRef s = IOSurfaceCreate((__bridge CFDictionaryRef)p);
    printf("id %u IsInUse before=%d\n", IOSurfaceGetID(s), IOSurfaceIsInUse(s));
    char cmd[256];
    snprintf(cmd, sizeof cmd, "%s check %u", argv[0], IOSurfaceGetID(s)); system(cmd);
    IOSurfaceIncrementUseCount(s);
    printf("same process after increment: IsInUse=%d\n", IOSurfaceIsInUse(s));
    system(cmd);
    IOSurfaceDecrementUseCount(s);
    system(cmd);
    return 0;
} }
