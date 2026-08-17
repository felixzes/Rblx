-- ═══════════════════════════════════════════════
--  KYOTO COMBO — Mobile-Optimized
--  Recorder + Playback + Thumb-Friendly UI
--  Executor: Synapse X / KRNL / Fluxus
-- ═══════════════════════════════════════════════

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ─── Detect Mobile ──────────────────────────────
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ─── Config ─────────────────────────────────────
local CONFIG = {
    M1_DELAY       = 0.045,
    ABILITY_OFFSET = 0.03,
    BLOCK_BYPASS   = 0.012,
    RESET_WINDOW   = 0.08,
    RECORD_KEYS    = { "Q", "E", "R", "F" },
}

-- ─── Built-in Kyoto Sequence ────────────────────
local KYOTO_COMBO = {
    { "M1", 0.045 },
    { "M1", 0.045 },
    { "M1", 0.045 },
    { "Q",  CONFIG.ABILITY_OFFSET },
    { "M1", 0.038 },
    { "M1", 0.038 },
    { "E",  CONFIG.ABILITY_OFFSET },
    { "M1", 0.042 },
    { "R",  CONFIG.ABILITY_OFFSET },
    { "M1", 0.040 },
    { "M1", 0.040 },
    { "F",  CONFIG.ABILITY_OFFSET },
    { "M1", 0.038 },
    { "M1", 0.038 },
    { "M1", 0.038 },
}

-- ─── Input Layer ────────────────────────────────
local function fireM1()
    mouse1click()
end

local function fireKey(key)
    local kc = Enum.KeyCode[key]
    if kc then
        keypress(kc.Value)
        task.wait(CONFIG.BLOCK_BYPASS)
        keyrelease(kc.Value)
    end
end

local function executeAction(action)
    if action == "M1" then fireM1()
    else fireKey(action) end
end

-- ─── Combo Engine ───────────────────────────────
local ComboState = { active = false, running = false }

local function runSequence(sequence, onDone)
    ComboState.active  = true
    ComboState.running = true
    task.spawn(function()
        while ComboState.active and ComboState.running do
            for _, step in ipairs(sequence) do
                if not ComboState.active or not ComboState.running then break end
                executeAction(step[1])
                task.wait(step[2])
            end
            task.wait(CONFIG.RESET_WINDOW)
        end
        ComboState.active = false
        if onDone then onDone() end
    end)
end

local function stopCombo()
    ComboState.running = false
    ComboState.active  = false
end

-- ─── Recorder ───────────────────────────────────
local Recorder = {
    recording   = false,
    sequence    = {},
    lastTime    = nil,
    connections = {},
}

function Recorder:start()
    self.recording = true
    self.sequence  = {}
    self.lastTime  = tick()

    local keySet = {}
    for _, k in ipairs(CONFIG.RECORD_KEYS) do keySet[k] = true end

    local m1Conn = UserInputService.InputBegan:Connect(function(input)
        if not self.recording then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            local now   = tick()
            local delay = now - self.lastTime
            self.lastTime = now
            table.insert(self.sequence, { "M1", math.floor(delay * 1000) / 1000 })
        end
    end)

    local keyConn = UserInputService.InputBegan:Connect(function(input)
        if not self.recording then return end
        local name = input.KeyCode.Name
        if keySet[name] then
            local now   = tick()
            local delay = now - self.lastTime
            self.lastTime = now
            table.insert(self.sequence, { name, math.floor(delay * 1000) / 1000 })
        end
    end)

    table.insert(self.connections, m1Conn)
    table.insert(self.connections, keyConn)
end

function Recorder:stop()
    self.recording = false
    for _, conn in ipairs(self.connections) do conn:Disconnect() end
    self.connections = {}
end

function Recorder:hasData()
    return #self.sequence > 0
end

function Recorder:getSequence()
    return self.sequence
end

-- ─── GUI ────────────────────────────────────────
-- Mobile layout targets:
--   Panel  : 220 × 320 px, anchored bottom-right (away from thumbstick)
--   Buttons: 48 px tall minimum (Apple HIG / Google MD touch target)
--   Drag   : dedicated 36 px handle at top, rest of panel is action-safe
--   Font   : GothamBold 13 on buttons, Gotham 11 on status — legible at arm's length
--   Spacing: 10 px gutter, 8 px between buttons — no accidental taps

local function makeGui()
    local old = PlayerGui:FindFirstChild("KyotoMobileUI")
    if old then old:Destroy() end

    -- ── Root ─────────────────────────────────────
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name           = "KyotoMobileUI"
    ScreenGui.ResetOnSpawn   = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent         = PlayerGui

    -- ── Panel ────────────────────────────────────
    -- Anchored bottom-right: clear of left-thumb joystick, right-thumb jump area padded 20 px
    local PANEL_W = 220
    local PANEL_H = 320
    local MARGIN  = 20

    local Frame = Instance.new("Frame")
    Frame.Name                   = "Panel"
    Frame.Size                   = UDim2.new(0, PANEL_W, 0, PANEL_H)
    Frame.Position               = UDim2.new(1, -(PANEL_W + MARGIN), 1, -(PANEL_H + MARGIN))
    Frame.AnchorPoint            = Vector2.new(0, 0)
    Frame.BackgroundColor3       = Color3.fromRGB(10, 10, 16)
    Frame.BackgroundTransparency = 0.08
    Frame.BorderSizePixel        = 0
    Frame.Active                 = true
    Frame.Draggable              = false   -- manual drag on handle only
    Frame.Parent                 = ScreenGui
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 14)

    local Stroke = Instance.new("UIStroke", Frame)
    Stroke.Color        = Color3.fromRGB(139, 92, 246)
    Stroke.Thickness    = 1.8
    Stroke.Transparency = 0.3

    -- ── Drag Handle (top 36 px only) ─────────────
    -- Separates intentional drag from accidental swipe across buttons
    local Handle = Instance.new("Frame")
    Handle.Name                   = "DragHandle"
    Handle.Size                   = UDim2.new(1, 0, 0, 36)
    Handle.Position               = UDim2.new(0, 0, 0, 0)
    Handle.BackgroundColor3       = Color3.fromRGB(20, 12, 38)
    Handle.BackgroundTransparency = 0.0
    Handle.BorderSizePixel        = 0
    Handle.Active                 = true
    Handle.ZIndex                 = 5
    Handle.Parent                 = Frame
    Instance.new("UICorner", Handle).CornerRadius = UDim.new(0, 14)

    -- Grip dots
    local GripLabel = Instance.new("TextLabel", Handle)
    GripLabel.Size                   = UDim2.new(1, 0, 1, 0)
    GripLabel.BackgroundTransparency = 1
    GripLabel.Text                   = "· · ·"
    GripLabel.TextColor3             = Color3.fromRGB(139, 92, 246)
    GripLabel.TextSize               = 14
    GripLabel.Font                   = Enum.Font.GothamBold
    GripLabel.TextXAlignment         = Enum.TextXAlignment.Center
    GripLabel.TextYAlignment         = Enum.TextYAlignment.Center
    GripLabel.ZIndex                 = 6

    -- Title beside grip
    local Title = Instance.new("TextLabel", Handle)
    Title.Size                   = UDim2.new(0.7, 0, 1, 0)
    Title.Position               = UDim2.new(0.15, 0, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text                   = "⚔  KYOTO"
    Title.TextColor3             = Color3.fromRGB(167, 139, 250)
    Title.TextSize               = 13
    Title.Font                   = Enum.Font.GothamBold
    Title.TextXAlignment         = Enum.TextXAlignment.Center
    Title.ZIndex                 = 6

    -- Manual drag via Handle
    do
        local dragging, dragStart, startPos = false, nil, nil

        Handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or
               input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging  = true
                dragStart = input.Position
                startPos  = Frame.Position
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.Touch or
               input.UserInputType == Enum.UserInputType.MouseMove then
                local delta = input.Position - dragStart
                Frame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or
               input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
    end

    -- ── Status bar ───────────────────────────────
    local StatusBar = Instance.new("Frame", Frame)
    StatusBar.Size                   = UDim2.new(1, -20, 0, 30)
    StatusBar.Position               = UDim2.new(0, 10, 0, 42)
    StatusBar.BackgroundColor3       = Color3.fromRGB(20, 18, 32)
    StatusBar.BackgroundTransparency = 0.2
    StatusBar.BorderSizePixel        = 0
    Instance.new("UICorner", StatusBar).CornerRadius = UDim.new(0, 8)

    local Status = Instance.new("TextLabel", StatusBar)
    Status.Size                   = UDim2.new(1, -10, 1, 0)
    Status.Position               = UDim2.new(0, 8, 0, 0)
    Status.BackgroundTransparency = 1
    Status.Text                   = "● IDLE"
    Status.TextColor3             = Color3.fromRGB(100, 100, 140)
    Status.TextSize               = 11
    Status.Font                   = Enum.Font.GothamBold
    Status.TextXAlignment         = Enum.TextXAlignment.Left
    Status.TextYAlignment         = Enum.TextYAlignment.Center

    -- ── Steps counter ────────────────────────────
    local RecLabel = Instance.new("TextLabel", Frame)
    RecLabel.Size                   = UDim2.new(1, -20, 0, 16)
    RecLabel.Position               = UDim2.new(0, 10, 0, 78)
    RecLabel.BackgroundTransparency = 1
    RecLabel.Text                   = "Recorded: 0 steps"
    RecLabel.TextColor3             = Color3.fromRGB(80, 80, 110)
    RecLabel.TextSize               = 10
    RecLabel.Font                   = Enum.Font.Gotham
    RecLabel.TextXAlignment         = Enum.TextXAlignment.Left

    -- ── Button factory ───────────────────────────
    -- 48 px height — meets mobile touch target spec
    -- 10 px horizontal padding, 8 px gap between buttons
    local BTN_H   = 48
    local BTN_GAP = 8
    local BTN_Y0  = 100   -- first button top

    local function makeBtn(label, color, index, cb)
        local posY = BTN_Y0 + (index - 1) * (BTN_H + BTN_GAP)

        local Btn = Instance.new("TextButton", Frame)
        Btn.Size                   = UDim2.new(1, -20, 0, BTN_H)
        Btn.Position               = UDim2.new(0, 10, 0, posY)
        Btn.BackgroundColor3       = color
        Btn.BackgroundTransparency = 0.22
        Btn.BorderSizePixel        = 0
        Btn.Text                   = label
        Btn.TextColor3             = Color3.fromRGB(230, 220, 255)
        Btn.TextSize               = 13
        Btn.Font                   = Enum.Font.GothamBold
        Btn.AutoButtonColor        = false
        Btn.ZIndex                 = 4
        Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 10)

        -- Subtle inner highlight line
        local Highlight = Instance.new("Frame", Btn)
        Highlight.Size                   = UDim2.new(0.6, 0, 0, 1)
        Highlight.Position               = UDim2.new(0.2, 0, 0, 2)
        Highlight.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
        Highlight.BackgroundTransparency = 0.82
        Highlight.BorderSizePixel        = 0
        Highlight.ZIndex                 = 5
        Instance.new("UICorner", Highlight).CornerRadius = UDim.new(1, 0)

        -- Press / release tween
        local pressDown = TweenInfo.new(0.06, Enum.EasingStyle.Quad)
        local pressUp   = TweenInfo.new(0.12, Enum.EasingStyle.Quad)

        Btn.MouseButton1Down:Connect(function()
            TweenService:Create(Btn, pressDown, {
                BackgroundTransparency = 0.05,
                Size = UDim2.new(0.96, -20 * 0.96, 0, BTN_H - 2),
                Position = UDim2.new(0.02, 0, 0, posY + 1),
            }):Play()
            cb()
        end)
        Btn.MouseButton1Up:Connect(function()
            TweenService:Create(Btn, pressUp, {
                BackgroundTransparency = 0.22,
                Size = UDim2.new(1, -20, 0, BTN_H),
                Position = UDim2.new(0, 10, 0, posY),
            }):Play()
        end)

        -- Touch equivalents
        Btn.TouchLongPress:Connect(function() end)  -- absorb to prevent accidental drag-through

        return Btn
    end

    -- ── Helpers ──────────────────────────────────
    local function setStatus(text, color)
        Status.Text       = text
        Status.TextColor3 = color
    end

    local function updateRecLabel()
        RecLabel.Text = "Recorded: " .. #Recorder:getSequence() .. " steps"
    end

    local activeSequence = KYOTO_COMBO

    -- ── Button 1 — Play Kyoto (built-in) ─────────
    makeBtn("▶  PLAY KYOTO", Color3.fromRGB(109, 40, 217), 1, function()
        if ComboState.active then stopCombo() end
        activeSequence = KYOTO_COMBO
        setStatus("● RUNNING  [KYOTO]", Color3.fromRGB(134, 239, 172))
        runSequence(activeSequence, function()
            setStatus("● IDLE", Color3.fromRGB(100, 100, 140))
        end)
    end)

    -- ── Button 2 — Record toggle ──────────────────
    local recActive = false
    local recBtn = makeBtn("⏺  RECORD", Color3.fromRGB(180, 40, 40), 2, function() end)

    -- Override cb to self-reference the button
    recBtn.MouseButton1Down:Connect(function()
        if not recActive then
            recActive = true
            Recorder:start()
            recBtn.Text = "⏹  STOP REC"
            setStatus("⏺ RECORDING...", Color3.fromRGB(248, 113, 113))
        else
            recActive = false
            Recorder:stop()
            updateRecLabel()
            recBtn.Text = "⏺  RECORD"
            if Recorder:hasData() then
                setStatus("● " .. #Recorder:getSequence() .. " steps saved", Color3.fromRGB(251, 191, 36))
            else
                setStatus("● IDLE  (nothing)", Color3.fromRGB(100, 100, 140))
            end
        end
    end)

    -- ── Button 3 — Play Recorded ──────────────────
    makeBtn("▶  PLAY REC", Color3.fromRGB(20, 120, 80), 3, function()
        if not Recorder:hasData() then
            setStatus("⚠ Record first", Color3.fromRGB(251, 191, 36))
            return
        end
        if ComboState.active then stopCombo() end
        activeSequence = Recorder:getSequence()
        setStatus("● RUNNING  [REC]", Color3.fromRGB(134, 239, 172))
        runSequence(activeSequence, function()
            setStatus("● IDLE", Color3.fromRGB(100, 100, 140))
        end)
    end)

    -- ── Button 4 — Stop ───────────────────────────
    makeBtn("■  STOP", Color3.fromRGB(140, 20, 50), 4, function()
        stopCombo()
        if recActive then
            recActive = false
            Recorder:stop()
            updateRecLabel()
            recBtn.Text = "⏺  RECORD"
        end
        setStatus("● IDLE", Color3.fromRGB(100, 100, 140))
    end)

    -- ── Minimize toggle ───────────────────────────
    -- Collapses panel to handle-only strip — frees screen real estate mid-match
    local minimized = false
    local fullH     = PANEL_H

    local MinBtn = Instance.new("TextButton", Handle)
    MinBtn.Size                   = UDim2.new(0, 28, 0, 22)
    MinBtn.Position               = UDim2.new(1, -32, 0.5, -11)
    MinBtn.BackgroundColor3       = Color3.fromRGB(60, 30, 90)
    MinBtn.BackgroundTransparency = 0.3
    MinBtn.BorderSizePixel        = 0
    MinBtn.Text                   = "—"
    MinBtn.TextColor3             = Color3.fromRGB(200, 170, 255)
    MinBtn.TextSize               = 12
    MinBtn.Font                   = Enum.Font.GothamBold
    MinBtn.ZIndex                 = 8
    Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

    MinBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        local targetH = minimized and 36 or fullH
        MinBtn.Text   = minimized and "+" or "—"

        TweenService:Create(Frame,
            TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, PANEL_W, 0, targetH) }
        ):Play()
    end)
end

-- ─── Init ───────────────────────────────────────
makeGui()
print("[KYOTO COMBO] Mobile UI active — drag handle to reposition, — to minimize")
