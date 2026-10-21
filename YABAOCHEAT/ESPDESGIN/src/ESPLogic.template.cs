using System;
using System.Collections;
using COW;
using COW.GamePlay;
using UnityEngine;

namespace ProjectEspPatch
{
    public static class Logic
    {
        private const int EspMaster = 1;
        private const int EspBox = 2;
        private const int EspTracer = 4;
        private const int EspHealth = 8;
        private const int EspName = 16;
        private const int EspDistance = 32;
        private const int EspAimbot = 64;
        private const int EspLine = 128;
        private const int EspSkeleton = 256;
        private const int Esp360Arrows = 512;
        private const int EnemyCount = 1024;
        private const int EspFov = 2048;
        private const int SniperScope = 4096;
        private const int SilentAim = 8192;
        private const int EspMask = EspMaster | EspBox | EspTracer | EspHealth | EspName | EspDistance | EspAimbot
            | EspLine | EspSkeleton | Esp360Arrows | EnemyCount | EspFov | SniperScope | SilentAim;

        private const int StateInitialized = 1 << 20;
        private const int StateThreeFinger = 1 << 21;
        private const int StateDragging = 1 << 22;
        private const int TapShift = 23;
        private const int TapMask = 0x7F800000;
        private const float AimbotFov = 150f;
        private const float AimbotSmooth = 0.18f;

        private static readonly string[] EspLabels = {
            "Enable ESP", "Player box", "Top tracer",
            "Health bar", "Player name", "Distance", "Aimbot",
            "Line ESP", "Skeleton ESP", "360 Arrows", "Enemy Count",
            "Draw FOV", "Sniper Scope", "Silent Aim"
        };
        private static readonly int[] EspBits = {
            EspMaster, EspBox, EspTracer, EspHealth, EspName, EspDistance, EspAimbot,
            EspLine, EspSkeleton, Esp360Arrows, EnemyCount, EspFov, SniperScope, SilentAim
        };
        private static GUIStyle titleStyle;
        private static GUIStyle hintStyle;
        private static GUIStyle rowStyle;
        private static GUIStyle buttonStyle;
        private static GUIStyle closeStyle;
        private static GUIStyle panelStyle;
        private static GUIStyle accentStyle;

        private static void PrepareMenuStyles(float scale)
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

                buttonStyle = new GUIStyle();
                buttonStyle.alignment = TextAnchor.MiddleCenter;

                closeStyle = new GUIStyle();
                closeStyle.alignment = TextAnchor.MiddleCenter;

                panelStyle = new GUIStyle();
                panelStyle.alignment = TextAnchor.MiddleCenter;

                accentStyle = new GUIStyle();
                accentStyle.alignment = TextAnchor.MiddleCenter;
            }

            titleStyle.fontSize = Mathf.RoundToInt(17f * scale);
            titleStyle.normal.textColor = new Color(0.94f, 0.95f, 0.93f, 1f);
            hintStyle.fontSize = Mathf.RoundToInt(10f * scale);
            hintStyle.normal.textColor = new Color(0.57f, 0.63f, 0.60f, 1f);
            rowStyle.fontSize = Mathf.RoundToInt(13f * scale);
            rowStyle.normal.textColor = new Color(0.88f, 0.90f, 0.88f, 1f);
            buttonStyle.fontSize = Mathf.RoundToInt(11f * scale);
            closeStyle.fontSize = Mathf.RoundToInt(14f * scale);
            closeStyle.normal.textColor = new Color(0.78f, 0.84f, 0.81f, 1f);
            accentStyle.normal.textColor = new Color(0.92f, 0.96f, 0.93f, 1f);
        }

        private static bool TryGetScreenPosition(Vector3 worldPosition, Camera camera, out Vector2 screenPosition)
        {
            screenPosition = Vector2.zero;
            if (camera == null)
            {
                return false;
            }

            Vector3 projected = camera.WorldToScreenPoint(worldPosition);
            if (projected.z < 0.01f)
            {
                return false;
            }

            screenPosition = new Vector2(projected.x, Screen.height - projected.y);
            return screenPosition.x >= 0f && screenPosition.x <= Screen.width &&
                   screenPosition.y >= 0f && screenPosition.y <= Screen.height;
        }

        private static Player FindAimbotTarget(Camera camera, Player localPlayer, IList players, float fovLimit)
        {
            if (camera == null || localPlayer == null || players == null || players.Count == 0)
            {
                return null;
            }

            Transform localRoot = localPlayer.RootTransform;
            Vector3 viewOrigin = localRoot != null ? localRoot.position : camera.transform.position;
            Vector2 screenCenter = new Vector2((float)Screen.width * 0.5f, (float)Screen.height * 0.5f);
            Player bestTarget = null;
            float bestScore = float.MaxValue;

            for (int index = 0; index < players.Count; index++)
            {
                Player player = players[index] as Player;
                if (player == null || player.IsLocalPlayer())
                {
                    continue;
                }

                GameObject playerObject = player.gameObject;
                if (playerObject == null || !playerObject.activeInHierarchy)
                {
                    continue;
                }

                Transform root = player.RootTransform;
                if (root == null)
                {
                    continue;
                }

                Vector3 diff = root.position - viewOrigin;
                if (diff.sqrMagnitude < 0.25f)
                {
                    continue;
                }

                Vector3 screenPoint = camera.WorldToScreenPoint(root.position);
                if (screenPoint.z <= 0f)
                {
                    continue;
                }

                Vector2 projected = new Vector2(screenPoint.x, Screen.height - screenPoint.y);
                float screenDistance = Vector2.Distance(projected, screenCenter);
                if (screenDistance > fovLimit)
                {
                    continue;
                }

                float score = screenDistance + Mathf.Abs(Vector3.Angle(camera.transform.forward, diff.normalized)) * 0.35f;
                if (bestTarget == null || score < bestScore)
                {
                    bestTarget = player;
                    bestScore = score;
                }
            }

            return bestTarget;
        }

        private static void ApplyAimbot(Camera camera, Player localPlayer, IList players, float fovLimit)
        {
            if (camera == null || localPlayer == null || players == null)
            {
                return;
            }

            Player target = FindAimbotTarget(camera, localPlayer, players, fovLimit);
            if (target == null)
            {
                return;
            }

            Transform root = target.RootTransform;
            if (root == null)
            {
                return;
            }

            Vector3 targetPoint = root.position + Vector3.up * 0.8f;
            Vector3 lookDirection = (targetPoint - camera.transform.position).normalized;
            if (lookDirection.sqrMagnitude < 0.001f)
            {
                return;
            }

            Quaternion aimRotation = Quaternion.LookRotation(lookDirection, Vector3.up);
            camera.transform.rotation = Quaternion.Slerp(
                camera.transform.rotation,
                aimRotation,
                AimbotSmooth);
        }

        private static void DrawCornerBox(Rect bounds, Color color, Texture2D pixel, float lineThickness = 2f)
        {
            float cornerSize = Mathf.Clamp(bounds.height * 0.22f, 8f, 22f);
            GUI.color = color;

            GUI.DrawTexture(new Rect(bounds.xMin, bounds.yMin, cornerSize, lineThickness), pixel);
            GUI.DrawTexture(new Rect(bounds.xMin, bounds.yMin, lineThickness, cornerSize), pixel);

            GUI.DrawTexture(new Rect(bounds.xMax - cornerSize, bounds.yMin, cornerSize, lineThickness), pixel);
            GUI.DrawTexture(new Rect(bounds.xMax - lineThickness, bounds.yMin, lineThickness, cornerSize), pixel);

            GUI.DrawTexture(new Rect(bounds.xMin, bounds.yMax - lineThickness, cornerSize, lineThickness), pixel);
            GUI.DrawTexture(new Rect(bounds.xMin, bounds.yMax - cornerSize, lineThickness, cornerSize), pixel);

            GUI.DrawTexture(new Rect(bounds.xMax - cornerSize, bounds.yMax - lineThickness, cornerSize, lineThickness), pixel);
            GUI.DrawTexture(new Rect(bounds.xMax - lineThickness, bounds.yMax - cornerSize, lineThickness, cornerSize), pixel);
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
                GameObject driver = GameObject.Find("__esp_driver");
                bool createdDriver = false;
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
                    driver = new GameObject("__esp_driver");
                    createdDriver = true;
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
                // Rendering setup must not break the queried player state.
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
            if (driverObject == null || driverObject.name != "__esp_driver")
            {
                return;
            }

            int screenWidth = Screen.width;
            int screenHeight = Screen.height;
            float uiScale = Mathf.Clamp(
                Mathf.Min((float)screenWidth / 390f, (float)screenHeight / 440f),
                0.72f, 1.08f);
            float panelWidth = Mathf.Clamp((float)screenWidth * 0.84f, 280f, 460f);
            float panelHeight = Mathf.Clamp((float)screenHeight * 0.82f, 430f, 620f);
            int state = (int)self.{{SCENE_STATE_FIELD}}.x;
            bool menuOpen = self.{{SCENE_MENU_FIELD}};

            if ((state & StateInitialized) == 0)
            {
                state = StateInitialized | EspMask;
                self.{{SCENE_POSITION_FIELD}} = new Vector2(
                    ((float)screenWidth - panelWidth) * 0.5f,
                    ((float)screenHeight - panelHeight) * 0.5f);
                self.{{SCENE_STATE_FIELD}} = new Vector2((float)state, 0f);
                menuOpen = false;
            }

            int mask = state & EspMask;
            int tapCount = (state & TapMask) >> TapShift;
            float lastTapTime = self.{{SCENE_STATE_FIELD}}.y;
            bool threeFingerActive = (state & StateThreeFinger) != 0;
            bool threeFingersDown = Input.touchCount >= 3;

            if (threeFingersDown && !threeFingerActive)
            {
                state |= StateThreeFinger;
            }
            else if (!threeFingersDown && threeFingerActive)
            {
                state &= ~StateThreeFinger;
                float nowTime = Time.unscaledTime;
                if (lastTapTime > 0f && nowTime - lastTapTime > 3f)
                {
                    tapCount = 0;
                }
                tapCount++;
                if (tapCount >= 5)
                {
                    tapCount = 0;
                    menuOpen = true;
                }
                state = (state & ~TapMask) | (tapCount << TapShift);
                lastTapTime = nowTime;
            }

            float maxPanelX = (float)screenWidth - panelWidth - 8f;
            float maxPanelY = (float)screenHeight - panelHeight - 8f;
            if (maxPanelX < 8f) maxPanelX = 8f;
            if (maxPanelY < 8f) maxPanelY = 8f;
            float panelX = Mathf.Clamp(self.{{SCENE_POSITION_FIELD}}.x, 8f, maxPanelX);
            float panelY = Mathf.Clamp(self.{{SCENE_POSITION_FIELD}}.y, 8f, maxPanelY);
            float rowHeight = 44f * uiScale;
            float firstRowY = panelY + 62f * uiScale;
            float rowInset = 14f * uiScale;
            float rowWidth = panelWidth - rowInset * 2f;
            float rowRectHeight = 40f * uiScale;
            float footerInset = 12f * uiScale;
            float footerGap = 8f * uiScale;
            float footerButtonWidth = (panelWidth - footerInset * 2f - footerGap) * 0.5f;
            float footerButtonHeight = 42f * uiScale;
            float footerY = panelY + panelHeight - 52f * uiScale;
            Rect panelRect = new Rect(panelX, panelY, panelWidth, panelHeight);
            Rect headerRect = new Rect(panelX, panelY, panelWidth, 58f * uiScale);
            Rect closeRect = new Rect(
                panelX + panelWidth - 40f * uiScale, panelY + 12f * uiScale,
                28f * uiScale, 28f * uiScale);
            Rect row1Rect = new Rect(panelX + rowInset, firstRowY, rowWidth, rowRectHeight);
            Rect row2Rect = new Rect(panelX + rowInset, firstRowY + rowHeight, rowWidth, rowRectHeight);
            Rect row3Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 2f, rowWidth, rowRectHeight);
            Rect row4Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 3f, rowWidth, rowRectHeight);
            Rect row5Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 4f, rowWidth, rowRectHeight);
            Rect row6Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 5f, rowWidth, rowRectHeight);
            Rect row7Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 6f, rowWidth, rowRectHeight);
            Rect row8Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 7f, rowWidth, rowRectHeight);
            Rect row9Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 8f, rowWidth, rowRectHeight);
            Rect row10Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 9f, rowWidth, rowRectHeight);
            Rect row11Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 10f, rowWidth, rowRectHeight);
            Rect row12Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 11f, rowWidth, rowRectHeight);
            Rect row13Rect = new Rect(panelX + rowInset, firstRowY + rowHeight * 12f, rowWidth, rowRectHeight);
            Rect resetRect = new Rect(
                panelX + footerInset, footerY, footerButtonWidth, footerButtonHeight);
            Rect hideRect = new Rect(
                resetRect.x + footerButtonWidth + footerGap, footerY,
                footerButtonWidth, footerButtonHeight);

            int rowCount = menuOpen ? 14 : 0;

            bool dragging = (state & StateDragging) != 0;
            bool releasedDrag = false;
            Vector2 pointer = currentEvent.mousePosition;
            if (menuOpen && currentEvent.type == EventType.MouseDown
                && headerRect.Contains(pointer) && !closeRect.Contains(pointer))
            {
                state |= StateDragging;
                dragging = true;
                currentEvent.Use();
            }
            else if (menuOpen && currentEvent.type == EventType.MouseDrag && dragging)
            {
                Vector2 delta = currentEvent.delta;
                panelX = Mathf.Clamp(panelX + delta.x, 8f, maxPanelX);
                panelY = Mathf.Clamp(panelY + delta.y, 8f, maxPanelY);
                self.{{SCENE_POSITION_FIELD}} = new Vector2(panelX, panelY);
                currentEvent.Use();
            }
            else if (currentEvent.type == EventType.MouseUp && dragging)
            {
                state &= ~StateDragging;
                dragging = false;
                releasedDrag = true;
                currentEvent.Use();
            }

            if (menuOpen && currentEvent.type == EventType.MouseUp
                && !dragging && !releasedDrag)
            {
                if (closeRect.Contains(pointer))
                {
                    menuOpen = false;
                }
                else if (resetRect.Contains(pointer))
                {
                    mask = EspMask;
                }
                else if (hideRect.Contains(pointer))
                {
                    menuOpen = false;
                }
                else
                {
                    int selectedRow = -1;
                    if (row1Rect.Contains(pointer)) selectedRow = 0;
                    else if (row2Rect.Contains(pointer)) selectedRow = 1;
                    else if (row3Rect.Contains(pointer)) selectedRow = 2;
                    else if (row4Rect.Contains(pointer)) selectedRow = 3;
                    else if (row5Rect.Contains(pointer)) selectedRow = 4;
                    else if (row6Rect.Contains(pointer)) selectedRow = 5;
                    else if (row7Rect.Contains(pointer)) selectedRow = 6;
                    else if (row8Rect.Contains(pointer)) selectedRow = 7;
                    else if (row9Rect.Contains(pointer)) selectedRow = 8;
                    else if (row10Rect.Contains(pointer)) selectedRow = 9;
                    else if (row11Rect.Contains(pointer)) selectedRow = 10;
                    else if (row12Rect.Contains(pointer)) selectedRow = 11;
                    else if (row13Rect.Contains(pointer)) selectedRow = 12;

                    if (selectedRow >= 0 && selectedRow < rowCount)
                    {
                        int espBit = 0;
                        if (selectedRow == 0) espBit = EspMaster;
                        else if (selectedRow == 1) espBit = EspBox;
                        else if (selectedRow == 2) espBit = EspTracer;
                        else if (selectedRow == 3) espBit = EspHealth;
                        else if (selectedRow == 4) espBit = EspName;
                        else if (selectedRow == 5) espBit = EspDistance;
                        else if (selectedRow == 6) espBit = EspAimbot;
                        else if (selectedRow == 7) espBit = EspLine;
                        else if (selectedRow == 8) espBit = EspSkeleton;
                        else if (selectedRow == 9) espBit = Esp360Arrows;
                        else if (selectedRow == 10) espBit = EnemyCount;
                        else if (selectedRow == 11) espBit = EspFov;
                        else if (selectedRow == 12) espBit = SniperScope;
                        mask ^= espBit;
                    }
                }
                if (panelRect.Contains(pointer))
                {
                    currentEvent.Use();
                }
            }

            state = (state & ~EspMask) | mask;
            self.{{SCENE_MENU_FIELD}} = menuOpen;
            self.{{SCENE_POSITION_FIELD}} = new Vector2(panelX, panelY);
            self.{{SCENE_STATE_FIELD}} = new Vector2((float)state, lastTapTime);

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
                if (pixel != null
                    && screenWidth > 0 && screenHeight > 0)
                {
                    Camera camera = Camera.main;
                    Player localPlayer = GameFacade.CurrentLocalPlayer();
                    Transform localRoot = localPlayer == null ? null : localPlayer.RootTransform;

                    if ((mask & EspMaster) != 0)
                    {
                        {{MATCH_TYPE}} match = GameFacade.CurrentMatch();
                        IList players = match == null ? null : match.{{MATCH_PLAYERS_METHOD}}();
                        GameObject localObject = localPlayer == null
                            ? null : localPlayer.gameObject;
                        if (camera != null && localPlayer != null
                            && localObject != null && localObject.activeInHierarchy
                            && localRoot != null && players != null)
                        {
                            if ((mask & (EspAimbot | SilentAim)) != 0)
                            {
                                ApplyAimbot(camera, localPlayer, players, AimbotFov);
                            }

                            for (int index = 0; index < players.Count; index++)
                            {
                                try
                                {
                                Player player = players[index] as Player;
                                if (player == null)
                                {
                                    continue;
                                }
                                GameObject playerObject = player.gameObject;
                                if (playerObject == null || !playerObject.activeInHierarchy)
                                {
                                    continue;
                                }
                                Transform root = player.RootTransform;
                                if (player.IsLocalPlayer()
                                    || player.IsLocalTeammate(false) || !player.IsVisible())
                                {
                                    continue;
                                }

                                bool dying = player.IsDieing;
                                int health = player.CurHP;
                                int maximumHealth = player.MaxHP;
                                if (health <= 0 && !dying)
                                {
                                    continue;
                                }
                                Transform head = player.GetHeadTF();
                                if (root == null || head == null)
                                {
                                    continue;
                                }

                                float distance = Vector3.Distance(localRoot.position, root.position);
                                if (distance > 250f)
                                {
                                    continue;
                                }
                                Vector3 feetScreen = camera.WorldToScreenPoint(root.position);
                                Vector3 headScreen = camera.WorldToScreenPoint(head.position);
                                if (feetScreen.z <= 0f || headScreen.z <= 0f)
                                {
                                    continue;
                                }
                                if (float.IsNaN(feetScreen.x) || float.IsNaN(feetScreen.y)
                                    || float.IsNaN(feetScreen.z) || float.IsNaN(headScreen.x)
                                    || float.IsNaN(headScreen.y) || float.IsNaN(headScreen.z)
                                    || float.IsInfinity(feetScreen.x) || float.IsInfinity(feetScreen.y)
                                    || float.IsInfinity(headScreen.x) || float.IsInfinity(headScreen.y))
                                {
                                    continue;
                                }

                                float height = Mathf.Abs(headScreen.y - feetScreen.y) * 1.0909091f;
                                if (height < 2f)
                                {
                                    continue;
                                }
                                float width = height * 0.5f;
                                float left = headScreen.x - width * 0.5f;
                                float top = (float)screenHeight - headScreen.y;
                                float thickness = 1.5f;
                                if (float.IsNaN(left) || float.IsNaN(top)
                                    || float.IsInfinity(left) || float.IsInfinity(top)
                                    || left > (float)screenWidth || left + width < 0f
                                    || top > (float)screenHeight || top + height < 0f)
                                {
                                    continue;
                                }
                                if ((mask & EspBox) != 0)
                                {
                                    DrawCornerBox(
                                        new Rect(left, top, width, height),
                                        new Color(0.35f, 0.86f, 0.56f, 1f),
                                        pixel,
                                        1.8f);
                                }

                                if ((mask & EspTracer) != 0)
                                {
                                    Vector2 start = new Vector2((float)screenWidth * 0.5f, (float)screenHeight - 6f);
                                    Vector2 end = new Vector2(left + width * 0.5f, top + height);

                                    GL.PushMatrix();
                                    GL.LoadOrtho();
                                    GL.Begin(1);
                                    GL.Color(new Color(0.35f, 0.86f, 0.56f, 1f));
                                    GL.Vertex3(start.x / (float)screenWidth, 1f - start.y / (float)screenHeight, 0f);
                                    GL.Vertex3(end.x / (float)screenWidth, 1f - end.y / (float)screenHeight, 0f);
                                    GL.End();
                                    GL.PopMatrix();
                                }

                                if ((mask & EspLine) != 0)
                                {
                                    Vector2 start = new Vector2((float)screenWidth * 0.5f, (float)screenHeight - 2f);
                                    Vector2 end = new Vector2(left + width * 0.5f, top + height * 0.5f);

                                    GL.PushMatrix();
                                    GL.LoadOrtho();
                                    GL.Begin(1);
                                    GL.Color(new Color(0.42f, 0.7f, 0.86f, 1f));
                                    GL.Vertex3(start.x / (float)screenWidth, 1f - start.y / (float)screenHeight, 0f);
                                    GL.Vertex3(end.x / (float)screenWidth, 1f - end.y / (float)screenHeight, 0f);
                                    GL.End();
                                    GL.PopMatrix();
                                }

                                if ((mask & EspSkeleton) != 0)
                                {
                                    Vector2 head2d = new Vector2(left + width * 0.5f, top);
                                    Vector2 body2d = new Vector2(left + width * 0.5f, top + height * 0.6f);
                                    Vector2 leftLeg = new Vector2(left + width * 0.2f, top + height);
                                    Vector2 rightLeg = new Vector2(left + width * 0.8f, top + height);
                                    Vector2 leftArm = new Vector2(left + 2f, top + height * 0.45f);
                                    Vector2 rightArm = new Vector2(left + width - 2f, top + height * 0.45f);

                                    GL.PushMatrix();
                                    GL.LoadOrtho();
                                    GL.Begin(1);
                                    GL.Color(new Color(0.9f, 0.85f, 0.3f, 1f));
                                    GL.Vertex3(head2d.x / (float)screenWidth, 1f - head2d.y / (float)screenHeight, 0f);
                                    GL.Vertex3(body2d.x / (float)screenWidth, 1f - body2d.y / (float)screenHeight, 0f);
                                    GL.Vertex3(body2d.x / (float)screenWidth, 1f - body2d.y / (float)screenHeight, 0f);
                                    GL.Vertex3(leftArm.x / (float)screenWidth, 1f - leftArm.y / (float)screenHeight, 0f);
                                    GL.Vertex3(body2d.x / (float)screenWidth, 1f - body2d.y / (float)screenHeight, 0f);
                                    GL.Vertex3(rightArm.x / (float)screenWidth, 1f - rightArm.y / (float)screenHeight, 0f);
                                    GL.Vertex3(body2d.x / (float)screenWidth, 1f - body2d.y / (float)screenHeight, 0f);
                                    GL.Vertex3(leftLeg.x / (float)screenWidth, 1f - leftLeg.y / (float)screenHeight, 0f);
                                    GL.Vertex3(body2d.x / (float)screenWidth, 1f - body2d.y / (float)screenHeight, 0f);
                                    GL.Vertex3(rightLeg.x / (float)screenWidth, 1f - rightLeg.y / (float)screenHeight, 0f);
                                    GL.End();
                                    GL.PopMatrix();
                                }

                                if ((mask & Esp360Arrows) != 0)
                                {
                                    Vector2 center = new Vector2((float)screenWidth * 0.5f, (float)screenHeight * 0.5f);
                                    Vector2 dir = new Vector2(left + width * 0.5f - center.x, top + height * 0.5f - center.y);
                                    float magnitude = dir.magnitude;
                                    if (magnitude > 5f)
                                    {
                                        dir = dir / magnitude;
                                        Vector2 arrowEnd = center + dir * 36f;
                                        GL.PushMatrix();
                                        GL.LoadOrtho();
                                        GL.Begin(1);
                                        GL.Color(new Color(0.42f, 0.85f, 0.95f, 1f));
                                        GL.Vertex3(center.x / (float)screenWidth, 1f - center.y / (float)screenHeight, 0f);
                                        GL.Vertex3(arrowEnd.x / (float)screenWidth, 1f - arrowEnd.y / (float)screenHeight, 0f);
                                        GL.End();
                                        GL.PopMatrix();
                                    }
                                }

                                if ((mask & EnemyCount) != 0)
                                {
                                    int enemyCount = 0;
                                    for (int countIndex = 0; countIndex < players.Count; countIndex++)
                                    {
                                        Player enemy = players[countIndex] as Player;
                                        if (enemy != null && enemy.gameObject != null && enemy.gameObject.activeInHierarchy
                                            && !enemy.IsLocalPlayer() && !enemy.IsLocalTeammate(false) && enemy.IsVisible())
                                        {
                                            enemyCount++;
                                        }
                                    }
                                    GUI.color = new Color(1f, 1f, 1f, 1f);
                                    GUI.Label(new Rect(12f, 45f, 200f, 20f), "Enemies: " + enemyCount, rowStyle);
                                }

                                if ((mask & EspFov) != 0)
                                {
                                    Vector2 center = new Vector2((float)screenWidth * 0.5f, (float)screenHeight * 0.5f);
                                    GUI.color = new Color(0.4f, 0.7f, 0.9f, 0.25f);
                                    GUI.DrawTexture(new Rect(center.x - AimbotFov, center.y - AimbotFov, AimbotFov * 2f, AimbotFov * 2f), Texture2D.whiteTexture);
                                }

                                if ((mask & SniperScope) != 0)
                                {
                                    Vector2 center = new Vector2((float)screenWidth * 0.5f, (float)screenHeight * 0.5f);
                                    GUI.color = new Color(0.2f, 0.2f, 0.2f, 0.75f);
                                    GUI.DrawTexture(new Rect(center.x - 20f, center.y - 1f, 40f, 2f), pixel);
                                    GUI.DrawTexture(new Rect(center.x - 1f, center.y - 20f, 2f, 40f), pixel);
                                }

                                if ((mask & EspHealth) != 0)
                                {
                                    float healthRatio = maximumHealth > 0
                                        ? Mathf.Clamp01((float)health / (float)maximumHealth)
                                        : 0f;
                                    float healthBarWidth = 5f;
                                    float healthX = left - 8f;
                                    GUI.color = new Color(0.12f, 0.12f, 0.12f, 0.9f);
                                    GUI.DrawTexture(new Rect(healthX, top, healthBarWidth, height), pixel);

                                    Color healthColor = Color.Lerp(
                                        Color.red,
                                        Color.green,
                                        healthRatio);
                                    GUI.color = healthColor;
                                    GUI.DrawTexture(new Rect(
                                        healthX + 1f,
                                        top + height - (height * healthRatio),
                                        healthBarWidth - 2f,
                                        Mathf.Max(2f, height * healthRatio)), pixel);
                                }

                                float labelScale = 0.72f;
                                if ((mask & EspName) != 0)
                                {
                                    string nickname = player.NickName;
                                    if (nickname == null) nickname = "?";
                                    GUI.color = dying
                                        ? new Color(1f, 0f, 0f, 1f)
                                        : new Color(1f, 1f, 0f, 1f);
                                    float nicknameWidth = Mathf.Clamp(
                                        (float)nickname.Length * 6.2f, width, 220f);
                                    GUI.matrix = Matrix4x4.TRS(
                                        new Vector3(
                                            left + width * 0.5f - nicknameWidth * 0.5f,
                                            top - 14f,
                                            0f),
                                        Quaternion.identity,
                                        new Vector3(labelScale, labelScale, 1f));
                                    GUI.Label(new Rect(
                                        0f, 0f,
                                        nicknameWidth / labelScale,
                                        18f / labelScale), nickname);
                                    GUI.matrix = Matrix4x4.identity;
                                }

                                if ((mask & EspDistance) != 0)
                                {
                                    int distanceValue = (int)distance;
                                    if (distanceValue < 0) distanceValue = 0;
                                    if (distanceValue > 999) distanceValue = 999;
                                    int digitCount = distanceValue >= 100 ? 3
                                        : (distanceValue >= 10 ? 2 : 1);
                                    float glyphWidth = 6f;
                                    float glyphHeight = 10f;
                                    float glyphThickness = 1.5f;
                                    float glyphAdvance = 8f;
                                    float meterWidth = 7f;
                                    float distanceWidth = digitCount * glyphAdvance
                                        + meterWidth + 2f;
                                    float distanceX = left + width * 0.5f
                                        - distanceWidth * 0.5f;
                                    float distanceY = top + height + 5f;
                                    GUI.color = Color.white;
                                    int divisor = digitCount == 3 ? 100
                                        : (digitCount == 2 ? 10 : 1);
                                    for (int digitIndex = 0; digitIndex < digitCount; digitIndex++)
                                    {
                                        int digit = (distanceValue / divisor) % 10;
                                        int segments = digit == 0 ? 63
                                            : (digit == 1 ? 6
                                            : (digit == 2 ? 91
                                            : (digit == 3 ? 79
                                            : (digit == 4 ? 102
                                            : (digit == 5 ? 109
                                            : (digit == 6 ? 125
                                            : (digit == 7 ? 7
                                            : (digit == 8 ? 127 : 111))))))));
                                        float glyphX = distanceX + digitIndex * glyphAdvance;
                                        float middleY = distanceY + glyphHeight * 0.5f
                                            - glyphThickness * 0.5f;
                                        if ((segments & 1) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX, distanceY, glyphWidth, glyphThickness), pixel);
                                        if ((segments & 2) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX + glyphWidth - glyphThickness,
                                                distanceY, glyphThickness, glyphHeight * 0.5f), pixel);
                                        if ((segments & 4) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX + glyphWidth - glyphThickness,
                                                middleY, glyphThickness, glyphHeight * 0.5f), pixel);
                                        if ((segments & 8) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX, distanceY + glyphHeight - glyphThickness,
                                                glyphWidth, glyphThickness), pixel);
                                        if ((segments & 16) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX, middleY, glyphThickness, glyphHeight * 0.5f), pixel);
                                        if ((segments & 32) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX, distanceY, glyphThickness, glyphHeight * 0.5f), pixel);
                                        if ((segments & 64) != 0)
                                            GUI.DrawTexture(new Rect(
                                                glyphX, middleY, glyphWidth, glyphThickness), pixel);
                                        divisor /= 10;
                                    }
                                    float meterX = distanceX + digitCount * glyphAdvance + 1f;
                                    float meterY = distanceY + 2f;
                                    GUI.DrawTexture(new Rect(
                                        meterX, meterY, glyphThickness, glyphHeight - 2f), pixel);
                                    GUI.DrawTexture(new Rect(
                                        meterX + 3f, meterY, glyphThickness, glyphHeight - 2f), pixel);
                                    GUI.DrawTexture(new Rect(
                                        meterX + glyphThickness, meterY,
                                        2f, glyphThickness), pixel);
                                    GUI.DrawTexture(new Rect(
                                        meterX + glyphThickness, meterY + 4f,
                                        2f, glyphThickness), pixel);
                                    GUI.matrix = Matrix4x4.identity;
                                }
                                }
                                catch (Exception)
                                {
                                    // A recycled entity is skipped without aborting the frame.
                                }
                            }
                        }
                    }

                    if (menuOpen)
                    {
                        GUI.matrix = Matrix4x4.identity;
                        PrepareMenuStyles(uiScale);

                        GUI.color = new Color(0.035f, 0.04f, 0.043f, 0.98f);
                        GUI.DrawTexture(panelRect, pixel);
                        GUI.color = new Color(0.11f, 0.13f, 0.12f, 1f);
                        GUI.DrawTexture(headerRect, pixel);
                        GUI.color = new Color(0.42f, 0.68f, 0.60f, 0.9f);
                        GUI.DrawTexture(new Rect(
                            panelX, panelY, panelWidth, 2f * uiScale), pixel);
                        GUI.DrawTexture(new Rect(
                            panelX, panelY, 1f * uiScale, panelHeight), pixel);
                        GUI.DrawTexture(new Rect(
                            panelX + panelWidth - 1f * uiScale,
                            panelY, 1f * uiScale, panelHeight), pixel);
                        GUI.DrawTexture(new Rect(
                            panelX, panelY + panelHeight - 1f * uiScale,
                            panelWidth, 1f * uiScale), pixel);

                        int enabledCount = 0;
                        for (int index = 1; index < EspBits.Length; index++)
                        {
                            if ((mask & EspBits[index]) != 0) enabledCount++;
                        }
                        string statusText = (mask & EspMaster) != 0
                            ? enabledCount + " FEATURES ON  |  DRAG HEADER TO MOVE"
                            : "ESP OFF  |  DRAG HEADER TO MOVE";

                        GUI.color = Color.white;
                        GUI.Label(new Rect(
                            panelX + 18f * uiScale, panelY + 5f * uiScale,
                            panelWidth - 72f * uiScale, 25f * uiScale),
                            "ESP SETTINGS", titleStyle);
                        GUI.Label(new Rect(
                            panelX + 18f * uiScale, panelY + 30f * uiScale,
                            panelWidth - 72f * uiScale, 17f * uiScale),
                            statusText, hintStyle);

                        GUI.color = new Color(0.15f, 0.18f, 0.17f, 1f);
                        GUI.DrawTexture(closeRect, pixel);
                        GUI.color = Color.white;
                        GUI.Label(closeRect, "X", closeStyle);

                        for (int row = 0; row < rowCount; row++)
                        {
                            Rect rowRect;
                            if (row == 0) rowRect = row1Rect;
                            else if (row == 1) rowRect = row2Rect;
                            else if (row == 2) rowRect = row3Rect;
                            else if (row == 3) rowRect = row4Rect;
                            else if (row == 4) rowRect = row5Rect;
                            else if (row == 5) rowRect = row6Rect;
                            else if (row == 6) rowRect = row7Rect;
                            else if (row == 7) rowRect = row8Rect;
                            else if (row == 8) rowRect = row9Rect;
                            else if (row == 9) rowRect = row10Rect;
                            else if (row == 10) rowRect = row11Rect;
                            else if (row == 11) rowRect = row12Rect;
                            else rowRect = row13Rect;

                            bool enabled = (mask & EspBits[row]) != 0;
                            GUI.color = enabled
                                ? new Color(0.075f, 0.105f, 0.095f, 1f)
                                : new Color(0.055f, 0.062f, 0.062f, 1f);
                            GUI.DrawTexture(rowRect, pixel);
                            GUI.color = enabled
                                ? new Color(0.42f, 0.68f, 0.60f, 0.9f)
                                : new Color(0.20f, 0.23f, 0.22f, 1f);
                            GUI.DrawTexture(new Rect(
                                rowRect.x, rowRect.y, 2f * uiScale, rowRect.height), pixel);

                            rowStyle.normal.textColor = enabled
                                ? new Color(0.94f, 0.96f, 0.93f, 1f)
                                : new Color(0.72f, 0.76f, 0.73f, 1f);
                            GUI.color = Color.white;
                            GUI.Label(new Rect(
                                rowRect.x + 14f * uiScale, rowRect.y,
                                rowRect.width - 90f * uiScale, rowRect.height),
                                EspLabels[row], rowStyle);

                            float switchWidth = 52f * uiScale;
                            float switchHeight = 26f * uiScale;
                            Rect track = new Rect(
                                rowRect.x + rowRect.width - switchWidth - 8f * uiScale,
                                rowRect.y + (rowRect.height - switchHeight) * 0.5f,
                                switchWidth, switchHeight);
                            GUI.color = enabled
                                ? new Color(0.31f, 0.57f, 0.49f, 1f)
                                : new Color(0.13f, 0.15f, 0.15f, 1f);
                            GUI.DrawTexture(track, pixel);
                            GUI.color = enabled
                                ? new Color(0.06f, 0.10f, 0.09f, 1f)
                                : new Color(0.68f, 0.72f, 0.69f, 1f);
                            float knobSize = 20f * uiScale;
                            float knobX = enabled
                                ? track.x + track.width - knobSize - 3f * uiScale
                                : track.x + 3f * uiScale;
                            GUI.DrawTexture(new Rect(
                                knobX, track.y + (track.height - knobSize) * 0.5f,
                                knobSize, knobSize), pixel);
                        }

                        GUI.color = new Color(0.31f, 0.57f, 0.49f, 1f);
                        GUI.DrawTexture(resetRect, pixel);
                        GUI.color = new Color(0.06f, 0.10f, 0.09f, 1f);
                        GUI.Label(resetRect, "ENABLE ALL", buttonStyle);

                        GUI.color = new Color(0.075f, 0.085f, 0.082f, 1f);
                        GUI.DrawTexture(hideRect, pixel);
                        GUI.color = new Color(0.80f, 0.84f, 0.81f, 1f);
                        GUI.Label(hideRect, "HIDE MENU", buttonStyle);
                    }
                }
            }
            catch (Exception)
            {
                // A transient Unity object is skipped for this event.
            }

            GUI.matrix = savedMatrix;
            GUI.color = savedColor;
        }
    }
}
