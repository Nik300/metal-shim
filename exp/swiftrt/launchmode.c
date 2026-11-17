#include <dlfcn.h>
#include <stdio.h>
int main(void) {
    unsigned (*m)(void) = dlsym(RTLD_DEFAULT, "_dyld_launch_mode");
    printf("_dyld_launch_mode = %#x (1 using closure, 2 built at launch, 4 saved to file, 8 from OS, 0x10 minimal, 0x20 interposing, 0x40 optimized cache)\n", m ? m() : 0xdead);
}
