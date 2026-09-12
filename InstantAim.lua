--[[
    InstantAim — Silent Head-Lock
    Engine  : Roblox (executor environment)
    Author  : Zeus / DieStupidNinja
    Version : 1.0

    Behaviour:
      Hold the bind key (default: Q) → camera snaps INSTANTLY to the
      nearest enemy's head, every single frame. No lerp, no smoothing,
      no drift. The moment you press, you are on their head.

      Works through walls (FOV filtering optional).
      Targets the Head part → HumanoidRootPart fallback if no Head.
      Skips teammates (checks Teams service if available).
      Skips dead / nil characters.
      Silent-aim variant included — toggle S key for silent (bullet goes
      to head without moving your actual camera, useful for some games).

    Controls (change below):
      HOLD   Q → aim lock ON while held
      TOGGLE T → toggle aim lock on/off
      HOLD   E → silent aim (no cam movement, bullet redirected)
      Key    X → cycle FOV wall (off / 100 / 200 / full)
      Key    Z → toggle team check on/off
      Key    C → toggle head / torso target
]]

-- ═══════════════════════════════════════════════════════════════════════════
--  SETTINGS — edit these
-- ═══════════════════════════════════════════════════════════════════════════
local CFG = {
    -- keybinds
    HOLD_KEY      = Enum.KeyCode.Q,   -- hold to aim
    TOGGLE_KEY    = Enum.KeyCode.T,   -- toggle aim
    SILENT_KEY    = Enum.KeyCode.E,   -- hold for silent aim
    FOV_CYCLE_KEY = Enum.KeyCode.X,   -- cycle FOV limit
    TEAM_KEY      = Enum.KeyCode.Z,   -- toggle team check
    TARGET_KEY    = Enum.KeyCode.C,   -- toggle head / torso

    -- aim settings
    FOV_ENABLED   = true,             -- false = lock to anyone on screen
    FOV_RADIUS    = 200,              -- pixels from screen center (0 = fullscreen)
    TEAM_CHECK    = true,             -- skip teammates
    TARGET_PART   = "Head",          -- "Head" or "HumanoidRootPart"
    SMOOTHING     = 0,                -- 0 = instant. 1-10 = lerp frames (0 recommended)
    PREDICT       = true,             -- lead moving targets by velocity
    PREDICT_MULT  = 0.08,             -- how far ahead to lead (tune per game)
    VISIBLE_ONLY  = false,            -- only lock targets you can see (raycast)
}

-- FOV cycle order (pixels). 0 = no limit.
local FOV_CYCLE = {100, 200, 400, 0}
local fovCycleIdx = 2 -- starts at 200

-- ═══════════════════════════════════════════════════════════════════════════
--  Services
-- ═══════════════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Teams            = game:GetService("Teams")
local Workspace        = game:GetService("Workspace")
local GuiService       = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════════════════
--  State
-- ═══════════════════════════════════════════════════════════════════════════
local aiming       = false   -- toggle state
local silentActive = false
local lockedTarget = nil     -- Part (Head/HRP) of current lock
local lockedPlayer = nil

-- ═══════════════════════════════════════════════════════════════════════════
--  Helpers
-- ═══════════════════════════════════════════════════════════════════════════
local function getScreenCenter()
    local vp = Camera.ViewportSize
    local inset = GuiService:GetGuiInset()
    return Vector2.new(vp.X / 2, vp.Y / 2 - inset.Y)
end

local function worldToScreen(pos)
    local sp, onScreen = Camera:WorldToScreenPoint(pos)
    return Vector2.new(sp.X, sp.Y), onScreen, sp.Z
end

local function isTeammate(player)
    if not CFG.TEAM_CHECK then return false end
    if not LocalPlayer.Team then return false end
    return player.Team == LocalPlayer.Team
end

local function isAlive(player)
    local char = player.Character
    if not char then return false end
    local h = char:FindFirstChildOfClass("Humanoid")
    if not h then return false end
    return h.Health > 0
end

local function getTargetPart(player)
    local char = player.Character
    if not char then return nil end
    local part = char:FindFirstChild(CFG.TARGET_PART)
               or char:FindFirstChild("HumanoidRootPart")
    return part
end

local function getPredictedPos(part)
    if not CFG.PREDICT then return part.Position end
    local vel = part:IsA("BasePart") and part.AssemblyLinearVelocity or Vector3.zero
    return part.Position + vel * CFG.PREDICT_MULT
end

local function canSee(part)
    if not CFG.VISIBLE_ONLY then return true end
    local origin = Camera.CFrame.Position
    local dir    = (part.Position - origin)
    local ray    = RaycastParams.new()
    ray.FilterDescendantsInstances = {LocalPlayer.Character, part.Parent}
    ray.FilterType = Enum.RaycastFilterType.Exclude
    local result = Workspace:Raycast(origin, dir, ray)
    return result == nil
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Target picker — returns the Part closest to screen center within FOV
-- ═══════════════════════════════════════════════════════════════════════════
local function pickTarget()
    local center  = getScreenCenter()
    local bestPart = nil
    local bestDist = math.huge
    local fovLimit = (CFG.FOV_ENABLED and CFG.FOV_RADIUS > 0)
                     and CFG.FOV_RADIUS or math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if isTeammate(player)    then continue end
        if not isAlive(player)   then continue end

        local part = getTargetPart(player)
        if not part then continue end

        local predicted = getPredictedPos(part)
        local sp, onScreen, depth = worldToScreen(predicted)
        if not onScreen or depth < 0 then continue end

        local distPx = (sp - center).Magnitude
        if distPx > fovLimit then continue end

        if not canSee(part) then continue end

        if distPx < bestDist then
            bestDist   = distPx
            bestPart   = part
            lockedPlayer = player
        end
    end

    return bestPart
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Aim function — snaps camera CFrame to look at target
-- ═══════════════════════════════════════════════════════════════════════════
local function snapTo(part)
    if not part or not part.Parent then return end
    local pos = getPredictedPos(part)
    if CFG.SMOOTHING <= 0 then
        -- INSTANT — zero frames, zero lerp
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, pos)
    else
        -- Optional soft lerp (not recommended — defeats "instant")
        local alpha = 1 / (CFG.SMOOTHING + 1)
        local currentLook = Camera.CFrame.LookVector
        local wantedLook  = (pos - Camera.CFrame.Position).Unit
        local newLook     = currentLook:Lerp(wantedLook, alpha).Unit
        Camera.CFrame = CFrame.new(Camera.CFrame.Position,
                        Camera.CFrame.Position + newLook)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Silent aim — redirect bullet origin/direction server-side illusion
--  Works on games that use Camera.CFrame for projectile direction.
--  Hooks the camera read without moving visible camera.
-- ═══════════════════════════════════════════════════════════════════════════
local origCamIndex = nil
local silentOverride = false
local silentTargetPos = nil

local function enableSilent()
    if origCamIndex then return end
    local mt = getrawmetatable and getrawmetatable(Camera)
    if not mt then return end -- executor doesn't support metatable hooks
    local old__index = mt.__index
    setreadonly(mt, false)
    origCamIndex = old__index
    mt.__index = function(t, k)
        if silentOverride and k == "CFrame" and silentTargetPos then
            return CFrame.new(
                origCamIndex(t, "CFrame").Position,
                silentTargetPos
            )
        end
        return origCamIndex(t, k)
    end
    setreadonly(mt, true)
end

local function disableSilent()
    if not origCamIndex then return end
    local mt = getrawmetatable and getrawmetatable(Camera)
    if not mt then return end
    setreadonly(mt, false)
    mt.__index = origCamIndex
    setreadonly(mt, true)
    origCamIndex = nil
    silentOverride = false
    silentTargetPos = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Key input
-- ═══════════════════════════════════════════════════════════════════════════
local heldKeys = {}

UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    heldKeys[inp.KeyCode] = true

    if inp.KeyCode == CFG.TOGGLE_KEY then
        aiming = not aiming
    end

    if inp.KeyCode == CFG.FOV_CYCLE_KEY then
        fovCycleIdx = (fovCycleIdx % #FOV_CYCLE) + 1
        CFG.FOV_RADIUS = FOV_CYCLE[fovCycleIdx]
        print("[InstantAim] FOV:", CFG.FOV_RADIUS == 0 and "OFF (fullscreen)" or CFG.FOV_RADIUS.."px")
    end

    if inp.KeyCode == CFG.TEAM_KEY then
        CFG.TEAM_CHECK = not CFG.TEAM_CHECK
        print("[InstantAim] Team check:", CFG.TEAM_CHECK)
    end

    if inp.KeyCode == CFG.TARGET_KEY then
        CFG.TARGET_PART = CFG.TARGET_PART == "Head" and "HumanoidRootPart" or "Head"
        print("[InstantAim] Targeting:", CFG.TARGET_PART)
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    heldKeys[inp.KeyCode] = nil
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  Main loop
-- ═══════════════════════════════════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    -- resolve whether we're active this frame
    local holdActive   = heldKeys[CFG.HOLD_KEY]   == true
    local silentFrame  = heldKeys[CFG.SILENT_KEY]  == true
    local active       = aiming or holdActive

    -- silent aim state
    if silentFrame and active then
        -- try to enable metatable hook (executor-dependent)
        pcall(enableSilent)
        silentOverride = true
    else
        silentOverride = false
        if not silentFrame then
            pcall(disableSilent)
        end
    end

    if not active then
        lockedTarget = nil
        lockedPlayer = nil
        return
    end

    -- re-pick target every frame (or keep lock if still valid)
    if lockedTarget and lockedTarget.Parent and isAlive(lockedPlayer) then
        -- keep current lock, just update aim
    else
        lockedTarget = pickTarget()
    end

    if not lockedTarget then return end

    if silentFrame then
        -- silent: update silent target position but don't move camera
        silentTargetPos = getPredictedPos(lockedTarget)
    else
        -- hard snap
        snapTo(lockedTarget)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  GUI
-- ═══════════════════════════════════════════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "InstantAimGUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = LocalPlayer:WaitForChild("PlayerGui")

local C = Color3.fromRGB

local Main = Instance.new("Frame")
Main.Size                   = UDim2.new(0, 240, 0, 260)
Main.Position               = UDim2.new(0, 12, 0.5, -130)
Main.BackgroundColor3       = C(10, 2, 4)
Main.BorderSizePixel        = 0
Main.ClipsDescendants       = true
Main.Parent                 = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 14)

-- drag
local dragging = false; local dragTouch = nil
local dragStart = Vector2.new(); local startPos = Main.Position
Main.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragTouch = inp
        dragStart = Vector2.new(inp.Position.X, inp.Position.Y)
        startPos  = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not dragging or inp ~= dragTouch then return end
    local dx = inp.Position.X - dragStart.X
    local dy = inp.Position.Y - dragStart.Y
    Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+dx,
                               startPos.Y.Scale, startPos.Y.Offset+dy)
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp == dragTouch then dragging = false; dragTouch = nil end
end)

-- title
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1,0,0,32)
TitleBar.BackgroundColor3 = C(140,0,0)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Main
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0,14)

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size                = UDim2.new(1,-8,1,0)
TitleLbl.Position            = UDim2.new(0,8,0,0)
TitleLbl.Text                = "🎯  InstantAim — Head Lock"
TitleLbl.Font                = Enum.Font.Fondamento
TitleLbl.TextSize            = 13
TitleLbl.TextColor3          = C(255,255,255)
TitleLbl.BackgroundTransparency = 1
TitleLbl.TextXAlignment      = Enum.TextXAlignment.Left
TitleLbl.Parent              = TitleBar

-- helper: make a status row
local function statusRow(parent, yOff, keyName, desc)
    local row = Instance.new("Frame")
    row.Size                   = UDim2.new(1,-16,0,28)
    row.Position               = UDim2.new(0,8,0,yOff)
    row.BackgroundColor3       = C(22,5,8)
    row.BorderSizePixel        = 0
    row.Parent                 = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0,7)

    local kl = Instance.new("TextLabel")
    kl.Size                = UDim2.new(0,30,1,0)
    kl.BackgroundColor3    = C(140,0,0)
    kl.TextColor3          = C(255,255,255)
    kl.Font                = Enum.Font.Fondamento
    kl.TextSize            = 11
    kl.Text                = keyName
    kl.BorderSizePixel     = 0
    kl.TextXAlignment      = Enum.TextXAlignment.Center
    kl.Parent              = row
    Instance.new("UICorner", kl).CornerRadius = UDim.new(0,5)

    local dl = Instance.new("TextLabel")
    dl.Size                = UDim2.new(1,-36,1,0)
    dl.Position            = UDim2.new(0,34,0,0)
    dl.BackgroundTransparency = 1
    dl.TextColor3          = C(200,160,160)
    dl.Font                = Enum.Font.Fondamento
    dl.TextSize            = 11
    dl.Text                = desc
    dl.TextXAlignment      = Enum.TextXAlignment.Left
    dl.Parent              = row

    return dl
end

statusRow(Main, 38,  "Q",  "Hold → aim lock")
statusRow(Main, 72,  "T",  "Toggle aim lock")
statusRow(Main, 106, "E",  "Hold → silent aim")
statusRow(Main, 140, "X",  "Cycle FOV limit")
statusRow(Main, 174, "Z",  "Toggle team check")
statusRow(Main, 208, "C",  "Head / Torso")

-- live status indicator
local StatusBar = Instance.new("Frame")
StatusBar.Size             = UDim2.new(1,-16,0,22)
StatusBar.Position         = UDim2.new(0,8,1,-30)
StatusBar.BackgroundColor3 = C(18,4,6)
StatusBar.BorderSizePixel  = 0
StatusBar.Parent           = Main
Instance.new("UICorner", StatusBar).CornerRadius = UDim.new(0,6)

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size                = UDim2.new(1,0,1,0)
StatusLbl.BackgroundTransparency = 1
StatusLbl.Font                = Enum.Font.Fondamento
StatusLbl.TextSize            = 11
StatusLbl.TextColor3          = C(255,80,80)
StatusLbl.Text                = "● IDLE"
StatusLbl.TextXAlignment      = Enum.TextXAlignment.Center
StatusLbl.Parent              = StatusBar

-- FOV circle on screen
local FOVCircle = Instance.new("Frame")
FOVCircle.AnchorPoint        = Vector2.new(0.5, 0.5)
FOVCircle.BackgroundTransparency = 1
FOVCircle.BorderSizePixel    = 0
FOVCircle.Parent             = ScreenGui
Instance.new("UICorner", FOVCircle).CornerRadius = UDim.new(1, 0)

local FOVStroke = Instance.new("UIStroke", FOVCircle)
FOVStroke.Color     = C(200,0,0)
FOVStroke.Thickness = 1
FOVStroke.Transparency = 0.45

-- update FOV circle and status every frame
RunService.RenderStepped:Connect(function()
    local holdActive  = heldKeys[CFG.HOLD_KEY]  == true
    local silentFrame = heldKeys[CFG.SILENT_KEY] == true
    local active      = aiming or holdActive

    -- status label
    if active and lockedTarget and lockedTarget.Parent then
        local name = lockedPlayer and lockedPlayer.Name or "?"
        if silentFrame then
            StatusLbl.Text       = "◉ SILENT → "..name
            StatusLbl.TextColor3 = C(80,180,255)
        else
            StatusLbl.Text       = "◉ LOCKED → "..name
            StatusLbl.TextColor3 = C(255,60,60)
        end
    elseif active then
        StatusLbl.Text       = "◌ SCANNING..."
        StatusLbl.TextColor3 = C(255,200,80)
    else
        StatusLbl.Text       = "● IDLE"
        StatusLbl.TextColor3 = C(140,80,80)
    end

    -- FOV circle
    local vp     = Camera.ViewportSize
    local cx, cy = vp.X/2, vp.Y/2
    if CFG.FOV_ENABLED and CFG.FOV_RADIUS > 0 then
        local r = CFG.FOV_RADIUS
        FOVCircle.Visible  = true
        FOVCircle.Size     = UDim2.new(0, r*2, 0, r*2)
        FOVCircle.Position = UDim2.new(0, cx-r, 0, cy-r)
        FOVStroke.Color    = active and C(255,30,30) or C(140,0,0)
    else
        FOVCircle.Visible = false
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
print("[InstantAim] Loaded. Hold Q to lock, T to toggle, E for silent.")
print("[InstantAim] FOV:", CFG.FOV_RADIUS, "| Team check:", CFG.TEAM_CHECK)
-- ═══════════════════════════════════════════════════════════════════════════
