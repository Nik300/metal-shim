// fdump <symbol> [bytes]: dumps the first bytes of an exported libswiftCore function to f.bin (address in stdout), then sleeps.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    void *h = dlopen("/usr/lib/swift/libswiftCore.dylib", RTLD_NOW); void *f = dlsym(h, argv[1]);
    int n = argc > 2 ? atoi(argv[2]) : 160; FILE *o = fopen("f.bin", "wb"); fwrite(f, 1, n, o); fclose(o);
    printf("%p\n", f); fflush(stdout); sleep(20);
}
