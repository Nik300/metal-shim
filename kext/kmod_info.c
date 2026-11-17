// kmod_info for TSMetalEnabler (what Xcode generates for a kext target): libkmod's _start/_stop
// call _realmain/_antimain, which are Lilu's plugin entry points from plugin_start.cpp.
#include <mach/mach_types.h>

extern kern_return_t TSMetalEnabler_kern_start(kmod_info_t *, void *);
extern kern_return_t TSMetalEnabler_kern_stop(kmod_info_t *, void *);
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);

__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(com.terascale.TSMetalEnabler, "1.0.0", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = TSMetalEnabler_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = TSMetalEnabler_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
