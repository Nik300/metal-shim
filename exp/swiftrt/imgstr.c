// imgstr <image-substring> <pattern>...: prints the C strings of a loaded image (shared cache included) containing a pattern.
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    dlopen("/usr/lib/swift/libswiftCore.dylib", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph", RTLD_NOW);
    dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI", RTLD_NOW);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (!strstr(n, argv[1])) continue;
        const struct mach_header_64 *mh = (const void *)_dyld_get_image_header(i);
        const char *secs[][2] = {{"__TEXT", "__cstring"}, {"__TEXT", "__const"}, {"__DATA_CONST", "__const"}};
        for (int s = 0; s < 3; s++) {
            unsigned long sz; char *p = (char *)getsectiondata(mh, secs[s][0], secs[s][1], &sz);
            if (!p) continue;
            for (char *e = p + sz; p < e; p += strnlen(p, e - p) + 1)
                for (int a = 2; a < argc; a++) if (strstr(p, argv[a])) { printf("%s\n", p); break; }
        }
    }
}
