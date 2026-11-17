// xref <string>: finds rip-relative references to a C string inside libswiftCore's __text, dumps the enclosing code as a
// tiny raw file per hit (xref-N.bin, with its load address in xref-N.addr), then sleeps so atos -p can symbolize.
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    dlopen("/usr/lib/swift/libswiftCore.dylib", RTLD_NOW);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (!strstr(_dyld_get_image_name(i), "libswiftCore.dylib")) continue;
        const struct mach_header_64 *mh = (const void *)_dyld_get_image_header(i);
        unsigned long cs, ts; char *c = (char *)getsectiondata(mh, "__TEXT", "__cstring", &cs); unsigned char *t = getsectiondata(mh, "__TEXT", "__text", &ts);
        char *s = NULL; for (char *p = c; p < c + cs; p += strlen(p) + 1) if (!strcmp(p, argv[1])) s = p;
        printf("string at %p, text %p\n", s, t);
        int hits = 0;
        for (unsigned long k = 0; k + 7 < ts; k++) {
            if ((t[k] & 0xFB) != 0x48 || t[k + 1] != 0x8D || (t[k + 2] & 0xC7) != 0x05) continue;
            int32_t d; memcpy(&d, t + k + 3, 4);
            if ((char *)t + k + 7 + d != s) continue;
            unsigned char *b = t + k - 160; char fn[64]; snprintf(fn, 64, "xref-%d.bin", hits);
            FILE *f = fopen(fn, "wb"); fwrite(b, 1, 400, f); fclose(f);
            printf("hit %d at %p (dump from %p)\n", hits, t + k, b); hits++;
        }
        fflush(stdout); sleep(30);
    }
}
