// tsmtl-fake-emitter: test helper that imitates the TeraScale Metal bundle's os_log output
// (subsystem com.terascale.mtlshim, every category of docs/FASE4-INTERFACCE.md) so that the
// control app and `tsmtl` can be tested without installing anything.
//
// Stats lines follow the contract's lease: the emitter registers for the Darwin notification
// com.terascale.mtlshim.stats with notify_register_dispatch, and only after a post with a fresh
// lease (state = Unix time, now - state < 5) starts a 1 s timer that writes one JSON line per
// second; the timer stops as soon as the lease is stale or zero.
//
// Usage: tsmtl-fake-emitter [--id <bundle id>] [--name <name>] [--path <app path>]
//                           [--seconds N] [--off] [--once] [--quiet]
//   --once   emit one line per category (policy, general, warning, error, unimplemented) and exit
//   --off    report the process as "policy: off" (reason outside) and never write stats
//   --quiet  no stderr trace
// Build:   clang -O2 -Wall tools/tsmtl-fake-emitter.c -o build/tsmtl-fake-emitter
#include <os/log.h>
#include <notify.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define STATS_NOTIFY "com.terascale.mtlshim.stats"

static os_log_t lgGeneral, lgWarning, lgError, lgUnimpl, lgPolicy, lgStats;
static const char *appId = "com.example.FakeApp", *appName = "FakeApp", *appPath = "/Applications/FakeApp.app";
static int quiet, statsLines;
static int leaseToken = NOTIFY_TOKEN_INVALID;
static dispatch_queue_t leaseQueue;
static dispatch_source_t leaseTimer;

static void trace(const char *what) { if (!quiet) fprintf(stderr, "[fake %d] %s\n", getpid(), what); }

static int leaseFresh(void) {
    uint64_t state = 0;
    if (notify_get_state(leaseToken, &state) != NOTIFY_STATUS_OK || !state) return 0;
    int64_t age = (int64_t)time(NULL) - (int64_t)state;
    return age >= -5 && age < 5;
}

static void emitStats(void) {
    static unsigned tick;
    tick++;
    double fps = 28 + (tick % 7) * 0.4, busy = 0.12 + (tick % 5) * 0.03;
    char line[512];
    snprintf(line, sizeof line,
             "{\"app\":\"%s\",\"bufKB\":%u,\"cmdbufs\":%u,\"draws\":%u,\"drawableWaitMs\":%u,\"fallbacks\":%u,"
             "\"fps\":%.1f,\"gpuBusy\":%.3f,\"links\":%u,\"memMB\":%.1f,\"name\":\"%s\",\"passes\":%u,"
             "\"pid\":%d,\"pipelines\":%u,\"readbacks\":%u,\"texKB\":%u,\"translations\":%u,\"v\":1}",
             appId, 256 + (tick % 9) * 64, 60, 1100 + (tick % 13) * 25, 640, tick > 5 ? 1u : 0u,
             fps, busy, tick < 3 ? 2u : 0u, 64.0 + tick * 0.1, appName, 80,
             getpid(), 140 + (tick < 20 ? tick : 20), 0, 1024 + (tick % 4) * 512, tick < 3 ? 2u : 0u);
    os_log(lgStats, "%{public}s", line);
    statsLines++;
}

// Same shape as TSLeaseCheck() in src/TSMtlSystem.m: start the 1 s timer on a post with a fresh lease.
static void leaseCheck(void) {
    if (leaseTimer || !leaseFresh()) return;
    trace("lease fresh: stats on");
    leaseTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, leaseQueue);
    dispatch_source_set_timer(leaseTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 20);
    dispatch_source_set_event_handler(leaseTimer, ^{
        if (!leaseFresh()) {
            trace("lease stale: stats off");
            dispatch_source_cancel(leaseTimer);
            leaseTimer = NULL;
            return;
        }
        emitStats();
    });
    dispatch_resume(leaseTimer);
}


int main(int argc, char **argv) {
    int seconds = 30, off = 0, once = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--id") && i + 1 < argc) appId = argv[++i];
        else if (!strcmp(argv[i], "--name") && i + 1 < argc) appName = argv[++i];
        else if (!strcmp(argv[i], "--path") && i + 1 < argc) appPath = argv[++i];
        else if (!strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--off")) off = 1;
        else if (!strcmp(argv[i], "--once")) once = 1;
        else if (!strcmp(argv[i], "--quiet")) quiet = 1;
        else { fprintf(stderr, "usage: %s [--id ID] [--name NAME] [--path PATH] [--seconds N] [--off] [--once] [--quiet]\n", argv[0]); return 2; }
    }
    lgGeneral = os_log_create("com.terascale.mtlshim", "general");
    lgWarning = os_log_create("com.terascale.mtlshim", "warning");
    lgError   = os_log_create("com.terascale.mtlshim", "error");
    lgUnimpl  = os_log_create("com.terascale.mtlshim", "unimplemented");
    lgPolicy  = os_log_create("com.terascale.mtlshim", "policy");
    lgStats   = os_log_create("com.terascale.mtlshim", "stats");

    os_log(lgPolicy, "policy: %{public}s id=%{public}s reason=%{public}s name=%{public}s path=%{public}s",
           off ? "off" : "on", appId, off ? "outside" : "auto", appName, appPath);
    if (off) return 0;
    os_log_info(lgGeneral, "%{public}s", "device ready: AMD Radeon HD 6750M via OpenGL 4.1 (fake emitter)");
    os_log(lgWarning, "%{public}s", "pixel format MTLPixelFormatBGR10A2Unorm replaced with RGB10_A2 (fake)");
    os_log_error(lgError, "%{public}s", "framebuffer incomplete (0x8CD6) in pass 'Shadow' (fake)");
    os_log(lgUnimpl, "%{public}s", "-[MTLComputeCommandEncoder dispatchThreadgroups:threadsPerThreadgroup:] is a no-op (fake)");
    if (once) { trace("emitted one line per category"); return 0; }

    leaseQueue = dispatch_queue_create("fake.lease", DISPATCH_QUEUE_SERIAL);
    if (notify_register_dispatch(STATS_NOTIFY, &leaseToken, leaseQueue, ^(int t) { (void)t; leaseCheck(); }) != NOTIFY_STATUS_OK) {
        fprintf(stderr, "notify_register_dispatch failed\n");
        return 1;
    }
    dispatch_async(leaseQueue, ^{ leaseCheck(); });   // a viewer may already be open

    // Some background chatter in every category, a few seconds apart.
    static const char *unimpl[] = {
        "-[MTLDevice newIndirectCommandBufferWithDescriptor:maxCommandCount:options:] returns a stub (fake)",
        "-[MTLRenderCommandEncoder setTessellationFactorBuffer:offset:instanceStride:] is a no-op (fake)",
        "-[MTLDevice newAccelerationStructureWithSize:] returns a stub (fake)",
    };
    __block unsigned n = 0;
    dispatch_source_t chatter = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(chatter, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 3 * NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(chatter, ^{
        switch (n++ % 4) {
        case 0: os_log_info(lgGeneral, "translation cache hit: %{public}s (fake)", "vs_0x1a2b/fs_0x3c4d"); break;
        case 1: os_log(lgWarning, "separate back-face stencil ignored in pipeline #%{public}u (fake)", n); break;
        case 2: os_log_error(lgError, "AIR translation failed for 'fragment_main_%{public}u' -> fallback shader (fake)", n); break;
        case 3: os_log(lgUnimpl, "%{public}s", unimpl[(n / 4) % 3]); break;
        }
    });
    dispatch_resume(chatter);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        char msg[64];
        snprintf(msg, sizeof msg, "done, %d stats lines", statsLines);
        trace(msg);
        exit(0);
    });
    dispatch_main();
}
