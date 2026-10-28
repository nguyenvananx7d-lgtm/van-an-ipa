using System;
using System.Collections;
using System.IO;
using COW;
using COW.GamePlay;
using UnityEngine;

namespace ProjectEspPatch
{
    // The marker tells InjectFix to compile this helper type *into* the patch
    // instead of emitting extern references back to the ESPLogic assembly,
    // which does not exist inside the game process. With it, every helper
    // method body and every static field lives in the patch blob itself.
    [System.Runtime.CompilerServices.CompilerGenerated]
    public static partial class Logic
    {
        // ---- feature bits (low 20 bits of the packed scene state) ----
        private const int EspMaster = 1;
        private const int EspBox = 1 << 1;
        private const int EspName = 1 << 2;
        private const int EspDistance = 1 << 3;
        private const int EspHealth = 1 << 4;
        private const int EspSkeleton = 1 << 5;
        private const int EspTracer = 1 << 6;
        private const int EspLine = 1 << 7;
        private const int Esp360Arrows = 1 << 8;
        private const int EnemyCount = 1 << 9;
        private const int EspFov = 1 << 10;
        private const int SniperScope = 1 << 11;
        private const int EspHeadDot = 1 << 12;
        private const int EspShowDowned = 1 << 13;
        private const int EspBoxFill = 1 << 14;
        private const int AimMaster = 1 << 15;
        private const int AimVisibleOnly = 1 << 16;
        private const int AimIgnoreKnocked = 1 << 17;
        private const int AimTouchGate = 1 << 18;
        private const int EspVisibleOnly = 1 << 19;
        private const int EspMask = (1 << 20) - 1;

        // ---- extra scene-state flags (kept out of the feature mask) ----
        private const int StateInitialized = 1 << 20;
        private const int StateThreeFinger = 1 << 21;
        private const int StateDragging = 1 << 22;
        private const int TapShift = 23;
        private const int TapMask = 0x1F800000;
        private static int menuTapCount;
        private static float menuLastTapTime;

        // ---- menu tabs ----
        // The panel mirrors the YABAOCHEAT app UI: same three screens the
        // runtime can honour, same row set, same graphite/sea-glass theme.
        private const int TabVisual = 0;
        private const int TabAim = 1;
        private const int TabExtras = 2;

        private const int RowToggle = 0;
        private const int RowSlider = 1;
        private const int RowCycle = 2;
        private const int RowPalette = 3;

        private static readonly string[] VisualLabels = {
            "Enable markers", "Connector", "Player box", "Player name", "Distance",
            "Health bar", "Skeleton", "Top tracer", "360 arrows",
            "Box style", "Box size", "Box drop", "Palette", "Rainbow"
        };
        private static readonly string[] AimLabels = {
            "Assist", "Touch only", "Visible only", "Ignore knocked",
            "Bone", "Field of view", "Smoothing", "Hit chance",
            "Reaction", "Prediction", "Range"
        };
        private static readonly string[] ExtraLabels = {
            "Enemy count", "Head dot", "Downed marker", "LOS filter",
            "Box fill", "Fill opacity", "Health side", "Max distance",
            "Text scale", "FOV ring", "Sniper scope"
        };

        private static readonly string[] PaletteNames = {
            "EMERALD", "ICE", "VIOLET", "AMBER", "ROSE", "LIME", "AQUA", "PEARL"
        };
        private static readonly string[] BoneNames = {
            "MIXED", "HEAD", "NECK", "CHEST"
        };
        private static readonly Color[] Palette = {
            new Color(0.32f, 0.98f, 0.66f, 1f),
            new Color(0.38f, 0.82f, 1f, 1f),
            new Color(0.74f, 0.56f, 1f, 1f),
            new Color(1f, 0.74f, 0.30f, 1f),
            new Color(1f, 0.45f, 0.66f, 1f),
            new Color(0.74f, 1f, 0.42f, 1f),
            new Color(0.30f, 1f, 0.92f, 1f),
            new Color(0.94f, 0.97f, 1f, 1f)
        };

        // ---- runtime configuration ----
        private static bool configLoaded;
        private static string configJson;
        private static float bootstrapTime;
        // Live reload: the app rewrites localConfig.json while the match runs,
        // so the document is re-read on a slow timer and a content change is
        // applied immediately. `pendingMaskApply` carries the new feature bits
        // to Draw, which owns the scene-state vector the mask lives in.
        private static float configPollAt;
        private static bool pendingMaskApply;
        // Cached driver: Bootstrap runs on every Player.IsReallyInStealth call,
        // which can be several times per frame. GameObject.Find is a scene-wide
        // search, so it must only run until the driver exists.
        private static GameObject cachedDriver;
        private static int mask = EspMask;
        private static int boxStyle;
        private static int healthSide = 1;
        private static int paletteIndex;
        private static bool rainbow;
        private static int aimBone;
        private static float aimFov = 150f;
        private static float aimSmooth = 0.18f;
        private static float aimHitChance = 0.85f;
        private static float aimReaction = 0.18f;
        private static float aimLead = 0.10f;
        private static float aimHeight = 0.8f;
        private static float aimMaxDistance = 200f;
        private static float espMaxDistance = 250f;
        private static float espBoxScale = 1.15f;
        private static float espBoxOffset = 10f;
        private static float espTextScale = 1f;
        private static float espFillAlpha = 0.18f;

        // ---- ESP presentation tuning (read once from localConfig.json) ----
        private static bool espSmoothBox = true;
        private static bool espFadeFar = true;
        private static bool espOffscreenArrows = true;
        private static bool espHealthText = true;

        // ---- aim-assist feel (read once from localConfig.json) ----
        private static bool aimLatch = true;
        private static bool aimRamp = true;
        private static float aimDeadzone = 0.20f;
        // Hard lock: hold the target instead of the humanised release pattern.
        // It forces the anti-ban envelope open (see ApplyConfiguration), so it
        // is a switch the operator makes, never a default.
        private static bool aimLock;
        // Ring + centre dot at the crosshair while the assist is armed.
        private static bool aimCrosshair = true;

        // ---- behavioural anti-ban (read from the config document) ----
        // The assist is a measurable input anomaly: time-on-target, snap rate
        // and engagement length are the statistics a server can score without
        // ever looking at the client. These limits keep those statistics inside
        // a human envelope instead of holding a perfect lock for a whole fight.
        //
        // The per-frame token bucket that used to sit here is gone. Skipping
        // writes to stay under a duty fraction did not hide anything — an
        // instant correction followed by silence scores worse than smooth
        // tracking — and it handed the camera controller back the error every
        // frame it skipped.
        private static float antibanMaxEngage = 2.4f;
        private static float antibanCooldown = 0.9f;
        private static float aimEngageStart;
        private static Player aimCoolTarget;
        private static float aimCoolUntil;

        // ---- recovered keys from the previous build ----
        // Kept by exact name so an existing localConfig.json keeps working. The
        // semantics below are rebuilt from the key names: humanisation gate,
        // latch strength, target-switch bias, turn-rate cap, tracking gain,
        // engage overshoot, forced micro-breaks, and a post-kill quiet window.
        private static bool aimHumanize = true;
        private static float aimStickiness = 0.45f;
        private static float aimSwitchBias = 0.30f;
        private static float aimMaxTurn = 110f;
        private static float aimTrackGain = 0.70f;
        private static float aimOvershoot = 1.8f;
        private static float aimBreakMin = 0.14f;
        private static float aimBreakMax = 0.42f;
        private static float aimKillGuard = 0.90f;
        private static bool espGlow = true;
        private static bool espNameChip = true;
        private static bool espSkeletonJoints = true;
        private static bool espTargetHighlight = true;
        private static float aimBreakUntil;
        private static float aimNextBreakAt;
        private static float aimKillGuardUntil;

        // ---- overlay host ----
        // Deliberately not a word a cheat scanner searches for, and not derived
        // from the panel's own vocabulary. The name is only ever read back by
        // this patch, so it can be anything plausible.
        private const string OverlayHostName = "uievent_relay";

        // ---- per-frame target cache ----
        // Fixed arrays instead of a Dictionary: IFix translates newarr, while a
        // managed map would allocate on every frame and every entity. The
        // reference caches are typed object[] on purpose — the dump declares
        // System.Object[] but not COW.GamePlay.Player[], and the verifier
        // rejects an array type the target build does not contain.
        private const int EspCapacity = 64;
        private const int BoxSlots = 128;
        private static object[] espTargets;
        private static float[] espTargetDistance;
        private static bool[] espTargetDowned;
        private static object[] boxOwner;
        private static float[] boxX;
        private static float[] boxY;
        private static float[] boxWidth;
        private static float[] boxHeight;
        private static float[] boxStamp;

        // ---- sticky aim state ----
        private static Player aimTarget;
        private static float aimAcquireAt;
        private static float aimLockUntil;
        private static float aimRoll;
        private static Vector3 aimLastPoint;
        private static float aimLastPointTime;
        private static Vector3 aimSmoothPoint;
        private static float aimEngageTime;
        private static Vector3 aimVelocity;
        private static float aimPhase;
        private static bool aimEngaged;

        // ---- cross-file aim plumbing ----
        // `Logic.Aim.cs` solves the assist from Bootstrap, which has no access to
        // the scene-edit component that owns the menu flag, and cannot use the
        // obfuscated match accessors because that file is compiled verbatim rather
        // than through the placeholder pass. So the two values it needs are
        // mirrored here, where the bindings are legal.
        private static bool sceneMenuOpen;

        // ---- floating orb: the in-match entry point ----
        // The panel lives behind this reticle disc at the right edge. One tap
        // opens the panel, drag moves the orb. Drawn by the patch itself, so
        // it works on any iOS the IFix patch loads on — no task port, no
        // injected dylib, no certificate of its own.
        private static Vector2 orbPosition = new Vector2(-1f, -1f);
        private static bool orbDragging;
        private static bool orbMoved;
        private static float orbGrabDX;
        private static float orbGrabDY;
        private static float orbLastTouch = -100f;
        private const float OrbSize = 48f;

        private static IList CurrentPlayers()
        {
            {{MATCH_TYPE}} match = GameFacade.CurrentMatch();
            return match == null ? null : match.{{MATCH_PLAYERS_METHOD}}();
        }

        // ---- cached gui objects ----
        private static GUIStyle titleStyle;
        private static GUIStyle hintStyle;
        private static GUIStyle rowStyle;
        private static GUIStyle smallStyle;
        private static GUIStyle buttonStyle;
        private static GUIStyle closeStyle;

        // ---- YABAOCHEAT theme (UI/Theme.swift) ----
        // The in-game panel reuses the app palette so the injected overlay and
        // the SwiftUI shell read as one product: graphite surfaces, a single
        // sea-glass accent, and hairline edges. These are set in SetDefaults()
        // rather than with field initialisers to keep csc/IFix translation
        // simple.
        private static Color uiVoid;
        private static Color uiBase;
        private static Color uiSurface;
        private static Color uiSurfaceHi;
        private static Color uiWell;
        private static Color uiText;
        private static Color uiTextDim;
        private static Color uiTextFaint;
        private static Color uiAccent;
        private static Color uiAccentHi;
        private static Color uiGood;
        private static Color uiHairline;
        private static Color uiEdge;

        // ---- menu interaction ----
        private static float menuScroll;
        private static int menuScrollTab = -1;
        private static float menuScrollMax;
        private static int menuScrollGrab = -1;
        private static bool menuBodyGrab;
        private static bool menuBodyMoved;
        private static float menuGrabY;
        private static float menuGrabScroll;

        private static void SetDefaults()
        {
            mask = EspMaster | EspBox | EspName | EspDistance | EspHealth | EspSkeleton
                | EspTracer | EspLine | Esp360Arrows | EnemyCount | EspFov
                | EspHeadDot | EspShowDowned | EspBoxFill | AimMaster
                | AimVisibleOnly | AimIgnoreKnocked | AimTouchGate | EspVisibleOnly;
            boxStyle = 0;
            healthSide = 1;
            paletteIndex = 0;
            rainbow = false;
            aimBone = 0;
            aimFov = 150f;
            aimSmooth = 0.18f;
            aimHitChance = 0.85f;
            aimReaction = 0.18f;
            aimLead = 0.10f;
            aimHeight = 0.8f;
            aimMaxDistance = 200f;
            espMaxDistance = 250f;
            espBoxScale = 1.15f;
            espBoxOffset = 10f;
            espTextScale = 1f;
            espFillAlpha = 0.18f;

            espSmoothBox = true;
            espFadeFar = true;
            espOffscreenArrows = true;
            espHealthText = true;
            aimLatch = true;
            aimRamp = true;
            aimDeadzone = 0.20f;
            antibanMaxEngage = 2.4f;
            antibanCooldown = 0.9f;
            aimEngageStart = 0f;
            aimCoolTarget = null;
            aimCoolUntil = 0f;
            aimHumanize = true;
            aimStickiness = 0.45f;
            aimSwitchBias = 0.30f;
            aimMaxTurn = 110f;
            aimTrackGain = 0.70f;
            aimOvershoot = 1.8f;
            aimBreakMin = 0.14f;
            aimBreakMax = 0.42f;
            aimKillGuard = 0.90f;
            espGlow = true;
            espNameChip = true;
            espSkeletonJoints = true;
            espTargetHighlight = true;
            aimBreakUntil = 0f;
            aimNextBreakAt = 0f;
            aimKillGuardUntil = 0f;
            aimEngageTime = 0f;
            aimSmoothPoint = Vector3.zero;

            // Aim core (`Logic.Aim.cs`) state. Its fields carry initialisers, so
            // this only matters for a re-load inside one process: a stale
            // `holdDesired` would be replayed onto a camera that no longer has
            // anything to do with the previous target.
            aimStealth = 2;
            aimFrom = 0;
            holdGain = 1f;
            commitInterval = 0.05f;
            holdLastSolveAt = 0f;
            holdPrevAt = 0f;
            holdLastCommitAt = 0f;
            holdValid = false;
            holdValidAt = 0f;
            holdDesired = Quaternion.identity;
            sceneMenuOpen = false;

            // Allocated here, not at field initialisation: csc would emit
            // ldtoken/InitializeArray for the array literal, which IFix cannot
            // translate. newarr at runtime is fine.
            espTargets = new object[EspCapacity];
            espTargetDistance = new float[EspCapacity];
            espTargetDowned = new bool[EspCapacity];
            boxOwner = new object[BoxSlots];
            boxX = new float[BoxSlots];
            boxY = new float[BoxSlots];
            boxWidth = new float[BoxSlots];
            boxHeight = new float[BoxSlots];
            boxStamp = new float[BoxSlots];

            uiVoid = new Color(0.031f, 0.035f, 0.039f, 1f);
            uiBase = new Color(13f / 255f, 15f / 255f, 17f / 255f, 1f);
            uiSurface = new Color(21f / 255f, 24f / 255f, 27f / 255f, 1f);
            uiSurfaceHi = new Color(29f / 255f, 33f / 255f, 36f / 255f, 1f);
            uiWell = new Color(9f / 255f, 11f / 255f, 13f / 255f, 1f);
            uiText = new Color(240f / 255f, 241f / 255f, 236f / 255f, 1f);
            uiTextDim = new Color(173f / 255f, 178f / 255f, 176f / 255f, 1f);
            uiTextFaint = new Color(125f / 255f, 133f / 255f, 130f / 255f, 1f);
            uiAccent = new Color(112f / 255f, 185f / 255f, 170f / 255f, 1f);
            uiAccentHi = new Color(155f / 255f, 211f / 255f, 198f / 255f, 1f);
            uiGood = new Color(76f / 255f, 201f / 255f, 135f / 255f, 1f);
            uiHairline = new Color(1f, 1f, 1f, 0.085f);
            uiEdge = new Color(1f, 1f, 1f, 0.10f);

            menuScroll = 0f;
            menuScrollTab = -1;
            menuScrollGrab = -1;
            menuBodyGrab = false;
            menuBodyMoved = false;
        }

        private static int DigitOf(string text, int index)
        {
            string c = text.Substring(index, 1);
            if (c == "0") return 0;
            if (c == "1") return 1;
            if (c == "2") return 2;
            if (c == "3") return 3;
            if (c == "4") return 4;
            if (c == "5") return 5;
            if (c == "6") return 6;
            if (c == "7") return 7;
            if (c == "8") return 8;
            if (c == "9") return 9;
            return -1;
        }

        private static bool IsSpace(string c)
        {
            return c == " " || c == "\t" || c == "\r" || c == "\n";
        }

        private static int FindJsonValue(string json, string key)
        {
            if (json == null || json.Length == 0)
            {
                return -1;
            }
            int at = json.IndexOf("\"" + key + "\"");
            if (at < 0)
            {
                return -1;
            }
            int colon = json.IndexOf(':', at + key.Length + 2);
            if (colon < 0)
            {
                return -1;
            }
            int index = colon + 1;
            while (index < json.Length && IsSpace(json.Substring(index, 1)))
            {
                index++;
            }
            return index;
        }

        /// <summary>
        /// True when a key is present at all. The tier presets and the individual
        /// sliders both write the same fields, and `CfgNumber` cannot tell "the
        /// panel sent 110" from "the panel sent nothing, give me the default".
        /// Guarding the overrides on presence is what lets a tier set a value the
        /// document happens not to carry.
        /// </summary>
        private static bool CfgHas(string json, string key)
        {
            return FindJsonValue(json, key) >= 0;
        }

        private static bool CfgBool(string json, string key, bool fallback)
        {
            int index = FindJsonValue(json, key);
            if (index < 0 || index + 4 > json.Length)
            {
                return fallback;
            }
            string value = json.Substring(index, 4);
            if (value == "true")
            {
                return true;
            }
            if (value == "fals")
            {
                return false;
            }
            return fallback;
        }

        private static float CfgNumber(string json, string key, float fallback)
        {
            int index = FindJsonValue(json, key);
            if (index < 0 || index >= json.Length)
            {
                return fallback;
            }
            float sign = 1f;
            if (json.Substring(index, 1) == "-")
            {
                sign = -1f;
                index++;
                if (index >= json.Length)
                {
                    return fallback;
                }
            }
            float value = 0f;
            float fraction = 0.1f;
            bool any = false;
            bool afterPoint = false;
            while (index < json.Length)
            {
                string c = json.Substring(index, 1);
                int digit = DigitOf(json, index);
                if (digit >= 0)
                {
                    any = true;
                    if (afterPoint)
                    {
                        value += (float)digit * fraction;
                        fraction *= 0.1f;
                    }
                    else
                    {
                        value = value * 10f + (float)digit;
                    }
                }
                else if (c == "." && !afterPoint)
                {
                    afterPoint = true;
                }
                else
                {
                    break;
                }
                index++;
            }
            if (!any)
            {
                return fallback;
            }
            return value * sign;
        }

        private static string CfgString(string json, string key, string fallback)
        {
            int index = FindJsonValue(json, key);
            if (index < 0 || json.Substring(index, 1) != "\"")
            {
                return fallback;
            }
            index++;
            int end = json.IndexOf('"', index);
            if (end <= index)
            {
                return fallback;
            }
            return json.Substring(index, end - index);
        }

        private static void LoadConfiguration()
        {
            try
            {
                string path = Application.persistentDataPath + "/localConfig.json";
                if (File.Exists(path))
                {
                    configJson = File.ReadAllText(path);
                }
            }
            catch (Exception)
            {
                configJson = null;
            }
            configPollAt = Time.unscaledTime + 1.5f;
            ApplyConfiguration();
        }

        /// Re-read the document the app rewrites while a match is running.
        /// Throttled to one small read every 1.5 s and only a content change
        /// costs a parse, so the hot paths stay cheap. Without this the panel's
        /// switches would only land on the next launch: the config was read
        /// once at bootstrap.
        private static void PollConfiguration()
        {
            float now = Time.unscaledTime;
            if (now < configPollAt)
            {
                return;
            }
            configPollAt = now + 1.5f;

            string path = Application.persistentDataPath + "/localConfig.json";
            string text = null;
            try
            {
                if (File.Exists(path))
                {
                    text = File.ReadAllText(path);
                }
            }
            catch (Exception)
            {
                return;
            }
            if (text == null || text.Length == 0 || text == configJson)
            {
                return;
            }
            configJson = text;
            ApplyConfiguration();
            pendingMaskApply = true;
        }

        private static void ApplyConfiguration()
        {
            if (configJson == null || configJson.Length == 0)
            {
                return;
            }

            int loaded = 0;
            if (CfgBool(configJson, "EspMaster", true)) loaded |= EspMaster;
            if (CfgBool(configJson, "EspBox", true)) loaded |= EspBox;
            if (CfgBool(configJson, "EspName", true)) loaded |= EspName;
            if (CfgBool(configJson, "EspDistance", true)) loaded |= EspDistance;
            if (CfgBool(configJson, "EspHealth", true)) loaded |= EspHealth;
            if (CfgBool(configJson, "EspSkeleton", true)) loaded |= EspSkeleton;
            if (CfgBool(configJson, "EspTracer", true)) loaded |= EspTracer;
            if (CfgBool(configJson, "EspLine", true)) loaded |= EspLine;
            if (CfgBool(configJson, "Esp360Arrows", true)) loaded |= Esp360Arrows;
            if (CfgBool(configJson, "EnemyCount", true)) loaded |= EnemyCount;
            if (CfgBool(configJson, "EspFov", true)) loaded |= EspFov;
            if (CfgBool(configJson, "SniperScope", false)) loaded |= SniperScope;
            if (CfgBool(configJson, "EspHeadDot", true)) loaded |= EspHeadDot;
            if (CfgBool(configJson, "EspShowDowned", true)) loaded |= EspShowDowned;
            if (CfgBool(configJson, "EspBoxFill", true)) loaded |= EspBoxFill;
            if (CfgBool(configJson, "EspVisibleOnly", true)) loaded |= EspVisibleOnly;
            if (CfgBool(configJson, "AimSystemEnabled", true)) loaded |= AimMaster;
            if (CfgBool(configJson, "LegitAimbot", true)) loaded |= AimMaster;
            // The panel has two more masters: `AimEnabled` (its own aim toggle,
            // also armed by silent aim) and `SilentAim`. Neither was read here,
            // so a profile with silent aim on and the legacy master off loaded
            // with AimMaster cleared and the assist never ran.
            if (CfgBool(configJson, "AimEnabled", false)) loaded |= AimMaster;
            if (CfgBool(configJson, "SilentAim", false)) loaded |= AimMaster;
            if (CfgBool(configJson, "AimVisibleOnly", true)) loaded |= AimVisibleOnly;
            if (CfgBool(configJson, "IgnoreKnocked", true)) loaded |= AimIgnoreKnocked;
            if (CfgBool(configJson, "AimTouchGate", true)) loaded |= AimTouchGate;
            mask = loaded;

            string boxType = CfgString(configJson, "BoxType", "corner");
            boxStyle = boxType == "edge" ? 1 : 0;
            string healthType = CfgString(configJson, "HealthType", "right");
            healthSide = healthType == "left" ? 0 : 1;
            string paletteName = CfgString(configJson, "EspPalette", "emerald");
            paletteIndex = PaletteIndex(paletteName);
            rainbow = CfgBool(configJson, "Rainbow", false) || CfgBool(configJson, "AllRainbow", false);

            string bone = CfgString(configJson, "AimBone", "mixed");
            if (bone == "head") aimBone = 1;
            else if (bone == "neck") aimBone = 2;
            else if (bone == "chest") aimBone = 3;
            else aimBone = 0;

            aimFov = Mathf.Clamp(CfgNumber(configJson, "FovSize",
                CfgNumber(configJson, "AimFovRadius", 220f)), 40f, 320f);
            aimSmooth = Mathf.Clamp(CfgNumber(configJson, "AimSmooth", 0.18f), 0.02f, 1f);
            aimHitChance = Mathf.Clamp(CfgNumber(configJson, "HitChance", 85f) > 1f
                ? CfgNumber(configJson, "HitChance", 85f) / 100f
                : CfgNumber(configJson, "HitChance", 0.85f), 0.5f, 1f);
            aimReaction = Mathf.Clamp(CfgNumber(configJson, "AimReactionMs", 180f) / 1000f,
                0.06f, 0.4f);
            aimLead = Mathf.Clamp(CfgNumber(configJson, "AimLeadMs", 100f) / 1000f, 0f, 0.25f);
            aimHeight = Mathf.Clamp(CfgNumber(configJson, "AimHeight", 0.8f), 0.35f, 1.6f);
            aimMaxDistance = Mathf.Clamp(CfgNumber(configJson, "AimMaxDistance",
                CfgNumber(configJson, "AimDistance", 200f)), 20f, 400f);
            espMaxDistance = Mathf.Clamp(CfgNumber(configJson, "EspMaxDistance", 250f), 20f, 500f);
            espBoxScale = Mathf.Clamp(CfgNumber(configJson, "EspBoxScale", 1.15f), 0.5f, 2f);
            espBoxOffset = Mathf.Clamp(CfgNumber(configJson, "EspBoxOffset", 10f), -60f, 60f);
            espTextScale = Mathf.Clamp(CfgNumber(configJson, "EspTextScale", 1f), 0.5f, 1.6f);
            espFillAlpha = Mathf.Clamp(CfgNumber(configJson, "EspBoxFillAlpha", 0.18f), 0.05f, 0.9f);

            espSmoothBox = CfgBool(configJson, "EspSmoothBox", true);
            espFadeFar = CfgBool(configJson, "EspFadeFar", true);
            espOffscreenArrows = CfgBool(configJson, "EspOffscreenArrows", true);
            espHealthText = CfgBool(configJson, "EspHealthText", true);
            aimLatch = CfgBool(configJson, "AimLatch", true);
            aimRamp = CfgBool(configJson, "AimRamp", true);
            aimCrosshair = CfgBool(configJson, "AimCrosshair", true);

            // Tier first, then the individual sliders. `AimLock` is tier 0 under
            // a different name — the old branch that opened every limit at once
            // is gone, so raising strength no longer means dropping stealth off
            // a cliff. The envelope values the tier picks survive only where the
            // document does not carry an explicit slider for them.
            aimLock = CfgBool(configJson, "AimLock", false);
            aimStealth = (int)Mathf.Clamp(CfgNumber(configJson, "AimStealth", 2f), 0f, 3f);
            aimFrom = (int)Mathf.Clamp(CfgNumber(configJson, "AimFrom", 0f), 0f, 1f);
            if (aimLock)
            {
                aimStealth = 0;
            }
            ApplyStealthTier();

            if (CfgHas(configJson, "AimDeadzone"))
            {
                aimDeadzone = Mathf.Clamp(CfgNumber(configJson, "AimDeadzone", 0.20f), 0f, 2f);
            }
            if (CfgHas(configJson, "AimOvershootDeg"))
            {
                aimOvershoot = Mathf.Clamp(CfgNumber(configJson, "AimOvershootDeg", 1.8f),
                    0f, 8f);
            }
            if (CfgHas(configJson, "AimMaxTurn"))
            {
                aimMaxTurn = Mathf.Clamp(CfgNumber(configJson, "AimMaxTurn", 110f), 20f, 720f);
            }
            if (CfgHas(configJson, "AimHumanize"))
            {
                aimHumanize = CfgBool(configJson, "AimHumanize", true);
            }
            if (CfgHas(configJson, "AntibanMaxEngageMs") || CfgHas(configJson, "AimLockMs"))
            {
                antibanMaxEngage = Mathf.Clamp(CfgNumber(configJson, "AntibanMaxEngageMs",
                    CfgNumber(configJson, "AimLockMs", 2400f)) / 1000f, 0.3f, 8f);
            }
            if (CfgHas(configJson, "AntibanCooldownMs"))
            {
                antibanCooldown = Mathf.Clamp(CfgNumber(configJson, "AntibanCooldownMs", 900f)
                    / 1000f, 0f, 5f);
            }
            if (CfgHas(configJson, "AimHoldGain"))
            {
                holdGain = Mathf.Clamp(CfgNumber(configJson, "AimHoldGain", 1f), 0.3f, 2.5f);
            }
            if (CfgHas(configJson, "AimCommitMs"))
            {
                commitInterval = Mathf.Clamp(CfgNumber(configJson, "AimCommitMs", 50f) / 1000f,
                    0.01f, 0.5f);
            }

            aimStickiness = Mathf.Clamp(CfgNumber(configJson, "AimStickiness", 0.45f), 0f, 1f);
            aimSwitchBias = Mathf.Clamp(CfgNumber(configJson, "AimSwitchBias", 0.30f), 0f, 1f);
            aimTrackGain = Mathf.Clamp(CfgNumber(configJson, "AimTrackGain", 0.70f), 0f, 2f);
            aimBreakMin = Mathf.Clamp(CfgNumber(configJson, "AimBreakMinMs", 140f) / 1000f,
                0.02f, 1f);
            aimBreakMax = Mathf.Clamp(CfgNumber(configJson, "AimBreakMaxMs", 420f) / 1000f,
                aimBreakMin, 2f);
            aimKillGuard = Mathf.Clamp(CfgNumber(configJson, "AimKillGuardMs", 900f) / 1000f,
                0f, 4f);
            espGlow = CfgBool(configJson, "EspGlow", true);
            espNameChip = CfgBool(configJson, "EspNameChip", true);
            espSkeletonJoints = CfgBool(configJson, "EspSkeletonJoints", true);
            espTargetHighlight = CfgBool(configJson, "EspTargetHighlight", true);
        }

        private static int PaletteIndex(string name)
        {
            if (name == "ice") return 1;
            if (name == "violet") return 2;
            if (name == "amber") return 3;
            if (name == "rose") return 4;
            if (name == "lime") return 5;
            if (name == "aqua") return 6;
            if (name == "pearl" || name == "white") return 7;
            return 0;
        }

        private static Color RainbowColor(float offset)
        {
            float t = Mathf.Repeat(Time.unscaledTime * 0.10f + offset, 1f);
            float scaled = t * 6f;
            int sector = (int)scaled;
            float f = scaled - (float)sector;
            float r = 0f;
            float g = 0f;
            float b = 0f;
            if (sector == 0) { r = 1f; g = f; }
            else if (sector == 1) { r = 1f - f; g = 1f; }
            else if (sector == 2) { g = 1f; b = f; }
            else if (sector == 3) { g = 1f - f; b = 1f; }
            else if (sector == 4) { r = f; b = 1f; }
            else { r = 1f; b = 1f - f; }
            return new Color(0.35f + r * 0.65f, 0.35f + g * 0.65f, 0.35f + b * 0.65f, 1f);
        }

        private static Color BaseColor()
        {
            if (rainbow)
            {
                return RainbowColor(0f);
            }
            int index = paletteIndex;
            if (index < 0) index = 0;
            if (index >= Palette.Length) index = Palette.Length - 1;
            return Palette[index];
        }

        private static Color HealthColor(float ratio)
        {
            if (ratio > 0.5f)
            {
                return Color.Lerp(new Color(0.98f, 0.78f, 0.26f, 1f),
                    new Color(0.34f, 0.95f, 0.55f, 1f), (ratio - 0.5f) * 2f);
            }
            return Color.Lerp(new Color(0.96f, 0.30f, 0.32f, 1f),
                new Color(0.98f, 0.78f, 0.26f, 1f), ratio * 2f);
        }

        private static Color WithAlpha(Color color, float alpha)
        {
            return new Color(color.r, color.g, color.b, alpha);
        }

        // The game can be built with the new Input System, where every legacy
        // `UnityEngine.Input` getter throws. Both the touch gate in AimFrame and
        // the three-finger gesture used to read `Input.touchCount` directly, so
        // one exception aborted the whole OnGUI/aim path. -1 means "unknown":
        // the aim gate treats it as allowed, the gesture as no fingers down.
        private static int SafeTouchCount()
        {
            try
            {
                return Input.touchCount;
            }
            catch (Exception)
            {
                return -1;
            }
        }

        private static float Noise01(float seed)
        {
            float value = Mathf.Sin(seed * 12.9898f) * 43758.5453f;
            return value - Mathf.Floor(value);
        }

        private static bool TryGetAimPoint(Player player, out Vector3 point)
        {
            point = Vector3.zero;
            if (player == null)
            {
                return false;
            }
            Transform head = null;
            Transform neck = null;
            try
            {
                head = player.GetHeadTF();
                neck = player.NeckBone;
            }
            catch (Exception)
            {
                return false;
            }

            if (aimBone == 1)
            {
                if (head == null) return false;
                point = head.position;
                return true;
            }
            if (aimBone == 2)
            {
                if (neck == null) return false;
                point = neck.position;
                return true;
            }
            if (aimBone == 3)
            {
                try
                {
                    point = player.GetChestPos(true);
                    return true;
                }
                catch (Exception)
                {
                    return false;
                }
            }

            // Mixed: mostly head, blended down toward the chest so the lock
            // never looks like a hard snap onto one bone.
            bool hasHead = head != null;
            bool hasChest = false;
            Vector3 chest = Vector3.zero;
            try
            {
                chest = player.GetChestPos(true);
                hasChest = true;
            }
            catch (Exception)
            {
                hasChest = false;
            }
            if (hasHead && hasChest)
            {
                point = Vector3.Lerp(chest, head.position, Mathf.Clamp01(aimHeight));
                return true;
            }
            if (hasHead)
            {
                point = head.position;
                return true;
            }
            if (hasChest)
            {
                point = chest;
                return true;
            }
            return false;
        }

        private static bool IsAimCandidate(Player player, Player local, Camera camera, bool ignoreFov,
            out Vector3 point)
        {
            point = Vector3.zero;
            if (player == null || player == local)
            {
                return false;
            }
            GameObject playerObject = player.gameObject;
            if (playerObject == null || !playerObject.activeInHierarchy)
            {
                return false;
            }
            if (player.IsLocalPlayer() || player.IsLocalTeammate(false))
            {
                return false;
            }
            bool downed = player.IsDieing;
            if (downed && (mask & AimIgnoreKnocked) != 0)
            {
                return false;
            }
            if (!downed)
            {
                if (player.CurHP <= 0)
                {
                    return false;
                }
                if ((mask & AimVisibleOnly) != 0 && !player.IsVisible())
                {
                    return false;
                }
            }
            Transform root = player.RootTransform;
            if (root == null)
            {
                return false;
            }
            if (Vector3.Distance(root.position, local.RootTransform.position) > aimMaxDistance)
            {
                return false;
            }
            if (!TryGetAimPoint(player, out point))
            {
                return false;
            }
            Vector3 projected = camera.WorldToScreenPoint(point);
            if (projected.z <= 0.01f)
            {
                return false;
            }
            if (float.IsNaN(projected.x) || float.IsNaN(projected.y)
                || float.IsInfinity(projected.x) || float.IsInfinity(projected.y))
            {
                return false;
            }
            if (ignoreFov)
            {
                return true;
            }
            Vector2 screenPoint = new Vector2(projected.x, (float)Screen.height - projected.y);
            Vector2 center = new Vector2((float)Screen.width * 0.5f, (float)Screen.height * 0.5f);
            float screenDistance = Vector2.Distance(screenPoint, center);
            return screenDistance <= aimFov;
        }

        private static Player FindStickyTarget(Camera camera, Player local, IList players, out Vector3 point)
        {
            point = Vector3.zero;
            if (players == null || camera == null || local == null)
            {
                return null;
            }

            // Hysteresis: keep the current target while it stays reachable,
            // even if a closer enemy drifts into the field of view.
            if (aimTarget != null && aimTarget != aimCoolTarget
                && Time.unscaledTime < aimLockUntil)
            {
                Vector3 currentPoint;
                if (IsAimCandidate(aimTarget, local, camera, aimLatch, out currentPoint))
                {
                    if (!aimLatch)
                    {
                        point = currentPoint;
                        return aimTarget;
                    }
                    // Latch: the target may drift out of the acquisition FOV
                    // for a moment. Keeping it inside a wider cone is what
                    // stops the assist flicking between two enemies who are
                    // both near the crosshair.
                    Vector3 projected = camera.WorldToScreenPoint(currentPoint);
                    if (projected.z > 0.01f)
                    {
                        Vector2 screenPoint = new Vector2(projected.x,
                            (float)Screen.height - projected.y);
                        Vector2 center = new Vector2((float)Screen.width * 0.5f,
                            (float)Screen.height * 0.5f);
                        // Stickiness widens the retention cone: a stickier lock
                        // tolerates the target leaving the acquisition FOV for
                        // longer before the assist looks for someone else.
                        float cone = aimFov * (1f + aimStickiness * 0.6f);
                        if (Vector2.Distance(screenPoint, center) <= cone)
                        {
                            point = currentPoint;
                            return aimTarget;
                        }
                    }
                }
            }

            Player bestTarget = null;
            Vector3 bestPoint = Vector3.zero;
            float bestScore = float.MaxValue;
            Vector2 crosshair = new Vector2((float)Screen.width * 0.5f, (float)Screen.height * 0.5f);
            for (int index = 0; index < players.Count; index++)
            {
                Player player = players[index] as Player;
                if (player == aimCoolTarget && Time.unscaledTime < aimCoolUntil)
                {
                    // Just released: leave it alone for a beat so a re-lock
                    // reads as the player re-aiming, not as a machine.
                    continue;
                }
                Vector3 candidatePoint;
                if (!IsAimCandidate(player, local, camera, false, out candidatePoint))
                {
                    continue;
                }
                Vector3 projected = camera.WorldToScreenPoint(candidatePoint);
                Vector2 screenPoint = new Vector2(projected.x, (float)Screen.height - projected.y);
                float screenDistance = Vector2.Distance(screenPoint, crosshair);
                float distanceToLocal = Vector3.Distance(
                    player.RootTransform.position, local.RootTransform.position);
                // The tie-breaker is seeded by the entity id, not by the clock:
                // two enemies at the same range keep a stable rank instead of
                // swapping the lock every frame.
                float jitter = Noise01((float)(player.GetInstanceID() & 1023) * 0.37f) * 4f;
                float score = screenDistance + distanceToLocal * 0.10f + jitter;
                // Switch bias: the incumbent gets a score bonus, so a marginal
                // newcomer does not steal a lock that is already working. This
                // is what a human does, and it is also what stops the assist
                // from looking omniscient about which enemy is "best".
                if (player == aimTarget)
                {
                    score -= aimSwitchBias * 60f;
                }
                if (score < bestScore)
                {
                    bestScore = score;
                    bestTarget = player;
                    bestPoint = candidatePoint;
                }
            }
            point = bestPoint;
            return bestTarget;
        }

        private static void ResetAim()
        {
            aimTarget = null;
            aimEngaged = false;
            aimVelocity = Vector3.zero;
            aimSmoothPoint = Vector3.zero;
            aimLastPointTime = 0f;
            aimNextBreakAt = 0f;
        }

        private static void PrepareStyles(float scale)
        {
            if (GUI.skin == null)
            {
                return;
            }
            if (titleStyle == null)
            {
                titleStyle = new GUIStyle();
                titleStyle.alignment = TextAnchor.MiddleLeft;
                hintStyle = new GUIStyle();
                hintStyle.alignment = TextAnchor.MiddleLeft;
                rowStyle = new GUIStyle();
                rowStyle.alignment = TextAnchor.MiddleLeft;
                smallStyle = new GUIStyle();
                smallStyle.alignment = TextAnchor.MiddleCenter;
                buttonStyle = new GUIStyle();
                buttonStyle.alignment = TextAnchor.MiddleCenter;
                closeStyle = new GUIStyle();
                closeStyle.alignment = TextAnchor.MiddleCenter;
            }
            titleStyle.fontSize = Mathf.RoundToInt(17f * scale);
            titleStyle.normal.textColor = new Color(0.95f, 0.97f, 0.96f, 1f);
            hintStyle.fontSize = Mathf.RoundToInt(10f * scale);
            hintStyle.normal.textColor = new Color(0.52f, 0.60f, 0.57f, 1f);
            rowStyle.fontSize = Mathf.RoundToInt(13f * scale);
            smallStyle.fontSize = Mathf.RoundToInt(11f * scale);
            buttonStyle.fontSize = Mathf.RoundToInt(11f * scale);
            closeStyle.fontSize = Mathf.RoundToInt(15f * scale);
            closeStyle.normal.textColor = new Color(0.78f, 0.85f, 0.82f, 1f);
        }

        private static void Fill(Rect rect, Color color, Texture2D pixel)
        {
            GUI.color = color;
            GUI.DrawTexture(rect, pixel);
        }

        private static void RoundedFill(Rect rect, Color color, Texture2D pixel, float radius)
        {
            float r = Mathf.Min(radius, Mathf.Min(rect.width, rect.height) * 0.5f);
            if (r <= 0.5f)
            {
                Fill(rect, color, pixel);
                return;
            }
            Fill(new Rect(rect.x + r, rect.y, rect.width - r * 2f, rect.height), color, pixel);
            Fill(new Rect(rect.x, rect.y + r, rect.width, rect.height - r * 2f), color, pixel);
            int steps = 5;
            float rowHeight = r / (float)steps;
            for (int i = 0; i < steps; i++)
            {
                float t = ((float)i + 0.5f) / (float)steps;
                float inset = r * (1f - Mathf.Sqrt(1f - t * t));
                float topY = rect.y + (float)i * rowHeight;
                float bottomY = rect.yMax - (float)(i + 1) * rowHeight;
                Fill(new Rect(rect.x + inset, topY, rect.width - inset * 2f, rowHeight + 0.6f),
                    color, pixel);
                Fill(new Rect(rect.x + inset, bottomY, rect.width - inset * 2f, rowHeight + 0.6f),
                    color, pixel);
            }
        }


        private static void Stroke(Rect rect, float thickness, Color color, Texture2D pixel)
        {
            Fill(new Rect(rect.x, rect.y, rect.width, thickness), color, pixel);
            Fill(new Rect(rect.x, rect.yMax - thickness, rect.width, thickness), color, pixel);
            Fill(new Rect(rect.x, rect.y, thickness, rect.height), color, pixel);
            Fill(new Rect(rect.xMax - thickness, rect.y, thickness, rect.height), color, pixel);
        }

        private static void OutlinedLabel(Rect rect, string text, GUIStyle style,
            Color color, float offset)
        {
            style.normal.textColor = new Color(0f, 0f, 0f, 0.86f);
            GUI.Label(new Rect(rect.x - offset, rect.y, rect.width, rect.height), text, style);
            GUI.Label(new Rect(rect.x + offset, rect.y, rect.width, rect.height), text, style);
            GUI.Label(new Rect(rect.x, rect.y - offset, rect.width, rect.height), text, style);
            GUI.Label(new Rect(rect.x, rect.y + offset, rect.width, rect.height), text, style);
            style.normal.textColor = color;
            GUI.Label(rect, text, style);
            style.normal.textColor = color;
        }

        private static void ScreenVertex(Vector2 point, int width, int height)
        {
            GL.Vertex3(point.x / (float)width, 1f - point.y / (float)height, 0f);
        }

        private static void DrawCircle(Vector2 center, float radius, int segments,
            Color color, int width, int height)
        {
            GL.PushMatrix();
            GL.LoadOrtho();
            GL.Begin(1);
            GL.Color(color);
            for (int i = 0; i < segments; i++)
            {
                float a0 = (float)i / (float)segments * 6.2831853f;
                float a1 = (float)(i + 1) / (float)segments * 6.2831853f;
                ScreenVertex(new Vector2(center.x + Mathf.Cos(a0) * radius,
                    center.y + Mathf.Sin(a0) * radius), width, height);
                ScreenVertex(new Vector2(center.x + Mathf.Cos(a1) * radius,
                    center.y + Mathf.Sin(a1) * radius), width, height);
            }
            GL.End();
            GL.PopMatrix();
        }

        private static void DrawGlowLine(Vector2 start, Vector2 end, Color color, float spread,
            int width, int height)
        {
            GL.PushMatrix();
            GL.LoadOrtho();
            GL.Begin(1);
            GL.Color(WithAlpha(color, 0.22f));
            ScreenVertex(new Vector2(start.x, start.y - spread), width, height);
            ScreenVertex(new Vector2(end.x, end.y - spread), width, height);
            GL.Color(WithAlpha(color, 0.9f));
            ScreenVertex(start, width, height);
            ScreenVertex(end, width, height);
            GL.End();
            GL.PopMatrix();
        }

        private static void DrawArrow(Vector2 center, Vector2 target, float radius,
            Color color, int width, int height)
        {
            Vector2 delta = new Vector2(target.x - center.x, target.y - center.y);
            float length = delta.magnitude;
            if (length < 1f)
            {
                return;
            }
            Vector2 direction = delta / length;
            Vector2 normal = new Vector2(-direction.y, direction.x);
            Vector2 tip = center + direction * radius;
            Vector2 basePoint = center + direction * (radius - 13f);
            Vector2 left = basePoint + normal * 7f;
            Vector2 right = basePoint - normal * 7f;

            GL.PushMatrix();
            GL.LoadOrtho();
            GL.Begin(4);
            GL.Color(color);
            ScreenVertex(tip, width, height);
            ScreenVertex(left, width, height);
            ScreenVertex(right, width, height);
            GL.End();
            GL.Begin(1);
            GL.Color(WithAlpha(color, 0.30f));
            ScreenVertex(center + direction * (radius - 13f), width, height);
            ScreenVertex(center + direction * (radius - 30f), width, height);
            GL.End();
            GL.PopMatrix();
        }

        private static bool TryScreen(Camera camera, Vector3 world, out Vector2 point)
        {
            point = Vector2.zero;
            if (camera == null)
            {
                return false;
            }
            Vector3 projected = camera.WorldToScreenPoint(world);
            if (projected.z <= 0.01f)
            {
                return false;
            }
            if (float.IsNaN(projected.x) || float.IsNaN(projected.y)
                || float.IsInfinity(projected.x) || float.IsInfinity(projected.y))
            {
                return false;
            }
            point = new Vector2(projected.x, (float)Screen.height - projected.y);
            return true;
        }

        private static bool TryBoneScreen(Camera camera, Transform bone, out Vector2 point)
        {
            point = Vector2.zero;
            if (bone == null)
            {
                return false;
            }
            return TryScreen(camera, bone.position, out point);
        }

        private static void AddScreenLine(Vector2 start, Vector2 end, int width, int height)
        {
            ScreenVertex(start, width, height);
            ScreenVertex(end, width, height);
        }

        private static void DrawSkeleton(Player player, Camera camera, Rect bounds, Color color,
            Texture2D pixel, int screenWidth, int screenHeight)
        {
            Vector2 head;
            Vector2 neck;
            Vector2 chest;
            Vector2 root;
            bool hasHead = TryBoneScreen(camera, player.GetHeadTF(), out head);
            bool hasNeck = TryBoneScreen(camera, player.NeckBone, out neck);
            bool hasChest = TryScreen(camera, player.GetChestPos(true), out chest);
            bool hasRoot = TryBoneScreen(camera, player.RootTransform, out root);

            Vector2 hip;
            if (hasChest && hasRoot)
            {
                hip = new Vector2((chest.x + root.x) * 0.5f, (chest.y + root.y) * 0.5f);
            }
            else
            {
                hip = new Vector2(bounds.center.x, bounds.y + bounds.height * 0.58f);
            }

            Vector2 torso = hasChest
                ? chest : new Vector2(bounds.center.x, bounds.y + bounds.height * 0.34f);
            float armSpan = Mathf.Max(3f, bounds.width * 0.30f);
            Vector2 leftShoulder = new Vector2(torso.x - armSpan, torso.y + bounds.height * 0.02f);
            Vector2 rightShoulder = new Vector2(torso.x + armSpan, torso.y + bounds.height * 0.02f);
            Vector2 leftElbow = new Vector2(leftShoulder.x - armSpan * 0.45f,
                leftShoulder.y + bounds.height * 0.16f);
            Vector2 rightElbow = new Vector2(rightShoulder.x + armSpan * 0.45f,
                rightShoulder.y + bounds.height * 0.16f);
            Vector2 leftHand = new Vector2(leftElbow.x + armSpan * 0.10f,
                leftElbow.y + bounds.height * 0.14f);
            Vector2 rightHand = new Vector2(rightElbow.x - armSpan * 0.10f,
                rightElbow.y + bounds.height * 0.14f);
            Vector2 leftFoot = new Vector2(bounds.x + bounds.width * 0.30f, bounds.yMax);
            Vector2 rightFoot = new Vector2(bounds.x + bounds.width * 0.70f, bounds.yMax);

            GL.PushMatrix();
            GL.LoadOrtho();
            GL.Begin(1);
            GL.Color(WithAlpha(color, 0.92f));
            if (hasHead)
            {
                Vector2 neckPoint = hasNeck ? neck : torso;
                AddScreenLine(head, neckPoint, screenWidth, screenHeight);
            }
            if (hasNeck)
            {
                AddScreenLine(neck, torso, screenWidth, screenHeight);
            }
            AddScreenLine(torso, leftShoulder, screenWidth, screenHeight);
            AddScreenLine(torso, rightShoulder, screenWidth, screenHeight);
            AddScreenLine(leftShoulder, leftElbow, screenWidth, screenHeight);
            AddScreenLine(rightShoulder, rightElbow, screenWidth, screenHeight);
            AddScreenLine(leftElbow, leftHand, screenWidth, screenHeight);
            AddScreenLine(rightElbow, rightHand, screenWidth, screenHeight);
            AddScreenLine(torso, hip, screenWidth, screenHeight);
            AddScreenLine(hip, leftFoot, screenWidth, screenHeight);
            AddScreenLine(hip, rightFoot, screenWidth, screenHeight);
            GL.End();
            GL.PopMatrix();

            float joint = Mathf.Max(1.5f, 2.6f);
            if (espSkeletonJoints)
            {
                if (hasHead)
                {
                    Fill(new Rect(head.x - joint, head.y - joint, joint * 2f, joint * 2f),
                        color, pixel);
                }
                Fill(new Rect(torso.x - joint, torso.y - joint, joint * 2f, joint * 2f),
                    color, pixel);
                Fill(new Rect(hip.x - joint, hip.y - joint, joint * 2f, joint * 2f), color, pixel);
                Fill(new Rect(leftHand.x - joint * 0.7f, leftHand.y - joint * 0.7f,
                    joint * 1.4f, joint * 1.4f), color, pixel);
                Fill(new Rect(rightHand.x - joint * 0.7f, rightHand.y - joint * 0.7f,
                    joint * 1.4f, joint * 1.4f), color, pixel);
            }
        }

        private static void ShadowLabel(Rect rect, string text, GUIStyle style, Color color,
            float scale)
        {
            // Two passes instead of OutlinedLabel's five: at 20+ enemies the
            // extra labels are the difference between 60 and 40 fps.
            style.fontSize = Mathf.RoundToInt(10f * scale);
            style.alignment = TextAnchor.MiddleCenter;
            style.normal.textColor = new Color(0f, 0f, 0f, 0.90f);
            GUI.color = Color.white;
            GUI.Label(new Rect(rect.x + 1f, rect.y + 1f, rect.width, rect.height), text, style);
            style.normal.textColor = color;
            GUI.Label(rect, text, style);
        }

        private static void DrawPlayerEsp(Player player, Camera camera, Player localPlayer,
            Texture2D pixel, int screenWidth, int screenHeight, int currentMask, float distance)
        {
            Transform root = player.RootTransform;
            Transform head = player.GetHeadTF();
            if (root == null || head == null)
            {
                return;
            }

            bool downed = player.IsDieing;
            int currentHealth = player.CurHP;
            int maximumHealth = player.MaxHP;

            Vector2 feet;
            Vector2 headPoint;
            bool feetVisible = TryScreen(camera, root.position, out feet);
            bool headVisible = TryScreen(camera, head.position, out headPoint);
            Vector2 screenCenter = new Vector2((float)screenWidth * 0.5f,
                (float)screenHeight * 0.5f);

            if (!feetVisible || !headVisible)
            {
                // Behind the camera or outside the frustum: the 360 ring still
                // gets a bearing, so a target behind you is never invisible.
                if ((currentMask & Esp360Arrows) != 0 && espOffscreenArrows)
                {
                    Vector3 raw = camera.WorldToScreenPoint(root.position);
                    Vector2 bearing = new Vector2(raw.x, (float)screenHeight - raw.y)
                        - screenCenter;
                    if (raw.z <= 0.01f)
                    {
                        bearing = new Vector2(-bearing.x, -bearing.y);
                    }
                    float offscreenRadius = Mathf.Min((float)screenWidth,
                        (float)screenHeight) * 0.40f;
                    DrawArrow(screenCenter, screenCenter + bearing, offscreenRadius,
                        WithAlpha(BaseColor(), 0.40f), screenWidth, screenHeight);
                }
                return;
            }

            float rawHeight = Mathf.Abs(headPoint.y - feet.y);
            if (rawHeight < 1f)
            {
                return;
            }
            float height = Mathf.Max(6f, rawHeight * espBoxScale);
            float width = height * 0.52f;
            float centerX = headPoint.x + (feet.x - headPoint.x) * 0.10f;
            float left = centerX - width * 0.5f;
            float top = headPoint.y - (height - rawHeight) * 0.55f - espBoxOffset;

            // Per-entity smoothing: at range the projection alone jitters the
            // box by a pixel per frame, which reads as noise. The slot is the
            // instance id, so an enemy keeps the same history all match.
            if (espSmoothBox)
            {
                int slot = (int)(player.GetInstanceID() & (BoxSlots - 1));
                float now = Time.unscaledTime;
                if (boxOwner[slot] == player && now - boxStamp[slot] < 0.5f)
                {
                    float k = Mathf.Clamp01(Time.unscaledDeltaTime * 24f);
                    left = Mathf.Lerp(boxX[slot], left, k);
                    top = Mathf.Lerp(boxY[slot], top, k);
                    width = Mathf.Lerp(boxWidth[slot], width, k);
                    height = Mathf.Lerp(boxHeight[slot], height, k);
                }
                boxOwner[slot] = player;
                boxX[slot] = left;
                boxY[slot] = top;
                boxWidth[slot] = width;
                boxHeight[slot] = height;
                boxStamp[slot] = now;
            }

            Rect bounds = new Rect(left, top, width, height);
            Vector2 boxCenter = new Vector2(bounds.center.x, bounds.center.y);

            if (bounds.xMax < 0f || bounds.x > (float)screenWidth
                || bounds.yMax < 0f || bounds.y > (float)screenHeight)
            {
                if ((currentMask & Esp360Arrows) != 0 && espOffscreenArrows)
                {
                    float edgeRadius = Mathf.Min((float)screenWidth,
                        (float)screenHeight) * 0.40f;
                    DrawArrow(screenCenter, boxCenter, edgeRadius,
                        WithAlpha(BaseColor(), 0.40f), screenWidth, screenHeight);
                }
                return;
            }

            Color accent = BaseColor();
            if (downed)
            {
                // Downed is state, not danger: a muted slate reads as "out of
                // the fight" without competing with the health track.
                accent = new Color(0.62f, 0.66f, 0.72f, 1f);
            }
            else if (rainbow)
            {
                accent = RainbowColor(distance * 0.006f);
            }

            // Distance falloff: a box at 240 m should whisper, not shout. The
            // floor keeps the far end of the list readable instead of empty.
            float fade = 1f;
            if (espFadeFar && espMaxDistance > 1f)
            {
                fade = Mathf.Clamp(1f - distance / espMaxDistance * 0.62f, 0.38f, 1f);
            }

            // One pixel unit that follows the screen, so the same preset looks
            // the same on a phone and on a tablet.
            float ui = Mathf.Clamp((float)screenHeight / 900f, 0.8f, 1.6f);

            if ((currentMask & EspBoxFill) != 0)
            {
                // A flat tint, not a gradient: at these box sizes a gradient is
                // just a coloured blob, and the brackets should carry the shape.
                Fill(bounds, WithAlpha(accent, espFillAlpha * 0.34f * fade), pixel);
            }

            if ((currentMask & EspBox) != 0)
            {
                float thickness = Mathf.Max(1.1f, 1.45f * ui);
                Color line = WithAlpha(accent, 0.94f * fade);
                if (boxStyle == 1)
                {
                    Stroke(bounds, thickness, line, pixel);
                }
                else
                {
                    float corner = Mathf.Clamp(Mathf.Min(width, height) * 0.24f,
                        7f * ui, 20f * ui);
                    Fill(new Rect(bounds.xMin, bounds.yMin, corner, thickness), line, pixel);
                    Fill(new Rect(bounds.xMin, bounds.yMin, thickness, corner), line, pixel);
                    Fill(new Rect(bounds.xMax - corner, bounds.yMin, corner, thickness), line, pixel);
                    Fill(new Rect(bounds.xMax - thickness, bounds.yMin, thickness, corner), line, pixel);
                    Fill(new Rect(bounds.xMin, bounds.yMax - thickness, corner, thickness), line, pixel);
                    Fill(new Rect(bounds.xMin, bounds.yMax - corner, thickness, corner), line, pixel);
                    Fill(new Rect(bounds.xMax - corner, bounds.yMax - thickness, corner, thickness), line, pixel);
                    Fill(new Rect(bounds.xMax - thickness, bounds.yMax - corner, thickness, corner), line, pixel);
                }
                // `EspGlow` stays a working switch, but as one faint outline
                // rather than four halo slabs.
                if (espGlow)
                {
                    Stroke(new Rect(bounds.x - 2f, bounds.y - 2f,
                        bounds.width + 4f, bounds.height + 4f), 1f,
                        WithAlpha(accent, 0.16f * fade), pixel);
                }
            }

            // The locked target gets a hairline outline just outside its own
            // brackets — enough to read as "the assist is on this one" without
            // a second box competing with the first.
            if (espTargetHighlight && player == aimTarget)
            {
                Stroke(new Rect(bounds.x - 2f, bounds.y - 2f,
                    bounds.width + 4f, bounds.height + 4f), 1f,
                    new Color(1f, 1f, 1f, 0.42f * fade), pixel);
            }

            float healthRatio = 0f;
            float trackH = Mathf.Max(2f, 3f * ui);
            float trackY = bounds.yMax + 3f * ui;
            if ((currentMask & EspHealth) != 0)
            {
                healthRatio = maximumHealth > 0
                    ? Mathf.Clamp01((float)currentHealth / (float)maximumHealth) : 0f;
                // One thin track under the box, filled from the side the panel
                // picked. The old rail ran the full height beside the brackets
                // and read as a second frame.
                Fill(new Rect(bounds.x, trackY, width, trackH),
                    new Color(0.02f, 0.03f, 0.04f, 0.62f * fade), pixel);
                float filled = width * healthRatio;
                if (filled > 0f)
                {
                    float fillX = healthSide == 0 ? bounds.xMax - filled : bounds.x;
                    Fill(new Rect(fillX, trackY, filled, trackH),
                        WithAlpha(HealthColor(healthRatio), fade), pixel);
                }

                if (espHealthText && !downed)
                {
                    ShadowLabel(new Rect(bounds.x, trackY + trackH + 1f * ui,
                        width, 11f * espTextScale), currentHealth + " hp", smallStyle,
                        WithAlpha(HealthColor(healthRatio), 0.92f * fade), espTextScale);
                }
            }

            if ((currentMask & EspSkeleton) != 0)
            {
                DrawSkeleton(player, camera, bounds, WithAlpha(accent, 0.72f * fade), pixel,
                    screenWidth, screenHeight);
            }

            if ((currentMask & EspHeadDot) != 0)
            {
                // A filled square, not a ring: at three pixels a ring is a
                // smudge, and a dot is all the head marker needs to be.
                float dot = Mathf.Max(2.4f, 2.6f * ui);
                Fill(new Rect(headPoint.x - dot * 0.5f, headPoint.y - dot * 0.5f,
                    dot, dot), new Color(1f, 1f, 1f, 0.88f * fade), pixel);
            }

            // One plate above the box carries everything textual: name,
            // distance and the downed tag. Stacking three labels under the box
            // was the busiest part of the old overlay.
            string nickname = null;
            if ((currentMask & EspName) != 0)
            {
                nickname = player.NickName;
                if (nickname == null || nickname.Length == 0)
                {
                    nickname = "?";
                }
                if (nickname.Length > 14)
                {
                    nickname = nickname.Substring(0, 12) + "..";
                }
            }

            int meters = (int)(distance + 0.5f);
            if (meters < 0) meters = 0;

            string chipText = "";
            if (nickname != null)
            {
                chipText = nickname;
            }
            if ((currentMask & EspDistance) != 0)
            {
                if (chipText.Length > 0)
                {
                    chipText = chipText + "  |  " + meters + "m";
                }
                else
                {
                    chipText = meters + "m";
                }
            }
            if (downed)
            {
                chipText = chipText.Length > 0 ? chipText + "  |  DOWN" : "DOWN";
            }

            if (chipText.Length > 0)
            {
                float chipH = 16f * espTextScale;
                float chipWidth = (float)chipText.Length * 6.4f * espTextScale + 16f;
                float maxChip = Mathf.Max(width * 3.2f, 56f);
                chipWidth = Mathf.Clamp(chipWidth, 42f, maxChip);
                Rect chip = new Rect(bounds.center.x - chipWidth * 0.5f,
                    bounds.y - chipH - 5f * ui, chipWidth, chipH);
                if (espNameChip)
                {
                    Fill(chip, new Color(0.02f, 0.03f, 0.04f, 0.66f * fade), pixel);
                }
                // A single accent hairline ties the plate to the box; no border,
                // no second fill.
                Fill(new Rect(chip.x, chip.y, chip.width, Mathf.Max(1f, 1.2f * ui)),
                    WithAlpha(accent, 0.92f * fade), pixel);
                ShadowLabel(chip, chipText, smallStyle,
                    downed ? new Color(0.92f, 0.94f, 0.96f, 0.95f)
                        : new Color(0.96f, 0.98f, 0.97f, 0.96f), espTextScale);
            }

            if ((currentMask & EspTracer) != 0)
            {
                DrawGlowLine(
                    new Vector2((float)screenWidth * 0.5f, (float)screenHeight),
                    new Vector2(bounds.center.x, bounds.yMax + 2f),
                    WithAlpha(accent, 0.34f * fade), 0f, screenWidth, screenHeight);
            }

            if ((currentMask & EspLine) != 0)
            {
                Vector2 from = new Vector2((float)screenWidth * 0.5f,
                    (float)screenHeight * 0.5f);
                Vector2 to = new Vector2(bounds.center.x, bounds.center.y);
                for (int dash = 0; dash < 3; dash++)
                {
                    float t0 = 0.18f + (float)dash * 0.26f;
                    float t1 = t0 + 0.15f;
                    DrawGlowLine(
                        new Vector2(from.x + (to.x - from.x) * t0,
                            from.y + (to.y - from.y) * t0),
                        new Vector2(from.x + (to.x - from.x) * t1,
                            from.y + (to.y - from.y) * t1),
                        WithAlpha(accent, 0.26f * fade), 0f, screenWidth, screenHeight);
                }
            }

            if ((currentMask & Esp360Arrows) != 0)
            {
                float radius = Mathf.Min((float)screenWidth, (float)screenHeight) * 0.34f
                    + Mathf.Min(distance, 60f) * 0.35f;
                DrawArrow(screenCenter, boxCenter, radius, WithAlpha(accent, 0.72f * fade),
                    screenWidth, screenHeight);
            }
        }
        // Filled in SetDefaults() instead of with field initialisers: csc would
        // otherwise emit ldtoken/InitializeArray, which IFix cannot translate.
        private static int activeTab;

        private static int RowCount(int tab)
        {
            if (tab == TabAim) return 11;
            if (tab == TabExtras) return 11;
            return 14;
        }

        private static string[] RowLabels(int tab)
        {
            if (tab == TabAim) return AimLabels;
            if (tab == TabExtras) return ExtraLabels;
            return VisualLabels;
        }

        private static int RowKind(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 9) return RowCycle;
                if (row == 10 || row == 11) return RowSlider;
                if (row == 12) return RowPalette;
                return RowToggle;
            }
            if (tab == TabAim)
            {
                if (row == 4) return RowCycle;
                if (row >= 5) return RowSlider;
                return RowToggle;
            }
            if (row == 6) return RowCycle;
            if (row == 5 || row == 7 || row == 8) return RowSlider;
            return RowToggle;
        }

        private static string SectionAt(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 0) return "MARKERS";
                if (row == 9) return "FRAME";
                if (row == 12) return "COLOR";
            }
            else if (tab == TabAim)
            {
                if (row == 0) return "ASSIST";
                if (row == 4) return "TARGETING";
                if (row == 5) return "BEHAVIOUR";
            }
            else
            {
                if (row == 0) return "HUD";
                if (row == 4) return "ADVANCED";
                if (row == 9) return "OVERLAY";
            }
            return null;
        }

        private static bool IsGroupStart(int tab, int row)
        {
            if (row == 0) return true;
            return SectionAt(tab, row) != null;
        }

        private static int GroupEnd(int tab, int row)
        {
            int rows = RowCount(tab);
            int next = row + 1;
            while (next < rows && SectionAt(tab, next) == null)
            {
                next++;
            }
            return next - 1;
        }

        private static bool RowEnabled(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 0) return (mask & EspMaster) != 0;
                if (row == 1) return (mask & EspLine) != 0;
                if (row == 2) return (mask & EspBox) != 0;
                if (row == 3) return (mask & EspName) != 0;
                if (row == 4) return (mask & EspDistance) != 0;
                if (row == 5) return (mask & EspHealth) != 0;
                if (row == 6) return (mask & EspSkeleton) != 0;
                if (row == 7) return (mask & EspTracer) != 0;
                if (row == 8) return (mask & Esp360Arrows) != 0;
                if (row == 13) return rainbow;
                return false;
            }
            if (tab == TabAim)
            {
                if (row == 0) return (mask & AimMaster) != 0;
                if (row == 1) return (mask & AimTouchGate) != 0;
                if (row == 2) return (mask & AimVisibleOnly) != 0;
                if (row == 3) return (mask & AimIgnoreKnocked) != 0;
                return false;
            }
            if (row == 0) return (mask & EnemyCount) != 0;
            if (row == 1) return (mask & EspHeadDot) != 0;
            if (row == 2) return (mask & EspShowDowned) != 0;
            if (row == 3) return (mask & EspVisibleOnly) != 0;
            if (row == 4) return (mask & EspBoxFill) != 0;
            if (row == 9) return (mask & EspFov) != 0;
            if (row == 10) return (mask & SniperScope) != 0;
            return false;
        }

        private static string RowValue(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 9) return boxStyle == 1 ? "EDGE" : "CORNER";
                if (row == 12)
                {
                    int index = paletteIndex;
                    if (index < 0) index = 0;
                    if (index >= PaletteNames.Length) index = PaletteNames.Length - 1;
                    return PaletteNames[index];
                }
                return "";
            }
            if (tab == TabAim)
            {
                if (row == 4)
                {
                    int bone = aimBone;
                    if (bone < 0) bone = 0;
                    if (bone >= BoneNames.Length) bone = BoneNames.Length - 1;
                    return BoneNames[bone];
                }
                return "";
            }
            if (row == 6) return healthSide == 0 ? "LEFT" : "RIGHT";
            return "";
        }

        private static void ToggleRow(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 0) mask ^= EspMaster;
                else if (row == 1) mask ^= EspLine;
                else if (row == 2) mask ^= EspBox;
                else if (row == 3) mask ^= EspName;
                else if (row == 4) mask ^= EspDistance;
                else if (row == 5) mask ^= EspHealth;
                else if (row == 6) mask ^= EspSkeleton;
                else if (row == 7) mask ^= EspTracer;
                else if (row == 8) mask ^= Esp360Arrows;
                else if (row == 13) rainbow = !rainbow;
                return;
            }
            if (tab == TabAim)
            {
                if (row == 0)
                {
                    mask ^= AimMaster;
                    if ((mask & AimMaster) == 0)
                    {
                        ResetAim();
                    }
                }
                else if (row == 1) mask ^= AimTouchGate;
                else if (row == 2) mask ^= AimVisibleOnly;
                else if (row == 3) mask ^= AimIgnoreKnocked;
                return;
            }
            if (row == 0) mask ^= EnemyCount;
            else if (row == 1) mask ^= EspHeadDot;
            else if (row == 2) mask ^= EspShowDowned;
            else if (row == 3) mask ^= EspVisibleOnly;
            else if (row == 4) mask ^= EspBoxFill;
            else if (row == 9) mask ^= EspFov;
            else if (row == 10) mask ^= SniperScope;
        }

        private static void CycleRow(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 9) boxStyle = boxStyle == 0 ? 1 : 0;
                return;
            }
            if (tab == TabAim)
            {
                if (row == 4)
                {
                    aimBone++;
                    if (aimBone > 3) aimBone = 0;
                }
                return;
            }
            if (row == 6) healthSide = healthSide == 0 ? 1 : 0;
        }

        private static float SliderMin(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 10) return 50f;
                if (row == 11) return -60f;
            }
            if (tab == TabAim)
            {
                if (row == 5) return 40f;
                if (row == 6) return 2f;
                if (row == 7) return 50f;
                if (row == 8) return 60f;
                if (row == 9) return 0f;
                if (row == 10) return 20f;
            }
            if (tab == TabExtras)
            {
                if (row == 5) return 5f;
                if (row == 7) return 20f;
                if (row == 8) return 50f;
            }
            return 0f;
        }

        private static float SliderMax(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 10) return 200f;
                if (row == 11) return 60f;
            }
            if (tab == TabAim)
            {
                if (row == 5) return 320f;
                if (row == 6) return 100f;
                if (row == 7) return 100f;
                if (row == 8) return 400f;
                if (row == 9) return 250f;
                if (row == 10) return 400f;
            }
            if (tab == TabExtras)
            {
                if (row == 5) return 90f;
                if (row == 7) return 500f;
                if (row == 8) return 160f;
            }
            return 100f;
        }

        private static float SliderGet(int tab, int row)
        {
            if (tab == TabVisual)
            {
                if (row == 10) return espBoxScale * 100f;
                if (row == 11) return espBoxOffset;
            }
            if (tab == TabAim)
            {
                if (row == 5) return aimFov;
                if (row == 6) return aimSmooth * 100f;
                if (row == 7) return aimHitChance * 100f;
                if (row == 8) return aimReaction * 1000f;
                if (row == 9) return aimLead * 1000f;
                if (row == 10) return aimMaxDistance;
            }
            if (tab == TabExtras)
            {
                if (row == 5) return espFillAlpha * 100f;
                if (row == 7) return espMaxDistance;
                if (row == 8) return espTextScale * 100f;
            }
            return 0f;
        }

        private static void SliderSet(int tab, int row, float value)
        {
            if (tab == TabVisual)
            {
                if (row == 10) espBoxScale = Mathf.Clamp(value / 100f, 0.5f, 2f);
                else if (row == 11) espBoxOffset = Mathf.Clamp(value, -60f, 60f);
                return;
            }
            if (tab == TabAim)
            {
                if (row == 5) aimFov = Mathf.Clamp(value, 40f, 320f);
                else if (row == 6) aimSmooth = Mathf.Clamp(value / 100f, 0.02f, 1f);
                else if (row == 7) aimHitChance = Mathf.Clamp(value / 100f, 0.5f, 1f);
                else if (row == 8) aimReaction = Mathf.Clamp(value / 1000f, 0.06f, 0.4f);
                else if (row == 9) aimLead = Mathf.Clamp(value / 1000f, 0f, 0.25f);
                else if (row == 10) aimMaxDistance = Mathf.Clamp(value, 20f, 400f);
                return;
            }
            if (row == 5) espFillAlpha = Mathf.Clamp(value / 100f, 0.05f, 0.9f);
            else if (row == 7) espMaxDistance = Mathf.Clamp(value, 20f, 500f);
            else if (row == 8) espTextScale = Mathf.Clamp(value / 100f, 0.5f, 1.6f);
        }

        private static string SliderText(int tab, int row)
        {
            int shown = Mathf.RoundToInt(SliderGet(tab, row));
            if (tab == TabVisual)
            {
                if (row == 10) return shown + "%";
                if (row == 11) return shown + " px";
            }
            else if (tab == TabAim)
            {
                if (row == 5) return shown + " px";
                if (row == 6 || row == 7) return shown + "%";
                if (row == 8 || row == 9) return shown + " ms";
                if (row == 10) return shown + " m";
            }
            else
            {
                if (row == 5 || row == 8) return shown + "%";
                if (row == 7) return shown + " m";
            }
            return "";
        }

        private static void ActivateRow(int tab, int row, Vector2 pointer, Rect body, float scale)
        {
            int kind = RowKind(tab, row);
            if (kind == RowToggle) ToggleRow(tab, row);
            else if (kind == RowCycle) CycleRow(tab, row);
            else if (kind == RowPalette)
            {
                int index = PaletteHit(row, pointer, body, scale);
                if (index >= 0)
                {
                    paletteIndex = index;
                    rainbow = false;
                }
            }
        }

        private static void ApplySlider(int tab, int row, float pointerX, Rect body, float scale)
        {
            float trackX = body.x + 15f * scale;
            float trackWidth = body.width - 30f * scale;
            float t = Mathf.Clamp01((pointerX - trackX) / Mathf.Max(1f, trackWidth));
            SliderSet(tab, row, Mathf.Lerp(SliderMin(tab, row), SliderMax(tab, row), t));
        }

        private static float PanelScale(int screenWidth, int screenHeight)
        {
            return Mathf.Clamp(Mathf.Min((float)screenWidth / 880f,
                (float)screenHeight / 560f), 0.62f, 1.12f);
        }

        private static float PanelWidth(int screenWidth)
        {
            return Mathf.Clamp((float)screenWidth * 0.46f, 300f, 430f);
        }

        private static Rect OrbRect(float scale, int screenWidth, int screenHeight)
        {
            float size = OrbSize * scale;
            if (orbPosition.x < 0f || orbPosition.y < 0f)
            {
                orbPosition = new Vector2(screenWidth - size - 16f * scale,
                    (float)screenHeight * 0.45f);
            }
            orbPosition = new Vector2(
                Mathf.Clamp(orbPosition.x, 4f, Mathf.Max(4f, (float)screenWidth - size - 4f)),
                Mathf.Clamp(orbPosition.y, 4f, Mathf.Max(4f, (float)screenHeight - size - 4f)));
            return new Rect(orbPosition.x, orbPosition.y, size, size);
        }

        private static void DrawOrb(float scale, int screenWidth, int screenHeight)
        {
            Rect rect = OrbRect(scale, screenWidth, screenHeight);
            Vector2 center = new Vector2(rect.x + rect.width * 0.5f,
                rect.y + rect.height * 0.5f);
            float radius = rect.width * 0.5f;
            // Idle orb sits quiet: low fill, thin ring. It wakes only under a
            // recent touch, so a clean screen never carries a bright marker.
            bool awake = Time.unscaledTime - orbLastTouch < 4f;
            float ringAlpha = awake ? 0.85f : 0.42f;
            float fillAlpha = awake ? 0.55f : 0.30f;
            Color accent = BaseColor();
            Color fill = new Color(0.02f, 0.03f, 0.04f, fillAlpha);
            for (float inner = radius - 1f; inner > 1f; inner -= 2f)
            {
                DrawCircle(center, inner, 20, fill, screenWidth, screenHeight);
            }
            DrawCircle(center, radius, 44, WithAlpha(accent, ringAlpha),
                screenWidth, screenHeight);
            DrawCircle(center, radius * 0.66f, 36, WithAlpha(accent, ringAlpha * 0.5f),
                screenWidth, screenHeight);
            DrawCircle(center, 2.2f * scale, 10, WithAlpha(accent, ringAlpha),
                screenWidth, screenHeight);
        }

        private static float HeaderHeight(float scale) { return 58f * scale; }
        private static float HeadingHeight(float scale) { return 50f * scale; }
        private static float FooterHeight(float scale) { return 54f * scale; }
        private static float TabBarHeight(float scale) { return 56f * scale; }
        private static float SectionHeight(float scale) { return 28f * scale; }

        private static float RowHeightForKind(int kind, float scale)
        {
            if (kind == RowSlider) return 52f * scale;
            if (kind == RowPalette) return 56f * scale;
            return 42f * scale;
        }

        private static float ContentHeight(int tab, float scale)
        {
            float height = 0f;
            int rows = RowCount(tab);
            for (int row = 0; row < rows; row++)
            {
                if (SectionAt(tab, row) != null) height += SectionHeight(scale);
                height += RowHeightForKind(RowKind(tab, row), scale);
            }
            return height + 6f * scale;
        }

        private static float RowTop(int tab, int row, float scale)
        {
            float y = 0f;
            for (int i = 0; i < row; i++)
            {
                if (SectionAt(tab, i) != null) y += SectionHeight(scale);
                y += RowHeightForKind(RowKind(tab, i), scale);
            }
            return y;
        }

        private static float PanelHeightFor(float scale, int tab, int screenHeight)
        {
            float fixedHeight = HeaderHeight(scale) + HeadingHeight(scale)
                + FooterHeight(scale) + TabBarHeight(scale);
            float height = fixedHeight + ContentHeight(tab, scale) + 8f * scale;
            float limit = (float)screenHeight - 16f;
            if (height > limit) height = limit;
            return height;
        }

        private static float BodyHeightFor(float panelHeight, float scale)
        {
            float height = panelHeight - HeaderHeight(scale) - HeadingHeight(scale)
                - FooterHeight(scale) - TabBarHeight(scale);
            if (height < 32f * scale) height = 32f * scale;
            return height;
        }

        private static Rect BodyRect(float x, float y, float width, float height, float scale)
        {
            return new Rect(x + 15f * scale, y + HeaderHeight(scale) + HeadingHeight(scale),
                width - 30f * scale, BodyHeightFor(height, scale));
        }

        private static Rect RowRect(int tab, int row, Rect body, float scale)
        {
            return new Rect(body.x, body.y + RowTop(tab, row, scale) - menuScroll,
                body.width, RowHeightForKind(RowKind(tab, row), scale));
        }

        private static int HitRow(int tab, Vector2 pointer, Rect body, float scale)
        {
            if (!body.Contains(pointer))
            {
                return -1;
            }
            float contentY = pointer.y - body.y + menuScroll;
            int rows = RowCount(tab);
            for (int row = 0; row < rows; row++)
            {
                float top = RowTop(tab, row, scale);
                float height = RowHeightForKind(RowKind(tab, row), scale);
                if (contentY >= top && contentY <= top + height)
                {
                    return row;
                }
            }
            return -1;
        }

        private static int PaletteHit(int row, Vector2 pointer, Rect body, float scale)
        {
            Rect rowRect = RowRect(TabVisual, row, body, scale);
            float size = 22f * scale;
            float startX = rowRect.x + 15f * scale;
            float gap = (rowRect.width - 30f * scale - size * (float)Palette.Length)
                / (float)(Palette.Length - 1);
            if (gap < 4f * scale) gap = 4f * scale;
            float y = rowRect.y + 25f * scale;
            for (int index = 0; index < Palette.Length; index++)
            {
                Rect swatch = new Rect(startX + (size + gap) * (float)index, y, size, size);
                if (swatch.Contains(pointer)) return index;
            }
            return -1;
        }

        private static string TabTitle(int tab)
        {
            if (tab == TabAim) return "TRACK";
            if (tab == TabExtras) return "MISC";
            return "VIEW";
        }

        private static Rect TabBounds(int index, float x, float y, float width, float height,
            float scale)
        {
            float barY = y + height - TabBarHeight(scale);
            float tabWidth = width / 3f;
            return new Rect(x + tabWidth * (float)index, barY + 6f * scale,
                tabWidth, TabBarHeight(scale) - 6f * scale);
        }

        private static Rect CloseBounds(float x, float y, float width, float scale)
        {
            return new Rect(x + width - 40f * scale, y + 11f * scale,
                24f * scale, 24f * scale);
        }

        private static Rect FooterBounds(int index, float x, float y, float width,
            float height, float scale)
        {
            float inset = 15f * scale;
            float gap = 10f * scale;
            float buttonWidth = (width - inset * 2f - gap) * 0.5f;
            float buttonY = y + height - TabBarHeight(scale) - FooterHeight(scale)
                + 10f * scale;
            return new Rect(x + inset + (buttonWidth + gap) * (float)index,
                buttonY, buttonWidth, 34f * scale);
        }

        private static void DrawMenu(float x, float y, float width, float height, float scale,
            int currentMask, Texture2D pixel)
        {
            RoundedFill(new Rect(x + 2f * scale, y + 6f * scale, width, height),
                new Color(0f, 0f, 0f, 0.34f), pixel, 14f * scale);
            RoundedFill(new Rect(x, y, width, height), uiEdge, pixel, 14f * scale);
            RoundedFill(new Rect(x + 1f, y + 1f, width - 2f, height - 2f),
                new Color(uiBase.r, uiBase.g, uiBase.b, 0.985f), pixel, 13f * scale);

            // The body is painted first: rows scrolled past the viewport edges
            // run underneath the chrome, and every band below repaints an
            // opaque strip over them. That clips the list without needing
            // GUI groups, which this Unity build does not expose.
            Rect body = BodyRect(x, y, width, height, scale);
            menuScrollMax = Mathf.Max(0f, ContentHeight(activeTab, scale) - body.height);
            if (menuScrollTab != activeTab)
            {
                menuScrollTab = activeTab;
                menuScroll = 0f;
            }
            menuScroll = Mathf.Clamp(menuScroll, 0f, menuScrollMax);

            DrawMenuBody(activeTab, body, scale, pixel);
            DrawScrollBar(body, scale, pixel);
            DrawMenuHeader(x, y, width, scale, pixel, currentMask);
            DrawMenuHeading(x, y, width, scale, pixel);
            DrawMenuFooter(x, y, width, height, scale, pixel);
            DrawMenuTabs(x, y, width, height, scale, pixel);
        }

        private static void FillBand(float x, float y, float width, float height, Color color,
            Texture2D pixel)
        {
            Fill(new Rect(x + 1f, y, width - 2f, height), color, pixel);
        }

        private static void DrawMenuHeader(float x, float y, float width, float scale,
            Texture2D pixel, int currentMask)
        {
            Color band = new Color(uiBase.r, uiBase.g, uiBase.b, 1f);
            RoundedFill(new Rect(x, y, width, HeaderHeight(scale) + 14f * scale),
                band, pixel, 13f * scale);

            float markSize = 34f * scale;
            Rect mark = new Rect(x + 16f * scale, y + 11f * scale, markSize, markSize);
            RoundedFill(new Rect(mark.x - 1f, mark.y - 1f,
                mark.width + 2f, mark.height + 2f), uiEdge, pixel, 8f * scale);
            RoundedFill(mark, uiSurfaceHi, pixel, 7f * scale);

            float ring = 12f * scale;
            float cx = mark.center.x;
            float cy = mark.center.y;
            RoundedFill(new Rect(cx - ring * 0.5f, cy - ring * 0.5f, ring, ring),
                uiAccent, pixel, ring * 0.5f);
            RoundedFill(new Rect(cx - ring * 0.5f + 1.3f * scale,
                cy - ring * 0.5f + 1.3f * scale, ring - 2.6f * scale,
                ring - 2.6f * scale), uiSurfaceHi, pixel, ring * 0.5f);
            RoundedFill(new Rect(cx - 1.6f * scale, cy - 1.6f * scale,
                3.2f * scale, 3.2f * scale), uiAccent, pixel, 1.6f * scale);
            Fill(new Rect(cx - 0.75f * scale, cy - ring * 0.5f - 2.4f * scale,
                1.5f * scale, 3.4f * scale), uiAccent, pixel);
            Fill(new Rect(cx - 0.75f * scale, cy + ring * 0.5f - 1f * scale,
                1.5f * scale, 3.4f * scale), uiAccent, pixel);
            Fill(new Rect(cx - ring * 0.5f - 2.4f * scale, cy - 0.75f * scale,
                3.4f * scale, 1.5f * scale), uiAccent, pixel);
            Fill(new Rect(cx + ring * 0.5f - 1f * scale, cy - 0.75f * scale,
                3.4f * scale, 1.5f * scale), uiAccent, pixel);

            titleStyle.alignment = TextAnchor.MiddleLeft;
            titleStyle.fontSize = Mathf.RoundToInt(15f * scale);
            titleStyle.normal.textColor = uiText;
            GUI.color = Color.white;
            GUI.Label(new Rect(x + 58f * scale, y + 8f * scale, width - 165f * scale,
                20f * scale), "UI OVERLAY", titleStyle);

            hintStyle.alignment = TextAnchor.MiddleLeft;
            hintStyle.fontSize = Mathf.RoundToInt(9f * scale);
            hintStyle.normal.textColor = uiTextFaint;
            GUI.Label(new Rect(x + 58f * scale, y + 27f * scale, width - 165f * scale,
                15f * scale), "DRAG HEADER TO MOVE", hintStyle);

            bool armed = (currentMask & EspMaster) != 0;
            Color tone = armed ? uiGood : uiTextDim;
            string status = armed ? "ON" : "OFF";
            float badgeWidth = 62f * scale;
            Rect badge = new Rect(x + width - 78f * scale - badgeWidth,
                y + 17f * scale, badgeWidth, 19f * scale);
            RoundedFill(new Rect(badge.x - 1f, badge.y - 1f, badge.width + 2f,
                badge.height + 2f), WithAlpha(tone, 0.25f), pixel, 10f * scale);
            RoundedFill(badge, WithAlpha(tone, 0.10f), pixel, 9.5f * scale);
            Fill(new Rect(badge.x + 9f * scale,
                badge.y + badge.height * 0.5f - 2.5f * scale,
                5f * scale, 5f * scale), tone, pixel);
            smallStyle.alignment = TextAnchor.MiddleLeft;
            smallStyle.fontSize = Mathf.RoundToInt(9f * scale);
            smallStyle.normal.textColor = tone;
            GUI.color = Color.white;
            GUI.Label(new Rect(badge.x + 19f * scale, badge.y,
                badge.width - 19f * scale, badge.height), status, smallStyle);

            Rect close = CloseBounds(x, y, width, scale);
            closeStyle.alignment = TextAnchor.MiddleCenter;
            closeStyle.fontSize = Mathf.RoundToInt(12f * scale);
            closeStyle.normal.textColor = uiTextFaint;
            GUI.color = Color.white;
            GUI.Label(close, "X", closeStyle);

            Fill(new Rect(x + 15f * scale, y + HeaderHeight(scale) - 1f,
                width - 30f * scale, 1f), uiHairline, pixel);
        }

        private static void DrawMenuHeading(float x, float y, float width, float scale,
            Texture2D pixel)
        {
            float top = y + HeaderHeight(scale);
            Color band = new Color(uiBase.r, uiBase.g, uiBase.b, 1f);
            FillBand(x, top, width, HeadingHeight(scale), band, pixel);
            hintStyle.alignment = TextAnchor.MiddleLeft;
            hintStyle.fontSize = Mathf.RoundToInt(9f * scale);
            hintStyle.normal.textColor = uiTextFaint;
            GUI.color = Color.white;
            GUI.Label(new Rect(x + 16f * scale, top + 5f * scale, width - 90f * scale,
                16f * scale), "CONTROLS", hintStyle);

            titleStyle.alignment = TextAnchor.MiddleLeft;
            titleStyle.fontSize = Mathf.RoundToInt(23f * scale);
            titleStyle.normal.textColor = uiText;
            GUI.Label(new Rect(x + 16f * scale, top + 18f * scale, width - 90f * scale,
                28f * scale), TabTitle(activeTab), titleStyle);

            hintStyle.alignment = TextAnchor.MiddleRight;
            hintStyle.fontSize = Mathf.RoundToInt(12f * scale);
            hintStyle.normal.textColor = uiTextFaint;
            GUI.Label(new Rect(x + width - 80f * scale, top + 12f * scale,
                60f * scale, 18f * scale), "0" + (activeTab + 1), hintStyle);
            RoundedFill(new Rect(x + width - 38f * scale, top + 33f * scale,
                22f * scale, 2f * scale), uiAccent, pixel, 1f * scale);
        }

        private static void DrawMenuBody(int tab, Rect body, float scale, Texture2D pixel)
        {
            int rows = RowCount(tab);
            float cullTop = body.y - 10f * scale;
            float cullBottom = body.yMax + 10f * scale;
            for (int row = 0; row < rows; row++)
            {
                float top = body.y + RowTop(tab, row, scale) - menuScroll;
                if (IsGroupStart(tab, row))
                {
                    int last = GroupEnd(tab, row);
                    float bottom = body.y + RowTop(tab, last, scale)
                        + RowHeightForKind(RowKind(tab, last), scale) - menuScroll;
                    if (bottom >= cullTop && top <= cullBottom)
                    {
                        Rect card = new Rect(body.x, top + SectionHeight(scale),
                            body.width, bottom - top - SectionHeight(scale));
                        RoundedFill(card, uiSurface, pixel, 12f * scale);

                        Fill(new Rect(body.x + 2f * scale, top + 9f * scale,
                            3f * scale, 9f * scale), uiAccent, pixel);
                        Fill(new Rect(body.x + 108f * scale,
                            top + SectionHeight(scale) * 0.5f,
                            body.width - 108f * scale, 1f), uiHairline, pixel);
                        smallStyle.alignment = TextAnchor.MiddleLeft;
                        smallStyle.fontSize = Mathf.RoundToInt(9.5f * scale);
                        smallStyle.normal.textColor = uiTextDim;
                        GUI.color = Color.white;
                        GUI.Label(new Rect(body.x + 10f * scale, top,
                            body.width - 20f * scale, SectionHeight(scale)),
                            SectionAt(tab, row), smallStyle);
                    }
                }
                float rowHeight = RowHeightForKind(RowKind(tab, row), scale);
                if (top + rowHeight < cullTop || top > cullBottom)
                {
                    continue;
                }
                Rect rowRect = new Rect(body.x, top, body.width, rowHeight);
                DrawMenuRow(tab, row, rowRect, scale, pixel);
            }
        }

        private static void DrawMenuRow(int tab, int row, Rect rowRect, float scale,
            Texture2D pixel)
        {
            int kind = RowKind(tab, row);
            float inset = rowRect.x + 15f * scale;
            if (!IsGroupStart(tab, row))
            {
                Fill(new Rect(inset, rowRect.y,
                    rowRect.width - 15f * scale, 1f), uiHairline, pixel);
            }

            rowStyle.alignment = TextAnchor.MiddleLeft;
            rowStyle.fontSize = Mathf.RoundToInt(13f * scale);
            rowStyle.normal.textColor = (kind == RowToggle && !RowEnabled(tab, row))
                ? uiTextDim : uiText;
            GUI.color = Color.white;
            float labelY = rowRect.y;
            float labelHeight = rowRect.height;
            if (kind == RowSlider)
            {
                labelY = rowRect.y + 4f * scale;
                labelHeight = 24f * scale;
            }
            GUI.Label(new Rect(inset, labelY, rowRect.width - 120f * scale,
                labelHeight), RowLabels(tab)[row], rowStyle);

            if (kind == RowToggle)
            {
                bool on = RowEnabled(tab, row);
                float trackWidth = 44f * scale;
                float trackHeight = 26f * scale;
                Rect track = new Rect(rowRect.xMax - 15f * scale - trackWidth,
                    rowRect.y + (rowRect.height - trackHeight) * 0.5f,
                    trackWidth, trackHeight);
                Color ring = on ? WithAlpha(uiAccentHi, 0.45f) : uiHairline;
                RoundedFill(new Rect(track.x - 1f, track.y - 1f,
                    track.width + 2f, track.height + 2f), ring, pixel,
                    trackHeight * 0.5f + 1f);
                RoundedFill(track, on ? uiAccent : uiWell, pixel,
                    trackHeight * 0.5f);
                float knob = 20f * scale;
                float knobX = on ? track.xMax - knob - 3f * scale : track.x + 3f * scale;
                RoundedFill(new Rect(knobX, track.y + 3f * scale, knob, knob),
                    on ? uiVoid : uiTextDim, pixel, knob * 0.5f);
            }
            else if (kind == RowSlider)
            {
                float pillWidth = 58f * scale;
                Rect pill = new Rect(rowRect.xMax - 15f * scale - pillWidth,
                    rowRect.y + 5f * scale, pillWidth, 20f * scale);
                RoundedFill(pill, WithAlpha(uiAccent, 0.12f), pixel, 10f * scale);
                smallStyle.alignment = TextAnchor.MiddleCenter;
                smallStyle.fontSize = Mathf.RoundToInt(10f * scale);
                smallStyle.normal.textColor = uiAccent;
                GUI.color = Color.white;
                GUI.Label(pill, SliderText(tab, row), smallStyle);

                Rect track = new Rect(inset, rowRect.y + rowRect.height - 16f * scale,
                    rowRect.width - 30f * scale, 4f * scale);
                RoundedFill(track, uiWell, pixel, 2f * scale);
                float t = Mathf.InverseLerp(SliderMin(tab, row), SliderMax(tab, row),
                    SliderGet(tab, row));
                if (t > 0.001f)
                {
                    RoundedFill(new Rect(track.x, track.y, track.width * t,
                        track.height), uiAccent, pixel, 2f * scale);
                }
                float knob = 11f * scale;
                RoundedFill(new Rect(track.x + track.width * t - knob * 0.5f,
                    track.y + track.height * 0.5f - knob * 0.5f, knob, knob),
                    uiAccentHi, pixel, knob * 0.5f);
            }
            else if (kind == RowCycle)
            {
                float pillWidth = 74f * scale;
                Rect pill = new Rect(rowRect.xMax - 15f * scale - pillWidth,
                    rowRect.y + (rowRect.height - 20f * scale) * 0.5f,
                    pillWidth, 20f * scale);
                RoundedFill(pill, WithAlpha(uiAccent, 0.10f), pixel, 10f * scale);
                smallStyle.alignment = TextAnchor.MiddleCenter;
                smallStyle.fontSize = Mathf.RoundToInt(10f * scale);
                smallStyle.normal.textColor = uiAccent;
                GUI.color = Color.white;
                GUI.Label(pill, RowValue(tab, row), smallStyle);
            }
            else if (kind == RowPalette)
            {
                float size = 22f * scale;
                float gap = (rowRect.width - 30f * scale - size * (float)Palette.Length)
                    / (float)(Palette.Length - 1);
                if (gap < 4f * scale) gap = 4f * scale;
                float startX = rowRect.x + 15f * scale;
                float top = rowRect.y + 25f * scale;
                for (int index = 0; index < Palette.Length; index++)
                {
                    Rect swatch = new Rect(startX + (size + gap) * (float)index,
                        top, size, size);
                    bool selected = paletteIndex == index;
                    if (selected)
                    {
                        RoundedFill(new Rect(swatch.x - 3f * scale, swatch.y - 3f * scale,
                            size + 6f * scale, size + 6f * scale), uiAccent, pixel,
                            (size + 6f * scale) * 0.5f);
                    }
                    else
                    {
                        RoundedFill(new Rect(swatch.x - 1f, swatch.y - 1f,
                            size + 2f * scale, size + 2f * scale),
                            new Color(1f, 1f, 1f, 0.14f), pixel,
                            (size + 2f * scale) * 0.5f);
                    }
                    RoundedFill(swatch, Palette[index], pixel, size * 0.5f);
                }
            }
        }

        private static void DrawScrollBar(Rect body, float scale, Texture2D pixel)
        {
            if (menuScrollMax <= 0.5f) return;
            float trackX = body.xMax + 5f * scale;
            float trackY = body.y + 4f * scale;
            float trackHeight = body.height - 8f * scale;
            RoundedFill(new Rect(trackX, trackY, 2f * scale, trackHeight),
                new Color(1f, 1f, 1f, 0.06f), pixel, 1f * scale);
            float thumbHeight = trackHeight * (body.height / (body.height + menuScrollMax));
            if (thumbHeight < 24f * scale) thumbHeight = 24f * scale;
            float t = menuScrollMax <= 0f ? 0f : menuScroll / menuScrollMax;
            float thumbY = trackY + (trackHeight - thumbHeight) * t;
            RoundedFill(new Rect(trackX, thumbY, 2f * scale, thumbHeight),
                WithAlpha(uiAccent, 0.55f), pixel, 1f * scale);
        }

        private static void DrawMenuFooter(float x, float y, float width, float height,
            float scale, Texture2D pixel)
        {
            Color band = new Color(uiBase.r, uiBase.g, uiBase.b, 1f);
            FillBand(x, y + height - TabBarHeight(scale) - FooterHeight(scale),
                width, FooterHeight(scale) + 10f * scale, band, pixel);

            Rect primary = FooterBounds(0, x, y, width, height, scale);
            Rect secondary = FooterBounds(1, x, y, width, height, scale);
            RoundedFill(primary, uiAccent, pixel, 12f * scale);
            buttonStyle.alignment = TextAnchor.MiddleCenter;
            buttonStyle.fontSize = Mathf.RoundToInt(10.5f * scale);
            buttonStyle.normal.textColor = uiVoid;
            GUI.color = Color.white;
            GUI.Label(primary, "ENABLE ALL", buttonStyle);

            RoundedFill(new Rect(secondary.x - 1f, secondary.y - 1f,
                secondary.width + 2f, secondary.height + 2f), uiEdge, pixel,
                12f * scale);
            RoundedFill(secondary, uiSurfaceHi, pixel, 11f * scale);
            buttonStyle.normal.textColor = uiText;
            GUI.color = Color.white;
            GUI.Label(secondary, "HIDE MENU", buttonStyle);
        }

        private static void DrawMenuTabs(float x, float y, float width, float height,
            float scale, Texture2D pixel)
        {
            float barY = y + height - TabBarHeight(scale);
            Color band = new Color(uiVoid.r, uiVoid.g, uiVoid.b, 1f);
            RoundedFill(new Rect(x, barY - 8f * scale, width,
                TabBarHeight(scale) + 8f * scale), band, pixel, 13f * scale);
            Fill(new Rect(x + 15f * scale, barY, width - 30f * scale, 1f),
                uiHairline, pixel);
            string[] names = { "VIEW", "TRACK", "MISC" };
            for (int tab = 0; tab < 3; tab++)
            {
                Rect bounds = TabBounds(tab, x, y, width, height, scale);
                bool selected = activeTab == tab;
                Color ink = selected ? uiText : uiTextFaint;
                if (selected)
                {
                    RoundedFill(new Rect(bounds.center.x - 10f * scale,
                        bounds.y + 3f * scale, 20f * scale, 2f * scale),
                        uiAccent, pixel, 1f * scale);
                }
                DrawTabGlyph(bounds, tab, scale, ink, pixel);
                smallStyle.alignment = TextAnchor.MiddleCenter;
                smallStyle.fontSize = Mathf.RoundToInt(9.5f * scale);
                smallStyle.normal.textColor = ink;
                GUI.color = Color.white;
                GUI.Label(new Rect(bounds.x, bounds.y + 20f * scale, bounds.width,
                    16f * scale), names[tab], smallStyle);
            }
        }

        private static void DrawTabGlyph(Rect bounds, int tab, float scale, Color ink,
            Texture2D pixel)
        {
            float cx = bounds.center.x;
            float cy = bounds.y + 13f * scale;
            if (tab == 0)
            {
                Rect eye = new Rect(cx - 9f * scale, cy - 5f * scale,
                    18f * scale, 10f * scale);
                RoundedFill(eye, ink, pixel, 5f * scale);
                RoundedFill(new Rect(eye.x + 1.2f * scale, eye.y + 1.2f * scale,
                    eye.width - 2.4f * scale, eye.height - 2.4f * scale),
                    uiBase, pixel, 4f * scale);
                RoundedFill(new Rect(cx - 2f * scale, cy - 2f * scale,
                    4f * scale, 4f * scale), ink, pixel, 2f * scale);
            }
            else if (tab == 1)
            {
                float ring = 7f * scale;
                RoundedFill(new Rect(cx - ring, cy - ring, ring * 2f, ring * 2f),
                    ink, pixel, ring);
                RoundedFill(new Rect(cx - ring + 1.4f * scale,
                    cy - ring + 1.4f * scale, (ring - 1.4f * scale) * 2f,
                    (ring - 1.4f * scale) * 2f), uiBase, pixel, ring);
                RoundedFill(new Rect(cx - 1.5f * scale, cy - 1.5f * scale,
                    3f * scale, 3f * scale), ink, pixel, 1.5f * scale);
                Fill(new Rect(cx - 10f * scale, cy - 0.5f * scale,
                    20f * scale, 1f * scale), ink, pixel);
                Fill(new Rect(cx - 0.5f * scale, cy - 10f * scale,
                    1f * scale, 20f * scale), ink, pixel);
            }
            else
            {
                float half = 9f * scale;
                for (int i = 0; i < 3; i++)
                {
                    float lineY = cy - 5f * scale + (float)i * 5f * scale;
                    Fill(new Rect(cx - half, lineY, half * 2f, 1.2f * scale), ink, pixel);
                    float knobX = cx + (i == 0 ? 4f : (i == 1 ? -5f : 1.5f)) * scale;
                    RoundedFill(new Rect(knobX - 1.8f * scale, lineY - 1.6f * scale,
                        3.6f * scale, 4f * scale), ink, pixel, 1.8f * scale);
                }
            }
        }

        public static bool Bootstrap(Player self)
        {
            if (self == null)
            {
                return false;
            }
            bool stealthState;
            try
            {
                stealthState = self.IsInStealth();
                if (!configLoaded)
                {
                    configLoaded = true;
                    SetDefaults();
                    LoadConfiguration();
                    bootstrapTime = Time.unscaledTime;
                }
                else
                {
                    // Cheap while idle, and the only path that exists once the
                    // overlay is torn down — so it is also what re-arms it.
                    PollConfiguration();
                }

                // Idle means idle. With every feature off there is nothing to
                // draw and nothing to aim, so the patch must not leave a host
                // object, a component or a destroy call behind — the whole point
                // of a "nothing enabled" session is that it is indistinguishable
                // from an unmodified client.
                if ((mask & EspMask) == 0 && (mask & AimMaster) == 0)
                {
                    if (cachedDriver != null)
                    {
                        UnityEngine.Object.Destroy(cachedDriver);
                        cachedDriver = null;
                    }
                    return stealthState;
                }

                // The assist solves from here rather than from OnGUI: this call
                // site runs every frame in the game's own per-player pass, while
                // a Repaint event can be skipped and always lands after the frame
                // has been rendered. Its own guard keeps the cost at one solve per
                // frame however many times the game calls into it. It is wrapped
                // separately because the surrounding catch writes stealthState —
                // a throw in the aim maths must not answer a stealth query wrong.
                try
                {
                    AimFrame();
                }
                catch (Exception)
                {
                }

                GameObject driver = cachedDriver;
                bool createdDriver = false;
                if (driver == null)
                {
                    driver = GameObject.Find(OverlayHostName);
                    cachedDriver = driver;
                }
                if (driver == null)
                {
                    Camera camera = Camera.main;
                    Transform legacyFov = camera == null
                        ? null
                        : camera.transform.Find("__esp_fov");
                    if (legacyFov != null)
                    {
                        UnityEngine.Object.Destroy(legacyFov.gameObject);
                    }
                    driver = new GameObject(OverlayHostName);
                    cachedDriver = driver;
                    createdDriver = true;
                    bootstrapTime = Time.unscaledTime;
                }

                Component component = driver.GetComponent(typeof(SceneEditBoxSelectTool));
                if (component == null)
                {
                    component = driver.AddComponent(typeof(SceneEditBoxSelectTool));
                }
                if (component == null)
                {
                    if (createdDriver)
                    {
                        UnityEngine.Object.Destroy(driver);
                    }
                }
                else
                {
                    if (createdDriver)
                    {
                        UnityEngine.Object.DontDestroyOnLoad(driver);
                    }
                }
            }
            catch (Exception)
            {
                stealthState = false;
            }
            return stealthState;
        }
        public static void Draw(SceneEditBoxSelectTool self)
        {
            if (self == null)
            {
                return;
            }
            Event currentEvent = Event.current;
            if (currentEvent == null)
            {
                return;
            }
            GameObject driverObject = self.gameObject;
            if (driverObject == null || driverObject.name != OverlayHostName)
            {
                return;
            }
            cachedDriver = driverObject;

            if (!configLoaded)
            {
                configLoaded = true;
                SetDefaults();
                LoadConfiguration();
                bootstrapTime = Time.unscaledTime;
            }
            else
            {
                PollConfiguration();
            }

            // Nothing enabled: no overlay, no menu, no per-frame work. The host
            // object is not created in this state either (see Bootstrap), so an
            // idle session costs the game nothing and leaves nothing behind.
            // Re-arming happens from the panel, which rewrites the config.
            if ((mask & EspMask) == 0 && (mask & AimMaster) == 0)
            {
                return;
            }

            int screenWidth = Screen.width;
            int screenHeight = Screen.height;
            if (screenWidth <= 0 || screenHeight <= 0)
            {
                return;
            }

            float uiScale = PanelScale(screenWidth, screenHeight);
            float panelWidth = PanelWidth(screenWidth);
            int state = (int)self.{{SCENE_STATE_FIELD}}.x;
            bool menuOpen = self.{{SCENE_MENU_FIELD}};

            // A live reload replaced the feature bits. Push them into the
            // scene-state vector, otherwise the `mask = state & EspMask` read
            // below would immediately restore the old values.
            if (pendingMaskApply)
            {
                pendingMaskApply = false;
                state = (state & ~EspMask) | (mask & EspMask);
                self.{{SCENE_STATE_FIELD}} = new Vector2((float)state, 0f);
            }

            if ((state & StateInitialized) == 0)
            {
                state = StateInitialized | (mask & EspMask);
                self.{{SCENE_POSITION_FIELD}} = new Vector2(
                    ((float)screenWidth - panelWidth) * 0.5f,
                    ((float)screenHeight - PanelHeightFor(uiScale, activeTab, screenHeight)) * 0.5f);
                self.{{SCENE_STATE_FIELD}} = new Vector2((float)state, 0f);
                menuOpen = false;
            }
            else
            {
                mask = state & EspMask;
            }

            bool threeFingerActive = (state & StateThreeFinger) != 0;
            int touchCount = SafeTouchCount();
            bool threeFingersDown = touchCount >= 3;
            if (threeFingersDown && !threeFingerActive)
            {
                state |= StateThreeFinger;
            }
            else if (!threeFingersDown && threeFingerActive)
            {
                state &= ~StateThreeFinger;
                float nowTime = Time.unscaledTime;
                if (menuLastTapTime > 0f && nowTime - menuLastTapTime > 3f)
                {
                    menuTapCount = 0;
                }
                menuTapCount++;
                if (menuTapCount >= 5)
                {
                    menuTapCount = 0;
                    // The gesture stays as a recovery path; the orb is the
                    // normal entry point.
                    menuOpen = !menuOpen;
                }
                menuLastTapTime = nowTime;
            }

            float panelHeight = PanelHeightFor(uiScale, activeTab, screenHeight);
            float maxPanelX = (float)screenWidth - panelWidth - 8f;
            float maxPanelY = (float)screenHeight - panelHeight - 8f;
            if (maxPanelX < 8f) maxPanelX = 8f;
            if (maxPanelY < 8f) maxPanelY = 8f;
            float panelX = Mathf.Clamp(self.{{SCENE_POSITION_FIELD}}.x, 8f, maxPanelX);
            float panelY = Mathf.Clamp(self.{{SCENE_POSITION_FIELD}}.y, 8f, maxPanelY);
            Rect headerRect = new Rect(panelX, panelY, panelWidth, HeaderHeight(uiScale));
            Rect bodyRect = BodyRect(panelX, panelY, panelWidth, panelHeight, uiScale);
            menuScrollMax = Mathf.Max(0f, ContentHeight(activeTab, uiScale) - bodyRect.height);
            menuScroll = Mathf.Clamp(menuScroll, 0f, menuScrollMax);

            bool dragging = (state & StateDragging) != 0;
            bool releasedDrag = false;
            Vector2 pointer = currentEvent.mousePosition;
            if (menuOpen && currentEvent.type == EventType.MouseDown
                && headerRect.Contains(pointer)
                && !CloseBounds(panelX, panelY, panelWidth, uiScale).Contains(pointer))
            {
                state |= StateDragging;
                dragging = true;
                currentEvent.Use();
            }
            else if (menuOpen && currentEvent.type == EventType.MouseDown
                && bodyRect.Contains(pointer))
            {
                menuBodyGrab = true;
                menuBodyMoved = false;
                menuGrabY = pointer.y;
                menuGrabScroll = menuScroll;
                menuScrollGrab = -1;
                int grabRow = HitRow(activeTab, pointer, bodyRect, uiScale);
                if (grabRow >= 0 && RowKind(activeTab, grabRow) == RowSlider)
                {
                    menuScrollGrab = grabRow;
                    ApplySlider(activeTab, grabRow, pointer.x, bodyRect, uiScale);
                }
                currentEvent.Use();
            }
            else if (currentEvent.type == EventType.MouseDrag && dragging)
            {
                panelX = Mathf.Clamp(panelX + currentEvent.delta.x, 8f, maxPanelX);
                panelY = Mathf.Clamp(panelY + currentEvent.delta.y, 8f, maxPanelY);
                self.{{SCENE_POSITION_FIELD}} = new Vector2(panelX, panelY);
                currentEvent.Use();
            }
            else if (currentEvent.type == EventType.MouseDrag && menuBodyGrab)
            {
                float travel = pointer.y - menuGrabY;
                if (travel > 6f * uiScale || travel < -6f * uiScale)
                {
                    menuBodyMoved = true;
                }
                if (menuScrollGrab >= 0)
                {
                    ApplySlider(activeTab, menuScrollGrab, pointer.x, bodyRect, uiScale);
                }
                else if (menuBodyMoved)
                {
                    menuScroll = Mathf.Clamp(menuGrabScroll - travel, 0f, menuScrollMax);
                }
                currentEvent.Use();
            }
            else if (menuOpen && currentEvent.type == EventType.ScrollWheel
                && bodyRect.Contains(pointer))
            {
                menuScroll = Mathf.Clamp(menuScroll + currentEvent.delta.y * 22f * uiScale,
                    0f, menuScrollMax);
                currentEvent.Use();
            }
            else if (currentEvent.type == EventType.MouseUp && dragging)
            {
                state &= ~StateDragging;
                dragging = false;
                releasedDrag = true;
                currentEvent.Use();
            }
            else if (currentEvent.type == EventType.MouseUp && menuBodyGrab)
            {
                menuBodyGrab = false;
                int heldSlider = menuScrollGrab;
                bool moved = menuBodyMoved;
                menuBodyMoved = false;
                menuScrollGrab = -1;
                if (menuOpen && heldSlider < 0 && !moved && bodyRect.Contains(pointer))
                {
                    int hitRow = HitRow(activeTab, pointer, bodyRect, uiScale);
                    if (hitRow >= 0)
                    {
                        ActivateRow(activeTab, hitRow, pointer, bodyRect, uiScale);
                    }
                }
                currentEvent.Use();
            }
            else if (menuOpen && currentEvent.type == EventType.MouseUp
                && !dragging && !releasedDrag)
            {
                int previousTab = activeTab;
                if (CloseBounds(panelX, panelY, panelWidth, uiScale).Contains(pointer))
                {
                    menuOpen = false;
                }
                else if (FooterBounds(0, panelX, panelY, panelWidth, panelHeight, uiScale).Contains(pointer))
                {
                    mask = EspMask;
                }
                else if (FooterBounds(1, panelX, panelY, panelWidth, panelHeight, uiScale).Contains(pointer))
                {
                    menuOpen = false;
                }
                else if (TabBounds(0, panelX, panelY, panelWidth, panelHeight, uiScale).Contains(pointer))
                {
                    activeTab = TabVisual;
                }
                else if (TabBounds(1, panelX, panelY, panelWidth, panelHeight, uiScale).Contains(pointer))
                {
                    activeTab = TabAim;
                }
                else if (TabBounds(2, panelX, panelY, panelWidth, panelHeight, uiScale).Contains(pointer))
                {
                    activeTab = TabExtras;
                }
                if (previousTab != activeTab)
                {
                    panelHeight = PanelHeightFor(uiScale, activeTab, screenHeight);
                    maxPanelY = (float)screenHeight - panelHeight - 8f;
                    if (maxPanelY < 8f) maxPanelY = 8f;
                    panelY = Mathf.Clamp(panelY, 8f, maxPanelY);
                    bodyRect = BodyRect(panelX, panelY, panelWidth, panelHeight, uiScale);
                    menuScrollMax = Mathf.Max(0f,
                        ContentHeight(activeTab, uiScale) - bodyRect.height);
                    menuScrollTab = activeTab;
                    menuScroll = 0f;
                    self.{{SCENE_POSITION_FIELD}} = new Vector2(panelX, panelY);
                }
                if (new Rect(panelX, panelY, panelWidth, panelHeight).Contains(pointer))
                {
                    currentEvent.Use();
                }
            }
            else if (!menuOpen && currentEvent.type == EventType.MouseDown
                && OrbRect(uiScale, screenWidth, screenHeight).Contains(pointer))
            {
                orbDragging = true;
                orbMoved = false;
                orbLastTouch = Time.unscaledTime;
                Rect orb = OrbRect(uiScale, screenWidth, screenHeight);
                orbGrabDX = pointer.x - orb.x;
                orbGrabDY = pointer.y - orb.y;
                currentEvent.Use();
            }
            else if (orbDragging && currentEvent.type == EventType.MouseDrag)
            {
                orbPosition = new Vector2(pointer.x - orbGrabDX, pointer.y - orbGrabDY);
                orbMoved = true;
                orbLastTouch = Time.unscaledTime;
                currentEvent.Use();
            }
            else if (orbDragging && currentEvent.type == EventType.MouseUp)
            {
                orbDragging = false;
                orbLastTouch = Time.unscaledTime;
                if (!orbMoved)
                {
                    menuOpen = true;
                }
                orbMoved = false;
                currentEvent.Use();
            }

            state = (state & ~EspMask) | (mask & EspMask);
            sceneMenuOpen = menuOpen;
            self.{{SCENE_MENU_FIELD}} = menuOpen;
            self.{{SCENE_POSITION_FIELD}} = new Vector2(panelX, panelY);
            self.{{SCENE_STATE_FIELD}} = new Vector2((float)state, 0f);

            if (currentEvent.type != EventType.Repaint)
            {
                return;
            }

            Matrix4x4 savedMatrix = GUI.matrix;
            Color savedColor = GUI.color;
            try
            {
                GUI.matrix = Matrix4x4.identity;
                Texture2D pixel = Texture2D.whiteTexture;
                if (pixel != null)
                {
                    Camera camera = Camera.main;
                    Player localPlayer = GameFacade.CurrentLocalPlayer();
                    Transform localRoot = localPlayer == null ? null : localPlayer.RootTransform;
                    GameObject localObject = localPlayer == null ? null : localPlayer.gameObject;
                    {{MATCH_TYPE}} match = GameFacade.CurrentMatch();
                    IList players = match == null ? null : match.{{MATCH_PLAYERS_METHOD}}();
                    bool localReady = localPlayer != null && localObject != null
                        && localObject.activeInHierarchy && localRoot != null;

                    PrepareStyles(uiScale);

                    if (camera != null && localReady)
                    {
                        try
                        {
                            // Solve on this pass too: the game's own per-player
                            // hook drives the assist, but a GUI repaint is the
                            // one event we can prove fires while the match
                            // renders. The solve itself dedupes to one per
                            // frame, so running it from both hooks costs one
                            // solve and guarantees a write lands in the frame
                            // being drawn.
                            AimFrame();
                            AimReassert();
                        }
                        catch (Exception)
                        {
                            // Assist must never abort the visual pass.
                        }

                        // Crosshair the assist aims through: a thin ring with a
                        // centre pip. Drawn whenever the assist is armed, with
                        // or without the ESP layer, so the lock point is always
                        // visible.
                        if ((mask & AimMaster) != 0 && aimCrosshair)
                        {
                            Vector2 cross = new Vector2((float)screenWidth * 0.5f,
                                (float)screenHeight * 0.5f);
                            float crossRadius = Mathf.Max(5f, (float)screenHeight * 0.009f);
                            DrawCircle(cross, crossRadius, 28, new Color(1f, 1f, 1f, 0.82f),
                                screenWidth, screenHeight);
                            DrawCircle(cross, 1.6f, 10, new Color(1f, 1f, 1f, 0.92f),
                                screenWidth, screenHeight);
                        }
                    }

                    if ((mask & EspMaster) != 0 && camera != null && localReady && players != null)
                    {
                        // Collect, then sort by range. Painting in list order
                        // buries the enemy in front of you under the boxes of
                        // three players behind him; farthest-first fixes that.
                        int targetCount = 0;
                        int playerCount = players.Count;
                        for (int index = 0; index < playerCount && targetCount < EspCapacity; index++)
                        {
                            Player player = players[index] as Player;
                            if (player == null) continue;
                            GameObject playerObject = player.gameObject;
                            if (playerObject == null || !playerObject.activeInHierarchy) continue;
                            if (player.IsLocalPlayer() || player.IsLocalTeammate(false)) continue;
                            Transform targetRoot = player.RootTransform;
                            if (targetRoot == null) continue;
                            float distance = Vector3.Distance(localRoot.position, targetRoot.position);
                            if (distance > espMaxDistance) continue;
                            bool downed = player.IsDieing;
                            if (downed && (mask & EspShowDowned) == 0) continue;
                            if (!downed && player.CurHP <= 0) continue;
                            if ((mask & EspVisibleOnly) != 0 && !downed && !player.IsVisible()) continue;
                            espTargets[targetCount] = player;
                            espTargetDistance[targetCount] = distance;
                            espTargetDowned[targetCount] = downed;
                            targetCount++;
                        }

                        for (int i = 1; i < targetCount; i++)
                        {
                            object keyPlayer = espTargets[i];
                            float keyDistance = espTargetDistance[i];
                            bool keyDowned = espTargetDowned[i];
                            int j = i - 1;
                            while (j >= 0 && espTargetDistance[j] < keyDistance)
                            {
                                espTargets[j + 1] = espTargets[j];
                                espTargetDistance[j + 1] = espTargetDistance[j];
                                espTargetDowned[j + 1] = espTargetDowned[j];
                                j--;
                            }
                            espTargets[j + 1] = keyPlayer;
                            espTargetDistance[j + 1] = keyDistance;
                            espTargetDowned[j + 1] = keyDowned;
                        }

                        for (int index = 0; index < targetCount; index++)
                        {
                            try
                            {
                                DrawPlayerEsp(espTargets[index] as Player, camera, localPlayer, pixel,
                                    screenWidth, screenHeight, mask, espTargetDistance[index]);
                            }
                            catch (Exception)
                            {
                                // Recycled entity: skip this frame only.
                            }
                        }

                        if ((mask & EnemyCount) != 0)
                        {
                            Color badgeAccent = BaseColor();
                            Rect badge = new Rect(14f, 44f, 128f, 26f);
                            RoundedFill(badge, new Color(0.03f, 0.05f, 0.05f, 0.86f), pixel, 13f);
                            Fill(new Rect(badge.x + 10f, badge.y + 9f, 8f, 8f), badgeAccent, pixel);
                            rowStyle.normal.textColor = new Color(0.93f, 0.96f, 0.95f, 1f);
                            GUI.color = Color.white;
                            GUI.Label(new Rect(badge.x + 22f, badge.y, badge.width - 22f,
                                badge.height), "Enemies: " + targetCount, rowStyle);
                        }
                    }

                    Vector2 center = new Vector2((float)screenWidth * 0.5f,
                        (float)screenHeight * 0.5f);
                    Color ringColor = BaseColor();
                    if ((mask & EspFov) != 0)
                    {
                        DrawCircle(center, aimFov, 72, WithAlpha(ringColor, 0.14f),
                            screenWidth, screenHeight);
                        DrawCircle(center, aimFov - 1f, 72, WithAlpha(ringColor, 0.38f),
                            screenWidth, screenHeight);
                        DrawCircle(center, 2.5f, 12, WithAlpha(ringColor, 0.65f),
                            screenWidth, screenHeight);
                    }

                    if ((mask & SniperScope) != 0)
                    {
                        float scopeRadius = Mathf.Min((float)screenWidth,
                            (float)screenHeight) * 0.42f;
                        Color shade = new Color(0f, 0f, 0f, 0.62f);
                        Fill(new Rect(0f, 0f, (float)screenWidth,
                            center.y - scopeRadius), shade, pixel);
                        Fill(new Rect(0f, center.y + scopeRadius, (float)screenWidth,
                            (float)screenHeight - center.y - scopeRadius), shade, pixel);
                        Fill(new Rect(0f, center.y - scopeRadius, center.x - scopeRadius,
                            scopeRadius * 2f), shade, pixel);
                        Fill(new Rect(center.x + scopeRadius, center.y - scopeRadius,
                            (float)screenWidth - center.x - scopeRadius,
                            scopeRadius * 2f), shade, pixel);
                        DrawCircle(center, scopeRadius, 96, WithAlpha(ringColor, 0.50f),
                            screenWidth, screenHeight);
                        DrawGlowLine(new Vector2(center.x - scopeRadius * 0.62f, center.y),
                            new Vector2(center.x - 8f, center.y), ringColor, 0f,
                            screenWidth, screenHeight);
                        DrawGlowLine(new Vector2(center.x + 8f, center.y),
                            new Vector2(center.x + scopeRadius * 0.62f, center.y), ringColor, 0f,
                            screenWidth, screenHeight);
                        DrawGlowLine(new Vector2(center.x, center.y - scopeRadius * 0.62f),
                            new Vector2(center.x, center.y - 8f), ringColor, 0f,
                            screenWidth, screenHeight);
                        DrawGlowLine(new Vector2(center.x, center.y + 8f),
                            new Vector2(center.x, center.y + scopeRadius * 0.62f), ringColor, 0f,
                            screenWidth, screenHeight);
                    }

                    if (menuOpen)
                    {
                        GUI.matrix = Matrix4x4.identity;
                        DrawMenu(panelX, panelY, panelWidth, panelHeight, uiScale,
                            mask, pixel);
                    }
                    else if (mask != 0)
                    {
                        // Nothing armed means nothing on screen: the orb only
                        // exists while at least one feature is live, and it
                        // dims itself after four idle seconds.
                        GUI.matrix = Matrix4x4.identity;
                        DrawOrb(uiScale, screenWidth, screenHeight);
                    }
                }
            }
            catch (Exception)
            {
                // A transient Unity object must not break the render loop.
            }

            GUI.matrix = savedMatrix;
            GUI.color = savedColor;
        }
    }
}
