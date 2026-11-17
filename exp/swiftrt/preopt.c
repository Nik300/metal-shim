// For each loaded image with Swift conformances: does dyld say its conformances are pre-optimized in the shared cache?
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) dlopen(argv[i], RTLD_NOW);
    _Bool (*has)(const void *) = dlsym(RTLD_DEFAULT, "_dyld_has_preoptimized_swift_protocol_conformances");
    unsigned long yes = 0, no = 0, ry = 0, rn = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header_64 *mh = (const void *)_dyld_get_image_header(i); unsigned long sz;
        if (!getsectiondata(mh, "__TEXT", "__swift5_proto", &sz)) continue;
        if (has(mh)) { yes++; ry += sz / 4; } else { no++; rn += sz / 4; if (no <= 8) printf("  not preoptimized: %s (%lu)\n", _dyld_get_image_name(i), sz / 4); }
    }
    printf("preoptimized images %lu (%lu records), not %lu (%lu records)\n", yes, ry, no, rn);
}
