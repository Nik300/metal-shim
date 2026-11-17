// Is some shared-cache image overridden by a file on disk (a "root")? Which loaded /System images come from disk?
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) dlopen(argv[i], RTLD_NOW);
    _Bool (*some)(void) = dlsym(RTLD_DEFAULT, "dyld_shared_cache_some_image_overridden");
    printf("dyld_shared_cache_some_image_overridden: %d\n", some ? some() : -1);
    int n = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *mh = _dyld_get_image_header(i); const char *p = _dyld_get_image_name(i);
        if (!(mh->flags & 0x80000000) && (!strncmp(p, "/System/", 8) || !strncmp(p, "/usr/lib/", 9))) { printf("  from disk: %s\n", p); n++; }
    }
    printf("%d system images loaded from disk out of %u\n", n, _dyld_image_count());
}
