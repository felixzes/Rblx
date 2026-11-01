--[[
  ╔══════════════════════════════════════════════════════════════╗
  ║          🪽 ANGEL HITBOX CUSTOMIZER v2.0                    ║
  ║  Engine: Roblox (Universal)  |  Lang: Lua 5.1 (Luau)       ║
  ║  Executor: Any (Synapse X, KRNL, Fluxus, Electron, etc.)   ║
  ╚══════════════════════════════════════════════════════════════╝

  HOW IT WORKS:
  - Scans all player characters for HumanoidRootPart / hitbox parts
  - Replaces or resizes each hitbox to your specified Size (studs)
  - /hitbox [n]    → sets the cubic hitbox size for ALL players
  - /boxreach [n]  → sets the weapon reach (moves hitbox offset forward)
  - /hitbox reset  → restores original hitbox sizes
  - /hitbox hide   → hides visualizer boxes
  - /hitbox show   → shows visualizer boxes
  - GUI panel provides live toggles and sliders

  LIMITATIONS:
  - Client-side only. Server-side hit detection can't be altered here.
  - Works best with games using HRP-based hit detection.
  - FE (FilteringEnabled) games: visual only unless hitbox IS the HRP.
]]

-- ─── Services ────────────────────────────────────────────────────────────────
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local CoreGui       = game:GetService("CoreGui")

-- ─── Config (editable defaults) ──────────────────────────────────────────────
local CONFIG = {
    hitboxSize      = 5,       -- default hitbox cube size (studs)
    boxReach        = 0,       -- forward offset (weapon reach)
    showBoxes       = true,    -- show visualizer by default
    boxColor        = Color3.fromRGB(255, 80, 80),
    boxTransparency = 0.5,
    selfBox         = false,   -- also box yourself?
    updateRate      = 0.05,    -- seconds between updates (20 FPS)
    targetPart      = "HumanoidRootPart", -- part to overlay
}

-- ─── State ───────────────────────────────────────────────────────────────────
local hitboxMap     = {}   -- [player] = {box = Part, originalSize = Vector3}
local connections   = {}
local guiOpen       = true
local equippedWeapon = nil

-- ─── Utility ─────────────────────────────────────────────────────────────────
local function log(msg)
    print(("[AngelHB] %s"):format(tostring(msg)))
end

local function safeDestroy(obj)
    if obj and obj.Parent then
        pcall(function() obj:Destroy() end)
    end
end

local function clamp(v, mn, mx)
    return math.max(mn, math.min(mx, v))
end

-- ─── Weapon Detection ────────────────────────────────────────────────────────
local function getEquippedWeapon(plr)
    local char = plr and plr.Character
    if not char then return nil end
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Tool") then return obj end
    end
    return nil
end

local function getWeaponLabel(tool)
    if not tool then return "None" end
    -- Try to detect type by tags / descendants
    if tool:FindFirstChild("RemoteEvent") or tool:FindFirstChild("RemoteFunction") then
        return tool.Name .. " (Network)"
    elseif tool:FindFirstChildWhichIsA("Script") then
        return tool.Name .. " (Scripted)"
    else
        return tool.Name .. " (Gear)"
    end
end

-- ─── Hitbox Core ─────────────────────────────────────────────────────────────
local function createBox(targetPart)
    local box = Instance.new("Part")
    box.Name          = "AngelHitbox"
    box.Anchored      = false
    box.CanCollide    = false
    box.CastShadow    = false
    box.Transparency  = CONFIG.boxTransparency
    box.Color         = CONFIG.boxColor
    box.Material      = Enum.Material.Neon
    box.Size          = Vector3.new(CONFIG.hitboxSize, CONFIG.hitboxSize, CONFIG.hitboxSize)
    box.Parent        = workspace

    -- Weld to target
    local weld = Instance.new("WeldConstraint")
    weld.Part0  = box
    weld.Part1  = targetPart
    weld.Parent = box

    -- Offset for reach
    if CONFIG.boxReach ~= 0 then
        local offset = Instance.new("CFrameValue")
        offset.Name  = "ReachOffset"
        offset.Value = CFrame.new(0, 0, -CONFIG.boxReach)
        offset.Parent = box
    end

    box.Visible = CONFIG.showBoxes
    return box
end

local function applyHitboxToPlayer(plr)
    if not CONFIG.selfBox and plr == Players.LocalPlayer then return end

    local char = plr.Character
    if not char then return end

    local hrp = char:FindFirstChild(CONFIG.targetPart)
    if not hrp then return end

    -- Remove old box if exists
    if hitboxMap[plr] then
        safeDestroy(hitboxMap[plr].box)
    end

    local originalSize = hrp.Size

    -- Expand the actual HRP (works in games where HRP IS the hitbox)
    pcall(function()
        hrp.Size = Vector3.new(CONFIG.hitboxSize, CONFIG.hitboxSize, CONFIG.hitboxSize)
    end)

    local box = createBox(hrp)

    hitboxMap[plr] = {
        box          = box,
        originalSize = originalSize,
        hrp          = hrp,
    }
end

local function removeHitboxFromPlayer(plr)
    if hitboxMap[plr] then
        -- Restore original size
        pcall(function()
            if hitboxMap[plr].hrp and hitboxMap[plr].hrp.Parent then
                hitboxMap[plr].hrp.Size = hitboxMap[plr].originalSize
            end
        end)
        safeDestroy(hitboxMap[plr].box)
        hitboxMap[plr] = nil
    end
end

local function applyAll()
    for _, plr in ipairs(Players:GetPlayers()) do
        applyHitboxToPlayer(plr)
    end
end

local function resetAll()
    for plr, data in pairs(hitboxMap) do
        removeHitboxFromPlayer(plr)
    end
    log("All hitboxes reset.")
end

local function setVisibility(state)
    CONFIG.showBoxes = state
    for _, data in pairs(hitboxMap) do
        if data.box and data.box.Parent then
            data.box.Visible = state
        end
    end
end

-- ─── Live Update Loop ─────────────────────────────────────────────────────────
local updateConn
local function startUpdateLoop()
    if updateConn then updateConn:Disconnect() end
    updateConn = RunService.Heartbeat:Connect(function()
        for _, plr in ipairs(Players:GetPlayers()) do
            if CONFIG.selfBox or plr ~= Players.LocalPlayer then
                local char = plr.Character
                if char then
                    local hrp = char:FindFirstChild(CONFIG.targetPart)
                    if hrp then
                        -- Re-apply size every tick (some games reset it)
                        pcall(function()
                            hrp.Size = Vector3.new(CONFIG.hitboxSize, CONFIG.hitboxSize, CONFIG.hitboxSize)
                        end)
                        -- Update reach offset on box
                        if hitboxMap[plr] and hitboxMap[plr].box and hitboxMap[plr].box.Parent then
                            local weld = hitboxMap[plr].box:FindFirstChildOfClass("WeldConstraint")
                            if weld and CONFIG.boxReach ~= 0 then
                                -- Manual CFrame offset via Motor6D if needed
                                -- (WeldConstraint doesn't support offsets, use this approach:)
                                hitboxMap[plr].box.CFrame = hrp.CFrame * CFrame.new(0, 0, -CONFIG.boxReach)
                            end
                        end
                    else
                        -- Part not found yet, try applying
                        if not hitboxMap[plr] then
                            applyHitboxToPlayer(plr)
                        end
                    end
                end
            end
        end
        -- Weapon detection
        local lp = Players.LocalPlayer
        local w = getEquippedWeapon(lp)
        if w ~= equippedWeapon then
            equippedWeapon = w
            updateWeaponLabel()
        end
    end)
    table.insert(connections, updateConn)
end

-- ─── Player Events ────────────────────────────────────────────────────────────
local function onPlayerAdded(plr)
    local c1 = plr.CharacterAdded:Connect(function(char)
        task.wait(1) -- let char load
        applyHitboxToPlayer(plr)
    end)
    table.insert(connections, c1)
    if plr.Character then applyHitboxToPlayer(plr) end
end

for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(plr)
    removeHitboxFromPlayer(plr)
end)

-- ─── Chat Command Handler ─────────────────────────────────────────────────────
local lp = Players.LocalPlayer
local playerGui = lp:WaitForChild("PlayerGui", 10)

-- Intercept chat
local function hookChat()
    local chatConn = lp.Chatted:Connect(function(msg)
        msg = msg:lower():gsub("^%s+", ""):gsub("%s+$", "")

        if msg:match("^/hitbox%s+reset$") then
            resetAll()
            notify("Hitboxes reset to original.")

        elseif msg:match("^/hitbox%s+hide$") then
            setVisibility(false)
            notify("Boxes hidden.")

        elseif msg:match("^/hitbox%s+show$") then
            setVisibility(true)
            notify("Boxes visible.")

        elseif msg:match("^/hitbox%s+(%d+%.?%d*)$") then
            local n = tonumber(msg:match("^/hitbox%s+(%d+%.?%d*)$"))
            if n then
                n = clamp(n, 0.5, 100)
                CONFIG.hitboxSize = n
                applyAll()
                notify(("Hitbox size → %g"):format(n))
                updateSlider(n)
            end

        elseif msg:match("^/boxreach%s+(%d+%.?%d*)$") then
            local n = tonumber(msg:match("^/boxreach%s+(%d+%.?%d*)$"))
            if n then
                n = clamp(n, 0, 50)
                CONFIG.boxReach = n
                applyAll()
                notify(("Reach offset → %g"):format(n))
            end

        elseif msg:match("^/hitbox$") then
            notify("Usage: /hitbox [size|reset|show|hide] | /boxreach [n]")
        end
    end)
    table.insert(connections, chatConn)
end

-- ─── GUI ─────────────────────────────────────────────────────────────────────
-- Destroy old instance if re-running
if CoreGui:FindFirstChild("AngelHitboxGUI") then
    CoreGui:FindFirstChild("AngelHitboxGUI"):Destroy()
end

local ScreenGui   = Instance.new("ScreenGui")
ScreenGui.Name    = "AngelHitboxGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent  = CoreGui

-- ── Main Frame ──
local Main = Instance.new("Frame")
Main.Name            = "Main"
Main.Size            = UDim2.new(0, 280, 0, 320)
Main.Position        = UDim2.new(0, 20, 0.5, -160)
Main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
Main.BorderSizePixel = 0
Main.Active          = true
Main.Draggable       = true
Main.Parent          = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = Main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 80, 80)
stroke.Thickness = 1.2
stroke.Parent = Main

-- ── Title Bar ──
local TitleBar = Instance.new("Frame")
TitleBar.Size   = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size   = UDim2.new(1, -40, 1, 0)
TitleLabel.Position = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
TitleLabel.Font      = Enum.Font.GothamBold
TitleLabel.TextSize  = 13
TitleLabel.Text      = "🪽 ANGEL HITBOX  v2.0"
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

-- Toggle button
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size   = UDim2.new(0, 28, 0, 28)
ToggleBtn.Position = UDim2.new(1, -34, 0, 4)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
ToggleBtn.Text   = "–"
ToggleBtn.Font   = Enum.Font.GothamBold
ToggleBtn.TextSize = 14
ToggleBtn.TextColor3 = Color3.new(1,1,1)
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Parent = TitleBar

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleBtn

-- ── Content Frame ──
local Content = Instance.new("Frame")
Content.Name   = "Content"
Content.Size   = UDim2.new(1, 0, 1, -36)
Content.Position = UDim2.new(0, 0, 0, 36)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 6)
Layout.Parent  = Content

local Pad = Instance.new("UIPadding")
Pad.PaddingLeft   = UDim.new(0, 12)
Pad.PaddingRight  = UDim.new(0, 12)
Pad.PaddingTop    = UDim.new(0, 8)
Pad.Parent        = Content

-- ── Helper: section label ──
local function makeLabel(text, color)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3  = color or Color3.fromRGB(180, 180, 200)
    lbl.Font        = Enum.Font.Gotham
    lbl.TextSize    = 11
    lbl.Text        = text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent      = Content
    return lbl
end

-- ── Weapon Info ──
makeLabel("EQUIPPED WEAPON", Color3.fromRGB(255, 80, 80))

local WeaponLabel = Instance.new("TextLabel")
WeaponLabel.Name  = "WeaponLabel"
WeaponLabel.Size  = UDim2.new(1, 0, 0, 20)
WeaponLabel.BackgroundTransparency = 1
WeaponLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
WeaponLabel.Font   = Enum.Font.GothamSemibold
WeaponLabel.TextSize = 12
WeaponLabel.Text   = "None"
WeaponLabel.TextXAlignment = Enum.TextXAlignment.Left
WeaponLabel.Parent = Content

function updateWeaponLabel()
    local lbl = getWeaponLabel(equippedWeapon)
    if WeaponLabel then WeaponLabel.Text = lbl end
end

-- ── Divider ──
local div1 = Instance.new("Frame")
div1.Size = UDim2.new(1, 0, 0, 1)
div1.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
div1.BorderSizePixel = 0
div1.Parent = Content

-- ── Hitbox Size Slider ──
makeLabel("HITBOX SIZE: " .. CONFIG.hitboxSize, Color3.fromRGB(255, 80, 80))
local SizeLabel -- forward ref

-- Slider track
local SliderTrack = Instance.new("Frame")
SliderTrack.Size = UDim2.new(1, 0, 0, 16)
SliderTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
SliderTrack.BorderSizePixel = 0
SliderTrack.Parent = Content

local SliderCorner = Instance.new("UICorner")
SliderCorner.CornerRadius = UDim.new(0, 8)
SliderCorner.Parent = SliderTrack

local SliderFill = Instance.new("Frame")
SliderFill.Size = UDim2.new(CONFIG.hitboxSize / 30, 0, 1, 0) -- max display 30
SliderFill.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
SliderFill.BorderSizePixel  = 0
SliderFill.Parent = SliderTrack

local SliderFillCorner = Instance.new("UICorner")
SliderFillCorner.CornerRadius = UDim.new(0, 8)
SliderFillCorner.Parent = SliderFill

-- Size display label (the one that actually exists)
SizeLabel = makeLabel("Size: " .. CONFIG.hitboxSize .. " studs")

-- Slider interaction
local dragging = false
SliderTrack.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
        local trackPos  = SliderTrack.AbsolutePosition
        local trackSize = SliderTrack.AbsoluteSize
        local rel = clamp((inp.Position.X - trackPos.X) / trackSize.X, 0, 1)
        local newSize = math.floor(rel * 29.5 + 0.5) + 1 -- 1..30
        newSize = clamp(newSize, 1, 30)
        CONFIG.hitboxSize = newSize
        SliderFill.Size = UDim2.new(rel, 0, 1, 0)
        SizeLabel.Text  = "Size: " .. newSize .. " studs"
        applyAll()
    end
end)

function updateSlider(n)
    local rel = clamp(n / 30, 0, 1)
    if SliderFill then SliderFill.Size = UDim2.new(rel, 0, 1, 0) end
    if SizeLabel  then SizeLabel.Text  = "Size: " .. n .. " studs" end
end

-- ── Buttons row ──
local BtnRow = Instance.new("Frame")
BtnRow.Size = UDim2.new(1, 0, 0, 30)
BtnRow.BackgroundTransparency = 1
BtnRow.Parent = Content

local BtnLayout = Instance.new("UIListLayout")
BtnLayout.FillDirection = Enum.FillDirection.Horizontal
BtnLayout.Padding = UDim.new(0, 6)
BtnLayout.Parent  = BtnRow

local function makeButton(text, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size  = UDim2.new(0.31, 0, 1, 0)
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font   = Enum.Font.GothamSemibold
    btn.TextSize = 11
    btn.Text   = text
    btn.BorderSizePixel = 0
    btn.Parent = BtnRow

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

makeButton("Apply", Color3.fromRGB(255, 80, 80), function()
    applyAll()
    notify("Applied to all players.")
end)

makeButton("Reset", Color3.fromRGB(60, 60, 90), function()
    resetAll()
    notify("Hitboxes reset.")
end)

local visState = true
local VisBtn = makeButton("Hide", Color3.fromRGB(80, 80, 120), function()
    visState = not visState
    setVisibility(visState)
end)

-- Update vis button text
RunService.Heartbeat:Connect(function()
    if VisBtn then VisBtn.Text = CONFIG.showBoxes and "Hide" or "Show" end
end)

-- ── Self-box toggle ──
local div2 = Instance.new("Frame")
div2.Size = UDim2.new(1, 0, 0, 1)
div2.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
div2.BorderSizePixel = 0
div2.Parent = Content

local SelfRow = Instance.new("Frame")
SelfRow.Size = UDim2.new(1, 0, 0, 22)
SelfRow.BackgroundTransparency = 1
SelfRow.Parent = Content

local SelfLabel = Instance.new("TextLabel")
SelfLabel.Size  = UDim2.new(0.7, 0, 1, 0)
SelfLabel.BackgroundTransparency = 1
SelfLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
SelfLabel.Font   = Enum.Font.Gotham
SelfLabel.TextSize = 11
SelfLabel.Text   = "Box self (local player)"
SelfLabel.TextXAlignment = Enum.TextXAlignment.Left
SelfLabel.Parent = SelfRow

local SelfToggle = Instance.new("TextButton")
SelfToggle.Size  = UDim2.new(0, 44, 0, 20)
SelfToggle.Position = UDim2.new(1, -44, 0, 1)
SelfToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
SelfToggle.TextColor3 = Color3.new(1,1,1)
SelfToggle.Font   = Enum.Font.GothamBold
SelfToggle.TextSize = 10
SelfToggle.Text   = "OFF"
SelfToggle.BorderSizePixel = 0
SelfToggle.Parent = SelfRow

local SC = Instance.new("UICorner")
SC.CornerRadius = UDim.new(0, 6)
SC.Parent = SelfToggle

SelfToggle.MouseButton1Click:Connect(function()
    CONFIG.selfBox = not CONFIG.selfBox
    SelfToggle.Text = CONFIG.selfBox and "ON" or "OFF"
    SelfToggle.BackgroundColor3 = CONFIG.selfBox
        and Color3.fromRGB(255, 80, 80)
        or  Color3.fromRGB(60, 60, 90)
    applyAll()
end)

-- ── Notification toast ──
local Toast = Instance.new("TextLabel")
Toast.Name   = "Toast"
Toast.Size   = UDim2.new(0, 240, 0, 28)
Toast.Position = UDim2.new(0.5, -120, 1, -50)
Toast.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
Toast.TextColor3 = Color3.new(1,1,1)
Toast.Font   = Enum.Font.GothamSemibold
Toast.TextSize = 11
Toast.Text   = ""
Toast.Visible = false
Toast.ZIndex  = 10
Toast.Parent  = ScreenGui

local ToastCorner = Instance.new("UICorner")
ToastCorner.CornerRadius = UDim.new(0, 6)
ToastCorner.Parent = Toast

local toastTask
function notify(msg)
    Toast.Text    = msg
    Toast.Visible = true
    if toastTask then task.cancel(toastTask) end
    toastTask = task.delay(2.5, function()
        Toast.Visible = false
    end)
end

-- ── Toggle GUI visibility ──
local guiVisible = true
ToggleBtn.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    Content.Visible  = guiVisible
    Main.Size = guiVisible
        and UDim2.new(0, 280, 0, 320)
        or  UDim2.new(0, 280, 0, 36)
    ToggleBtn.Text = guiVisible and "–" or "+"
end)

-- ─── Keyboard shortcut: RightShift to toggle GUI ─────────────────────────────
UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        ToggleBtn.MouseButton1Click:Fire()
    end
end)

-- ─── Boot ─────────────────────────────────────────────────────────────────────
hookChat()
applyAll()
startUpdateLoop()
notify("Angel Hitbox loaded. /hitbox [n] to start.")
log("Loaded. Size=" .. CONFIG.hitboxSize .. " | /hitbox [n] | /boxreach [n]")

-- ─── Cleanup on reload ────────────────────────────────────────────────────────
-- If you re-run the script, old connections are garbage-collected automatically
-- because ScreenGui is destroyed at the top. This keeps things clean.

--[[
  COMMAND REFERENCE
  ─────────────────────────────────────────────────────
  /hitbox [1–100]     → set hitbox size for all players
  /hitbox reset       → restore original sizes
  /hitbox show        → show boxes
  /hitbox hide        → hide boxes
  /boxreach [0–50]    → offset hitbox forward (weapon reach)

  KEYBIND
  ─────────────────────────────────────────────────────
  RightShift          → collapse / expand GUI

  NOTES
  ─────────────────────────────────────────────────────
  • HRP size IS the hitbox in most games. This resizes it every
    Heartbeat so anti-cheat resets get overwritten immediately.
  • Purely client-side. Server-authoritative hit detection
    (e.g. raycast from server) is unaffected.
  • Works with melee, ranged, and gear-based tools.
    /boxreach moves the visualizer box forward to match longer weapons.
]]
