#import "w2s.h"
#import "il2cpp_resolver.h"
#include <cmath>

extern IL2CPPResolver* GetResolver();

static void EnsureAttached() {
    if (!il2cpp_thread_attach || !il2cpp_domain_get) return;
    static thread_local bool attached = false;
    if (attached) return;
    const Il2CppDomain* d = il2cpp_domain_get();
    if (d) { il2cpp_thread_attach(d); attached = true; }
}

Vector3 WorldToScreenPoint(void* camera, Vector3 world) {
    auto* r = GetResolver();
    if (!r || !camera || !r->classes.Camera) return {};
    EnsureAttached();

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Camera, "WorldToScreenPoint", 1);
    if (!m) return {};

    Il2CppException* exc = nullptr;
    void* params[] = { &world };
    Il2CppObject* result = il2cpp_runtime_invoke(m, camera, params, &exc);
    if (!result || exc) return {};
    return *(Vector3*)il2cpp_object_unbox(result);
}

void* GetTransformOf(void* component) {
    auto* r = GetResolver();
    if (!r || !component || !r->classes.Component) return nullptr;
    EnsureAttached();

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Component, "get_transform", 0);
    if (!m) return nullptr;
    Il2CppException* exc = nullptr;
    Il2CppObject* res = il2cpp_runtime_invoke(m, component, nullptr, &exc);
    if (!res || exc) return nullptr;
    return res;
}

Vector3 GetTransformPositionOf(void* transform) {
    auto* r = GetResolver();
    if (!r || !transform || !r->classes.Transform) return {};
    EnsureAttached();

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Transform, "get_position", 0);
    if (!m) return {};
    Il2CppException* exc = nullptr;
    Il2CppObject* res = il2cpp_runtime_invoke(m, transform, nullptr, &exc);
    if (!res || exc) return {};
    return *(Vector3*)il2cpp_object_unbox(res);
}

Vector3 GetTransformUpOf(void* transform) {
    auto* r = GetResolver();
    if (!r || !transform || !r->classes.Transform) return {0, 1, 0};
    EnsureAttached();

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Transform, "get_up", 0);
    if (!m) return {0, 1, 0};
    Il2CppException* exc = nullptr;
    Il2CppObject* res = il2cpp_runtime_invoke(m, transform, nullptr, &exc);
    if (!res || exc) return {0, 1, 0};
    return *(Vector3*)il2cpp_object_unbox(res);
}

Quaternion GetTransformRotationOf(void* transform) {
    auto* r = GetResolver();
    if (!r || !transform || !r->classes.Transform) return {0, 0, 0, 1};
    EnsureAttached();

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Transform, "get_rotation", 0);
    if (!m) return {0, 0, 0, 1};
    Il2CppException* exc = nullptr;
    Il2CppObject* res = il2cpp_runtime_invoke(m, transform, nullptr, &exc);
    if (!res || exc) return {0, 0, 0, 1};
    return *(Quaternion*)il2cpp_object_unbox(res);
}

bool SetTransformRotation(void* transform, Quaternion q) {
    auto* r = GetResolver();
    if (!r || !transform || !r->classes.Transform) return false;
    EnsureAttached();

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Transform, "set_rotation", 1);
    if (!m) return false;
    Il2CppException* exc = nullptr;
    void* params[] = { &q };
    il2cpp_runtime_invoke(m, transform, params, &exc);
    return exc == nullptr;
}

Vector3 GetTransformPositionShared(void* transform) {
    return GetTransformPositionOf(transform);
}

void* GetComponentOn(void* component, void* componentClass) {
    auto* r = GetResolver();
    if (!r || !component || !componentClass || !r->classes.Component) return nullptr;
    EnsureAttached();

    // Component.GetComponent(Type) needs a System.Type instance, not an Il2CppClass*.
    const Il2CppType* t = il2cpp_class_get_type((const Il2CppClass*)componentClass);
    Il2CppObject* typeObj = t ? il2cpp_type_get_object(t) : nullptr;
    if (!typeObj) return nullptr;

    const Il2CppMethodInfo* m = il2cpp_class_get_method_from_name(r->classes.Component, "GetComponent", 1);
    if (!m) return nullptr;

    Il2CppException* exc = nullptr;
    void* params[] = { typeObj };
    Il2CppObject* res = il2cpp_runtime_invoke(m, component, params, &exc);
    if (exc) return nullptr;
    return res;
}
