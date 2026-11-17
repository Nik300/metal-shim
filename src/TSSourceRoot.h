// The metal-shim folder at run time: walks up from the executable (tools/x, build/x, build/bench/x) to the folder
// holding Makefile and src/, so the tree works wherever it is moved. TS_SOURCE_DIR (the build-time path) is the fallback.
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>

static inline NSString *TSSourceRoot(void) {
    char buf[PATH_MAX];
    uint32_t size = sizeof buf;
    if (_NSGetExecutablePath(buf, &size) == 0) {
        NSString *dir = [@(buf) stringByResolvingSymlinksInPath];
        for (int i = 0; i < 4; i++) {
            dir = dir.stringByDeletingLastPathComponent;
            BOOL isDir = NO;
            if ([NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:@"Makefile"]] &&
                [NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:@"src"] isDirectory:&isDir] && isDir)
                return dir;
        }
    }
#ifdef TS_SOURCE_DIR
    return @TS_SOURCE_DIR;
#else
    return NSFileManager.defaultManager.currentDirectoryPath;
#endif
}
