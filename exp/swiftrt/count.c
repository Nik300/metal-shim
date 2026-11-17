// count [framework paths...]: dlopens the given images, then counts Swift conformance records per loaded image.
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { unsigned long n; const char *name; } E;
static int cmp(const void *a, const void *b) { return (int)((const E *)b)->n - (int)((const E *)a)->n; }
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) if (!dlopen(argv[i], RTLD_NOW)) fprintf(stderr, "no %s\n", argv[i]);
    E e[4096]; int k = 0; unsigned long tot = 0, out = 0, types = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header_64 *mh = (const void *)_dyld_get_image_header(i);
        unsigned long sz = 0, tsz = 0;
        if (!getsectiondata(mh, "__TEXT", "__swift5_proto", &sz)) continue;
        getsectiondata(mh, "__TEXT", "__swift5_types", &tsz);
        types += tsz / 4;
        e[k].n = sz / 4; e[k].name = strrchr(_dyld_get_image_name(i), '/') + 1; k++; tot += sz / 4;
        if (!(mh->flags & 0x80000000)) out += sz / 4;
    }
    qsort(e, k, sizeof *e, cmp);
    printf("images %u, with conformances %d, records %lu (outside shared cache %lu), type descriptors %lu\n", _dyld_image_count(), k, tot, out, types);
    for (int i = 0; i < 12 && i < k; i++) printf("  %6lu %s\n", e[i].n, e[i].name);
}
