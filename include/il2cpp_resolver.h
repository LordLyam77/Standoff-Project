#pragma once
#include "il2cpp_api.h"
#include <vector>
#include <string>
#include <unordered_map>
#include <cstring>

class IL2CPPResolver {
public:
    bool Initialize();
    bool IsReady() const { return m_ready; }

    const Il2CppDomain* domain = nullptr;
    const Il2CppAssembly** assemblies = nullptr;
    size_t assemblyCount = 0;

    struct {
        const Il2CppClass* PlayerController;
        const Il2CppClass* PlayerManager;
        const Il2CppClass* BipedMap;
        const Il2CppClass* PlayerCharacterView;
        const Il2CppClass* PlayerView;
        const Il2CppClass* Player;
        const Il2CppClass* WeaponController;
        const Il2CppClass* RecoilControl;
        const Il2CppClass* RecoilParameters;
        const Il2CppClass* CameraScopeZoomer;
        const Il2CppClass* AimView;
        const Il2CppClass* ShootArea;
        const Il2CppClass* HUDView;
        const Il2CppClass* FpsOverlay;
        const Il2CppClass* WeaponManager;
        const Il2CppClass* PlayerInputs;
        const Il2CppClass* Raycaster;
        const Il2CppClass* SpectatorCameraEffect;
        const Il2CppClass* PhotonPlayerGameExtension;
        const Il2CppClass* PhotonView;
        const Il2CppClass* PhotonPlayer;
        const Il2CppClass* GameObject;
        const Il2CppClass* Transform;
        const Il2CppClass* Camera;
        const Il2CppClass* MonoBehaviour;
        const Il2CppClass* Behaviour;
        const Il2CppClass* Component;
        const Il2CppClass* Object;
        const Il2CppClass* Vector3;
        const Il2CppClass* Quaternion;
        const Il2CppClass* Rect;
        const Il2CppClass* Screen;
    } classes = {};

    // Global lookup by simple class name, across every loaded image.
    // This removes the namespace guessing that was silently returning null.
    void BuildClassIndex();
    const Il2CppClass* FindClassAnywhere(const char* name);
    std::vector<const Il2CppClass*> FindClassesContaining(const char* needle, int max = 32);

    void DumpClass(const Il2CppClass* klass, const char* label);
    void DumpClassesContaining(const char* needle, int max = 32);

    size_t GetFieldOffset(const Il2CppClass* klass, const char* fieldName);
    const Il2CppMethodInfo* GetMethod(const Il2CppClass* klass, const char* name, int paramCount = -1);

    // Engine side stats, filled once. Unity screen space is pixels; UIKit is points.
    int UnityScreenWidth();
    int UnityScreenHeight();

private:
    bool m_ready = false;
    bool m_indexBuilt = false;
    std::unordered_map<std::string, size_t> m_fieldCache;
    std::unordered_map<std::string, const Il2CppClass*> m_classIndex;
    std::unordered_map<std::string, std::string> m_classImage;

    const Il2CppClass* FindClass(const char* ns, const char* name);
    const Il2CppClass* FindClassRecursive(const char* name);
};

IL2CPPResolver* GetResolver();
