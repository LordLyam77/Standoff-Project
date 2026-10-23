#pragma once
#import "cheat_data.h"
#import "il2cpp_resolver.h"

class Aimbot {
public:
    void Update(float dt);
    void SetPlayerList(std::vector<PlayerData>* players) { m_players = players; }

private:
    PlayerData* FindBestTarget(const std::vector<PlayerData>& players, float* outAngle);
    void RotateCameraToward(Vector3 target, float smooth, float dt);
    void* GetCameraTransform();

    std::vector<PlayerData>* m_players = nullptr;
};

Aimbot* GetAimbot();
