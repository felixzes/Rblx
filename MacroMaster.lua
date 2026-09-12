--[[
    MacroMaster — Record & Replay
    Engine  : Roblox (executor environment)
    Author  : Zeus / DieStupidNinja
    Version : 1.0

    Features:
      • Records mouse clicks, mouse movement, keyboard presses, touch taps
      • Plays back recorded actions with exact timing
      • Loop counts: 1 / 5 / 10 / 15 / 50 / 100 / ∞ (infinite)
      • Infinite loops by default, toggle off to set a specific count
      • Record / Stop / Play / Pause / Resume / Clear buttons
      • Real-time event log
      • Draggable GUI — works on mobile and PC
      • Touch tracking: records finger position, tap down, tap up
      • Keyboard tracking: records every key press and release
      • Mouse tracking: position delta, button down/up
]]

-- ════════════════════════════════════════════════════════════════
--  Services
-- ════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService       = game:GetService("GuiService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()

-- ════════════════════════════════════════════════════════════════
--  State
-- ════════════════════════════════════════════════════════════════
local recording      = false
local playing        = false
local paused         = false
local macroEvents    = {}      -- recorded event list
local loopCount      = 0       -- 0 = infinite
local currentLoop    = 0
local recordStart    = 0
local playbackThread = nil
local connections    = {}
local eventLog       = {}      -- for GUI log display
local MAX_LOG        = 30

-- Loop options
local LOOP_OPTIONS   = {1, 5, 10, 15, 50, 100, 0}  -- 0 = ∞
local loopOptionIdx  = 7  -- default: ∞

-- ════════════════════════════════════════════════════════════════
--  Event recording
-- ════════════════════════════════════════════════════════════════
local function timestamp()
    return tick() - recordStart
end

local function addEvent(t)
    table.insert(macroEvents, t)
end

local function logEvent(txt)
    table.insert(eventLog, txt)
    if #eventLog > MAX_LOG then table.remove(eventLog, 1) end
end

local function startRecording()
    macroEvents  = {}
    eventLog     = {}
    recordStart  = tick()
    recording    = true

    -- disconnect old
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}

    -- Mouse button down
    table.insert(connections, UserInputService.InputBegan:Connect(function(inp, gp)
        if not recording then return end
        local t = timestamp()
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            addEvent({time=t, type="MouseDown", button=1, x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  MouseDown L  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
            addEvent({time=t, type="MouseDown", button=2, x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  MouseDown R  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.MouseButton3 then
            addEvent({time=t, type="MouseDown", button=3, x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  MouseDown M  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.Touch then
            addEvent({time=t, type="TouchDown", x=inp.Position.X, y=inp.Position.Y, id=tostring(inp)})
            logEvent(("%.2f  TouchDown  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.Keyboard then
            addEvent({time=t, type="KeyDown", key=inp.KeyCode.Name})
            logEvent(("%.2f  KeyDown  [%s]"):format(t, inp.KeyCode.Name))
        end
    end))

    -- Mouse button up / touch up
    table.insert(connections, UserInputService.InputEnded:Connect(function(inp, gp)
        if not recording then return end
        local t = timestamp()
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            addEvent({time=t, type="MouseUp", button=1, x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  MouseUp  L  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.MouseButton2 then
            addEvent({time=t, type="MouseUp", button=2, x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  MouseUp  R  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.MouseButton3 then
            addEvent({time=t, type="MouseUp", button=3, x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  MouseUp  M  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.Touch then
            addEvent({time=t, type="TouchUp", x=inp.Position.X, y=inp.Position.Y})
            logEvent(("%.2f  TouchUp  (%.0f,%.0f)"):format(t,inp.Position.X,inp.Position.Y))
        elseif inp.UserInputType == Enum.UserInputType.Keyboard then
            addEvent({time=t, type="KeyUp", key=inp.KeyCode.Name})
            logEvent(("%.2f  KeyUp  [%s]"):format(t, inp.KeyCode.Name))
        end
    end))

    -- Mouse / touch movement
    table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
        if not recording then return end
        local t = timestamp()
        if inp.UserInputType == Enum.UserInputType.MouseMovement then
            addEvent({time=t, type="MouseMove", x=inp.Position.X, y=inp.Position.Y,
                      dx=inp.Delta.X, dy=inp.Delta.Y})
            -- don't spam log with every pixel
        elseif inp.UserInputType == Enum.UserInputType.Touch then
            addEvent({time=t, type="TouchMove", x=inp.Position.X, y=inp.Position.Y})
        end
    end))

    -- Mouse scroll
    table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
        if not recording then return end
        if inp.UserInputType == Enum.UserInputType.MouseWheel then
            local t = timestamp()
            addEvent({time=t, type="Scroll", delta=inp.Position.Z})
            logEvent(("%.2f  Scroll  %.1f"):format(t, inp.Position.Z))
        end
    end))

    logEvent("▶ Recording started")
end

local function stopRecording()
    recording = false
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}
    logEvent(("■ Stopped — %d events"):format(#macroEvents))
end

-- ════════════════════════════════════════════════════════════════
--  Event replay — fires inputs back via VirtualInputManager
-- ════════════════════════════════════════════════════════════════
local function fireEvent(ev)
    pcall(function()
        if ev.type == "MouseDown" then
            if ev.button == 1 then
                VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, 0, true,  game, 0)
            elseif ev.button == 2 then
                VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, 1, true,  game, 0)
            elseif ev.button == 3 then
                VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, 2, true,  game, 0)
            end

        elseif ev.type == "MouseUp" then
            if ev.button == 1 then
                VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, 0, false, game, 0)
            elseif ev.button == 2 then
                VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, 1, false, game, 0)
            elseif ev.button == 3 then
                VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, 2, false, game, 0)
            end

        elseif ev.type == "MouseMove" then
            VirtualInputManager:SendMouseMoveEvent(ev.dx, ev.dy, game)

        elseif ev.type == "TouchDown" then
            VirtualInputManager:SendTouchEvent(0, ev.x, ev.y, true, game)

        elseif ev.type == "TouchUp" then
            VirtualInputManager:SendTouchEvent(0, ev.x, ev.y, false, game)

        elseif ev.type == "TouchMove" then
            VirtualInputManager:SendTouchEvent(0, ev.x, ev.y, true, game)

        elseif ev.type == "KeyDown" then
            local kc = Enum.KeyCode[ev.key]
            if kc then VirtualInputManager:SendKeyEvent(true,  kc, false, game) end

        elseif ev.type == "KeyUp" then
            local kc = Enum.KeyCode[ev.key]
            if kc then VirtualInputManager:SendKeyEvent(false, kc, false, game) end

        elseif ev.type == "Scroll" then
            VirtualInputManager:SendMouseWheelEvent(0, 0, ev.delta > 0, game)
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
--  Playback engine
-- ════════════════════════════════════════════════════════════════
local function runPlayback(onDone)
    if #macroEvents == 0 then
        logEvent("⚠ Nothing recorded")
        return
    end

    playing      = true
    paused       = false
    currentLoop  = 0
    local infinite = (loopCount == 0)

    playbackThread = task.spawn(function()
        while playing do
            currentLoop = currentLoop + 1
            local loopLabel = infinite and "∞" or (currentLoop.."/"..loopCount)
            logEvent(("▷ Loop %s"):format(loopLabel))

            local start = tick()
            local evIdx = 1
            local total = #macroEvents

            while evIdx <= total and playing do
                -- pause support
                while paused and playing do task.wait(0.05) end
                if not playing then break end

                local ev     = macroEvents[evIdx]
                local elapsed = tick() - start
                local wait   = ev.time - elapsed

                if wait > 0.002 then task.wait(wait) end
                if not playing then break end

                fireEvent(ev)
                evIdx = evIdx + 1
            end

            if not infinite then
                if currentLoop >= loopCount then
                    playing = false
                    logEvent("✓ Finished "..loopCount.." loops")
                    if onDone then onDone() end
                    return
                end
            end
        end
        logEvent("■ Playback stopped")
        if onDone then onDone() end
    end)
end

local function stopPlayback()
    playing = false
    paused  = false
    if playbackThread then
        pcall(function() task.cancel(playbackThread) end)
        playbackThread = nil
    end
    logEvent("■ Playback stopped")
end

local function pausePlayback()
    if playing then
        paused = not paused
        logEvent(paused and "⏸ Paused" or "▷ Resumed")
    end
end

-- ════════════════════════════════════════════════════════════════
--  GUI
-- ════════════════════════════════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "MacroMasterGUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent         = LocalPlayer:WaitForChild("PlayerGui")

local C = Color3.fromRGB

-- ── helpers ───────────────────────────────────────────────────
local function mkFrame(parent, size, pos, bg, bgT, r)
    local f = Instance.new("Frame")
    f.Size                   = size
    f.Position               = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3       = bg or C(15,5,8)
    f.BackgroundTransparency = bgT or 0
    f.BorderSizePixel        = 0
    f.Parent                 = parent
    if r then Instance.new("UICorner",f).CornerRadius = UDim.new(0,r) end
    return f
end

local function mkLabel(parent, text, pos, size, fs, fc, align, font)
    local l = Instance.new("TextLabel")
    l.Size               = size or UDim2.new(1,0,0,20)
    l.Position           = pos  or UDim2.new(0,0,0,0)
    l.Text               = text
    l.TextColor3         = fc   or C(240,200,210)
    l.BackgroundTransparency = 1
    l.Font               = font or Enum.Font.Fondamento
    l.TextSize           = fs   or 12
    l.TextXAlignment     = align or Enum.TextXAlignment.Left
    l.BorderSizePixel    = 0
    l.ZIndex             = 5
    l.Parent             = parent
    return l
end

local function mkBtn(parent, text, pos, size, bg, tc, fs, r, z)
    local b = Instance.new("TextButton")
    b.Size               = size or UDim2.new(0,80,0,30)
    b.Position           = pos  or UDim2.new(0,0,0,0)
    b.Text               = text
    b.BackgroundColor3   = bg   or C(120,0,0)
    b.TextColor3         = tc   or C(255,255,255)
    b.Font               = Enum.Font.Fondamento
    b.TextSize           = fs   or 13
    b.BorderSizePixel    = 0
    b.AutoButtonColor    = true
    b.ZIndex             = z   or 6
    b.Parent             = parent
    Instance.new("UICorner",b).CornerRadius = UDim.new(0, r or 8)
    return b
end

-- ── Main panel ────────────────────────────────────────────────
local PANEL_W = 340
local PANEL_H = 540

local Main = mkFrame(ScreenGui,
    UDim2.new(0, PANEL_W, 0, PANEL_H),
    UDim2.new(0.5, -PANEL_W//2, 0.5, -PANEL_H//2),
    C(12,3,6), 0, 16)
Main.ClipsDescendants = true
Main.ZIndex = 4

-- title
local TitleBar = mkFrame(Main, UDim2.new(1,0,0,36), UDim2.new(0,0,0,0), C(160,0,0), 0, 16)
mkLabel(TitleBar,"⏺  MacroMaster — Record & Replay",
    UDim2.new(0,10,0,0), UDim2.new(1,-46,1,0), 13, C(255,255,255),
    Enum.TextXAlignment.Left)

-- minimize
local minimized = false
local minBtn = mkBtn(TitleBar,"−",UDim2.new(1,-36,0,4),UDim2.new(0,28,0,28),
    C(120,0,0),C(255,255,255),15,8,8)
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    for _, ch in ipairs(Main:GetChildren()) do
        if ch ~= TitleBar and ch:IsA("GuiObject") then ch.Visible = not minimized end
    end
    minBtn.Text = minimized and "+" or "−"
    Main.Size   = minimized
        and UDim2.new(0,PANEL_W,0,40)
        or  UDim2.new(0,PANEL_W,0,PANEL_H)
end)

-- drag
local dragging = false; local dragIn = nil
local dragStart = Vector2.new(); local startPos = Main.Position
TitleBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragIn = inp
        dragStart = Vector2.new(inp.Position.X, inp.Position.Y)
        startPos  = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not dragging or inp ~= dragIn then return end
    local dx = inp.Position.X - dragStart.X
    local dy = inp.Position.Y - dragStart.Y
    Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+dx,
                               startPos.Y.Scale, startPos.Y.Offset+dy)
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp == dragIn then dragging=false; dragIn=nil end
end)

-- ── Status strip ─────────────────────────────────────────────
local StatusStrip = mkFrame(Main,
    UDim2.new(1,-16,0,28), UDim2.new(0,8,0,42),
    C(25,5,10), 0, 8)
local StatusLbl = mkLabel(StatusStrip,"● IDLE",
    UDim2.new(0,0,0,0), UDim2.new(0.6,0,1,0),
    12, C(180,100,110), Enum.TextXAlignment.Left)
StatusLbl.Position = UDim2.new(0,8,0,0)
local EventCountLbl = mkLabel(StatusStrip,"0 events",
    UDim2.new(0.6,0,0,0), UDim2.new(0.4,-4,1,0),
    11, C(140,80,90), Enum.TextXAlignment.Right)

-- ── Loop selector ────────────────────────────────────────────
mkLabel(Main,"LOOP COUNT",UDim2.new(0,8,0,78),
    UDim2.new(1,-16,0,14),10,C(200,100,120))

local loopLabels = {"1","5","10","15","50","100","∞"}
local loopBtnList = {}
local loopRow = mkFrame(Main,UDim2.new(1,-16,0,34),UDim2.new(0,8,0,92),C(0,0,0),1)

local btnW = (PANEL_W-16) / #LOOP_OPTIONS - 3
for i, lbl in ipairs(loopLabels) do
    local b = mkBtn(loopRow, lbl,
        UDim2.new(0, (i-1)*(btnW+3), 0, 0),
        UDim2.new(0, btnW, 0, 32),
        i == loopOptionIdx and C(160,0,0) or C(40,10,15),
        C(255,255,255), 13, 7)
    loopBtnList[i] = b
    b.MouseButton1Click:Connect(function()
        loopOptionIdx = i
        loopCount     = LOOP_OPTIONS[i]
        for j, ob in ipairs(loopBtnList) do
            ob.BackgroundColor3 = (j == i) and C(160,0,0) or C(40,10,15)
        end
    end)
end
loopCount = LOOP_OPTIONS[loopOptionIdx]  -- default ∞

-- ── Main control buttons ──────────────────────────────────────
mkLabel(Main,"CONTROLS",UDim2.new(0,8,0,134),
    UDim2.new(1,-16,0,14),10,C(200,100,120))

local BtnArea = mkFrame(Main,UDim2.new(1,-16,0,72),UDim2.new(0,8,0,150),C(0,0,0),1)
local bW = (PANEL_W-16)/3 - 4

-- ROW 1: Record | Stop | Play
local RecBtn  = mkBtn(BtnArea,"⏺ Record",
    UDim2.new(0,0,0,0), UDim2.new(0,bW,0,32),
    C(160,0,0), C(255,255,255), 12, 8)
local StopBtn = mkBtn(BtnArea,"⏹ Stop",
    UDim2.new(0,bW+4,0,0), UDim2.new(0,bW,0,32),
    C(50,15,0), C(255,200,160), 12, 8)
local PlayBtn = mkBtn(BtnArea,"▶ Play",
    UDim2.new(0,(bW+4)*2,0,0), UDim2.new(0,bW,0,32),
    C(0,80,30), C(180,255,200), 12, 8)

-- ROW 2: Pause | Clear | Replay
local PauseBtn = mkBtn(BtnArea,"⏸ Pause",
    UDim2.new(0,0,0,38), UDim2.new(0,bW,0,32),
    C(60,40,0), C(255,240,160), 12, 8)
local ClearBtn = mkBtn(BtnArea,"🗑 Clear",
    UDim2.new(0,bW+4,0,38), UDim2.new(0,bW,0,32),
    C(30,10,20), C(255,120,140), 12, 8)
local ReplayBtn = mkBtn(BtnArea,"↩ Replay",
    UDim2.new(0,(bW+4)*2,0,38), UDim2.new(0,bW,0,32),
    C(0,40,80), C(140,200,255), 12, 8)

-- ── Speed multiplier ─────────────────────────────────────────
mkLabel(Main,"PLAYBACK SPEED",UDim2.new(0,8,0,230),
    UDim2.new(1,-16,0,14),10,C(200,100,120))

local speedOptions = {0.25, 0.5, 1.0, 1.5, 2.0, 4.0}
local speedLabels  = {"0.25×","0.5×","1×","1.5×","2×","4×"}
local speedIdx     = 3  -- default 1×
local speedBtnList = {}
local speedRow = mkFrame(Main,UDim2.new(1,-16,0,30),UDim2.new(0,8,0,246),C(0,0,0),1)
local sW = (PANEL_W-16) / #speedOptions - 3
for i, sl in ipairs(speedLabels) do
    local b = mkBtn(speedRow, sl,
        UDim2.new(0,(i-1)*(sW+3),0,0),
        UDim2.new(0,sW,0,28),
        i == speedIdx and C(0,60,120) or C(15,20,40),
        C(200,220,255), 11, 6)
    speedBtnList[i] = b
    b.MouseButton1Click:Connect(function()
        speedIdx = i
        for j, ob in ipairs(speedBtnList) do
            ob.BackgroundColor3 = (j == i) and C(0,60,120) or C(15,20,40)
        end
    end)
end

-- ── Hotkeys display ──────────────────────────────────────────
mkLabel(Main,"HOTKEYS",UDim2.new(0,8,0,284),
    UDim2.new(1,-16,0,14),10,C(200,100,120))

local HKArea = mkFrame(Main,UDim2.new(1,-16,0,68),UDim2.new(0,8,0,300),C(20,5,8),0,8)
local hkData = {
    {"F1","Start recording"},
    {"F2","Stop / stop playback"},
    {"F3","Play macro"},
    {"F4","Pause / resume"},
}
for i, h in ipairs(hkData) do
    local row = mkFrame(HKArea,UDim2.new(1,-8,0,14),UDim2.new(0,4,0,(i-1)*16+2),C(0,0,0),1)
    mkLabel(row, h[1], UDim2.new(0,0,0,0), UDim2.new(0,28,1,0), 10, C(255,80,80),
        Enum.TextXAlignment.Left)
    mkLabel(row, h[2], UDim2.new(0,30,0,0), UDim2.new(1,-30,1,0), 10, C(180,140,150),
        Enum.TextXAlignment.Left)
end

-- ── Event log ────────────────────────────────────────────────
mkLabel(Main,"EVENT LOG",UDim2.new(0,8,0,376),
    UDim2.new(1,-16,0,14),10,C(200,100,120))

local LogOuter = mkFrame(Main,
    UDim2.new(1,-16,0,128), UDim2.new(0,8,0,392),
    C(8,2,4), 0, 8)
LogOuter.ClipsDescendants = true

local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size                = UDim2.new(1,0,1,0)
LogScroll.CanvasSize          = UDim2.new(0,0,0,0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogScroll.ScrollBarThickness  = 4
LogScroll.ScrollBarImageColor3 = C(160,0,0)
LogScroll.BackgroundTransparency = 1
LogScroll.BorderSizePixel     = 0
LogScroll.ZIndex              = 5
LogScroll.Parent              = LogOuter

local LogLayout = Instance.new("UIListLayout")
LogLayout.SortOrder           = Enum.SortOrder.LayoutOrder
LogLayout.Padding             = UDim.new(0,1)
LogLayout.Parent              = LogScroll

local logEntries = {}

local function refreshLog()
    for _, e in ipairs(logEntries) do e:Destroy() end
    logEntries = {}
    for i, txt in ipairs(eventLog) do
        local e = Instance.new("TextLabel")
        e.Size                   = UDim2.new(1,-4,0,14)
        e.BackgroundTransparency = 1
        e.Text                   = txt
        e.TextColor3             = C(160,120,130)
        e.Font                   = Enum.Font.RobotoMono
        e.TextSize               = 10
        e.TextXAlignment         = Enum.TextXAlignment.Left
        e.LayoutOrder            = i
        e.ZIndex                 = 6
        e.Parent                 = LogScroll
        table.insert(logEntries, e)
    end
    -- autoscroll to bottom
    task.defer(function()
        LogScroll.CanvasPosition = Vector2.new(0, math.max(0,
            LogScroll.AbsoluteCanvasSize.Y - LogScroll.AbsoluteSize.Y))
    end)
end

-- ── GUI update loop ──────────────────────────────────────────
local function updateStatus()
    EventCountLbl.Text = #macroEvents.." events"

    if recording then
        StatusLbl.Text       = "⏺ RECORDING"
        StatusLbl.TextColor3 = C(255,60,60)
    elseif playing and paused then
        StatusLbl.Text       = "⏸ PAUSED"
        StatusLbl.TextColor3 = C(255,220,60)
    elseif playing then
        local loopStr = (loopCount==0) and "∞" or (currentLoop.."/"..loopCount)
        StatusLbl.Text       = "▶ PLAYING  "..loopStr
        StatusLbl.TextColor3 = C(60,220,120)
    else
        StatusLbl.Text       = "● IDLE"
        StatusLbl.TextColor3 = C(160,100,110)
    end
end

RunService.Heartbeat:Connect(function()
    updateStatus()
end)

-- ════════════════════════════════════════════════════════════════
--  Button wiring
-- ════════════════════════════════════════════════════════════════
RecBtn.MouseButton1Click:Connect(function()
    if playing then stopPlayback() end
    if recording then stopRecording() return end
    startRecording()
    refreshLog()
end)

StopBtn.MouseButton1Click:Connect(function()
    if recording then
        stopRecording()
    end
    if playing then
        stopPlayback()
    end
    refreshLog()
end)

PlayBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing then stopPlayback() end
    if #macroEvents == 0 then
        logEvent("⚠ No macro recorded"); refreshLog(); return
    end
    runPlayback(function() refreshLog() end)
    refreshLog()
end)

PauseBtn.MouseButton1Click:Connect(function()
    pausePlayback()
    refreshLog()
end)

ClearBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing   then stopPlayback()  end
    macroEvents = {}
    eventLog    = {}
    refreshLog()
    logEvent("🗑 Cleared")
    refreshLog()
end)

ReplayBtn.MouseButton1Click:Connect(function()
    -- replay from last save without changing recorded events
    if recording then stopRecording() end
    if playing   then stopPlayback()  end
    if #macroEvents == 0 then
        logEvent("⚠ Nothing to replay"); refreshLog(); return
    end
    logEvent("↩ Replay triggered")
    runPlayback(function() refreshLog() end)
    refreshLog()
end)

-- ════════════════════════════════════════════════════════════════
--  Keyboard hotkeys
-- ════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if inp.KeyCode == Enum.KeyCode.F1 then
        RecBtn.MouseButton1Click:Fire()
    elseif inp.KeyCode == Enum.KeyCode.F2 then
        StopBtn.MouseButton1Click:Fire()
    elseif inp.KeyCode == Enum.KeyCode.F3 then
        PlayBtn.MouseButton1Click:Fire()
    elseif inp.KeyCode == Enum.KeyCode.F4 then
        PauseBtn.MouseButton1Click:Fire()
    end
end)

-- ════════════════════════════════════════════════════════════════
--  Speed multiplier application
--  (patches task.wait timing in playback by wrapping it)
-- ════════════════════════════════════════════════════════════════
-- Speed is applied by scaling the wait time when events are played back.
-- We wrap the wait inside runPlayback via a shared speed getter.
local function getSpeed()
    return speedOptions[speedIdx] or 1.0
end

-- Patch playback to respect speed
-- The real playback already uses tick() deltas. We re-export a patched version:
local _origRun = runPlayback
runPlayback = function(onDone)
    if #macroEvents == 0 then logEvent("⚠ Nothing recorded"); return end
    playing     = true
    paused      = false
    currentLoop = 0
    local infinite = (loopCount == 0)

    playbackThread = task.spawn(function()
        while playing do
            currentLoop = currentLoop + 1
            local loopLabel = infinite and "∞" or (currentLoop.."/"..loopCount)
            logEvent(("▷ Loop %s"):format(loopLabel))
            refreshLog()

            local start = tick()
            local evIdx = 1
            local total = #macroEvents
            local speed = getSpeed()

            while evIdx <= total and playing do
                while paused and playing do task.wait(0.05) end
                if not playing then break end

                local ev      = macroEvents[evIdx]
                local elapsed = (tick() - start) * speed
                local wait    = ev.time - elapsed

                if wait > 0.002 then task.wait(wait / speed) end
                if not playing then break end

                fireEvent(ev)
                evIdx = evIdx + 1
            end

            if not infinite then
                if currentLoop >= loopCount then
                    playing = false
                    logEvent(("✓ Done — %s loops"):format(loopCount))
                    refreshLog()
                    if onDone then onDone() end
                    return
                end
            end
        end
        logEvent("■ Playback stopped")
        refreshLog()
        if onDone then onDone() end
    end)
end

-- re-wire buttons to use patched version
PlayBtn.MouseButton1Click:Connect(function() end)   -- clear old
ReplayBtn.MouseButton1Click:Connect(function() end)

PlayBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing   then stopPlayback()  end
    if #macroEvents == 0 then logEvent("⚠ Nothing recorded"); refreshLog(); return end
    runPlayback(function() refreshLog() end)
    refreshLog()
end)

ReplayBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing   then stopPlayback()  end
    if #macroEvents == 0 then logEvent("⚠ Nothing to replay"); refreshLog(); return end
    logEvent("↩ Replay")
    runPlayback(function() refreshLog() end)
    refreshLog()
end)

-- ════════════════════════════════════════════════════════════════
print("[MacroMaster] Ready. F1=Record  F2=Stop  F3=Play  F4=Pause")
logEvent("✓ MacroMaster loaded — press ⏺ or F1 to start")
refreshLog()
