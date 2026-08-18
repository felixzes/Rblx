--[[
    Lil0darkie6 Rings v8 — Sphere Edition
    Ring formation replaced with uniform sphere distribution
    Everything else identical to original
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")
local StarterGui       = game:GetService("StarterGui")
local TextChatService  = game:GetService("TextChatService")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer

local character         = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local humanoidRootPart  = character:WaitForChild("HumanoidRootPart")

-- ─── Folder + invisible anchor part ─────────────
local Folder      = Instance.new("Folder", Workspace)
local Part        = Instance.new("Part", Folder)
Part.Anchored     = true
Part.CanCollide   = false
Part.Transparency = 1
local Attachment1 = Instance.new("Attachment", Part)

-- ─── Network ownership ───────────────────────────
if not getgenv().Network then
    getgenv().Network = {
        BaseParts = {},
        Velocity  = Vector3.new(14.46262424, 14.46262424, 14.46262424),
    }
    local Network = getgenv().Network
    Network.RetainPart = function(p)
        if typeof(p) == "Instance" and p:IsA("BasePart") and p:IsDescendantOf(Workspace) then
            if not table.find(Network.BaseParts, p) then
                table.insert(Network.BaseParts, p)
                p.CustomPhysicalProperties = PhysicalProperties.new(0,0,0,0,0)
                p.CanCollide = false
            end
        end
    end
    local function EnablePartControl()
        LocalPlayer.ReplicationFocus = Workspace
        RunService.Heartbeat:Connect(function()
            sethiddenproperty(LocalPlayer, "SimulationRadius", math.huge)
            for _, p in pairs(Network.BaseParts) do
                if p:IsDescendantOf(Workspace) then
                    p.Velocity = Network.Velocity
                end
            end
        end)
    end
    EnablePartControl()
end

-- ─── ForcePart ───────────────────────────────────
local function ForcePart(v)
    if v:IsA("Part") and not v.Anchored
        and not v.Parent:FindFirstChild("Humanoid")
        and not v.Parent:FindFirstChild("Head")
        and v.Name ~= "Handle" then
        for _, x in next, v:GetChildren() do
            if x:IsA("BodyAngularVelocity") or x:IsA("BodyForce") or x:IsA("BodyGyro")
               or x:IsA("BodyPosition") or x:IsA("BodyThrust") or x:IsA("BodyVelocity")
               or x:IsA("RocketPropulsion") then
                x:Destroy()
            end
        end
        if v:FindFirstChild("Attachment")    then v:FindFirstChild("Attachment"):Destroy()    end
        if v:FindFirstChild("AlignPosition") then v:FindFirstChild("AlignPosition"):Destroy() end
        if v:FindFirstChild("Torque")        then v:FindFirstChild("Torque"):Destroy()        end
        v.CanCollide = false
        local Torque         = Instance.new("Torque", v)
        Torque.Torque        = Vector3.new(100000, 100000, 100000)
        local AlignPosition  = Instance.new("AlignPosition", v)
        local Attachment2    = Instance.new("Attachment", v)
        Torque.Attachment0           = Attachment2
        AlignPosition.MaxForce       = 99999999999999999
        AlignPosition.MaxVelocity    = math.huge
        AlignPosition.Responsiveness = 200
        AlignPosition.Attachment0    = Attachment2
        AlignPosition.Attachment1    = Attachment1
    end
end

-- ─── Sound ───────────────────────────────────────
local function playSound(soundId)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. soundId
    sound.Parent  = SoundService
    sound:Play()
    sound.Ended:Connect(function() sound:Destroy() end)
end
playSound("2865227271")

-- ─── GUI ─────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "Lil0darkie6RingsGUI"
ScreenGui.ResetOnSpawn  = false
ScreenGui.Parent        = LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size              = UDim2.new(0, 220, 0, 190)
MainFrame.Position          = UDim2.new(0.5, -110, 0.5, -95)
MainFrame.BackgroundColor3  = Color3.fromRGB(0, 102, 51)
MainFrame.BorderSizePixel   = 0
MainFrame.Parent            = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 20)

local Title = Instance.new("TextLabel")
Title.Size              = UDim2.new(1, 0, 0, 40)
Title.Position          = UDim2.new(0, 0, 0, 0)
Title.Text              = "Lil0darkie6 Sphere v8"
Title.TextColor3        = Color3.fromRGB(255, 255, 255)
Title.BackgroundColor3  = Color3.fromRGB(0, 153, 76)
Title.Font              = Enum.Font.Fondamento
Title.TextSize          = 22
Title.Parent            = MainFrame
Instance.new("UICorner", Title).CornerRadius = UDim.new(0, 20)

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size             = UDim2.new(0.8, 0, 0, 35)
ToggleButton.Position         = UDim2.new(0.1, 0, 0.3, 0)
ToggleButton.Text             = "Off"
ToggleButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
ToggleButton.TextColor3       = Color3.fromRGB(255, 255, 255)
ToggleButton.Font             = Enum.Font.Fondamento
ToggleButton.TextSize         = 15
ToggleButton.Parent           = MainFrame
Instance.new("UICorner", ToggleButton).CornerRadius = UDim.new(0, 10)

local DecreaseRadius = Instance.new("TextButton")
DecreaseRadius.Size             = UDim2.new(0.2, 0, 0, 35)
DecreaseRadius.Position         = UDim2.new(0.1, 0, 0.6, 0)
DecreaseRadius.Text             = "<"
DecreaseRadius.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
DecreaseRadius.TextColor3       = Color3.fromRGB(0, 0, 0)
DecreaseRadius.Font             = Enum.Font.Fondamento
DecreaseRadius.TextSize         = 18
DecreaseRadius.Parent           = MainFrame
Instance.new("UICorner", DecreaseRadius).CornerRadius = UDim.new(0, 10)

local IncreaseRadius = Instance.new("TextButton")
IncreaseRadius.Size             = UDim2.new(0.2, 0, 0, 35)
IncreaseRadius.Position         = UDim2.new(0.7, 0, 0.6, 0)
IncreaseRadius.Text             = ">"
IncreaseRadius.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
IncreaseRadius.TextColor3       = Color3.fromRGB(0, 0, 0)
IncreaseRadius.Font             = Enum.Font.Fondamento
IncreaseRadius.TextSize         = 18
IncreaseRadius.Parent           = MainFrame
Instance.new("UICorner", IncreaseRadius).CornerRadius = UDim.new(0, 10)

local RadiusDisplay = Instance.new("TextLabel")
RadiusDisplay.Size             = UDim2.new(0.4, 0, 0, 35)
RadiusDisplay.Position         = UDim2.new(0.3, 0, 0.6, 0)
RadiusDisplay.Text             = "Radius: 50"
RadiusDisplay.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
RadiusDisplay.TextColor3       = Color3.fromRGB(0, 0, 0)
RadiusDisplay.Font             = Enum.Font.Fondamento
RadiusDisplay.TextSize         = 15
RadiusDisplay.Parent           = MainFrame
Instance.new("UICorner", RadiusDisplay).CornerRadius = UDim.new(0, 10)

local Watermark = Instance.new("TextLabel")
Watermark.Size                 = UDim2.new(1, 0, 0, 20)
Watermark.Position             = UDim2.new(0, 0, 1, -20)
Watermark.Text                 = "Lil0darkie6 Sphere [V8] by Zeus!"
Watermark.TextColor3           = Color3.fromRGB(255, 255, 255)
Watermark.BackgroundTransparency = 1
Watermark.Font                 = Enum.Font.Fondamento
Watermark.TextSize             = 14
Watermark.Parent               = MainFrame

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size             = UDim2.new(0, 30, 0, 30)
MinimizeButton.Position         = UDim2.new(1, -35, 0, 5)
MinimizeButton.Text             = "-"
MinimizeButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
MinimizeButton.TextColor3       = Color3.fromRGB(255, 255, 255)
MinimizeButton.Font             = Enum.Font.Fondamento
MinimizeButton.TextSize         = 15
MinimizeButton.Parent           = MainFrame
Instance.new("UICorner", MinimizeButton).CornerRadius = UDim.new(0, 15)

-- ─── Drag ────────────────────────────────────────
local dragging, dragInput, dragStart, startPos
local function update(input)
    local delta = input.Position - dragStart
    MainFrame.Position = UDim2.new(
        startPos.X.Scale, startPos.X.Offset + delta.X,
        startPos.Y.Scale, startPos.Y.Offset + delta.Y
    )
end
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
       or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then update(input) end
end)

-- ─── Minimize ────────────────────────────────────
local minimized = false
MinimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    for _, child in ipairs(MainFrame:GetChildren()) do
        if child ~= MinimizeButton and child.Name ~= "UICorner" then
            if child:IsA("GuiObject") then
                child.Visible = not minimized
            end
        end
    end
    MinimizeButton.Text = minimized and "+" or "-"
    MainFrame.Size = minimized
        and UDim2.new(0, 220, 0, 40)
        or  UDim2.new(0, 220, 0, 190)
end)

-- ─── Part pool ───────────────────────────────────
local radius             = 50
local rotationSpeed      = 0.5
local attractionStrength = 1000
local sphereEnabled      = false
local parts              = {}

-- Per-part stable angles — assigned once, persist across frames
-- so each part holds its position on the sphere surface instead of
-- recalculating from world position (which caused ring collapse)
local partAngles = {}   -- [part] = { phi, theta }

local function RetainPart(part)
    if part:IsA("BasePart") and not part.Anchored and part:IsDescendantOf(Workspace) then
        if part:IsDescendantOf(LocalPlayer.Character) then return false end
        part.CustomPhysicalProperties = PhysicalProperties.new(0,0,0,0,0)
        part.CanCollide = false
        return true
    end
    return false
end

local function addPart(part)
    if RetainPart(part) and not table.find(parts, part) then
        table.insert(parts, part)
        -- Assign stable spherical coordinates on first add
        -- phi   = polar angle    (0 → π)   — latitude
        -- theta = azimuth angle  (0 → 2π)  — longitude
        -- Uses golden-angle spiral for even surface distribution
        local idx   = #parts
        local phi   = math.acos(1 - 2 * idx / math.max(#parts, 1))
        local theta = math.pi * (1 + math.sqrt(5)) * idx
        partAngles[part] = { phi = phi, theta = theta }
    end
end

local function removePart(part)
    local idx = table.find(parts, part)
    if idx then
        table.remove(parts, idx)
        partAngles[part] = nil
    end
end

for _, part in pairs(Workspace:GetDescendants()) do addPart(part) end
Workspace.DescendantAdded:Connect(addPart)
Workspace.DescendantRemoving:Connect(removePart)

-- ─── Sphere heartbeat ────────────────────────────
-- Replaces original ring/tornado target position math.
--
-- Original used:
--   targetPos.Y = center.Y + height * math.abs(math.sin(...))   ← tornado column
--   targetPos.XZ = center.XZ + cos/sin(newAngle) * radius       ← flat ring
--
-- Sphere uses standard spherical → Cartesian conversion:
--   X = r · sin(phi) · cos(theta)
--   Y = r · cos(phi)
--   Z = r · sin(phi) · sin(theta)
-- phi and theta advance each frame at rotationSpeed so the whole
-- sphere rotates uniformly without parts collapsing to a flat plane.

local t = 0
RunService.Heartbeat:Connect(function(dt)
    if not sphereEnabled then return end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    t = t + dt * rotationSpeed

    local center = root.Position
    local count  = #parts

    for i, part in ipairs(parts) do
        if part.Parent and not part.Anchored then
            -- Redistribute phi evenly across the sphere surface as pool size changes
            local phi   = math.acos(1 - 2 * i / math.max(count, 1))
            local theta = (math.pi * (1 + math.sqrt(5)) * i) + t

            local targetPos = Vector3.new(
                center.X + radius * math.sin(phi) * math.cos(theta),
                center.Y + radius * math.cos(phi),
                center.Z + radius * math.sin(phi) * math.sin(theta)
            )

            local dir = (targetPos - part.Position)
            local mag = dir.Magnitude
            if mag > 0 then
                part.Velocity = (dir / mag) * attractionStrength
            end
        end
    end
end)

-- ─── Buttons ─────────────────────────────────────
ToggleButton.MouseButton1Click:Connect(function()
    sphereEnabled = not sphereEnabled
    ToggleButton.Text             = sphereEnabled and "Sphere On" or "Sphere Off"
    ToggleButton.BackgroundColor3 = sphereEnabled
        and Color3.fromRGB(50, 205, 50)
        or  Color3.fromRGB(255, 0, 0)
    playSound("12221967")
end)

DecreaseRadius.MouseButton1Click:Connect(function()
    radius = math.max(0, radius - 5)
    RadiusDisplay.Text = "Radius: " .. radius
    playSound("12221967")
end)

IncreaseRadius.MouseButton1Click:Connect(function()
    radius = math.min(10000, radius + 5)
    RadiusDisplay.Text = "Radius: " .. radius
    playSound("12221967")
end)

-- ─── Notifications ───────────────────────────────
local userId   = Players:GetUserIdFromNameAsync("Toolb0x3")
local content  = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
StarterGui:SetCore("SendNotification", { Title = "Lil0darkie6 Sphere V8", Text = "Modified",                     Icon = content, Duration = 5 })
StarterGui:SetCore("SendNotification", { Title = "Credits",               Text = "Original by Yumm Scriptblox", Icon = content, Duration = 5 })
StarterGui:SetCore("SendNotification", { Title = "Credits",               Text = "Edited by Zeus",              Icon = content, Duration = 5 })

-- ─── Chat ────────────────────────────────────────
local function SendChatMessage(msg)
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        TextChatService.TextChannels.RBXGeneral:SendAsync(msg)
    else
        game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
    end
end
SendChatMessage("i love LIL0DARKIE6 ")
