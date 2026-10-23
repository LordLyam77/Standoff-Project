#pragma once
#import "cheat_data.h"
#import "il2cpp_api.h"

Vector3 WorldToScreenPoint(void* camera, Vector3 world);
Vector3 GetTransformPositionShared(void* transform);
void* GetComponentOn(void* component, void* componentClass);

// Shared IL2CPP helpers. These use properties (get_transform / get_up) instead of
// Component.GetComponent(Type), which the old code invoked with a raw Il2CppClass*
// where a System.Type object is required — every one of those calls failed.
void* GetTransformOf(void* component);
Vector3 GetTransformPositionOf(void* transform);
Vector3 GetTransformUpOf(void* transform);
Quaternion GetTransformRotationOf(void* transform);
bool SetTransformRotation(void* transform, Quaternion q);
