// cfspy.dylib: DYLD_INSERT_LIBRARIES interposer for swift_conformsToProtocol{,2}. At exit (or after CFSPY_SECS seconds)
// prints how many top-level lookups ran, their time, how many failed, and how many a per-descriptor cache could skip.
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static int insert(uintptr_t s[][2], uintptr_t a, uintptr_t b);
static int contains(uintptr_t s[][2], uintptr_t a, uintptr_t b);
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
// Prototype index: (protocol descriptor, type descriptor) of every conformance record in the loaded images.
#define ICAP (1 << 18)
static uintptr_t idx[ICAP][2]; static uint32_t idxImages; static uint64_t idxRecords, idxSpecial, idxBuildNs;
static uint64_t nNoCand, nsNoCand, nCandFail, nsCandFail;
static const void *rel(const int32_t *p) { return (const char *)p + *p; }
static const void *relInd(const int32_t *p) { int32_t o = *p; const char *a = (const char *)p + (o & ~1); return (o & 1) ? *(const void *const *)a : a; }
static void buildIndex(void) {
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    memset(idx, 0, sizeof idx); idxRecords = idxSpecial = 0;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        unsigned long sz = 0; const int32_t *r = (const int32_t *)getsectiondata((const void *)_dyld_get_image_header(i), "__TEXT", "__swift5_proto", &sz);
        for (unsigned long k = 0; r && k < sz / 4; k++) {
            const int32_t *cd = rel(&r[k]); uint32_t fl = (uint32_t)cd[3]; unsigned kind = (fl >> 3) & 7;
            const void *proto = relInd(&cd[0]), *td;
            if (kind == 0) td = rel(&cd[1]); else if (kind == 1) td = *(const void *const *)rel(&cd[1]); else { idxSpecial++; continue; }
            if (fl & 0x80) idxSpecial++;   // synthesized non-unique: matched by name, the prototype defers on those types
            insert(idx, (uintptr_t)proto, (uintptr_t)td); idxRecords++;
        }
    }
    idxImages = n; idxBuildNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0;
}
#define DYLD_INTERPOSE(_r, _o) __attribute__((used)) static struct { const void *r, *o; } _ip_##_o \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)_r, (const void *)_o };
extern const void *swift_conformsToProtocol(const void *type, const void *proto);
extern const void *swift_conformsToProtocol2(const void *type, const void *proto);

static __thread int depth;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static uint64_t nDistDesc, nDistType;
static const void *pk[256]; static uint64_t pn[256], pns[256];
static uint64_t nRepType, nsRepType, nKind[4], nsKind[4];
static uint64_t n, nNeg, nGen, nNegGen, ns, nsNeg, nsNegRepeatDesc, nRepeatDesc, nsMax;
// open-addressing sets: (desc,proto) seen negative; (type,proto) seen
#define CAP (1 << 18)
static uintptr_t setA[CAP][2], setB[CAP][2];
static int insert(uintptr_t s[][2], uintptr_t a, uintptr_t b) {   // 1 if newly inserted
    uintptr_t h = (a * 0x9E3779B97F4A7C15ull ^ b * 0xC2B2AE3D27D4EB4Full) >> 40;
    for (;; h++) { uintptr_t *e = s[h & (CAP - 1)]; if (!e[0]) { e[0] = a; e[1] = b; return 1; } if (e[0] == a && e[1] == b) return 0; }
}
static int contains(uintptr_t s[][2], uintptr_t a, uintptr_t b) {
    uintptr_t h = (a * 0x9E3779B97F4A7C15ull ^ b * 0xC2B2AE3D27D4EB4Full) >> 40;
    for (;; h++) { uintptr_t *e = s[h & (CAP - 1)]; if (!e[0]) return 0; if (e[0] == a && e[1] == b) return 1; }
}
static const uint32_t *descOf(const uintptr_t *md) {
    uintptr_t kind = md[0];
    if (kind == 0x200 || kind == 0x201 || kind == 0x202) return (const uint32_t *)md[1];
    if (kind > 0x7FF && (md[4] & 3)) return (const uint32_t *)md[8];   // Swift class: Description at +64
    return NULL;
}
static const char *protoName(const void *p) {
    const int32_t *d = (const int32_t *)((uintptr_t)p & ~(uintptr_t)1);
    if ((uintptr_t)p & 1) return "(objc)";
    return (const char *)&d[2] + d[2];
}
static void report(void) {
    pthread_mutex_lock(&mu);
    fprintf(stderr, "[cfspy %d %s] lookups %llu (%.0f ms, max %.2f ms); failed %llu (%.0f ms); generic %llu (failed %llu); "
            "failed with a descriptor already seen failing: %llu (%.0f ms)\n", getpid(), getprogname(), n, ns / 1e6, nsMax / 1e6,
            nNeg, nsNeg / 1e6, nGen, nNegGen, nRepeatDesc, nsNegRepeatDesc / 1e6);
    fprintf(stderr, "    failed again on the same type: %llu (%.0f ms); failed by kind struct %llu/%.0f ms, enum %llu/%.0f ms, class %llu/%.0f ms, other %llu/%.0f ms\n",
            nRepType, nsRepType / 1e6, nKind[0], nsKind[0] / 1e6, nKind[1], nsKind[1] / 1e6, nKind[2], nsKind[2] / 1e6, nKind[3], nsKind[3] / 1e6);
    fprintf(stderr, "    index: %llu records (%llu special) from %u images, built in %.1f ms; failed struct/enum with NO candidate %llu (%.0f ms), with a candidate %llu (%.0f ms)\n",
            idxRecords, idxSpecial, idxImages, idxBuildNs / 1e6, nNoCand, nsNoCand / 1e6, nCandFail, nsCandFail / 1e6);
    fprintf(stderr, "    distinct failed (type,proto) %llu, distinct failed (descriptor,proto) %llu\n", nDistType, nDistDesc);
    for (int i = 0; i < 256 && pk[i]; i++) if (pns[i] > 50000000) fprintf(stderr, "    proto %-24s failed %llu (%.0f ms)\n", protoName(pk[i]), pn[i], pns[i] / 1e6);
    pthread_mutex_unlock(&mu);
}
static const void *wrap(const void *(*f)(const void *, const void *), const void *t, const void *p) {
    if (depth++) { const void *r = f(t, p); depth--; return r; }
    uint64_t a = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    const void *r = f(t, p);
    uint64_t d = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - a;
    depth--;
    const uint32_t *desc = descOf(t);
    int gen = desc && (desc[0] & 0x80);
    pthread_mutex_lock(&mu);
    n++; ns += d; if (d > nsMax) nsMax = d; nGen += gen;
    if (!r) {
        nNeg++; nsNeg += d; nNegGen += gen;
        if (desc && !insert(setA, (uintptr_t)desc, (uintptr_t)p)) { nRepeatDesc++; nsNegRepeatDesc += d; } else nDistDesc++;
        for (int i = 0; i < 256; i++) if (pk[i] == p || !pk[i]) { pk[i] = p; pn[i]++; pns[i] += d; break; }
        if (!insert(setB, (uintptr_t)t, (uintptr_t)p)) { nRepType++; nsRepType += d; } else nDistType++;
        uintptr_t k = *(const uintptr_t *)t; int c = k == 0x200 ? 0 : k == 0x201 || k == 0x202 ? 1 : k > 0x7FF ? 2 : 3;
        nKind[c]++; nsKind[c] += d;
        if (c < 2 && desc && !(desc[0] & (1u << 18))) {
            if (idxImages != _dyld_image_count()) buildIndex();
            if (!contains(idx, (uintptr_t)p, (uintptr_t)desc)) { nNoCand++; nsNoCand += d; } else { nCandFail++; nsCandFail += d; }
        }
        if (d > 5000000 && getenv("CFSPY_SLOW")) fprintf(stderr, "[cfspy] slow %.1f ms kind %#lx proto %s\n", d / 1e6, (unsigned long)k, protoName(p));
    }
    pthread_mutex_unlock(&mu);
    return r;
}
static const void *my1(const void *t, const void *p) { return wrap(swift_conformsToProtocol, t, p); }
static const void *my2(const void *t, const void *p) { return wrap(swift_conformsToProtocol2, t, p); }
DYLD_INTERPOSE(my1, swift_conformsToProtocol)
DYLD_INTERPOSE(my2, swift_conformsToProtocol2)
__attribute__((constructor)) static void init(void) {
    atexit(report);
    const char *s = getenv("CFSPY_SECS");
    if (s) for (char *e = strdup(s), *t; (t = strsep(&e, ","));)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(t) * 1e9)), dispatch_get_global_queue(0, 0), ^{ report(); });
}
