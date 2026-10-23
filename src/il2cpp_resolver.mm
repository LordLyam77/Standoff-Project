#import "il2cpp_resolver.h"
#include <dlfcn.h>
#include <cstdio>
#include "tracelog.h"

#define DEFINE_FPTR(ret, name, args) __attribute__((visibility("hidden"))) ret (*name) args = nullptr

extern "C" {
    DEFINE_FPTR(const Il2CppDomain*, il2cpp_domain_get, ());
    DEFINE_FPTR(const Il2CppAssembly**, il2cpp_domain_get_assemblies, (const Il2CppDomain*, size_t*));
    DEFINE_FPTR(const Il2CppImage*, il2cpp_assembly_get_image, (const Il2CppAssembly*));
    DEFINE_FPTR(const char*, il2cpp_image_get_name, (const Il2CppImage*));
    DEFINE_FPTR(size_t, il2cpp_image_get_class_count, (const Il2CppImage*));
    DEFINE_FPTR(const Il2CppClass*, il2cpp_image_get_class, (const Il2CppImage*, int));
    DEFINE_FPTR(const Il2CppClass*, il2cpp_class_from_name, (const Il2CppImage*, const char*, const char*));
    DEFINE_FPTR(const Il2CppClass*, il2cpp_class_get_parent, (const Il2CppClass*));
    DEFINE_FPTR(const Il2CppFieldInfo*, il2cpp_class_get_field_from_name, (const Il2CppClass*, const char*));
    DEFINE_FPTR(const Il2CppMethodInfo*, il2cpp_class_get_method_from_name, (const Il2CppClass*, const char*, int));
    DEFINE_FPTR(const char*, il2cpp_class_get_name, (const Il2CppClass*));
    DEFINE_FPTR(const char*, il2cpp_class_get_namespace, (const Il2CppClass*));
    DEFINE_FPTR(const Il2CppFieldInfo*, il2cpp_class_get_fields, (const Il2CppClass*, void**));
    DEFINE_FPTR(const Il2CppMethodInfo*, il2cpp_class_get_methods, (const Il2CppClass*, void**));
    DEFINE_FPTR(size_t, il2cpp_field_get_offset, (const Il2CppFieldInfo*));
    DEFINE_FPTR(const char*, il2cpp_field_get_name, (const Il2CppFieldInfo*));
    DEFINE_FPTR(const Il2CppType*, il2cpp_field_get_type, (const Il2CppFieldInfo*));
    DEFINE_FPTR(void, il2cpp_field_get_value, (void*, const Il2CppFieldInfo*, void*));
    DEFINE_FPTR(void, il2cpp_field_set_value, (void*, const Il2CppFieldInfo*, const void*));
    DEFINE_FPTR(void, il2cpp_field_static_get_value, (const Il2CppFieldInfo*, void*));
    DEFINE_FPTR(void, il2cpp_field_static_set_value, (const Il2CppFieldInfo*, const void*));
    DEFINE_FPTR(Il2CppObject*, il2cpp_runtime_invoke, (const Il2CppMethodInfo*, void*, void**, Il2CppException**));
    DEFINE_FPTR(const char*, il2cpp_method_get_name, (const Il2CppMethodInfo*));
    DEFINE_FPTR(int, il2cpp_method_get_param_count, (const Il2CppMethodInfo*));
    DEFINE_FPTR(Il2CppObject*, il2cpp_object_new, (const Il2CppClass*));
    DEFINE_FPTR(void*, il2cpp_object_unbox, (Il2CppObject*));
    DEFINE_FPTR(Il2CppClass*, il2cpp_object_get_class, (Il2CppObject*));
    DEFINE_FPTR(Il2CppThread*, il2cpp_thread_attach, (const Il2CppDomain*));
    DEFINE_FPTR(Il2CppThread*, il2cpp_thread_current, ());
    DEFINE_FPTR(const Il2CppDomain*, il2cpp_thread_get_domain, (Il2CppThread*));
    DEFINE_FPTR(Il2CppClass*, il2cpp_class_from_il2cpp_type, (const Il2CppType*));
    DEFINE_FPTR(const Il2CppType*, il2cpp_class_get_type, (const Il2CppClass*));
    DEFINE_FPTR(int, il2cpp_type_get_type, (const Il2CppType*));
    DEFINE_FPTR(Il2CppObject*, il2cpp_type_get_object, (const Il2CppType*));
    DEFINE_FPTR(Il2CppObject*, il2cpp_string_new, (const char*));
    DEFINE_FPTR(int32_t, il2cpp_string_length, (Il2CppObject*));
    DEFINE_FPTR(const Il2CppChar*, il2cpp_string_chars, (Il2CppObject*));
    DEFINE_FPTR(Il2CppArray*, il2cpp_array_new, (const Il2CppClass*, uintptr_t));
    DEFINE_FPTR(Il2CppArray*, il2cpp_array_new_specific, (const Il2CppClass*, uintptr_t));
    DEFINE_FPTR(Il2CppClass*, il2cpp_array_class_get, (const Il2CppClass*, uint32_t));
    DEFINE_FPTR(void*, il2cpp_array_addr_with_size, (const Il2CppArray*, int32_t, uintptr_t));
    DEFINE_FPTR(uintptr_t, il2cpp_array_length, (const Il2CppArray*));
}

extern IL2CPPResolver* g_resolver;

IL2CPPResolver* GetResolver() {
    return g_resolver;
}

// ---------------------------------------------------------------------------
// Global class index
// ---------------------------------------------------------------------------

void IL2CPPResolver::BuildClassIndex() {
    if (m_indexBuilt) return;
    m_indexBuilt = true;
    if (!il2cpp_image_get_class_count || !il2cpp_image_get_class) {
        CHEAT_LOG("r: image class enumeration unavailable");
        return;
    }

    size_t total = 0;
    for (size_t i = 0; i < assemblyCount; i++) {
        const Il2CppImage* img = il2cpp_assembly_get_image(assemblies[i]);
        if (!img) continue;
        const char* imgName = il2cpp_image_get_name(img);
        if (!imgName) imgName = "";

        size_t count = il2cpp_image_get_class_count(img);
        for (size_t c = 0; c < count; c++) {
            const Il2CppClass* k = il2cpp_image_get_class(img, (int)c);
            if (!k) continue;
            const char* nm = il2cpp_class_get_name(k);
            if (!nm || !*nm || nm[0] == '<') continue;

            std::string key(nm);
            auto it = m_classIndex.find(key);
            if (it == m_classIndex.end()) {
                m_classIndex.emplace(key, k);
                m_classImage.emplace(key, imgName);
            } else {
                bool hadGame = m_classImage[key].find("Assembly-CSharp") != std::string::npos;
                bool isGame = strstr(imgName, "Assembly-CSharp") != nullptr;
                if (!hadGame && isGame) {
                    it->second = k;
                    m_classImage[key] = imgName;
                }
            }
            total++;
        }
    }
    CHEAT_LOG("r: indexed %zu classes / %zu assemblies", total, assemblyCount);
}

const Il2CppClass* IL2CPPResolver::FindClassAnywhere(const char* name) {
    if (!name) return nullptr;
    BuildClassIndex();
    auto it = m_classIndex.find(name);
    if (it != m_classIndex.end()) return it->second;
    return nullptr;
}

std::vector<const Il2CppClass*> IL2CPPResolver::FindClassesContaining(const char* needle, int max) {
    std::vector<const Il2CppClass*> out;
    if (!needle) return out;
    BuildClassIndex();
    for (auto& kv : m_classIndex) {
        if ((int)out.size() >= max) break;
        if (kv.first.find(needle) != std::string::npos) out.push_back(kv.second);
    }
    return out;
}

void IL2CPPResolver::DumpClass(const Il2CppClass* klass, const char* label) {
    if (!klass) { CHEAT_LOG("d: %s = NOT FOUND", label ? label : "?"); return; }

    const char* ns = il2cpp_class_get_namespace ? il2cpp_class_get_namespace(klass) : "";
    const char* nm = il2cpp_class_get_name ? il2cpp_class_get_name(klass) : "";
    CHEAT_LOG("d: === %s  %s::%s  @%p", label ? label : "?", ns ? ns : "", nm ? nm : "", klass);

    const Il2CppClass* cur = klass;
    for (int depth = 0; depth < 3 && cur; depth++) {
        const char* cn = il2cpp_class_get_name(cur);
        CHEAT_LOG("d:  -- %s --", cn ? cn : "?");
        void* iter = nullptr;
        const Il2CppFieldInfo* f = nullptr;
        int n = 0;
        while (il2cpp_class_get_fields && (f = il2cpp_class_get_fields(cur, &iter)) != nullptr && n < 96) {
            const char* fn = il2cpp_field_get_name(f);
            CHEAT_LOG("d:    f %-36s off=0x%zx", fn ? fn : "?", il2cpp_field_get_offset(f));
            n++;
        }
        cur = il2cpp_class_get_parent ? il2cpp_class_get_parent(cur) : nullptr;
    }

    void* iter = nullptr;
    const Il2CppMethodInfo* m = nullptr;
    int n = 0;
    while (il2cpp_class_get_methods && (m = il2cpp_class_get_methods(klass, &iter)) != nullptr && n < 128) {
        const char* mn = il2cpp_method_get_name(m);
        if (mn) {
            int pc = il2cpp_method_get_param_count ? il2cpp_method_get_param_count(m) : -1;
            CHEAT_LOG("d:    m %s(%d)", mn, pc);
        }
        n++;
    }
}

void IL2CPPResolver::DumpClassesContaining(const char* needle, int max) {
    auto list = FindClassesContaining(needle, max);
    CHEAT_LOG("d: classes containing '%s': %zu", needle ? needle : "?", list.size());
    for (auto* k : list) {
        const char* ns = il2cpp_class_get_namespace ? il2cpp_class_get_namespace(k) : "";
        const char* nm = il2cpp_class_get_name ? il2cpp_class_get_name(k) : "";
        CHEAT_LOG("d:    %s::%s", ns ? ns : "", nm ? nm : "");
    }
}

// ---------------------------------------------------------------------------

const Il2CppClass* IL2CPPResolver::FindClass(const char* ns, const char* name) {
    for (size_t i = 0; i < assemblyCount; i++) {
        const Il2CppImage* img = il2cpp_assembly_get_image(assemblies[i]);
        if (!img) continue;
        const Il2CppClass* klass = il2cpp_class_from_name(img, ns, name);
        if (klass) return klass;
    }
    return nullptr;
}

const Il2CppClass* IL2CPPResolver::FindClassRecursive(const char* name) {
    const Il2CppClass* k = FindClassAnywhere(name);
    if (k) return k;
    return FindClass("", name);
}

size_t IL2CPPResolver::GetFieldOffset(const Il2CppClass* klass, const char* fieldName) {
    if (!klass || !fieldName) return 0;
    std::string key = std::string(il2cpp_class_get_name(klass)) + "." + fieldName;
    auto it = m_fieldCache.find(key);
    if (it != m_fieldCache.end()) return it->second;
    const Il2CppFieldInfo* field = il2cpp_class_get_field_from_name(klass, fieldName);
    if (!field) return 0;
    size_t offset = il2cpp_field_get_offset(field);
    m_fieldCache[key] = offset;
    return offset;
}

const Il2CppMethodInfo* IL2CPPResolver::GetMethod(const Il2CppClass* klass, const char* name, int paramCount) {
    if (!klass || !name) return nullptr;
    return il2cpp_class_get_method_from_name(klass, name, paramCount);
}

int IL2CPPResolver::UnityScreenWidth() {
    if (!classes.Screen) return 0;
    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(classes.Screen, "get_width", 0);
    if (!m) return 0;
    Il2CppObject* r = il2cpp_runtime_invoke(m, nullptr, nullptr, nullptr);
    if (!r) return 0;
    return *(int*)il2cpp_object_unbox(r);
}

int IL2CPPResolver::UnityScreenHeight() {
    if (!classes.Screen) return 0;
    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(classes.Screen, "get_height", 0);
    if (!m) return 0;
    Il2CppObject* r = il2cpp_runtime_invoke(m, nullptr, nullptr, nullptr);
    if (!r) return 0;
    return *(int*)il2cpp_object_unbox(r);
}

bool IL2CPPResolver::Initialize() {
    if (m_ready) return true;

    domain = il2cpp_domain_get();
    if (!domain) return false;

    assemblies = il2cpp_domain_get_assemblies(domain, &assemblyCount);
    if (!assemblies || assemblyCount == 0) return false;

    CHEAT_LOG("r: domain ok, %zu assemblies", assemblyCount);

    BuildClassIndex();

    // Game classes: resolved by simple name across every image, no namespace guessing.
    classes.PlayerController      = FindClassRecursive("PlayerController");
    classes.PlayerManager         = FindClassRecursive("PlayerManager");
    classes.BipedMap              = FindClassRecursive("BipedMap");
    classes.PlayerCharacterView   = FindClassRecursive("PlayerCharacterView");
    classes.PlayerView            = FindClassRecursive("PlayerView");
    classes.Player                = FindClassRecursive("Player");
    classes.WeaponController      = FindClassRecursive("WeaponController");
    classes.RecoilControl         = FindClassRecursive("RecoilControl");
    classes.RecoilParameters      = FindClassRecursive("RecoilParameters");
    classes.CameraScopeZoomer     = FindClassRecursive("CameraScopeZoomer");
    classes.AimView               = FindClassRecursive("AimView");
    classes.ShootArea             = FindClassRecursive("ShootArea");
    classes.HUDView               = FindClassRecursive("HUDView");
    classes.FpsOverlay            = FindClassRecursive("FpsOverlay");
    classes.WeaponManager         = FindClassRecursive("WeaponManager");
    classes.PlayerInputs          = FindClassRecursive("PlayerInputs");
    classes.Raycaster             = FindClassRecursive("Raycaster");
    classes.SpectatorCameraEffect = FindClassRecursive("SpectatorCameraEffect");
    classes.PhotonPlayerGameExtension = FindClassRecursive("PhotonPlayerGameExtension");

    CHEAT_LOG("r: game classes  PC=%p PM=%p BV=%p PCV=%p PV=%p P=%p WC=%p RC=%p AV=%p PI=%p",
              (void*)classes.PlayerController, (void*)classes.PlayerManager,
              (void*)classes.BipedMap, (void*)classes.PlayerCharacterView,
              (void*)classes.PlayerView, (void*)classes.Player,
              (void*)classes.WeaponController, (void*)classes.RecoilControl,
              (void*)classes.AimView, (void*)classes.PlayerInputs);

    classes.PhotonView   = FindClassRecursive("PhotonView");
    if (!classes.PhotonView) classes.PhotonView = FindClass("Photon", "PhotonView");
    classes.PhotonPlayer = FindClassRecursive("PhotonPlayer");
    if (!classes.PhotonPlayer) classes.PhotonPlayer = FindClass("", "PhotonPlayer");

    classes.GameObject    = FindClass("UnityEngine", "GameObject");
    classes.Transform     = FindClass("UnityEngine", "Transform");
    classes.Camera        = FindClass("UnityEngine", "Camera");
    classes.MonoBehaviour = FindClass("UnityEngine", "MonoBehaviour");
    classes.Behaviour     = FindClass("UnityEngine", "Behaviour");
    classes.Component     = FindClass("UnityEngine", "Component");
    classes.Object        = FindClass("UnityEngine", "Object");
    classes.Vector3       = FindClass("UnityEngine", "Vector3");
    classes.Quaternion    = FindClass("UnityEngine", "Quaternion");
    classes.Rect          = FindClass("UnityEngine", "Rect");
    classes.Screen        = FindClass("UnityEngine", "Screen");

    CHEAT_LOG("r: engine classes T=%p C=%p GO=%p O=%p V3=%p Q=%p S=%p",
              (void*)classes.Transform, (void*)classes.Camera, (void*)classes.GameObject,
              (void*)classes.Object, (void*)classes.Vector3, (void*)classes.Quaternion,
              (void*)classes.Screen);

    bool havePlayerClass = classes.PlayerController || classes.PlayerCharacterView ||
                           classes.PlayerView || classes.Player;

    if (!classes.Transform || !classes.Camera || !classes.Object || !classes.Component) {
        CHEAT_LOG("r: FAILED — engine classes missing (T=%p C=%p O=%p Comp=%p)",
                  (void*)classes.Transform, (void*)classes.Camera,
                  (void*)classes.Object, (void*)classes.Component);
        return false;
    }
    if (!havePlayerClass) {
        CHEAT_LOG("r: FAILED — no player class found by name");
        return false;
    }

    CHEAT_LOG("r: ready (unity screen %dx%d)", UnityScreenWidth(), UnityScreenHeight());
    m_ready = true;
    return true;
}
