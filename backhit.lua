-- ============================================================
-- THE STRONGEST BATTLEGROUNDS | CAMLOCK PRO
-- Tight back lock | Dodge & Return | Modern Tactical GUI
-- Execute via Synapse X, KRNL, or equivalent
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ============================================================
-- CONFIG
-- ============================================================

local CFG = {
    BEHIND_DISTANCE = 1.2,
    CAM_DISTANCE    = 14,
    CAM_HEIGHT      = 5.5,
    CAM_SMOOTHING   = 0.10,
    TOGGLE_KEY      = Enum.KeyCode.RightShift,
    DODGE_DISTANCE  = 22,
    DODGE_DURATION  = 0.35,
    DODGE_COOLDOWN  = 0.5,
    HP_THRESHOLD    = 2,
}

-- ============================================================
-- STATE
-- ============================================================

local locked    = false
local target    = nil
local dodging   = false
local lastDodge = 0
local lastHP    = nil
local dodgeSide = 1

-- ============================================================
-- PALETTE
-- ============================================================

local C = {
    BG          = Color3.fromRGB(10,  11,  15),
    SURFACE     = Color3.fromRGB(16,  18,  24),
    PANEL       = Color3.fromRGB(20,  22,  30),
    BORDER      = Color3.fromRGB(35,  38,  52),
    ACCENT      = Color3.fromRGB(99,  102, 241),   -- indigo
    ACCENT_HOT  = Color3.fromRGB(239, 68,  68),    -- red when locked
    ACCENT_GLOW = Color3.fromRGB(129, 132, 255),
    TEXT_HI     = Color3.fromRGB(240, 241, 255),
    TEXT_MID    = Color3.fromRGB(140, 143, 175),
    TEXT_DIM    = Color3.fromRGB(70,  74,  105),
    WHITE       = Color3.fromRGB(255, 255, 255),
    GREEN       = Color3.fromRGB(52,  211, 153),
    RED         = Color3.fromRGB(239, 68,  68),
}

-- ============================================================
-- GUI BUILDER HELPERS
-- ============================================================

local function make(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(radius, parent)
    return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(thickness, color, parent)
    return make("UIStroke", {
        Thickness    = thickness,
        Color        = color,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function gradient(c0, c1, rotation, parent)
    return make("UIGradient", {
        Color    = ColorSequence.new(c0, c1),
        Rotation = rotation,
    }, parent)
end

local function tween(inst, info, props)
    TweenService:Create(inst, info, props):Play()
end

local FAST  = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local MED   = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLOW  = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ============================================================
-- ROOT GUI
-- ============================================================

local ScreenGui = make("ScreenGui", {
    Name             = "CamLockPro",
    ResetOnSpawn     = false,
    ZIndexBehavior   = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset   = true,
}, LocalPlayer:WaitForChild("PlayerGui"))

-- ============================================================
-- MAIN WINDOW
-- ============================================================

local Window = make("Frame", {
    Size                  = UDim2.new(0, 280, 0, 340),
    Position              = UDim2.new(0, 24, 0.5, -170),
    BackgroundColor3      = C.BG,
    BorderSizePixel       = 0,
    ClipsDescendants      = true,
}, ScreenGui)
corner(16, Window)
stroke(1, C.BORDER, Window)

-- Subtle top-edge accent line
local TopAccent = make("Frame", {
    Size             = UDim2.new(1, 0, 0, 2),
    Position         = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = C.ACCENT,
    BorderSizePixel  = 0,
}, Window)
corner(2, TopAccent)
gradient(C.ACCENT, C.ACCENT_GLOW, 90, TopAccent)

-- Header bar
local Header = make("Frame", {
    Size             = UDim2.new(1, 0, 0, 52),
    Position         = UDim2.new(0, 0, 0, 2),
    BackgroundColor3 = C.SURFACE,
    BorderSizePixel  = 0,
}, Window)

local HeaderTitle = make("TextLabel", {
    Size             = UDim2.new(1, -20, 0, 20),
    Position         = UDim2.new(0, 16, 0, 10),
    BackgroundTransparency = 1,
    Text             = "CAMLOCK  PRO",
    TextColor3       = C.TEXT_HI,
    TextSize         = 13,
    Font             = Enum.Font.GothamBold,
    TextXAlignment   = Enum.TextXAlignment.Left,
    RichText         = true,
}, Header)

local HeaderSub = make("TextLabel", {
    Size             = UDim2.new(1, -20, 0, 14),
    Position         = UDim2.new(0, 16, 0, 30),
    BackgroundTransparency = 1,
    Text             = "The Strongest Battlegrounds",
    TextColor3       = C.TEXT_DIM,
    TextSize         = 10,
    Font             = Enum.Font.Gotham,
    TextXAlignment   = Enum.TextXAlignment.Left,
}, Header)

-- Status dot
local StatusDot = make("Frame", {
    Size             = UDim2.new(0, 8, 0, 8),
    Position         = UDim2.new(1, -20, 0, 22),
    BackgroundColor3 = C.TEXT_DIM,
    BorderSizePixel  = 0,
}, Header)
corner(99, StatusDot)

-- ============================================================
-- LOCK BUTTON (center hero)
-- ============================================================

local LockSection = make("Frame", {
    Size             = UDim2.new(1, -32, 0, 130),
    Position         = UDim2.new(0, 16, 0, 70),
    BackgroundColor3 = C.PANEL,
    BorderSizePixel  = 0,
}, Window)
corner(12, LockSection)
stroke(1, C.BORDER, LockSection)

-- Inner glow frame (shown when locked)
local LockGlow = make("Frame", {
    Size             = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = C.ACCENT_HOT,
    BackgroundTransparency = 1,
    BorderSizePixel  = 0,
}, LockSection)
corner(12, LockGlow)

local LockBtn = make("TextButton", {
    Size             = UDim2.new(0, 80, 0, 80),
    Position         = UDim2.new(0.5, -40, 0, 12),
    BackgroundColor3 = C.ACCENT,
    BorderSizePixel  = 0,
    Text             = "",
    AutoButtonColor  = false,
}, LockSection)
corner(99, LockBtn)

-- Lock icon (unicode lock)
local LockIcon = make("TextLabel", {
    Size             = UDim2.new(1, 0, 0, 44),
    Position         = UDim2.new(0, 0, 0, 14),
    BackgroundTransparency = 1,
    Text             = "🔒",
    TextSize         = 30,
    Font             = Enum.Font.GothamBold,
    TextColor3       = C.WHITE,
}, LockBtn)

local LockLabel = make("TextLabel", {
    Size             = UDim2.new(1, 0, 0, 16),
    Position         = UDim2.new(0, 0, 1, 8),
    BackgroundTransparency = 1,
    Text             = "INACTIVE",
    TextSize         = 10,
    Font             = Enum.Font.GothamBold,
    TextColor3       = C.TEXT_DIM,
    TextXAlignment   = Enum.TextXAlignment.Center,
}, LockSection)

local KeyHint = make("TextLabel", {
    Size             = UDim2.new(1, 0, 0, 12),
    Position         = UDim2.new(0, 0, 1, 26),
    BackgroundTransparency = 1,
    Text             = "RightShift  or  tap",
    TextSize         = 9,
    Font             = Enum.Font.Gotham,
    TextColor3       = C.TEXT_DIM,
    TextXAlignment   = Enum.TextXAlignment.Center,
}, LockSection)

-- ============================================================
-- STATS ROW
-- ============================================================

local StatsRow = make("Frame", {
    Size             = UDim2.new(1, -32, 0, 56),
    Position         = UDim2.new(0, 16, 0, 216),
    BackgroundColor3 = C.PANEL,
    BorderSizePixel  = 0,
}, Window)
corner(12, StatsRow)
stroke(1, C.BORDER, StatsRow)

local function statCell(label, value, xOffset, width)
    local cell = make("Frame", {
        Size             = UDim2.new(0, width, 1, 0),
        Position         = UDim2.new(0, xOffset, 0, 0),
        BackgroundTransparency = 1,
    }, StatsRow)

    make("TextLabel", {
        Size             = UDim2.new(1, 0, 0, 14),
        Position         = UDim2.new(0, 0, 0, 10),
        BackgroundTransparency = 1,
        Text             = value,
        TextSize         = 15,
        Font             = Enum.Font.GothamBold,
        TextColor3       = C.TEXT_HI,
        TextXAlignment   = Enum.TextXAlignment.Center,
    }, cell)

    make("TextLabel", {
        Size             = UDim2.new(1, 0, 0, 12),
        Position         = UDim2.new(0, 0, 0, 28),
        BackgroundTransparency = 1,
        Text             = label,
        TextSize         = 9,
        Font             = Enum.Font.Gotham,
        TextColor3       = C.TEXT_DIM,
        TextXAlignment   = Enum.TextXAlignment.Center,
    }, cell)

    return cell
end

local DodgeCountCell  = statCell("DODGES",  "0",  0,    80)
local TargetDistCell  = statCell("DIST",    "—",  80,   80)
local SessionCell     = statCell("SESSION", "0s", 160,  80)

local DodgeCountLabel = DodgeCountCell:FindFirstChildOfClass("TextLabel")
local TargetDistLabel = TargetDistCell:FindFirstChildOfClass("TextLabel")
local SessionLabel    = SessionCell:FindFirstChildOfClass("TextLabel")

-- Dividers
for _, x in ipairs({79, 159}) do
    make("Frame", {
        Size             = UDim2.new(0, 1, 0, 30),
        Position         = UDim2.new(0, x, 0, 13),
        BackgroundColor3 = C.BORDER,
        BorderSizePixel  = 0,
    }, StatsRow)
end

-- ============================================================
-- TARGET READOUT
-- ============================================================

local TargetBox = make("Frame", {
    Size             = UDim2.new(1, -32, 0, 36),
    Position         = UDim2.new(0, 16, 0, 286),
    BackgroundColor3 = C.PANEL,
    BorderSizePixel  = 0,
}, Window)
corner(10, TargetBox)
stroke(1, C.BORDER, TargetBox)

local TargetDot = make("Frame", {
    Size             = UDim2.new(0, 6, 0, 6),
    Position         = UDim2.new(0, 14, 0.5, -3),
    BackgroundColor3 = C.TEXT_DIM,
    BorderSizePixel  = 0,
}, TargetBox)
corner(99, TargetDot)

local TargetLabel = make("TextLabel", {
    Size             = UDim2.new(1, -40, 1, 0),
    Position         = UDim2.new(0, 28, 0, 0),
    BackgroundTransparency = 1,
    Text             = "No target",
    TextSize         = 11,
    Font             = Enum.Font.Gotham,
    TextColor3       = C.TEXT_DIM,
    TextXAlignment   = Enum.TextXAlignment.Left,
    TextTruncate     = Enum.TextTruncate.AtEnd,
}, TargetBox)

-- ============================================================
-- DRAG LOGIC (header drag zone)
-- ============================================================

local dragging, dragStart, winStart = false, nil, nil

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        winStart  = Window.Position
    end
end)

Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        local d = input.Position - dragStart
        Window.Position = UDim2.new(
            winStart.X.Scale, winStart.X.Offset + d.X,
            winStart.Y.Scale, winStart.Y.Offset + d.Y
        )
    end
end)

-- ============================================================
-- GUI STATE UPDATE
-- ============================================================

local dodgeCount   = 0
local sessionStart = nil

local function setLocked(state)
    locked = state

    if locked then
        -- Button → red
        tween(LockBtn,    FAST, { BackgroundColor3 = C.ACCENT_HOT })
        tween(LockGlow,   MED,  { BackgroundTransparency = 0.88 })
        tween(StatusDot,  FAST, { BackgroundColor3 = C.RED })
        tween(TopAccent,  FAST, { BackgroundColor3 = C.ACCENT_HOT })
        tween(TargetDot,  FAST, { BackgroundColor3 = C.GREEN })
        LockIcon.Text  = "🔓"
        LockLabel.Text = "LOCKED ON"
        LockLabel.TextColor3 = C.ACCENT_HOT
        sessionStart = tick()
    else
        tween(LockBtn,    FAST, { BackgroundColor3 = C.ACCENT })
        tween(LockGlow,   MED,  { BackgroundTransparency = 1 })
        tween(StatusDot,  FAST, { BackgroundColor3 = C.TEXT_DIM })
        tween(TopAccent,  FAST, { BackgroundColor3 = C.ACCENT })
        tween(TargetDot,  FAST, { BackgroundColor3 = C.TEXT_DIM })
        LockIcon.Text        = "🔒"
        LockLabel.Text       = "INACTIVE"
        LockLabel.TextColor3 = C.TEXT_DIM
        TargetLabel.Text     = "No target"
        TargetLabel.TextColor3 = C.TEXT_DIM
        sessionStart = nil
        dodgeCount   = 0
        DodgeCountLabel.Text = "0"
        TargetDistLabel.Text = "—"
        SessionLabel.Text    = "0s"
    end
end

local function pulseBtn()
    tween(LockBtn, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Size = UDim2.new(0, 72, 0, 72), Position = UDim2.new(0.5, -36, 0, 16) })
    task.delay(0.09, function()
        tween(LockBtn, TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, 80, 0, 80), Position = UDim2.new(0.5, -40, 0, 12) })
    end)
end

-- ============================================================
-- CORE LOGIC (unchanged from original — just rewired)
-- ============================================================

local function getNearestEnemy()
    local localChar = LocalPlayer.Character
    if not localChar then return nil end
    local localRoot = localChar:FindFirstChild("HumanoidRootPart")
    if not localRoot then return nil end
    local closest, closestDist = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                local hum  = char:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health > 0 then
                    local dist = (root.Position - localRoot.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest     = root
                    end
                end
            end
        end
    end
    return closest
end

local function getDodgeCFrame(targetCF)
    local flatLook  = Vector3.new(targetCF.LookVector.X, 0, targetCF.LookVector.Z).Unit
    local flatRight = flatLook:Cross(Vector3.new(0, 1, 0)) * -1
    local sideOff   = flatRight * (CFG.DODGE_DISTANCE * 0.6 * dodgeSide)
    local backOff   = flatLook  * -CFG.DODGE_DISTANCE
    dodgeSide       = dodgeSide * -1
    return CFrame.new(targetCF.Position + sideOff + backOff, targetCF.Position)
end

local function triggerDodge(targetCF, localRoot)
    local now = tick()
    if dodging or (now - lastDodge) < CFG.DODGE_COOLDOWN then return end
    dodging   = true
    lastDodge = now
    dodgeCount = dodgeCount + 1
    DodgeCountLabel.Text = tostring(dodgeCount)
    -- Flash dodge count green
    tween(DodgeCountLabel, FAST, { TextColor3 = C.GREEN })
    task.delay(0.4, function()
        tween(DodgeCountLabel, MED, { TextColor3 = C.TEXT_HI })
    end)
    localRoot.CFrame = getDodgeCFrame(targetCF)
    task.delay(CFG.DODGE_DURATION, function() dodging = false end)
end

local function toggleLock()
    if locked then
        locked  = false
        target  = nil
        dodging = false
        Camera.CameraType = Enum.CameraType.Custom
        setLocked(false)
    else
        target = getNearestEnemy()
        locked = true
        lastHP = nil
        Camera.CameraType = Enum.CameraType.Scriptable
        setLocked(true)
    end
    pulseBtn()
end

-- HP watcher
local function watchHP(humanoid, localRoot)
    humanoid.HealthChanged:Connect(function(newHP)
        if not locked then return end
        if lastHP == nil then lastHP = newHP return end
        local drop = lastHP - newHP
        lastHP = newHP
        if drop >= CFG.HP_THRESHOLD and target and target.Parent then
            triggerDodge(target.CFrame, localRoot)
        end
    end)
end

local function hookCharacter(char)
    local hum       = char:WaitForChild("Humanoid")
    local localRoot = char:WaitForChild("HumanoidRootPart")
    lastHP = hum.Health
    watchHP(hum, localRoot)
end

if LocalPlayer.Character then hookCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(char)
    dodging = false
    lastHP  = nil
    hookCharacter(char)
end)

-- ============================================================
-- INPUT
-- ============================================================

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CFG.TOGGLE_KEY then toggleLock() end
end)

LockBtn.MouseButton1Click:Connect(function() toggleLock() end)
LockBtn.TouchTap:Connect(function() toggleLock() end)

-- Hover glow
LockBtn.MouseEnter:Connect(function()
    tween(LockBtn, FAST, {
        BackgroundColor3 = locked and Color3.fromRGB(220, 50, 50) or C.ACCENT_GLOW
    })
end)
LockBtn.MouseLeave:Connect(function()
    tween(LockBtn, FAST, {
        BackgroundColor3 = locked and C.ACCENT_HOT or C.ACCENT
    })
end)

-- ============================================================
-- MAIN LOOP
-- ============================================================

RunService.RenderStepped:Connect(function()
    -- Session timer
    if sessionStart then
        local elapsed = math.floor(tick() - sessionStart)
        SessionLabel.Text = tostring(elapsed) .. "s"
    end

    if not locked then return end

    -- Retarget if lost
    if not target or not target.Parent then
        target = getNearestEnemy()
        if not target then
            Camera.CameraType = Enum.CameraType.Custom
            locked = false
            setLocked(false)
            return
        end
    end

    local localChar = LocalPlayer.Character
    if not localChar then return end
    local localRoot = localChar:FindFirstChild("HumanoidRootPart")
    if not localRoot then return end

    -- Update target readout
    local dist = math.floor((target.Position - localRoot.Position).Magnitude)
    TargetDistLabel.Text = tostring(dist) .. "s"
    local playerObj = Players:GetPlayerFromCharacter(target.Parent)
    if playerObj then
        TargetLabel.Text = playerObj.DisplayName
        TargetLabel.TextColor3 = C.TEXT_HI
        tween(TargetDot, FAST, { BackgroundColor3 = C.GREEN })
    end

    local targetCF  = target.CFrame
    local flatLook  = Vector3.new(targetCF.LookVector.X, 0, targetCF.LookVector.Z).Unit
    local flatRight = flatLook:Cross(Vector3.new(0, 1, 0)) * -1
    local flatUp    = Vector3.new(0, 1, 0)

    if not dodging then
        local backPos = targetCF.Position + (flatLook * -CFG.BEHIND_DISTANCE)
        localRoot.CFrame = CFrame.fromMatrix(backPos, flatRight, flatUp, flatLook * -1)
    end

    local refPos  = localRoot.Position
    local camPos  = refPos + (flatLook * -CFG.CAM_DISTANCE) + Vector3.new(0, CFG.CAM_HEIGHT, 0)
    local lookTgt = targetCF.Position + Vector3.new(0, CFG.CAM_HEIGHT * 0.35, 0)

    Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(camPos, lookTgt), CFG.CAM_SMOOTHING)
end)

print("[CamLock Pro] Loaded — RightShift or tap the button")