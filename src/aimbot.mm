#import "aimbot.h"
#import "il2cpp_resolver.h"
#import "w2s.h"
#import "tracelog.h"
#import <cmath>

extern IL2CPPResolver* GetResolver();
extern void* g_mainCamera;
static Aimbot s_aimbot;

static Vector3 RotateVector(const Quaternion& q, Vector3 v) {
    Vector3 u = { q.x, q.y, q.z };
    float s = q.w;
    Vector3 uv = { u.y*v.z - u.z*v.y, u.z*v.x - u.x*v.z, u.x*v.y - u.y*v.x };
    Vector3 uuv = { u.y*uv.z - u.z*uv.y, u.z*uv.x - u.x*uv.z, u.x*uv.y - u.y*uv.x };
    return { v.x + 2.0f*(s*uv.x + uuv.x),
             v.y + 2.0f*(s*uv.y + uuv.y),
             v.z + 2.0f*(s*uv.z + uuv.z) };
}

static Quaternion Slerp(const Quaternion& a, const Quaternion& b, float t) {
    float dot = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
    Quaternion bb = b;
    if (dot < 0.0f) { dot = -dot; bb = { -b.x, -b.y, -b.z, -b.w }; }
    if (dot > 0.9995f) {
        return { a.x + (bb.x - a.x)*t, a.y + (bb.y - a.y)*t,
                 a.z + (bb.z - a.z)*t, a.w + (bb.w - a.w)*t };
    }
    float theta = acosf(dot);
    float sinT = sinf(theta);
    float wa = sinf((1.0f - t) * theta) / sinT;
    float wb = sinf(t * theta) / sinT;
    return { a.x*wa + bb.x*wb, a.y*wa + bb.y*wb, a.z*wa + bb.z*wb, a.w*wa + bb.w*wb };
}

void* Aimbot::GetCameraTransform() {
    if (!g_mainCamera) return nullptr;
    return GetTransformOf(g_mainCamera);
}

void Aimbot::Update(float dt) {
    if (!g_config.initialized || !g_config.aimbotEnabled || !m_players) return;

    std::vector<PlayerData> players;
    {
        std::lock_guard<std::recursive_mutex> lock(g_playersMutex);
        players = *m_players;
    }
    if (players.empty()) return;

    float angle = 0.0f;
    PlayerData* target = FindBestTarget(players, &angle);
    if (!target) return;

    RotateCameraToward(target->headPosition, g_config.aimbotSmooth, dt);
}

PlayerData* Aimbot::FindBestTarget(const std::vector<PlayerData>& players, float* outAngle) {
    auto* r = GetResolver();
    if (!r) return nullptr;

    void* camT = GetCameraTransform();
    if (!camT) return nullptr;

    Vector3 camPos = GetTransformPositionOf(camT);
    Quaternion camRot = GetTransformRotationOf(camT);
    Vector3 forward = RotateVector(camRot, {0, 0, 1});

    float maxAngle = g_config.aimbotFov * 0.5f;
    if (maxAngle < 0.5f) maxAngle = 0.5f;

    float bestAngle = 999.0f;
    int bestIdx = -1;

    for (size_t i = 0; i < players.size(); i++) {
        const PlayerData& p = players[i];
        if (p.isLocal || !p.alive) continue;

        Vector3 dir = p.headPosition - camPos;
        float len = sqrtf(dir.x*dir.x + dir.y*dir.y + dir.z*dir.z);
        if (len < 0.05f) continue;
        dir.x /= len; dir.y /= len; dir.z /= len;

        float dot = dir.x*forward.x + dir.y*forward.y + dir.z*forward.z;
        if (dot < -1.0f) dot = -1.0f;
        if (dot > 1.0f) dot = 1.0f;
        float ang = acosf(dot) * (180.0f / M_PI);

        if (ang < bestAngle && (!g_config.aimbotOnShoot || ang <= maxAngle)) {
            bestAngle = ang;
            bestIdx = (int)i;
        }
    }

    if (bestIdx < 0) return nullptr;
    if (outAngle) *outAngle = bestAngle;

    static int logged = 0;
    if ((logged++ % 120) == 0)
        CHEAT_LOG("a: target %s angle %.1f° dist %.1fm", players[bestIdx].name, bestAngle, players[bestIdx].distance);

    return const_cast<PlayerData*>(&players[bestIdx]);
}

void Aimbot::RotateCameraToward(Vector3 target, float smooth, float dt) {
    auto* r = GetResolver();
    if (!r || !r->classes.Quaternion) return;

    void* camT = GetCameraTransform();
    if (!camT) return;

    Vector3 camPos = GetTransformPositionOf(camT);
    Vector3 dir = target - camPos;
    float len = sqrtf(dir.x*dir.x + dir.y*dir.y + dir.z*dir.z);
    if (len < 0.01f) return;

    const Il2CppMethodInfo* look = il2cpp_class_get_method_from_name(r->classes.Quaternion, "LookRotation", 2);
    if (!look) {
        static bool logged = false;
        if (!logged) { CHEAT_LOG("a: Quaternion.LookRotation(2) missing"); logged = true; }
        return;
    }

    Vector3 up = {0, 1, 0};
    void* params[] = { &dir, &up };
    Il2CppException* exc = nullptr;
    Il2CppObject* res = il2cpp_runtime_invoke(look, nullptr, params, &exc);
    if (!res || exc) return;

    Quaternion want = *(Quaternion*)il2cpp_object_unbox(res);
    Quaternion cur = GetTransformRotationOf(camT);

    float speed = (smooth > 0.05f) ? (22.0f / smooth) : 22.0f;
    if (speed > 30.0f) speed = 30.0f;
    if (speed < 0.6f) speed = 0.6f;
    float t = 1.0f - expf(-speed * (dt > 0.001f ? dt : 0.016f));
    if (t > 1.0f) t = 1.0f;

    Quaternion next = Slerp(cur, want, t);
    SetTransformRotation(camT, next);
}

Aimbot* GetAimbot() {
    return &s_aimbot;
}
