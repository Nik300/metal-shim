// Asks dyld's shared-cache Swift tables directly: Int:Equatable (yes) and Mirror:Equatable (no).
#include <dlfcn.h>
#include <stdio.h>
struct res { int kind; const void *value; };
int main(void) {
    void *core = dlopen("/usr/lib/swift/libswiftCore.dylib", RTLD_NOW);
    unsigned (*ver)(void) = dlsym(RTLD_DEFAULT, "_dyld_swift_optimizations_version");
    struct res (*find)(const void *, const void *, const void *) = dlsym(RTLD_DEFAULT, "_dyld_find_protocol_conformance");
    printf("optimizations version %u, find %p\n", ver ? ver() : 0, (void *)find);
    const void *eq = dlsym(core, "$sSQMp"), *intD = dlsym(core, "$sSiMn"), *intM = dlsym(core, "$sSiN"), *mirD = dlsym(core, "$ss6MirrorVMn"), *mirM = dlsym(core, "$ss6MirrorVN");
    printf("Equatable %p Int %p/%p Mirror %p/%p\n", eq, intD, intM, mirD, mirM);
    if (!find) return 0;
    struct res a = find(eq, intM, intD), b = find(eq, mirM, mirD);
    printf("Int:Equatable kind %d (%p)\nMirror:Equatable kind %d (%p)\n(0 descriptor, 1 witness table, 2 not found, 3 definitive failure)\n", a.kind, a.value, b.kind, b.value);
}
