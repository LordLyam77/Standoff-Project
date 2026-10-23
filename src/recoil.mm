#import "recoil.h"
#import "il2cpp_resolver.h"
#import "w2s.h"
#import "patch.h"
#import "tracelog.h"
#import <time.h>
#import <cstring>

extern IL2CPPResolver* GetResolver();
static RecoilControl s_recoil;

static Il2CppArray* FindAllOfType(const Il2CppClass* klass) {
    auto* r = GetResolver();
    if (!r || !klass || !r->classes.Object) return nullptr;
    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Object, "FindObjectsOfType", 1);
    if (!m) return nullptr;
    const Il2CppType* t = il2cpp_class_get_type(klass);
    Il2CppObject* typeObj = t ? il2cpp_type_get_object(t) : nullptr;
    if (!typeObj) return nullptr;
    Il2CppException* exc = nullptr;
    void* params[] = { typeObj };
    Il2CppObject* res = il2cpp_runtime_invoke(m, nullptr, params, &exc);
    if (exc || !res) return nullptr;
    return (Il2CppArray*)res;
}

// Patch the recoil application methods once. The old implementation did
// GameObject.Find("Weapon") and wrote to a field that does not exist on a class
// that was probably never resolved — it could never work.
static void PatchRecoilMethods(const Il2CppClass* klass) {
    if (!klass || !il2cpp_class_get_methods || !il2cpp_method_get_name) return;
    void* iter = nullptr;
    const Il2CppMethodInfo* m = nullptr;
    int patched = 0;
    while ((m = il2cpp_class_get_methods(klass, &iter)) != nullptr) {
        const char* name = il2cpp_method_get_name(m);
        if (!name) continue;
        if (strstr(name, ".ctor") || strstr(name, ".cctor") ||
            strstr(name, "get_") || strstr(name, "set_") ||
            strstr(name, "ToString") || strstr(name, "Equals")) continue;

        bool hit = strstr(name, "Apply") || strstr(name, "Recoil") ||
                   strstr(name, "Kick") || strstr(name, "Shot") ||
                   strstr(name, "Add") || strstr(name, "Update") ||
                   strstr(name, "Process") || strstr(name, "Calculate");
        if (!hit) continue;

        if (CheatPatchMethodZero(m)) {
            CHEAT_LOG("rc: patched %s", name);
            patched++;
        }
    }
    CHEAT_LOG("rc: %d recoil methods neutralised", patched);
}

void RecoilControl::Update() {
    if (!g_config.initialized || !g_config.recoilEnabled) return;

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double now = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
    if (now - m_last < 0.5) return;
    m_last = now;

    auto* r = GetResolver();
    if (!r || !r->classes.RecoilControl) {
        static bool logged = false;
        if (!logged) { CHEAT_LOG("rc: RecoilControl class not resolved"); logged = true; }
        return;
    }

    if (!m_dumped) {
        r->DumpClass(r->classes.RecoilControl, "RecoilControl(recoil)");
        m_dumped = true;
    }

    if (!m_patched) {
        PatchRecoilMethods(r->classes.RecoilControl);
        m_patched = true;
    }

    static const char* fields[] = {
        "_multiplier", "multiplier", "RecoilMultiplier", "_recoilMultiplier",
        "recoilMultiplier", "_kick", "kick", "_power", "power", "_strength", nullptr
    };

    Il2CppArray* instances = FindAllOfType(r->classes.RecoilControl);
    if (!instances) return;

    uintptr_t count = il2cpp_array_length ? il2cpp_array_length(instances) : 0;
    if (count > 64) count = 64;

    for (uintptr_t i = 0; i < count; i++) {
        void* obj = il2cpp_array_object_at(instances, i);
        if (!obj) continue;
        for (int f = 0; fields[f]; f++) {
            const Il2CppFieldInfo* field = il2cpp_class_get_field_from_name(r->classes.RecoilControl, fields[f]);
            if (!field) continue;
            float zero = 0.0f;
            il2cpp_field_set_value(obj, field, &zero);
        }
    }

    static bool loggedOnce = false;
    if (!loggedOnce) { CHEAT_LOG("rc: recoil sweep running over %lu instances", (unsigned long)count); loggedOnce = true; }
}

RecoilControl* GetRecoilControl() {
    return &s_recoil;
}
