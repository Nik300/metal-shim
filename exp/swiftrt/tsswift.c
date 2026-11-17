// tsswift.dylib – prototype of the Swift conformance accelerator (docs/OTTIMIZZAZIONE-SWIFT.md).
//
// libswiftCore answers a failed swift_conformsToProtocol by scanning every conformance record of every loaded image
// (70k–180k records in a SwiftUI app, 1–4 ms per lookup on this CPU). This library installs an override through the
// runtime's own per-entry-point override variable (data only, no code patching) and answers "no" immediately when no
// conformance record names the struct/enum's type descriptor for that protocol. Everything else goes to the runtime.
//
// Index: per queried protocol, a hash set of the type descriptors named by its conformance records, built lazily on the
// first query of that protocol and extended when images are added.
//
// Env: TSSWIFT_OFF=1 (no hook), TSSWIFT_VALIDATE=1 (also ask the runtime on every fast "no" and count mismatches),
//      TSSWIFT_STATS=s1,s2,... (print stats at those seconds and at exit).
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <os/lock.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef const void *(*conforms_fn)(const void *type, const void *proto);

static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
static int validate;

// ---- loaded conformance sections ----
typedef struct { const int32_t *rec; uint32_t n; } Section;
static Section *sections; static uint32_t nSections, capSections;

// ---- per-protocol descriptor sets ----
typedef struct {
    const void *proto;
    const void **set; uint32_t cap, count;   // open addressing, NULL = empty
    int unsafe;                              // has records we cannot key by descriptor (conformance of protocol)
} ProtoIndex;
static ProtoIndex protos[64]; static int nProtos;

static uint64_t nsFast;
// Images whose add-image callback has finished. While dyld counts more (an image is being added on another thread and
// the runtime may already see its conformances), the fast path is off.
static _Atomic uint32_t imagesSeen;
static uint64_t dN[6], dNs[6];   // deferred: struct/enum candidate yes/no-result, class yes/no, other yes/no
static uint64_t stFast, stDeferred, stMismatch, stBuildNs, stRecords, nsDeferred;

static const void *rel(const int32_t *p) { return (const char *)p + *p; }
static const void *relInd(const int32_t *p) {
    int32_t o = *p; const char *a = (const char *)p + (o & ~1);
    return (o & 1) ? *(const void *const *)a : a;
}
static uint32_t hashp(const void *p) { return (uint32_t)(((uintptr_t)p * 0x9E3779B97F4A7C15ull) >> 32); }
static void setAdd(ProtoIndex *pi, const void *d);
static void setGrow(ProtoIndex *pi) {
    const void **old = pi->set; uint32_t oc = pi->cap;
    pi->cap = oc ? oc * 2 : 256; pi->set = calloc(pi->cap, sizeof *pi->set); pi->count = 0;
    for (uint32_t i = 0; i < oc; i++) if (old[i]) setAdd(pi, old[i]);
    free(old);
}
static void setAdd(ProtoIndex *pi, const void *d) {
    if ((pi->count + 1) * 2 > pi->cap) setGrow(pi);
    for (uint32_t h = hashp(d);; h++) {
        const void **e = &pi->set[h & (pi->cap - 1)];
        if (*e == d) return;
        if (!*e) { *e = d; pi->count++; return; }
    }
}
static int setHas(const ProtoIndex *pi, const void *d) {
    if (!pi->cap) return 0;
    for (uint32_t h = hashp(d);; h++) {
        const void *e = pi->set[h & (pi->cap - 1)];
        if (e == d) return 1;
        if (!e) return 0;
    }
}

// Adds the records of one section that conform to pi->proto.
static void indexSection(ProtoIndex *pi, const Section *s) {
    for (uint32_t k = 0; k < s->n; k++) {
        const int32_t *cd = rel(&s->rec[k]);
        if (relInd(&cd[0]) != pi->proto) continue;
        uint32_t fl = (uint32_t)cd[3]; unsigned kind = (fl >> 3) & 7;
        if (fl & (1u << 18)) { pi->unsafe = 1; continue; }            // conformance of a protocol
        if (kind == 0) setAdd(pi, rel(&cd[1]));
        else if (kind == 1) { const void *d = *(const void *const *)rel(&cd[1]); if (d) setAdd(pi, d); }
        // kinds 2/3 name ObjC classes: irrelevant for structs and enums
    }
}

static ProtoIndex *indexFor(const void *proto) {
    for (int i = 0; i < nProtos; i++) if (protos[i].proto == proto) return &protos[i];
    if (nProtos == 64) return NULL;
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    ProtoIndex *pi = &protos[nProtos++]; pi->proto = proto;
    setGrow(pi);
    for (uint32_t i = 0; i < nSections; i++) indexSection(pi, &sections[i]);
    stBuildNs += clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0;
    return pi;
}

static void addImage(const struct mach_header *mh, intptr_t slide) {
    unsigned long sz = 0;
    const int32_t *r = (const int32_t *)getsectiondata((const void *)mh, "__TEXT", "__swift5_proto", &sz);
    if (!r || !sz) { atomic_fetch_add(&imagesSeen, 1); return; }
    os_unfair_lock_lock(&lock);
    if (nSections == capSections) { capSections = capSections ? capSections * 2 : 512; sections = realloc(sections, capSections * sizeof *sections); }
    Section *s = &sections[nSections++]; s->rec = r; s->n = (uint32_t)(sz / 4); stRecords += s->n;
    for (int i = 0; i < nProtos; i++) indexSection(&protos[i], s);
    os_unfair_lock_unlock(&lock);
    atomic_fetch_add(&imagesSeen, 1);
}

// The struct/enum type descriptor of a metadata, or NULL when the fast path does not apply.
static const uint32_t *nominalDescriptor(const void *type) {
    const uintptr_t *md = type; uintptr_t kind = md[0];
    if (kind != 0x200 && kind != 0x201 && kind != 0x202) return NULL;   // struct, enum, optional
    const uint32_t *d = (const uint32_t *)md[1];
    if (!d) return NULL;
    uint32_t fl = d[0];
    if (fl & (1u << 18)) return NULL;                  // has import info: C-imported, matched by name
    if (((fl >> 16) & 3) == 2) return NULL;            // foreign metadata initialization
    // Parent module "__C" / "__C_Synthesized": imported or synthesized types are not unique by address.
    const int32_t *parentRel = (const int32_t *)&d[1];
    const uint32_t *parent = relInd(parentRel);
    while (parent && (parent[0] & 0x1F) != 0) parent = relInd((const int32_t *)&parent[1]);
    if (parent) { const char *name = rel((const int32_t *)&parent[2]); if (!strncmp(name, "__C", 3)) return NULL; }
    return d;
}

static const void *accel(const void *type, const void *proto, conforms_fn orig) {
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    const uint32_t *d = nominalDescriptor(type);
    if (d && atomic_load(&imagesSeen) >= _dyld_image_count()) {
        os_unfair_lock_lock(&lock);
        ProtoIndex *pi = indexFor(proto);
        int no = pi && !pi->unsafe && !setHas(pi, d);
        os_unfair_lock_unlock(&lock);
        if (no) {
            __atomic_fetch_add(&stFast, 1, __ATOMIC_RELAXED);
            __atomic_fetch_add(&nsFast, clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0, __ATOMIC_RELAXED);
            if (validate && orig(type, proto)) __atomic_fetch_add(&stMismatch, 1, __ATOMIC_RELAXED);
            return NULL;
        }
    }
    const void *r = orig(type, proto);
    __atomic_fetch_add(&nsDeferred, clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0, __ATOMIC_RELAXED);
    __atomic_fetch_add(&stDeferred, 1, __ATOMIC_RELAXED);
    { uintptr_t k = *(const uintptr_t *)type; int c = (d ? 0 : k > 0x7FF ? 2 : 4) + (r == NULL);
      __atomic_fetch_add(&dN[c], 1, __ATOMIC_RELAXED); __atomic_fetch_add(&dNs[c], clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0, __ATOMIC_RELAXED); }
    return r;
}
static const void *ovr0(const void *t, const void *p, conforms_fn o) { return accel(t, p, o); }

// The runtime caches each entry point's override in an atomic word read at the top of the function:
//   +17: 48 8B 05 <disp32>   movq disp(%rip), %rax
//   +24: 48 83 F8 01         cmpq $1, %rax         (1 = no override, 0 = not computed yet)
static int hook(const char *sym) {
    const unsigned char *f = dlsym(RTLD_DEFAULT, sym);
    if (!f) return 0;
    for (int off = 0; off < 40; off++) {
        const unsigned char *p = f + off;
        if (p[0] == 0x48 && p[1] == 0x8B && p[2] == 0x05 && p[7] == 0x48 && p[8] == 0x83 && p[9] == 0xF8 && p[10] == 0x01) {
            int32_t disp; memcpy(&disp, p + 3, 4);
            _Atomic(uintptr_t) *slot = (_Atomic(uintptr_t) *)(p + 7 + disp);
            uintptr_t cur = atomic_load(slot);
            if (cur > 1) return -1;                        // someone else's override: leave it alone
            return atomic_compare_exchange_strong(slot, &cur, (uintptr_t)ovr0) ? 1 : -2;
        }
    }
    return -3;
}

static void report(void) {
    os_unfair_lock_lock(&lock);
    uint64_t setBytes = 0; for (int i = 0; i < nProtos; i++) setBytes += protos[i].cap * sizeof(void *);
    fprintf(stderr, "[tsswift %d %s] fast no %llu (%.1f ms), deferred %llu (%.0f ms), mismatches %llu; %d protocols indexed in %.1f ms "
            "(%.0f KB), %u sections, %llu records\n", getpid(), getprogname(), stFast, nsFast / 1e6, stDeferred, nsDeferred / 1e6, stMismatch,
            nProtos, stBuildNs / 1e6, setBytes / 1024.0, nSections, stRecords);
    fprintf(stderr, "    deferred: struct/enum yes %llu (%.0f ms) no %llu (%.0f ms); class yes %llu (%.0f ms) no %llu (%.0f ms); other yes %llu (%.0f ms) no %llu (%.0f ms)\n",
            dN[0], dNs[0] / 1e6, dN[1], dNs[1] / 1e6, dN[2], dNs[2] / 1e6, dN[3], dNs[3] / 1e6, dN[4], dNs[4] / 1e6, dN[5], dNs[5] / 1e6);
    os_unfair_lock_unlock(&lock);
}

__attribute__((constructor)) static void init(void) {
    if (getenv("TSSWIFT_OFF")) return;
    validate = getenv("TSSWIFT_VALIDATE") != NULL;
    _dyld_register_func_for_add_image(addImage);
    int a = hook("swift_conformsToProtocol"), b = hook("swift_conformsToProtocol2"), c = hook("swift_conformsToProtocolCommon");
    if (getenv("TSSWIFT_STATS")) {
        fprintf(stderr, "[tsswift %d] hooks %d %d %d\n", getpid(), a, b, c);
        atexit(report);
        for (char *e = strdup(getenv("TSSWIFT_STATS")), *t; (t = strsep(&e, ","));)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(t) * 1e9)), dispatch_get_global_queue(0, 0), ^{ report(); });
    }
}
