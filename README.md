# StandoffCheat

Runtime-resolved IL2CPP cheat for **Standoff 2 (iOS)** — ESP, aimbot, recoil control, overlay menu.
No hardcoded offsets: every class/field is resolved at runtime through the IL2CPP reflection API.

> This is a private research project. Build it, sideload it on your own device, and read the trace log — it is designed to tell you exactly which class names and fields the current game build uses.

## What's inside

| Path | Purpose |
| --- | --- |
| `src/main.mm` | Bootstrap, symbol binding, anti-cheat sweep, worker/init |
| `src/il2cpp_resolver.mm` | IL2CPP binding, **global class index**, class/field dumper |
| `src/w2s.mm` | World→screen + shared IL2CPP helpers (`get_transform`, `get_up`, …) |
| `src/esp.mm` | Player collection, boxes / health / names / distance / snaplines |
| `src/aimbot.mm` | Cone-based target pick, Quaternion.LookRotation + slerp |
| `src/recoil.mm` | Method-pointer neutralisation + field crawl on `RecoilControl` |
| `src/menu.mm` | Floating button + toggle/slider panel (+ "Dump classes" button) |
| `src/overlay.mm` | Touch-pass overlay + CADisplayLink update loop |
| `src/tracelog.mm` | `apptrace.log` writer |
| `build.sh` | Compiles `build/libgamedata.dylib` (arm64) on macOS |
| `inject.sh` | Classic dylib injection into the IPA |
| `shellswap.sh` | Replaces a real framework binary with the cheat (no new module) |

## Build & inject locally (macOS)

```bash
./build.sh                                   # → build/libgamedata.dylib
./inject.sh game.ipa game-cheat.ipa          # classic injection
./shellswap.sh game.ipa AppMetricaLog game-cheat-shell.ipa   # stealth variant
```

Requires Xcode + iOS SDK, and [insert_dylib](https://github.com/Tyilo/insert_dylib) for `inject.sh`.

## Build via GitHub Actions (no Mac needed)

1. Create a Release and attach the `.ipa` (decrypted), or host it at a direct HTTPS URL.
2. **Actions → Build StandoffCheat IPA → Run workflow**
   - `ipa`: `release` or a direct URL.
3. Download the artifact and sideload with Sideloadly / AltStore / TrollStore.

> Use the **shell** artifact if the game is banning on module-list checks. It swaps a framework the
> game already loads, so there is no extra `LC_LOAD_DYLIB` and no unknown image name.

## Debugging (do this first)

`inject.sh`/`shellswap.sh` enable `UIFileSharingEnabled`, so after running the game once:

- iOS **Files → On My iPhone → Standoff 2 → apptrace.log**

The log is written in phases:

```
t: IL2CPP API bound, ...
r: indexed N classes / M assemblies
r: game classes  PC=... PM=... ...
r: engine classes ...
d: === PlayerController ... (field + method dump)
ac: target WardenIos ...
ac: patch WardenIos::Check ... / ac: FAILED ...
e: first scan — N objects via PlayerController (local=...)
a: target ... angle ... dist ...
m: tick ...
```

What each failure looks like:

| Log line | Meaning |
| --- | --- |
| `r: FAILED — no player class found by name` | The class names changed. Press **Dump classes** in the menu and search the log for `Player`, `Aim`, `Recoil`. |
| `r: engine classes T=0x0 ...` | UnityFramework symbols bound but UnityEngine assembly not loaded yet — restart / wait longer. |
| `ac: no detector classes loaded yet` | Detectors are native (no managed `Warden`/`CheatDetector` class) or load later. |
| `ac: FAILED ... page not writable` | Metadata page is protected; the log will say so instead of silently doing nothing. |
| `e: first scan — 0 objects` | `FindObjectsOfType` found nothing — wrong player class, or you are in the menu/lobby. |
| `a: Quaternion.LookRotation(2) missing` | Stripped build — send the log and we pick a different rotation API. |

The dump is intentionally verbose. Attach `apptrace.log` when asking for a fix; class names and
field offsets in it are enough to wire the cheat to a new game build in one pass.

## Changes in this build

- **Anti-cheat sweep is actually called.** `NukeAntiCheat()` was defined and never invoked; the
  detector list was also namespace-hardcoded. It now scans every loaded image for
  `Warden*`, `*CheatDetector*`, `*AntiCheat*`, `*Anitcheat*` and patches detection methods on a
  retry loop (assemblies can load when a match starts).
- **Method-pointer patches are safe and verified.** `vm_protect` (with `VM_PROT_COPY` fallback) makes
  the metadata page writable, and the write is read back. The stub has the correct IL2CPP ABI.
- **Class lookup is a global index**, not a hand-written namespace list, so a namespace rename no
  longer kills resolution.
- **`Component.GetComponent(Type)` is invoked correctly.** The old code passed a raw `Il2CppClass*`
  where a `System.Type` object is required — every transform/bone lookup failed silently.
- **`il2cpp_array_get` was not a real export.** Object arrays are now read with
  `il2cpp_array_addr_with_size` (with a layout fallback).
- **DPI mismatch fixed.** `WorldToScreenPoint` is in Unity pixels, `drawRect` is in points. The old
  code multiplied by `UIScreen.scale` and drew every box off-screen on retina devices. Mapping is
  now derived from `UnityEngine.Screen.width/height` vs the view bounds.
- **Player scan moved to the main thread** (CADisplayLink), so `FindObjectsOfType` and camera reads
  happen in step with the engine.
- **Names, health, team, local-player flags** are read for real (UTF-16 → UTF-8 for names).
- **Aimbot** uses camera-relative cone angle + `Quaternion.LookRotation` + slerp instead of writing
  Euler angles that the game immediately overwrote.
- **Recoil** no longer does `GameObject.Find("Weapon")`; it patches `RecoilControl` methods and
  crawls live instances.
