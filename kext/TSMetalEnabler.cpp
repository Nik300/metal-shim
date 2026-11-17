//
//  TSMetalEnabler - Lilu plugin for the TeraScale Metal Shim (Phase 4, docs/FASE4-INTERFACCE.md).
//
//  1. Publishes MetalPluginName/MetalPluginClassName on the Radeon HD 6750M IOAccelerator, so that
//     Metal.framework loads /Library/GPUBundles/TeraScaleMTLDriver.bundle in processes that look for
//     a Metal device (the bundle then applies the per-app policy).
//  2. Library-validation exception for that bundle's executable only. Hardened and platform processes
//     may load only Apple-signed code (or same-team code), so AMFI would reject the ad-hoc signed
//     bundle silently. AMFI's two MAC policy entries that enforce it (file_check_library_validation,
//     file_check_mmap) are swapped in its mac_ops table for wrappers that call AMFI first and turn a
//     rejection into an approval only when the file is our executable, owned by root and not writable
//     by others, and the process is not one that draws the desktop. No AMFI code is patched, so this
//     coexists with AMFIPass whatever it patches; if the table does not hold the expected pointers the
//     exception is simply not installed.
//
//  3. Machine-model spoofing for chosen processes. ANGLE (Chrome, and WebKit for Safari) turns Metal off
//     on "old" models by reading the "model" property of IOPlatformExpertDevice (measured: spoofing
//     sysctl hw.model does nothing, spoofing that property gives WebGL on ANGLE Metal). The kernel side
//     of IORegistryEntryCreateCFProperty and friends is wrapped: when a listed process reads "model"
//     from the platform expert, the read is served from a decoy entry holding the spoof model. Every
//     other process, and every other property, is untouched. The list comes from the user's policy
//     file (Spoof section, docs/FASE4-INTERFACCE.md), re-read when it changes.
//
//  Boot-args: -tsmtloff (whole plugin off), -tsmtlnolv (no library-validation exception),
//             -tsmtlnospoof (no model spoofing).
//

#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_file.hpp>
#include <Headers/kern_mach.hpp>
#include <Headers/kern_patcher.hpp>
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <libkern/c++/OSUnserialize.h>
#include <kern/thread_call.h>
#include <libkern/OSAtomic.h>
#include <mach/vm_prot.h>
#include <sys/kauth.h>
#include <sys/proc.h>
#include <sys/stat.h>
#include <sys/vnode.h>

#define TS_VERSION "1.2.0"

static const char *bootargOff[] {"-tsmtloff"};
static const char *bootargDebug[] {"-tsmtldbg"};
static const char *bootargBeta[] {"-tsmtlbeta"};

static const char kBundleExecutable[] = "/Library/GPUBundles/TeraScaleMTLDriver.bundle/Contents/MacOS/TeraScaleMTLDriver";
static const char kBundleExecutableData[] = "/System/Volumes/Data/Library/GPUBundles/TeraScaleMTLDriver.bundle/Contents/MacOS/TeraScaleMTLDriver";

// Same list as the bundle (TSMtlSystem.m): these draw the desktop with the OCLP OpenGL stack.
static const char *const criticalProcesses[] {
	"WindowServer", "loginwindow", "Dock", "SystemUIServer", "ControlCenter",
	"NotificationCenter", "WallpaperAgent", "WindowManager",
};

static const char *pathAMFI[] {"/System/Library/Extensions/AppleMobileFileIntegrity.kext/Contents/MacOS/AppleMobileFileIntegrity"};
static KernelPatcher::KextInfo kextAMFI {
	"com.apple.driver.AppleMobileFileIntegrity", pathAMFI, arrsize(pathAMFI), {true, false, false, false, true}, {}, KernelPatcher::KextInfo::Unloaded
};

using fg_get_vnode_t = vnode_t (*)(void *fg);
using check_lv_t = int (*)(void *proc, void *fg, int64_t sliceOffset, int64_t errorMessage, size_t errorMessageSize);
using check_mmap_t = int (*)(kauth_cred_t cred, void *fg, void *label, int prot, int flags, uint64_t filePos, int *maxprot);

static fg_get_vnode_t fgGetVnode;
static check_lv_t orgCheckLV;
static check_mmap_t orgCheckMmap;

// Status shown on our IOService (read by tsmtl status / TeraScale Metal.app).
static volatile SInt32 lvAllowed, lvRefused;
static char lvLastProcess[33];
static const char *lvHookState = "not installed";
static bool acceleratorPatched;
static thread_call_t publishCall;
static IONotifier *acceleratorNotifier;
static const char *spoofState = "not installed";
static volatile SInt32 spoofCount;
static char spoofLastProcess[33];

static void publishStatus(thread_call_param_t, thread_call_param_t) {
	auto self = ADDPR(selfInstance);
	if (!self) {   // our IOService matches IOResources a little after the plugin starts
		uint64_t deadline;
		clock_interval_to_deadline(1, kSecondScale, &deadline);
		thread_call_enter_delayed(publishCall, deadline);
		return;
	}
	self->setProperty("TSVersion", TS_VERSION);
	self->setProperty("TSAcceleratorPatched", acceleratorPatched);
	self->setProperty("TSLVHook", lvHookState);
	self->setProperty("TSLVAllowed", static_cast<unsigned long long>(lvAllowed), 32);
	self->setProperty("TSLVRefused", static_cast<unsigned long long>(lvRefused), 32);
	char last[sizeof(lvLastProcess)];
	strlcpy(last, lvLastProcess, sizeof(last));
	self->setProperty("TSLVLastProcess", last);
	self->setProperty("TSSpoof", spoofState);
	self->setProperty("TSSpoofCount", static_cast<unsigned long long>(spoofCount), 32);
	strlcpy(last, spoofLastProcess, sizeof(last));
	self->setProperty("TSSpoofLastProcess", last);
}

static void schedulePublish() {
	if (publishCall) thread_call_enter(publishCall);
}

#pragma mark - Library validation exception

static bool isOurExecutable(void *fg) {
	vnode_t vp = fg && fgGetVnode ? fgGetVnode(fg) : nullptr;
	if (!vp || vnode_getwithref(vp) != 0) return false;
	bool ours = false;
	char path[256];   // kernel stack, deep in a MAC hook; a longer path cannot be ours (vn_getpath fails)
	int len = sizeof(path);
	if (vnode_isreg(vp) && vn_getpath(vp, path, &len) == 0 &&
		(!strcmp(path, kBundleExecutable) || !strcmp(path, kBundleExecutableData))) {
		struct vnode_attr va;
		VATTR_INIT(&va);
		VATTR_WANTED(&va, va_uid);
		VATTR_WANTED(&va, va_mode);
		ours = vnode_getattr(vp, &va, vfs_context_current()) == 0 &&
			VATTR_IS_SUPPORTED(&va, va_uid) && VATTR_IS_SUPPORTED(&va, va_mode) &&
			va.va_uid == 0 && (va.va_mode & (S_IWGRP | S_IWOTH)) == 0;
		if (!ours) SYSLOG("lv", "%s is not owned by root or is writable by others: no exception", path);
	}
	vnode_put(vp);
	return ours;
}

static bool glassAllowed();

// Called only after AMFI rejected the file. count: once per load (the library-validation check;
// the mmap check that follows for the same load is not counted).
static bool grantException(void *fg, bool count) {
	if (!isOurExecutable(fg)) return false;
	char name[sizeof(lvLastProcess)] {};
	proc_selfname(name, sizeof(name));
	for (auto critical : criticalProcesses) {
		// TeraScale Glass (docs/PIANO-GLASS.md): WindowServer only, and only while policy.plist has
		// System.Glass.Enabled; the bundle then runs nothing but the glass component there.
		if (!strcmp(name, critical) && !strcmp(name, "WindowServer") && glassAllowed()) {
			if (count) SYSLOG("lv", "allowed TeraScaleMTLDriver in WindowServer (pid %d): TeraScale Glass", proc_selfpid());
			break;
		}
		if (!strcmp(name, critical)) {
			if (count && OSIncrementAtomic(&lvRefused) < 20)
				SYSLOG("lv", "refused for %s (desktop process)", name);
			if (count) schedulePublish();
			return false;
		}
	}
	if (count) {
		if (OSIncrementAtomic(&lvAllowed) < 50)
			SYSLOG("lv", "allowed TeraScaleMTLDriver in %s (pid %d)", name, proc_selfpid());
		strlcpy(lvLastProcess, name, sizeof(lvLastProcess));
		schedulePublish();
	}
	return true;
}

static int wrapCheckLV(void *proc, void *fg, int64_t sliceOffset, int64_t errorMessage, size_t errorMessageSize) {
	int error = orgCheckLV(proc, fg, sliceOffset, errorMessage, errorMessageSize);
	if (error != 0 && grantException(fg, true)) return 0;
	return error;
}

static int wrapCheckMmap(kauth_cred_t cred, void *fg, void *label, int prot, int flags, uint64_t filePos, int *maxprot) {
	int error = orgCheckMmap(cred, fg, label, prot, flags, filePos, maxprot);
	if (error != 0 && (prot & VM_PROT_EXECUTE) && grantException(fg, false)) return 0;
	return error;
}

static void installLVException(KernelPatcher &patcher, size_t index) {
	fgGetVnode = reinterpret_cast<fg_get_vnode_t>(patcher.solveSymbol(KernelPatcher::KernelID, "_fg_get_vnode"));
	auto ops = reinterpret_cast<mach_vm_address_t *>(patcher.solveSymbol(index, "__ZL7mac_ops"));
	auto checkLV = patcher.solveSymbol(index, "__Z30_file_check_library_validationP4procP8fileglobxxm");
	auto checkMmap = patcher.solveSymbol(index, "__Z16_file_check_mmapP5ucredP8fileglobP5labeliiyPi");
	patcher.clearError();
	if (!fgGetVnode || !ops || !checkLV || !checkMmap) {
		lvHookState = "symbols not found";
		SYSLOG("lv", "symbols not found (fg_get_vnode %d, mac_ops %d, lv %d, mmap %d): no exception",
			   fgGetVnode != nullptr, ops != nullptr, checkLV != 0, checkMmap != 0);
		return;
	}
	// struct mac_policy_ops has about 340 entries; find the two slots by their current value.
	size_t slotLV = SIZE_MAX, slotMmap = SIZE_MAX;
	for (size_t i = 0; i < 400; i++) {
		if (ops[i] == checkLV) slotLV = (slotLV == SIZE_MAX) ? i : SIZE_MAX - 1;
		if (ops[i] == checkMmap) slotMmap = (slotMmap == SIZE_MAX) ? i : SIZE_MAX - 1;
	}
	if (slotLV >= 400 || slotMmap >= 400) {
		lvHookState = "AMFI mac_ops entries not found";
		SYSLOG("lv", "AMFI mac_ops entries not found (lv %lu, mmap %lu): no exception", slotLV, slotMmap);
		return;
	}
	orgCheckLV = reinterpret_cast<check_lv_t>(ops[slotLV]);
	orgCheckMmap = reinterpret_cast<check_mmap_t>(ops[slotMmap]);
	if (MachInfo::setKernelWriting(true, KernelPatcher::kernelWriteLock) != KERN_SUCCESS) {
		lvHookState = "kernel memory not writable";
		SYSLOG("lv", "cannot enable kernel writing: no exception");
		return;
	}
	ops[slotLV] = reinterpret_cast<mach_vm_address_t>(wrapCheckLV);
	ops[slotMmap] = reinterpret_cast<mach_vm_address_t>(wrapCheckMmap);
	MachInfo::setKernelWriting(false, KernelPatcher::kernelWriteLock);
	lvHookState = "installed";
	SYSLOG("lv", "library-validation exception installed (mac_ops slots %lu, %lu)", slotLV, slotMmap);
	schedulePublish();
}

#pragma mark - Machine-model spoofing

static const char kPolicyPath[] = "/Library/GPUBundles/TeraScaleMTLDriver.config/policy.plist";
static const char kDefaultModel[] = "iMac19,1";

// "Auto" rules: id as written by the control app, and a substring of the executable path.
// WebKit's XPC services (GPU, WebContent) live in WebKit.framework, not in Safari.app.
static const struct { const char *id, *match; } autoRules[] {
	{"com.google.Chrome", "/Google Chrome.app/"},
	{"com.apple.Safari", "/Safari.app/"},
	{"com.apple.WebKit", "/WebKit.framework/"},
};

struct SpoofRule { char match[256]; bool enabled; };
static constexpr size_t MaxRules = 64;

static IOLock *spoofLock;
static bool glassEnabled;                    // System.Glass.Enabled (spoofLock)
// Holds "model" = spoof model. Same class as the real platform expert device, because the kernel asks
// the sandbox (mac_iokit_check_get_property) about the entry it is given, and sandbox profiles allow
// properties by entry class.
static IORegistryEntry *modelDecoy;
static SpoofRule rules[MaxRules];            // explicit entries from the policy (spoofLock)
static size_t ruleCount;
static bool autoSpoof = true;
static struct timespec policyModified;
static bool policyLoaded;
static vfs_context_t (*vfsContextKernel)();
static uint64_t policyCheckedAt;             // mach_absolute_time of the last stat
static void *(*currentProc)();
static vnode_t (*procExecutableVnode)(void *proc);   // returns the vnode with an iocount

static void copyMatch(char *dst, OSDictionary *entry, const char *fallbackId) {
	dst[0] = '\0';
	if (auto m = OSDynamicCast(OSString, entry->getObject("Match"))) {
		strlcpy(dst, m->getCStringNoCopy(), sizeof(SpoofRule::match));
		return;
	}
	if (auto p = OSDynamicCast(OSString, entry->getObject("Path"))) {
		strlcpy(dst, p->getCStringNoCopy(), sizeof(SpoofRule::match));
		strlcat(dst, "/", sizeof(SpoofRule::match));
		return;
	}
	for (auto &r : autoRules)
		if (!strcmp(fallbackId, r.id)) strlcpy(dst, r.match, sizeof(SpoofRule::match));
}

// Re-reads the policy when its modification time changes (checked at most once a second). The file
// is read with the kernel's credentials: the caller may be a sandboxed process (Chrome's GPU helper)
// that could not open it. Missing or unreadable file: defaults (Auto on, iMac19,1, no explicit entries).
// Caller holds spoofLock.
static void refreshPolicy() {
	uint64_t now = mach_absolute_time(), second;
	nanoseconds_to_absolutetime(NSEC_PER_SEC, &second);
	if (policyLoaded && now - policyCheckedAt < second) return;
	policyCheckedAt = now;

	vfs_context_t ctx = vfsContextKernel();
	vnode_t vp = nullptr;
	struct vnode_attr va;
	VATTR_INIT(&va);
	VATTR_WANTED(&va, va_modify_time);
	VATTR_WANTED(&va, va_data_size);
	bool ok = vnode_lookup(kPolicyPath, 0, &vp, ctx) == 0 && vnode_getattr(vp, &va, ctx) == 0 &&
		vnode_isreg(vp) && va.va_data_size > 0 && va.va_data_size < 256 * 1024;
	struct timespec modified = ok ? va.va_modify_time : timespec {};
	if (policyLoaded && modified.tv_sec == policyModified.tv_sec && modified.tv_nsec == policyModified.tv_nsec) {
		if (vp) vnode_put(vp);
		return;
	}
	policyLoaded = true;
	policyModified = modified;

	OSObject *root = nullptr;
	if (ok) {
		size_t size = static_cast<size_t>(va.va_data_size);
		char *text = static_cast<char *>(IOMalloc(size + 1));
		if (text) {
			if (FileIO::readFileData(text, 0, size, vp, ctx) == 0) {
				text[size] = '\0';
				root = OSUnserializeXML(text);
			}
			IOFree(text, size + 1);
		}
	}
	if (vp) vnode_put(vp);

	ruleCount = 0;
	autoSpoof = true;
	glassEnabled = false;
	const char *model = kDefaultModel;
	char modelBuf[32];
	if (auto dict = OSDynamicCast(OSDictionary, root)) {
		if (auto system = OSDynamicCast(OSDictionary, dict->getObject("System")))
			if (auto glass = OSDynamicCast(OSDictionary, system->getObject("Glass")))
				if (auto enabled = OSDynamicCast(OSBoolean, glass->getObject("Enabled"))) glassEnabled = enabled->isTrue();
		if (auto spoof = OSDynamicCast(OSDictionary, dict->getObject("Spoof"))) {
			if (auto a = OSDynamicCast(OSBoolean, spoof->getObject("Auto"))) autoSpoof = a->isTrue();
			if (auto m = OSDynamicCast(OSString, spoof->getObject("Model")); m && m->getLength() > 0 && m->getLength() < sizeof(modelBuf)) {
				strlcpy(modelBuf, m->getCStringNoCopy(), sizeof(modelBuf));
				model = modelBuf;
			}
			if (auto apps = OSDynamicCast(OSDictionary, spoof->getObject("Apps"))) {
				auto it = OSCollectionIterator::withCollection(apps);
				while (auto key = it ? OSDynamicCast(OSString, it->getNextObject()) : nullptr) {
					auto entry = OSDynamicCast(OSDictionary, apps->getObject(key));
					auto enabled = entry ? OSDynamicCast(OSBoolean, entry->getObject("Enabled")) : nullptr;
					if (!enabled || ruleCount >= MaxRules) continue;
					copyMatch(rules[ruleCount].match, entry, key->getCStringNoCopy());
					rules[ruleCount].enabled = enabled->isTrue();
					if (rules[ruleCount].match[0]) ruleCount++;
				}
				OSSafeReleaseNULL(it);
			}
		}
	}
	OSSafeReleaseNULL(root);
	auto data = OSData::withBytes(model, static_cast<unsigned>(strlen(model) + 1));
	if (data) {
		modelDecoy->setProperty("model", data);
		data->release();
	}
	SYSLOG("spoof", "policy %s: auto %d, %lu entries, model %s, glass %d", ok ? "loaded" : "absent", autoSpoof, ruleCount, model, glassEnabled);
}

// The policy reader belongs to the spoofing part (it needs its kernel symbols): without it, no glass.
static bool glassAllowed() {
	if (!spoofLock) return false;
	IOLockLock(spoofLock);
	refreshPolicy();
	bool on = glassEnabled;
	IOLockUnlock(spoofLock);
	return on;
}

// Explicit disabled entries win, then explicit enabled ones, then the auto rules.
static bool processWantsSpoof() {
	vnode_t vp = procExecutableVnode(currentProc());
	if (!vp) return false;
	char path[512];
	int len = sizeof(path);
	bool havePath = vn_getpath(vp, path, &len) == 0;
	vnode_put(vp);
	if (!havePath) return false;
	IOLockLock(spoofLock);
	refreshPolicy();
	int verdict = -1;
	for (size_t i = 0; i < ruleCount && verdict != 0; i++)
		if (strstr(path, rules[i].match)) verdict = rules[i].enabled ? 1 : 0;
	if (verdict < 0 && autoSpoof)
		for (auto &r : autoRules)
			if (strstr(path, r.match)) { verdict = 1; break; }
	IOLockUnlock(spoofLock);
	return verdict == 1;
}

static OSObject *spoofEntry(OSObject *entry, const char *name) {
	if (!name || name[0] != 'm' || strcmp(name, "model") || !entry || entry == modelDecoy || !entry->metaCast("IOPlatformExpertDevice"))
		return entry;
	if (!processWantsSpoof()) return entry;
	char proc[sizeof(spoofLastProcess)] {};
	proc_selfname(proc, sizeof(proc));
	if (OSIncrementAtomic(&spoofCount) < 50) SYSLOG("spoof", "model spoofed for %s (pid %d)", proc, proc_selfpid());
	strlcpy(spoofLastProcess, proc, sizeof(spoofLastProcess));
	schedulePublish();
	return modelDecoy;
}

// The MIG server routines behind IORegistryEntryCreateCFProperty / IORegistryEntryGetProperty.
using get_bin_buf_t = kern_return_t (*)(OSObject *, char *, char *, uint32_t, mach_vm_address_t, mach_vm_size_t *, void *, void *);
using get_bin_t = kern_return_t (*)(OSObject *, char *, char *, uint32_t, void *, void *);
using get_bytes_t = kern_return_t (*)(OSObject *, char *, char *, void *);
using get_xml_t = kern_return_t (*)(OSObject *, char *, void *, void *);
static get_bin_buf_t orgGetBinBuf;
static get_bin_t orgGetBin;
static get_bytes_t orgGetBytes;
static get_xml_t orgGetXML;

static kern_return_t wrapGetBinBuf(OSObject *e, char *plane, char *name, uint32_t opt, mach_vm_address_t buf, mach_vm_size_t *size, void *props, void *cnt) {
	return orgGetBinBuf(spoofEntry(e, name), plane, name, opt, buf, size, props, cnt);
}
static kern_return_t wrapGetBin(OSObject *e, char *plane, char *name, uint32_t opt, void *props, void *cnt) {
	return orgGetBin(spoofEntry(e, name), plane, name, opt, props, cnt);
}
static kern_return_t wrapGetBytes(OSObject *e, char *name, char *buf, void *cnt) {
	return orgGetBytes(spoofEntry(e, name), name, buf, cnt);
}
static kern_return_t wrapGetXML(OSObject *e, char *name, void *props, void *cnt) {
	return orgGetXML(spoofEntry(e, name), name, props, cnt);
}

static void installSpoof(KernelPatcher &patcher) {
	currentProc = reinterpret_cast<void *(*)()>(patcher.solveSymbol(KernelPatcher::KernelID, "_current_proc"));
	procExecutableVnode = reinterpret_cast<vnode_t (*)(void *)>(patcher.solveSymbol(KernelPatcher::KernelID, "_proc_getexecutablevnode"));
	vfsContextKernel = reinterpret_cast<vfs_context_t (*)()>(patcher.solveSymbol(KernelPatcher::KernelID, "_vfs_context_kernel"));
	patcher.clearError();
	if (!currentProc || !procExecutableVnode || !vfsContextKernel) {
		spoofState = "symbols not found";
		SYSLOG("spoof", "current_proc/proc_getexecutablevnode/vfs_context_kernel not found: no spoofing");
		return;
	}
	spoofLock = IOLockAlloc();
	modelDecoy = OSDynamicCast(IORegistryEntry, OSMetaClass::allocClassWithName("IOPlatformExpertDevice"));
	if (!modelDecoy) modelDecoy = new IORegistryEntry;
	if (!spoofLock || !modelDecoy || !modelDecoy->init()) {
		spoofState = "no memory";
		return;
	}
	auto data = OSData::withBytes(kDefaultModel, sizeof(kDefaultModel));
	if (data) { modelDecoy->setProperty("model", data); data->release(); }
	KernelPatcher::RouteRequest requests[] {
		{"_is_io_registry_entry_get_property_bin_buf", wrapGetBinBuf, orgGetBinBuf},
		{"_is_io_registry_entry_get_property_bin", wrapGetBin, orgGetBin},
		{"_is_io_registry_entry_get_property_bytes", wrapGetBytes, orgGetBytes},
		{"_is_io_registry_entry_get_property", wrapGetXML, orgGetXML},
	};
	if (!patcher.routeMultiple(KernelPatcher::KernelID, requests)) {
		patcher.clearError();
		spoofState = "routing failed";
		SYSLOG("spoof", "cannot route the IORegistry property calls: no spoofing");
		return;
	}
	spoofState = "installed";
	SYSLOG("spoof", "model spoofing installed");
	schedulePublish();
}

#pragma mark - Accelerator properties

static bool acceleratorPublished(void *, void *, IOService *service, IONotifier *) {
	auto gl = OSDynamicCast(OSString, service->getProperty("IOGLBundleName"));
	if (!gl || !gl->isEqualTo("AMDRadeonX3000GLDriver") || service->getProperty("MetalPluginName")) return true;
	service->setProperty("MetalPluginName", "TeraScaleMTLDriver");
	service->setProperty("MetalPluginClassName", "TSMtlDevice");
	acceleratorPatched = true;
	SYSLOG("accel", "Metal plugin properties set on %s", service->getName());
	schedulePublish();
	return true;
}

#pragma mark - Start

static void pluginStart() {
	SYSLOG("init", "TSMetalEnabler %s starting", TS_VERSION);
	publishCall = thread_call_allocate(publishStatus, nullptr);

	auto matching = IOService::serviceMatching("IOAccelerator");
	if (matching) {
		acceleratorNotifier = IOService::addMatchingNotification(gIOFirstPublishNotification, matching, acceleratorPublished, nullptr);
		matching->release();
	}
	if (!acceleratorNotifier) SYSLOG("init", "cannot watch IOAccelerator services");
	schedulePublish();

	if (checkKernelArgument("-tsmtlnospoof")) {
		spoofState = "disabled by -tsmtlnospoof";
	} else {
		lilu.onPatcherLoadForce([](void *, KernelPatcher &patcher) { installSpoof(patcher); });
	}

	if (checkKernelArgument("-tsmtlnolv")) {
		lvHookState = "disabled by -tsmtlnolv";
		SYSLOG("init", "library-validation exception disabled by boot-arg");
		return;
	}
	lilu.onKextLoadForce(&kextAMFI, 1, [](void *, KernelPatcher &patcher, size_t index, mach_vm_address_t, size_t) {
		if (index == kextAMFI.loadIndex) installLVException(patcher, index);
	});
}

PluginConfiguration ADDPR(config) {
	xStringify(PRODUCT_NAME),
	parseModuleVersion(xStringify(MODULE_VERSION)),
	LiluAPI::AllowNormal,
	bootargOff, arrsize(bootargOff),
	bootargDebug, arrsize(bootargDebug),
	bootargBeta, arrsize(bootargBeta),
	KernelVersion::BigSur,
	KernelVersion::Tahoe,
	pluginStart
};
