using System;
using System.Collections;
using COW;
using COW.GamePlay;
using UnityEngine;

namespace ProjectEspPatch
{
    // Aim core, second half of the `Logic` partial.
    //
    // This replaces the OnGUI-driven assist. The old one solved and wrote inside
    // `SceneEditBoxSelectTool.OnGUI`, which costs a full frame of latency and
    // only runs on a Repaint event, and it throttled itself with a token bucket
    // that returned *without writing* on roughly half the frames. Both make the
    // reticle lose the target: the camera controller rebuilds orientation from
    // the player's aim state every LateUpdate, so a write that skips a frame
    // lets the error grow back before the next correction lands.
    //
    // The model here separates the two jobs that were conflated:
    //
    //   * tracking* is continuous — one solve per frame, a write every frame, so
    //     the crosshair actually holds;
    //   * stealth* is behavioural — engagement length, release beats, reaction,
    //     turn-rate and how often the game's own `SetAimRotation` is entered.
    //
    // Per-frame dropout is the worst of both: it does not hide the pattern (an
    // instant correction followed by silence is more machine-like than smooth
    // tracking) and it destroys aim.
    //
    // Only APIs the shipped patch already resolves are used here. No new externals
    // (no `Time.frameCount`, no extra field reads): InjectFix binds patch IL to the
    // game's generated wrapper table, so an external the running patch never called
    // is a runtime miss, not a compile error. Frame dedupe is therefore a 4 ms
    // floor on `Time.unscaledTime`, which is far below any real frame interval.
    public static partial class Logic
    {
        // ---- solve cadence ----
        // Bootstrap fires on every Player.IsReallyInStealth call, several times a
        // frame. 4 ms lets exactly one solve through per frame at any framerate
        // that exists on a phone and still tolerates a 240 Hz panel.
        private const float SolveFloor = 0.004f;
        private static float holdLastSolveAt;
        private static float holdPrevAt;

        // ---- re-assert ----
        // The rotation solved during this frame's update phase, replayed at GUI
        // time so the value the eye sees is the value we computed even if the
        // controller rebuilt the transform in between.
        private static Quaternion holdDesired;
        private static bool holdValid;
        private static float holdValidAt;
        private const float ReassertWindow = 0.25f;

        // ---- game-facing write throttle ----
        // SetAimRotation is the only write the game counts and can score. The
        // transform and the aim-rotation field are free; this one is rationed.
        private static float holdLastCommitAt;

        // ---- operator knobs (parsed in ApplyConfiguration) ----
        // 0 = lock, 1 = low, 2 = balanced, 3 = quiet.
        private static int aimStealth = 2;
        // 0 = solve from the camera, 1 = solve from the local player's eye.
        // Third-person puts the camera metres behind the aim axis, so which
        // origin you solve from decides whether the reticle and the bullet path
        // agree at range. Left to the operator because the game's own hit test
        // is not visible from the managed dump.
        private static int aimFrom;
        // Multiplier on the tracking gain, so the panel can soften or sharpen a
        // lock without touching the stealth envelope.
        private static float holdGain = 1f;
        // Minimum seconds between SetAimRotation commits.
        private static float commitInterval = 0.033f;

        /// <summary>
        /// One tracking step. Called from Bootstrap, which the game runs during
        /// its own per-player pass, so this lands after the frame's input has
        /// been read and the orientation written here survives into the render.
        /// </summary>
        public static void AimFrame()
        {
            if ((mask & AimMaster) == 0 || sceneMenuOpen)
            {
                holdValid = false;
                ResetAim();
                return;
            }

            float now = Time.unscaledTime;
            if (now - bootstrapTime < 1.2f)
            {
                return;
            }
            if ((mask & AimTouchGate) != 0)
            {
                int touchCount = SafeTouchCount();
                if (touchCount == 0)
                {
                    holdValid = false;
                    ResetAim();
                    return;
                }
            }
            if (now - holdLastSolveAt < SolveFloor)
            {
                return;
            }

            Camera camera = Camera.main;
            Player local = GameFacade.CurrentLocalPlayer();
            if (camera == null || local == null)
            {
                return;
            }
            GameObject localObject = local.gameObject;
            if (localObject == null || !localObject.activeInHierarchy)
            {
                return;
            }
            if (local.RootTransform == null)
            {
                return;
            }
            IList players = CurrentPlayers();
            if (players == null)
            {
                return;
            }

            holdLastSolveAt = now;
            float dt = now - holdPrevAt;
            holdPrevAt = now;
            if (dt <= 0f)
            {
                dt = Time.unscaledDeltaTime;
            }
            if (dt > 0.1f)
            {
                dt = 0.1f;
            }

            // A hitch or a paused menu must not read as an idle second of
            // recovery time; the engagement envelope below is what gates.
            if (aimCoolTarget != null && now >= aimCoolUntil)
            {
                aimCoolTarget = null;
            }

            // Kill guard: writing after the locked target dies — or snapping to
            // the next body in the same frame — is the clearest signature there
            // is, and it is a behavioural one, so it costs nothing to keep.
            if (aimTarget != null && aimTarget.IsDieing)
            {
                aimKillGuardUntil = now + aimKillGuard;
                holdValid = false;
                ResetAim();
                return;
            }
            if (now < aimKillGuardUntil)
            {
                holdValid = false;
                ResetAim();
                return;
            }

            Vector3 point;
            Player target = FindStickyTarget(camera, local, players, out point);
            if (target == null)
            {
                holdValid = false;
                ResetAim();
                return;
            }

            if (target != aimTarget)
            {
                aimTarget = target;
                aimEngaged = false;
                float reaction = aimReaction + Noise01(now * 4.37f) * 0.06f;
                aimAcquireAt = now + reaction;
                aimRoll = Noise01((float)(target.GetInstanceID() & 1023) * 0.019f
                    + now * 0.37f);
                aimLockUntil = now + 3.2f;
                aimLastPoint = point;
                aimSmoothPoint = point;
                aimLastPointTime = now;
                aimVelocity = Vector3.zero;
                aimPhase = Noise01(now * 1.93f) * 6f;
                aimEngageTime = now;
                aimEngageStart = now;
            }

            // Bone positions tick with the animation and jitter by centimetres;
            // writing that raw reads as a twitch. The filter constant is scaled
            // by dt so the lag is the same in seconds at 30, 60 or 120 fps —
            // the old fixed 0.35 blend made the assist lead differently per
            // device, which is exactly the kind of thing a replay shows.
            float positionAlpha = Mathf.Clamp01(dt * 26f);
            aimSmoothPoint = Vector3.Lerp(aimSmoothPoint, point, positionAlpha);

            float sampleDelta = now - aimLastPointTime;
            if (sampleDelta > 0.004f && sampleDelta < 0.4f)
            {
                Vector3 measured = (point - aimLastPoint) / sampleDelta;
                if (measured.magnitude < 15f)
                {
                    aimVelocity = Vector3.Lerp(aimVelocity, measured,
                        Mathf.Clamp01(sampleDelta * 6f));
                }
            }
            aimLastPoint = point;
            aimLastPointTime = now;
            aimLockUntil = now + (aimLatch ? 1.15f : 0.9f);

            if (!aimEngaged)
            {
                if (now < aimAcquireAt)
                {
                    return;
                }
                aimEngaged = true;
                aimEngageTime = now;
            }

            // Engagement envelope. This is the stealth dimension that actually
            // buys something: no lock survives a whole fight. Lock mode is the
            // operator opting out of it, not a default.
            if (aimStealth > 0 && !aimLock
                && now - aimEngageStart > antibanMaxEngage)
            {
                aimCoolTarget = aimTarget;
                aimCoolUntil = now + antibanCooldown;
                holdValid = false;
                ResetAim();
                return;
            }

            // Micro-breaks, same reasoning: a hand loses the bead and re-settles.
            if (aimHumanize)
            {
                if (now < aimBreakUntil)
                {
                    return;
                }
                if (aimNextBreakAt <= 0f)
                {
                    aimNextBreakAt = now + 0.8f + Noise01(now * 0.77f) * 0.8f;
                }
                if (now >= aimNextBreakAt)
                {
                    float span = aimBreakMax - aimBreakMin;
                    aimBreakUntil = now + aimBreakMin + Noise01(now * 1.31f + 2.7f) * span;
                    aimNextBreakAt = aimBreakUntil + 0.8f + Noise01(now * 0.53f + 5.1f) * 0.8f;
                    return;
                }
            }

            // One roll per engagement decides whether this burst is allowed to
            // take the head; otherwise it settles low and drifts laterally.
            bool precise = aimRoll <= aimHitChance;
            Vector3 aimPoint = aimSmoothPoint + aimVelocity * aimLead;
            if (!precise)
            {
                aimPoint.y -= 0.22f * Mathf.Clamp01(aimHeight);
                aimPoint.x += (Noise01(now * 0.7f + 3.3f) - 0.5f) * 0.35f;
            }

            // Prediction must not invent a target further away than the weapon
            // reaches; a 0.2 s lead on a sprinting enemy is four metres of miss.
            Vector3 leadOffset = aimPoint - aimSmoothPoint;
            float leadDistance = leadOffset.magnitude;
            if (leadDistance > 2.5f)
            {
                aimPoint = aimSmoothPoint + leadOffset * (2.5f / leadDistance);
            }

            Vector3 origin = camera.transform.position;
            if (aimFrom == 1)
            {
                Transform eye = null;
                try
                {
                    eye = local.GetHeadTF();
                }
                catch (Exception)
                {
                    eye = null;
                }
                if (eye != null)
                {
                    origin = eye.position;
                }
            }

            Vector3 direction = aimPoint - origin;
            if (direction.sqrMagnitude < 0.04f)
            {
                return;
            }

            Quaternion current = camera.transform.rotation;
            Quaternion wanted = Quaternion.LookRotation(direction.normalized, Vector3.up);
            float error = Quaternion.Angle(current, wanted);

            if (error <= aimDeadzone)
            {
                // On target: stop writing, but keep the last solved orientation
                // live so the GUI pass does not let the controller drift off it.
                holdDesired = current;
                holdValid = true;
                holdValidAt = now;
                return;
            }

            // Gain. Far from the bone it pulls, close to it it feathers. The
            // engage ramp adds a human beat before full strength, and holdGain
            // lets the panel scale the whole thing without touching stealth.
            float ramp = aimRamp ? Mathf.Clamp01((now - aimEngageTime) / 0.35f) : 1f;
            float agility = Mathf.Lerp(4.2f, 16.5f, 1f - aimSmooth);
            agility *= Mathf.Lerp(0.55f, 1.35f, Mathf.Clamp01(error / 14f));
            agility *= Mathf.Lerp(0.55f, 1f, ramp);
            agility *= holdGain;

            // Micro sway, faded out as the error closes so the last fraction of
            // a degree settles instead of twitching.
            aimPhase += dt;
            float swayAmount = Mathf.Clamp01(error / 6f);
            float swayScale = aimHumanize ? 1f : 0f;
            float yaw = ((Mathf.Sin(aimPhase * 2.3f) * 0.34f
                + Mathf.Sin(aimPhase * 5.9f + 1.1f) * 0.11f) * swayAmount) * swayScale;
            float pitch = Mathf.Sin(aimPhase * 3.7f + 2.2f) * 0.20f * swayAmount * swayScale;

            // A flick that lands exactly on the bone decelerates onto it; a hand
            // overshoots and comes back. Only in the first quarter second.
            float overshoot = 0f;
            if (aimHumanize && aimOvershoot > 0f)
            {
                float since = now - aimEngageStart;
                if (since >= 0f && since < 0.25f)
                {
                    overshoot = aimOvershoot * (1f - since / 0.25f);
                }
            }
            yaw += overshoot * swayScale;
            pitch += overshoot * 0.35f * swayScale;

            Quaternion next = Quaternion.Slerp(current,
                wanted * Quaternion.Euler(pitch, yaw, 0f),
                Mathf.Clamp01(dt * agility));

            // Turn-rate ceiling, per frame and per second. This is the single
            // most useful statistic to keep honest: angular velocity is what a
            // replay scorer measures first.
            float step = Quaternion.Angle(current, next);
            float cap = Mathf.Min(0.6f + dt * 13f, dt * aimMaxTurn + 0.05f);
            if (step > cap && step > 0.0001f)
            {
                next = Quaternion.Slerp(current, next, cap / step);
            }

            Commit(camera, local, next, now, error);
        }

        /// <summary>
        /// Apply the solved orientation. The camera transform and the player's
        /// aim-rotation field are plain writes the game re-reads next frame;
        /// SetAimRotation is the one call that leaves a countable trace, so it is
        /// rationed to commitInterval seconds and skipped entirely while the
        /// correction is small enough that the field write already carries it.
        /// </summary>
        private static void Commit(Camera camera, Player local, Quaternion next,
            float now, float error)
        {
            camera.transform.rotation = next;
            local.m_CurrentAimRotation = next;

            // SetAimRotation is the state the camera controller actually
            // rebuilds from. The bare field write above can be erased by the
            // game's own touch integration inside the same frame — the game
            // enters SetAimRotation once per frame while a finger is down, so
            // entering it once per frame while the assist corrects sits inside
            // the natural envelope. The 8 ms floor only stops the two drivers
            // (game hook + GUI pass) double-firing in one frame; the operator's
            // commit interval still applies above it.
            float commitFloor = Mathf.Max(commitInterval, 0.008f);
            if (error > aimDeadzone * 2f && now - holdLastCommitAt >= commitFloor)
            {
                local.SetAimRotation(next, true);
                holdLastCommitAt = now;
            }

            holdDesired = next;
            holdValid = true;
            holdValidAt = now;
        }

        /// <summary>
        /// Replay the last solved orientation at GUI time. Cheap and idempotent:
        /// it re-establishes the value if the camera controller rebuilt the
        /// transform between the solve and the frame being drawn.
        /// </summary>
        public static void AimReassert()
        {
            if (!holdValid)
            {
                return;
            }
            if (Time.unscaledTime - holdValidAt > ReassertWindow)
            {
                holdValid = false;
                return;
            }
            Camera camera = Camera.main;
            if (camera == null)
            {
                return;
            }
            camera.transform.rotation = holdDesired;
        }

        /// <summary>
        /// Fold a stealth tier into the behavioural limits. Tier 2 is the shipped
        /// envelope; the panel moves between them without the operator having to
        /// reason about eleven separate numbers.
        /// </summary>
        public static void ApplyStealthTier()
        {
            if (aimLock || aimStealth == 0)
            {
                antibanMaxEngage = 8f;
                antibanCooldown = 0f;
                aimHumanize = false;
                aimDeadzone = 0f;
                aimOvershoot = 0f;
                aimMaxTurn = 720f;
                commitInterval = 0.016f;
                holdGain = 1.35f;
                return;
            }
            aimHumanize = true;
            if (aimStealth == 1)
            {
                antibanMaxEngage = 4f;
                antibanCooldown = 0.5f;
                aimDeadzone = 0.14f;
                aimOvershoot = 1.1f;
                aimMaxTurn = 240f;
                commitInterval = 0.025f;
                holdGain = 1.15f;
            }
            else if (aimStealth == 3)
            {
                antibanMaxEngage = 1.4f;
                antibanCooldown = 1.4f;
                aimDeadzone = 0.3f;
                aimOvershoot = 2.6f;
                aimMaxTurn = 90f;
                commitInterval = 0.12f;
                holdGain = 0.85f;
            }
            else
            {
                antibanMaxEngage = 2.4f;
                antibanCooldown = 0.9f;
                aimDeadzone = 0.2f;
                aimOvershoot = 1.8f;
                aimMaxTurn = 110f;
                commitInterval = 0.033f;
                holdGain = 1f;
            }
        }
    }
}
