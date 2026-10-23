#import "esp.h"
#import "il2cpp_resolver.h"
#import "w2s.h"
#import "tracelog.h"
#import <time.h>
#import <cmath>

extern IL2CPPResolver* GetResolver();
static ESP s_esp;

// --- safe field readers -----------------------------------------------------

static Vector3 ReadVector3(void* obj, const Il2CppClass* klass, const char* field) {
    if (!obj || !klass || !field) return {};
    const Il2CppFieldInfo* f = il2cpp_class_get_field_from_name(klass, field);
    if (!f) return {};
    Vector3 out;
    il2cpp_field_get_value(obj, f, &out);
    return out;
}

static float ReadFloat(void* obj, const Il2CppClass* klass, const char* field) {
    if (!obj || !klass || !field) return 0;
    const Il2CppFieldInfo* f = il2cpp_class_get_field_from_name(klass, field);
    if (!f) return 0;
    float v = 0;
    il2cpp_field_get_value(obj, f, &v);
    return v;
}

static int ReadInt(void* obj, const Il2CppClass* klass, const char* field) {
    if (!obj || !klass || !field) return 0;
    const Il2CppFieldInfo* f = il2cpp_class_get_field_from_name(klass, field);
    if (!f) return 0;
    int v = 0;
    il2cpp_field_get_value(obj, f, &v);
    return v;
}

static bool ReadBool(void* obj, const Il2CppClass* klass, const char* field) {
    if (!obj || !klass || !field) return false;
    const Il2CppFieldInfo* f = il2cpp_class_get_field_from_name(klass, field);
    if (!f) return false;
    unsigned char v = 0;
    il2cpp_field_get_value(obj, f, &v);
    return v != 0;
}

static bool HasField(const Il2CppClass* klass, const char* field) {
    return klass && field && il2cpp_class_get_field_from_name(klass, field) != nullptr;
}

// IL2CPP strings are UTF-16. The old code never read them at all.
static void ReadString(void* obj, const Il2CppClass* klass, const char* field, char* out, size_t cap) {
    if (!out || cap == 0) return;
    out[0] = 0;
    if (!obj || !klass || !field || !il2cpp_string_length || !il2cpp_string_chars) return;
    const Il2CppFieldInfo* f = il2cpp_class_get_field_from_name(klass, field);
    if (!f) return;
    Il2CppObject* s = nullptr;
    il2cpp_field_get_value(obj, f, &s);
    if (!s) return;

    int len = il2cpp_string_length(s);
    const Il2CppChar* chars = il2cpp_string_chars(s);
    if (!chars || len <= 0) return;

    size_t n = 0;
    for (int i = 0; i < len && n + 1 < cap; i++) {
        uint32_t c = chars[i];
        if (c < 0x80) {
            out[n++] = (char)c;
        } else if (c < 0x800) {
            out[n++] = (char)(0xC0 | (c >> 6));
            if (n + 1 < cap) out[n++] = (char)(0x80 | (c & 0x3F));
        } else {
            out[n++] = (char)(0xE0 | (c >> 12));
            if (n + 1 < cap) out[n++] = (char)(0x80 | ((c >> 6) & 0x3F));
            if (n + 1 < cap) out[n++] = (char)(0x80 | (c & 0x3F));
        }
    }
    out[n] = 0;
}

// --- camera / player discovery ---------------------------------------------

static void* GetMainCamera() {
    auto* r = GetResolver();
    if (!r || !r->classes.Camera) return nullptr;
    const Il2CppMethodInfo* getMain = il2cpp_class_get_method_from_name(r->classes.Camera, "get_main", 0);
    if (!getMain) return nullptr;
    Il2CppException* exc = nullptr;
    Il2CppObject* cam = il2cpp_runtime_invoke(getMain, nullptr, nullptr, &exc);
    if (exc) return nullptr;
    return cam;
}

static Il2CppArray* FindObjectsOfType(const Il2CppClass* klass) {
    auto* r = GetResolver();
    if (!r || !klass || !r->classes.Object) return nullptr;

    // Object.FindObjectsOfType(Type) — the parameter must be a System.Type object.
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

static const Il2CppClass* PickPlayerClass(IL2CPPResolver* r) {
    if (!r) return nullptr;
    // Cycle through the candidates. If a class exists but has no scene
    // instances (a plain data class, not a MonoBehaviour), we need to try the
    // next one instead of staring at an empty array forever.
    static int cursor = 0;
    const Il2CppClass* cands[4] = {
        r->classes.PlayerController,
        r->classes.PlayerCharacterView,
        r->classes.PlayerView,
        r->classes.Player
    };
    for (int i = 0; i < 4; i++) {
        int k = (cursor + i) % 4;
        if (cands[k]) { cursor = (k + 1) % 4; return cands[k]; }
    }
    return nullptr;
}

static bool ReadAnyFloat(void* obj, const Il2CppClass* klass, const char** fields, float* out) {
    for (int i = 0; fields[i]; i++) {
        if (!HasField(klass, fields[i])) continue;
        float v = ReadFloat(obj, klass, fields[i]);
        if (v > 0.01f) { *out = v; return true; }
    }
    return false;
}

static bool ReadAnyInt(void* obj, const Il2CppClass* klass, const char** fields, int* out) {
    for (int i = 0; fields[i]; i++) {
        if (!HasField(klass, fields[i])) continue;
        int v = ReadInt(obj, klass, fields[i]);
        *out = v;
        return true;
    }
    return false;
}

// --- ESP --------------------------------------------------------------------

void ESP::Initialize() {
    CHEAT_LOG("e: init");
}

void ESP::Update() {
    if (!g_config.initialized) return;

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    double now = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
    if (now - m_lastCollect < 0.08) return;
    m_lastCollect = now;

    CollectPlayers();
}

void ESP::CollectPlayers() {
    auto* r = GetResolver();
    if (!r) return;

    void* camera = GetMainCamera();
    if (camera) g_mainCamera = camera;

    if (!m_playerClass) m_playerClass = PickPlayerClass(r);
    if (!m_playerClass) {
        if (!m_loggedEmpty) { CHEAT_LOG("e: no player class resolved"); m_loggedEmpty = true; }
        return;
    }

    Il2CppArray* all = FindObjectsOfType(m_playerClass);
    if (!all) {
        std::lock_guard<std::recursive_mutex> lock(g_playersMutex);
        g_players.clear();
        return;
    }

    uintptr_t count = il2cpp_array_length ? il2cpp_array_length(all) : 0;
    if (count > 128) count = 128;

    if (count == 0) {
        static int emptyScans = 0;
        if ((++emptyScans % 10) == 0) {
            m_playerClass = PickPlayerClass(r);
            CHEAT_LOG("e: scan empty, cycling player class -> %s",
                      m_playerClass ? il2cpp_class_get_name(m_playerClass) : "none");
        }
        std::lock_guard<std::recursive_mutex> lock(g_playersMutex);
        g_players.clear();
        return;
    }

    std::vector<PlayerData> collected;
    collected.reserve(count);

    static const char* hpFields[] = { "_hp", "_health", "health", "Health", "_currentHp", "hp", "HealthPoints", nullptr };
    static const char* maxHpFields[] = { "_maxHp", "_maxHealth", "maxHealth", "MaxHealth", "MaxHealthPoints", nullptr };
    static const char* teamFields[] = { "_team", "team", "Team", "playerTeam", "_teamId", "TeamId", "_command", nullptr };
    static const char* aliveFields[] = { "_alive", "isAlive", "IsAlive", "_isAlive", "alive", "_isDead", nullptr };
    static const char* localFields[] = { "isLocal", "_isLocal", "isLocalPlayer", "_isLocalPlayer", "isMyPlayer", "isMine", "local", nullptr };
    static const char* nameFields[] = { "_nickname", "nickname", "Nickname", "_name", "name", "playerName", "PlayerName", "_displayName", nullptr };

    Vector3 camPos = {};
    if (camera) {
        void* camT = GetTransformOf(camera);
        if (camT) camPos = GetTransformPositionOf(camT);
    }

    void* localObj = nullptr;
    Vector3 localPos = camPos;

    for (uintptr_t i = 0; i < count; i++) {
        void* player = il2cpp_array_object_at(all, i);
        if (!player) continue;

        PlayerData pd = {};
        pd.obj = player;
        pd.transform = GetTransformOf(player);
        if (!pd.transform) continue;

        pd.position = GetTransformPositionOf(pd.transform);
        Vector3 up = GetTransformUpOf(pd.transform);
        pd.headPosition = pd.position + up * 1.62f;

        pd.health = 100.0f;
        pd.maxHealth = 100.0f;
        ReadAnyFloat(player, m_playerClass, hpFields, &pd.health);
        ReadAnyFloat(player, m_playerClass, maxHpFields, &pd.maxHealth);
        if (pd.maxHealth <= 0.01f) pd.maxHealth = 100.0f;

        pd.team = 0;
        ReadAnyInt(player, m_playerClass, teamFields, &pd.team);

        pd.alive = true;
        for (int a = 0; aliveFields[a]; a++) {
            if (!HasField(m_playerClass, aliveFields[a])) continue;
            if (strcmp(aliveFields[a], "_isDead") == 0) pd.alive = !ReadBool(player, m_playerClass, aliveFields[a]);
            else pd.alive = ReadBool(player, m_playerClass, aliveFields[a]);
            break;
        }

        for (int n = 0; nameFields[n] && pd.name[0] == 0; n++)
            ReadString(player, m_playerClass, nameFields[n], pd.name, sizeof(pd.name));

        bool isLocal = false;
        for (int l = 0; localFields[l]; l++) {
            if (!HasField(m_playerClass, localFields[l])) continue;
            isLocal = ReadBool(player, m_playerClass, localFields[l]);
            break;
        }
        pd.isLocal = isLocal;
        if (isLocal && !localObj) {
            localObj = player;
            localPos = pd.position;
            g_localPlayer = player;
        }

        collected.push_back(pd);
    }

    // If the game exposes no isLocal flag, the closest body to the camera is us.
    if (!localObj && !collected.empty()) {
        float best = 1e9f;
        int bestIdx = -1;
        for (size_t i = 0; i < collected.size(); i++) {
            float d = collected[i].position.Distance(camPos);
            if (d < best) { best = d; bestIdx = (int)i; }
        }
        if (bestIdx >= 0) {
            collected[bestIdx].isLocal = true;
            localObj = collected[bestIdx].obj;
            localPos = collected[bestIdx].position;
            g_localPlayer = localObj;
        }
    }

    // Distances + projection (all in Unity pixel space here; Render converts).
    for (auto& pd : collected) {
        pd.distance = pd.position.Distance(localPos);
        pd.espColor = (pd.team == 2) ? Color::Blue() : Color::Red();

        pd.onScreen = false;
        if (g_mainCamera) {
            Vector3 h = WorldToScreenPoint(g_mainCamera, pd.headPosition);
            Vector3 f = WorldToScreenPoint(g_mainCamera, pd.position);
            if (h.z > 0.05f) {
                pd.headScreen = { h.x, h.y };
                pd.feetScreen = { f.x, f.y };
                pd.onScreen = true;
            }
        }
    }

    {
        std::lock_guard<std::recursive_mutex> lock(g_playersMutex);
        g_players.swap(collected);
    }

    if (!g_players.empty() && !m_loggedFirstMatch) {
        CHEAT_LOG("e: first scan — %zu objects via %s (local=%p)",
                  g_players.size(), il2cpp_class_get_name(m_playerClass), localObj);
        m_loggedFirstMatch = true;
    }
}

void ESP::Render(CGContextRef ctx, CGFloat width, CGFloat height) {
    if (!g_config.initialized || !g_config.espEnabled || !ctx) return;

    m_screenWidth = width;
    m_screenHeight = height;

    std::vector<PlayerData> snapshot;
    {
        std::lock_guard<std::recursive_mutex> lock(g_playersMutex);
        snapshot = g_players;
    }

    // WorldToScreenPoint is in Unity pixels. UIKit drawRect is in points.
    // The old build multiplied by UIScreen.scale instead, which pushed every
    // box off-screen on 2x/3x devices.
    auto* r = GetResolver();
    int uw = r ? r->UnityScreenWidth() : 0;
    int uh = r ? r->UnityScreenHeight() : 0;
    float pppX = (uw > 0 && width > 0) ? ((float)uw / (float)width) : 1.0f;
    float pppY = (uh > 0 && height > 0) ? ((float)uh / (float)height) : 1.0f;

    CGFloat thickness = 1.4f;

    for (auto& p : snapshot) {
        if (p.isLocal || !p.alive) continue;
        if (!p.onScreen) continue;

        float hx = p.headScreen.x / pppX;
        float hy = height - (p.headScreen.y / pppY);
        float fx = p.feetScreen.x / pppX;
        float fy = height - (p.feetScreen.y / pppY);

        if (!std::isfinite(hx) || !std::isfinite(hy) || !std::isfinite(fx) || !std::isfinite(fy)) continue;

        float boxH = fabsf(fy - hy);
        if (boxH < 6.0f) boxH = 6.0f;
        if (boxH > height) boxH = height;
        float boxW = boxH * 0.52f;
        float cx = (hx + fx) * 0.5f;
        float cy = (hy + fy) * 0.5f;

        if (cx < -boxW || cx > width + boxW) continue;

        Color col = g_config.espTeamColor ? p.espColor : Color::Yellow();

        if (g_config.espBoxes) DrawBox(ctx, {cx, cy}, boxW, boxH, col, thickness);

        if (g_config.espHealthBars)
            DrawHealthBar(ctx, {cx - boxW / 2 - 6, cy - boxH / 2}, boxH, p.health, p.maxHealth);

        if (g_config.espNames && p.name[0])
            DrawText(ctx, p.name, cx, hy - 16, col, 1.1f);

        if (g_config.espDistance) {
            char buf[32];
            snprintf(buf, sizeof(buf), "%dm", (int)p.distance);
            DrawText(ctx, buf, cx, fy + 4, Color::White(), 0.95f);
        }

        if (g_config.espSnaplines) DrawSnapline(ctx, {cx, fy}, col);
    }

    if (g_config.aimbotEnabled && g_config.aimbotShowFov && g_config.aimbotFov > 0) {
        float radius = height * 0.5f * (g_config.aimbotFov / 180.0f);
        DrawCircle(ctx, width / 2, height / 2, radius, Color::Yellow(), 1.0f);
    }
}

bool ESP::WorldToScreen(Vector3 world, Vector2& screen, float& distance) {
    if (!g_mainCamera) return false;
    Vector3 ws = WorldToScreenPoint(g_mainCamera, world);
    distance = ws.z;
    if (ws.z <= 0) return false;
    screen.x = ws.x;
    screen.y = m_screenHeight - ws.y;
    return true;
}

void ESP::DrawBox(CGContextRef ctx, Vector2 center, float w, float h, Color color, float thickness) {
    CGFloat x1 = center.x - w / 2, y1 = center.y - h / 2;
    CGFloat x2 = center.x + w / 2, y2 = center.y + h / 2;

    CGContextSetRGBStrokeColor(ctx, color.r, color.g, color.b, color.a);
    CGContextSetLineWidth(ctx, thickness);

    CGFloat cornerSize = w * 0.28f;
    if (cornerSize > 12) cornerSize = 12;

    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, x1, y1 + cornerSize);
    CGContextAddLineToPoint(ctx, x1, y1);
    CGContextAddLineToPoint(ctx, x1 + cornerSize, y1);

    CGContextMoveToPoint(ctx, x2 - cornerSize, y1);
    CGContextAddLineToPoint(ctx, x2, y1);
    CGContextAddLineToPoint(ctx, x2, y1 + cornerSize);

    CGContextMoveToPoint(ctx, x2, y2 - cornerSize);
    CGContextAddLineToPoint(ctx, x2, y2);
    CGContextAddLineToPoint(ctx, x2 - cornerSize, y2);

    CGContextMoveToPoint(ctx, x1 + cornerSize, y2);
    CGContextAddLineToPoint(ctx, x1, y2);
    CGContextAddLineToPoint(ctx, x1, y2 - cornerSize);
    CGContextStrokePath(ctx);

    if (color.a >= 0.2f) {
        CGContextSetRGBFillColor(ctx, color.r, color.g, color.b, 0.08f * color.a);
        CGContextFillRect(ctx, CGRectMake(x1, y1, w, h));
    }
}

void ESP::DrawHealthBar(CGContextRef ctx, Vector2 pos, float height, float health, float maxHealth) {
    float pct = maxHealth > 0 ? health / maxHealth : 0;
    if (pct < 0) pct = 0;
    if (pct > 1) pct = 1;

    CGContextSetRGBFillColor(ctx, 0, 0, 0, 0.55);
    CGContextFillRect(ctx, CGRectMake(pos.x, pos.y, 4, height));

    float barH = height * pct;
    float r, g;
    if (pct > 0.6f) { r = 0; g = 1; }
    else if (pct > 0.3f) { r = 1; g = 1; }
    else { r = 1; g = 0; }

    CGContextSetRGBFillColor(ctx, r, g, 0, 1);
    CGContextFillRect(ctx, CGRectMake(pos.x, pos.y + height - barH, 4, barH));

    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 0.7);
    CGContextSetLineWidth(ctx, 0.5);
    CGContextStrokeRect(ctx, CGRectMake(pos.x, pos.y, 4, height));
}

void ESP::DrawText(CGContextRef ctx, const char* text, float x, float y, Color color, float scale) {
    if (!text || strlen(text) == 0) return;
    NSString* str = [NSString stringWithUTF8String:text];
    if (!str) return;
    NSDictionary* attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:11 * scale],
        NSForegroundColorAttributeName: [UIColor colorWithRed:color.r green:color.g blue:color.b alpha:color.a],
        NSStrokeColorAttributeName: [UIColor blackColor],
        NSStrokeWidthAttributeName: @-2.0f
    };
    CGSize size = [str sizeWithAttributes:attrs];
    [str drawAtPoint:CGPointMake(x - size.width / 2, y) withAttributes:attrs];
}

void ESP::DrawLine(CGContextRef ctx, float x1, float y1, float x2, float y2, Color color, float thickness) {
    CGContextSetRGBStrokeColor(ctx, color.r, color.g, color.b, color.a);
    CGContextSetLineWidth(ctx, thickness);
    CGContextMoveToPoint(ctx, x1, y1);
    CGContextAddLineToPoint(ctx, x2, y2);
    CGContextStrokePath(ctx);
}

void ESP::DrawCircle(CGContextRef ctx, float cx, float cy, float radius, Color color, float thickness) {
    CGContextSetRGBStrokeColor(ctx, color.r, color.g, color.b, color.a);
    CGContextSetLineWidth(ctx, thickness);
    CGContextAddArc(ctx, cx, cy, radius, 0, 2 * M_PI, 0);
    CGContextStrokePath(ctx);
}

void ESP::DrawSnapline(CGContextRef ctx, Vector2 bottom, Color color) {
    CGContextSetRGBStrokeColor(ctx, color.r, color.g, color.b, 0.5f);
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextMoveToPoint(ctx, m_screenWidth / 2, m_screenHeight);
    CGContextAddLineToPoint(ctx, bottom.x, bottom.y);
    CGContextStrokePath(ctx);
}

ESP* GetESP() {
    return &s_esp;
}
