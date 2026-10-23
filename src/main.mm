#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <pthread.h>
#import <unistd.h>
#import <time.h>
#import <string.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>
#import <algorithm>
#import "cheat_data.h"
#import "menu.h"
#import "overlay.h"
#import "esp.h"
#import "aimbot.h"
#import "recoil.h"
#import "patch.h"
#import "tracelog.h"

IL2CPPResolver* g_resolver = nullptr;
void* g_localPlayer = nullptr;
void* g_mainCamera = nullptr;
bool g_firingDetected = true;
std::vector<PlayerData> g_players;
std::recursive_mutex g_playersMutex;
CheatConfig g_config;

static bool g_hooked = false;
static bool g_bindFailedLogged = false;

#pragma mark - IL2CPP bootstrap

static bool BindIL2CppFunctions(void* handle) {
    auto bind = [](void* h, const char* name) -> void* {
        void* ptr = nullptr;
        if (h && h != RTLD_DEFAULT) ptr = dlsym(h, name);
        if (!ptr) {
            void* uf = dlopen("@executable_path/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOLOAD);
            if (uf) ptr = dlsym(uf, name);
        }
        if (!ptr) {
            void* uf = dlopen("UnityFramework.framework/UnityFramework", RTLD_NOLOAD);
            if (uf) ptr = dlsym(uf, name);
        }
        if (!ptr) {
            void* uf = dlopen("UnityFramework", RTLD_NOLOAD);
            if (uf) ptr = dlsym(uf, name);
        }
        if (!ptr) ptr = dlsym(RTLD_NEXT, name);
        return ptr;
    };

    struct { const char* name; void** out; } binds[] = {
        {"il2cpp_domain_get", (void**)&il2cpp_domain_get},
        {"il2cpp_domain_get_assemblies", (void**)&il2cpp_domain_get_assemblies},
        {"il2cpp_assembly_get_image", (void**)&il2cpp_assembly_get_image},
        {"il2cpp_image_get_name", (void**)&il2cpp_image_get_name},
        {"il2cpp_image_get_class_count", (void**)&il2cpp_image_get_class_count},
        {"il2cpp_image_get_class", (void**)&il2cpp_image_get_class},
        {"il2cpp_class_from_name", (void**)&il2cpp_class_from_name},
        {"il2cpp_class_get_parent", (void**)&il2cpp_class_get_parent},
        {"il2cpp_class_get_field_from_name", (void**)&il2cpp_class_get_field_from_name},
        {"il2cpp_class_get_method_from_name", (void**)&il2cpp_class_get_method_from_name},
        {"il2cpp_class_get_methods", (void**)&il2cpp_class_get_methods},
        {"il2cpp_class_get_fields", (void**)&il2cpp_class_get_fields},
        {"il2cpp_class_get_name", (void**)&il2cpp_class_get_name},
        {"il2cpp_class_get_namespace", (void**)&il2cpp_class_get_namespace},
        {"il2cpp_field_get_offset", (void**)&il2cpp_field_get_offset},
        {"il2cpp_field_get_name", (void**)&il2cpp_field_get_name},
        {"il2cpp_field_get_type", (void**)&il2cpp_field_get_type},
        {"il2cpp_field_get_value", (void**)&il2cpp_field_get_value},
        {"il2cpp_field_set_value", (void**)&il2cpp_field_set_value},
        {"il2cpp_field_static_get_value", (void**)&il2cpp_field_static_get_value},
        {"il2cpp_field_static_set_value", (void**)&il2cpp_field_static_set_value},
        {"il2cpp_runtime_invoke", (void**)&il2cpp_runtime_invoke},
        {"il2cpp_method_get_name", (void**)&il2cpp_method_get_name},
        {"il2cpp_method_get_param_count", (void**)&il2cpp_method_get_param_count},
        {"il2cpp_object_new", (void**)&il2cpp_object_new},
        {"il2cpp_object_unbox", (void**)&il2cpp_object_unbox},
        {"il2cpp_object_get_class", (void**)&il2cpp_object_get_class},
        {"il2cpp_class_from_il2cpp_type", (void**)&il2cpp_class_from_il2cpp_type},
        {"il2cpp_class_get_type", (void**)&il2cpp_class_get_type},
        {"il2cpp_type_get_type", (void**)&il2cpp_type_get_type},
        {"il2cpp_type_get_object", (void**)&il2cpp_type_get_object},
        {"il2cpp_string_new", (void**)&il2cpp_string_new},
        {"il2cpp_string_length", (void**)&il2cpp_string_length},
        {"il2cpp_string_chars", (void**)&il2cpp_string_chars},
        {"il2cpp_array_new", (void**)&il2cpp_array_new},
        {"il2cpp_array_new_specific", (void**)&il2cpp_array_new_specific},
        {"il2cpp_array_class_get", (void**)&il2cpp_array_class_get},
        {"il2cpp_array_addr_with_size", (void**)&il2cpp_array_addr_with_size},
        {"il2cpp_array_length", (void**)&il2cpp_array_length},
        {"il2cpp_thread_attach", (void**)&il2cpp_thread_attach},
        {"il2cpp_thread_current", (void**)&il2cpp_thread_current},
        {"il2cpp_thread_get_domain", (void**)&il2cpp_thread_get_domain},
    };

    int resolved = 0;
    int total = (int)(sizeof(binds) / sizeof(binds[0]));
    for (auto& b : binds) {
        void* p = bind(handle, b.name);
        if (p) { *b.out = p; resolved++; }
    }

    // The old code just counted symbols and shrugged. These are the ones that
    // actually break everything if they are missing.
    bool critical = il2cpp_domain_get && il2cpp_domain_get_assemblies &&
                    il2cpp_assembly_get_image && il2cpp_image_get_class_count &&
                    il2cpp_image_get_class && il2cpp_class_from_name &&
                    il2cpp_class_get_field_from_name && il2cpp_class_get_method_from_name &&
                    il2cpp_runtime_invoke && il2cpp_field_get_value && il2cpp_field_set_value &&
                    il2cpp_thread_attach && il2cpp_type_get_object && il2cpp_class_get_type &&
                    il2cpp_class_get_fields && il2cpp_class_get_methods;

    if (!critical) {
        CHEAT_LOG("t: IL2CPP binding failed (%d/%d) critical=%d", resolved, total, (int)critical);
        return false;
    }
    CHEAT_LOG("t: IL2CPP API bound, %d/%d symbols", resolved, total);
    return true;
}

#pragma mark - Anti-cheat neutralization

// ABI-correct stub: IL2CPP calls methodPointer as (MethodInfo*, Il2CppObject*, void**).
static uintptr_t ACZeroStub(void*, void*, void*) { return 0; }

static void* g_patchedAddrs[1024];
static int g_patchedCount = 0;

static bool AlreadyPatched(void* addr) {
    for (int i = 0; i < g_patchedCount; i++)
        if (g_patchedAddrs[i] == addr) return true;
    return false;
}

static bool MakeWritable(void* addr, size_t len) {
    vm_address_t page = (vm_address_t)addr & ~(vm_address_t)(vm_page_size - 1);
    vm_address_t end = ((vm_address_t)addr + len + vm_page_size - 1) & ~(vm_address_t)(vm_page_size - 1);
    vm_size_t size = end - page;

    kern_return_t kr = vm_protect(mach_task_self(), page, size, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        kr = vm_protect(mach_task_self(), page, size, FALSE,
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    }
    return kr == KERN_SUCCESS;
}

static bool PatchReturnZero(const Il2CppMethodInfo* m) {
    if (!m) return false;
    void** slot = (void**)m;
    if (slot[0] == (void*)&ACZeroStub) return true;

    // MethodInfo->methodPointer lives at offset 0 on every shipping IL2CPP.
    // The metadata page is NOT always writable (__DATA_CONST). The previous
    // version wrote blind and silently failed when the page was read-only.
    if (!MakeWritable(slot, sizeof(void*) * 2)) {
        CHEAT_LOG("ac: page not writable for %p", m);
        return false;
    }
    slot[0] = (void*)&ACZeroStub;
    if (slot[0] != (void*)&ACZeroStub) {
        CHEAT_LOG("ac: write bounced at %p", m);
        return false;
    }
    return true;
}

// Exposed to recoil.mm (and anything else that wants a no-op method pointer).
bool CheatPatchMethodZero(const Il2CppMethodInfo* method) {
    return PatchReturnZero(method);
}

static const char* g_skipPrefixes[] = {
    ".ctor", ".cctor", ".dtor", "Equals", "GetHashCode", "ToString",
    "GetType", "op_", "Finalize", "get_", "set_", "get_", nullptr
};

static int NukeACClass(const Il2CppClass* klass, const char* name) {
    if (!klass) return 0;
    if (!il2cpp_class_get_methods || !il2cpp_method_get_name) return 0;

    int patched = 0;
    void* iter = nullptr;
    const Il2CppMethodInfo* m = nullptr;
    while ((m = il2cpp_class_get_methods(klass, &iter)) != nullptr) {
        const char* mn = il2cpp_method_get_name(m);
        if (!mn) continue;

        bool skip = false;
        for (int i = 0; g_skipPrefixes[i]; i++)
            if (strstr(mn, g_skipPrefixes[i])) { skip = true; break; }
        if (skip) continue;

        bool detection = strstr(mn, "Check") || strstr(mn, "Detect") ||
                         strstr(mn, "Is") || strstr(mn, "Has") || strstr(mn, "Verify") ||
                         strstr(mn, "Verdict") || strstr(mn, "Report") || strstr(mn, "Collect") ||
                         strstr(mn, "Update") || strstr(mn, "Run") || strstr(mn, "Execute") ||
                         strstr(mn, "Scan") || strstr(mn, "Validate") || strstr(mn, "Hash");

        if (!detection) continue;
        if (AlreadyPatched((void*)m)) continue;

        if (PatchReturnZero(m)) {
            if (g_patchedCount < 1024) g_patchedAddrs[g_patchedCount++] = (void*)m;
            patched++;
            CHEAT_LOG("ac: patch %s::%s", name, mn);
        } else {
            CHEAT_LOG("ac: FAILED %s::%s (%p)", name, mn, (void*)m);
        }
    }
    CHEAT_LOG("ac: %s -> %d methods patched", name, patched);
    return patched;
}

static int NukeAntiCheatSweep() {
    if (!g_resolver) return 0;

    const char* needles[] = {
        "Warden", "CheatDetector", "CheatController", "AntiCheat", "Anitcheat",
        "InjectionCheat", "HashCheat", "CheatReport", nullptr
    };

    std::vector<const Il2CppClass*> targets;
    for (int i = 0; needles[i]; i++) {
        auto v = g_resolver->FindClassesContaining(needles[i], 24);
        for (auto* k : v) {
            if (std::find(targets.begin(), targets.end(), k) == targets.end())
                targets.push_back(k);
        }
    }

    if (targets.empty()) {
        static int misses = 0;
        if ((misses++ % 5) == 0) CHEAT_LOG("ac: no detector classes loaded yet (sweep %d)", misses);
        return 0;
    }

    static bool logged = false;
    int totalPatched = 0;
    for (auto* k : targets) {
        const char* nm = il2cpp_class_get_name ? il2cpp_class_get_name(k) : "?";
        if (!logged) CHEAT_LOG("ac: target %s @%p", nm ? nm : "?", k);
        totalPatched += NukeACClass(k, nm ? nm : "?");
    }
    logged = true;

    CHEAT_LOG("ac: sweep done classes=%zu patched=%d total=%d",
              targets.size(), totalPatched, g_patchedCount);
    return totalPatched;
}

#pragma mark - Diagnostics

void DumpKeyClasses() {
    if (!g_resolver) return;
    IL2CPPResolver* r = g_resolver;
    CHEAT_LOG("d: ================= CLASS DUMP =================");
    CHEAT_LOG("d: unity screen %dx%d", r->UnityScreenWidth(), r->UnityScreenHeight());

    r->DumpClass(r->classes.PlayerController, "PlayerController");
    r->DumpClass(r->classes.PlayerView, "PlayerView");
    r->DumpClass(r->classes.PlayerCharacterView, "PlayerCharacterView");
    r->DumpClass(r->classes.PlayerManager, "PlayerManager");
    r->DumpClass(r->classes.WeaponController, "WeaponController");
    r->DumpClass(r->classes.RecoilControl, "RecoilControl");
    r->DumpClass(r->classes.AimView, "AimView");
    r->DumpClass(r->classes.PlayerInputs, "PlayerInputs");
    r->DumpClass(r->classes.Camera, "Camera");

    r->DumpClassesContaining("Warden", 24);
    r->DumpClassesContaining("Cheat", 32);
    r->DumpClassesContaining("Recoil", 16);
    r->DumpClassesContaining("Aim", 24);
    CHEAT_LOG("d: ================= END DUMP =================");
}

void CheatDumpNow() {
    DumpKeyClasses();
    if (g_config.acEnabled) NukeAntiCheatSweep();
}

#pragma mark - Worker thread

static void FinishInitialize() {
    if (g_hooked) return;
    if (!il2cpp_domain_get || !il2cpp_domain_get()) return;

    il2cpp_thread_attach(il2cpp_domain_get());

    IL2CPPResolver* r = new IL2CPPResolver();
    if (!r->Initialize()) {
        CHEAT_LOG("w: resolver Initialize FAILED — see 'r:' lines above for which class is missing");
        delete r;
        return;
    }

    g_resolver = r;
    CHEAT_LOG("w: ready");

    if (g_config.dumpOnInit) DumpKeyClasses();

    if (g_config.acEnabled) NukeAntiCheatSweep();

    g_config.initialized = true;
    g_hooked = true;
}

static void* cheatWorker(void* arg) {
    @autoreleasepool {
        CHEAT_LOG("w: worker start");

        int attempts = 0;
        while (attempts < 600) {
            void* uf = dlopen("@executable_path/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOLOAD);
            if (!uf) uf = dlopen("UnityFramework.framework/UnityFramework", RTLD_NOLOAD);
            if (!uf) uf = dlopen("UnityFramework", RTLD_NOLOAD);

            bool bound = false;
            if (uf) bound = BindIL2CppFunctions(uf);
            if (!bound) bound = BindIL2CppFunctions(RTLD_NEXT);

            if (bound) break;
            if (!g_bindFailedLogged && attempts == 50) {
                CHEAT_LOG("w: still waiting for UnityFramework symbols");
                g_bindFailedLogged = true;
            }
            attempts++;
            usleep(100 * 1000);
        }
        if (!il2cpp_domain_get) { CHEAT_LOG("w: gave up binding"); return NULL; }

        // Wait for the Unity runtime to actually finish booting.
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        double bootStart = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;

        int idle = 0;
        while (idle < 900) {
            usleep(200 * 1000);
            idle++;
            clock_gettime(CLOCK_MONOTONIC, &ts);
            double now = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
            if (now - bootStart < 6.0) continue;
            if (!il2cpp_domain_get() ) continue;
            FinishInitialize();
            if (g_hooked) break;
        }
        if (!g_hooked) { CHEAT_LOG("w: tapout — never hooked"); return NULL; }

        // Keep sweeping for detectors. Some assemblies only load when a match starts.
        int sweeps = 0;
        while (true) {
            usleep(2 * 1000 * 1000);
            if (!g_config.acEnabled) continue;
            if (sweeps < 30) {
                int n = NukeAntiCheatSweep();
                sweeps++;
                if (n > 0 && sweeps > 3) sweeps = 30;
            } else {
                usleep(8 * 1000 * 1000);
            }
        }
    }
    return NULL;
}

#pragma mark - UI scheduling (main thread)

static void ScheduleUI() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CHEAT_LOG("m: Creating cheat UI");
            ShowMenu();
            SetupOverlayWindow();
            CHEAT_LOG("m: UI created");
        });
    });
}

#pragma mark - Entry

__attribute__((constructor))
static void StandoffCheatInit() {
    CHEAT_LOG("init: StandoffCheat dylib loaded");

    pthread_t thread;
    pthread_create(&thread, NULL, cheatWorker, NULL);
    ScheduleUI();
}
