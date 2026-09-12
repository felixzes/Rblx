--[[
    MacroMaster v2 — Record & Replay
    Engine  : Roblox (executor environment)
    Author  : Zeus / DieStupidNinja
    Version : 2.0

    FIXES v2:
      • Mobile touch replay fixed — uses proper SendTouchEvent with
        touchId tracking so the game actually receives the touch
      • Play button auto-replays (infinite by default, or your chosen count)
      • Cleaner playback engine — no double-connection bug
      • Speed multiplier now correctly scales wait times
      • TouchMove events properly chained to their touchId

    Controls:
      F1 → Record
      F2 → Stop
      F3 → Play (auto-loops)
      F4 → Pause / Resume
]]

-- ════════════════════════════════════════════════════════════════════
--  Services
-- ════════════════════════════════════════════════════════════════════
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService          = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ════════════════════════════════════════════════════════════════════
--  Config
-- ════════════════════════════════════════════════════════════════════
local LOOP_OPTIONS  = {1, 5, 10, 15, 50, 100, 0}   -- 0 = ∞
local SPEED_OPTIONS = {0.25, 0.5, 1.0, 1.5, 2.0, 4.0}
local SPEED_LABELS  = {"0.25×","0.5×","1×","1.5×","2×","4×"}

-- ════════════════════════════════════════════════════════════════════
--  State
-- ════════════════════════════════════════════════════════════════════
local recording      = false
local playing        = false
local paused         = false
local macroEvents    = {}
local eventLog       = {}
local recordStart    = 0
local currentLoop    = 0
local loopCount      = 0          -- 0 = ∞
local speedMult      = 1.0
local playThread     = nil
local recConns       = {}
local loopIdx        = 7          -- default ∞
local speedIdx       = 3          -- default 1×
local MAX_LOG        = 40

-- touchId map: input object → slot index (0-9) for VirtualInputManager
local touchSlots     = {}
local nextSlot       = 0

local function getSlot(inp)
    if not touchSlots[inp] then
        touchSlots[inp] = nextSlot % 10
        nextSlot = nextSlot + 1
    end
    return touchSlots[inp]
end

local function freeSlot(inp)
    touchSlots[inp] = nil
end

-- ════════════════════════════════════════════════════════════════════
--  Logging
-- ════════════════════════════════════════════════════════════════════
local logRefreshFn = nil   -- set by GUI later

local function logAdd(txt)
    table.insert(eventLog, txt)
    if #eventLog > MAX_LOG then table.remove(eventLog, 1) end
    if logRefreshFn then logRefreshFn() end
end

local function ts()
    return tick() - recordStart
end

-- ════════════════════════════════════════════════════════════════════
--  Recording
-- ════════════════════════════════════════════════════════════════════
local function startRecording()
    if playing then return end
    macroEvents  = {}
    eventLog     = {}
    recordStart  = tick()
    recording    = true
    touchSlots   = {}
    nextSlot     = 0

    for _, c in ipairs(recConns) do c:Disconnect() end
    recConns = {}

    -- INPUT BEGAN
    table.insert(recConns, UserInputService.InputBegan:Connect(function(inp, gp)
        if not recording then return end
        local t = ts()
        local ut = inp.UserInputType
        local x, y = inp.Position.X, inp.Position.Y

        if ut == Enum.UserInputType.Touch then
            local slot = getSlot(inp)
            table.insert(macroEvents, {time=t, type="TD", slot=slot, x=x, y=y})
            logAdd(("%.2f  TouchDown #%d (%.0f,%.0f)"):format(t,slot,x,y))

        elseif ut == Enum.UserInputType.MouseButton1 then
            table.insert(macroEvents, {time=t, type="MD", btn=0, x=x, y=y})
            logAdd(("%.2f  MouseDown L"):format(t))
        elseif ut == Enum.UserInputType.MouseButton2 then
            table.insert(macroEvents, {time=t, type="MD", btn=1, x=x, y=y})
            logAdd(("%.2f  MouseDown R"):format(t))
        elseif ut == Enum.UserInputType.MouseButton3 then
            table.insert(macroEvents, {time=t, type="MD", btn=2, x=x, y=y})
            logAdd(("%.2f  MouseDown M"):format(t))

        elseif ut == Enum.UserInputType.Keyboard then
            table.insert(macroEvents, {time=t, type="KD", key=inp.KeyCode.Name})
            logAdd(("%.2f  KeyDown [%s]"):format(t, inp.KeyCode.Name))
        end
    end))

    -- INPUT CHANGED (move / scroll)
    table.insert(recConns, UserInputService.InputChanged:Connect(function(inp)
        if not recording then return end
        local t = ts()
        local ut = inp.UserInputType
        local x, y = inp.Position.X, inp.Position.Y

        if ut == Enum.UserInputType.Touch then
            local slot = getSlot(inp)
            table.insert(macroEvents, {time=t, type="TM", slot=slot, x=x, y=y})

        elseif ut == Enum.UserInputType.MouseMovement then
            table.insert(macroEvents, {time=t, type="MM",
                x=x, y=y, dx=inp.Delta.X, dy=inp.Delta.Y})

        elseif ut == Enum.UserInputType.MouseWheel then
            local d = inp.Position.Z
            table.insert(macroEvents, {time=t, type="MW", delta=d})
            logAdd(("%.2f  Scroll %.1f"):format(t,d))
        end
    end))

    -- INPUT ENDED
    table.insert(recConns, UserInputService.InputEnded:Connect(function(inp)
        if not recording then return end
        local t = ts()
        local ut = inp.UserInputType
        local x, y = inp.Position.X, inp.Position.Y

        if ut == Enum.UserInputType.Touch then
            local slot = getSlot(inp)
            table.insert(macroEvents, {time=t, type="TU", slot=slot, x=x, y=y})
            logAdd(("%.2f  TouchUp #%d"):format(t, slot))
            freeSlot(inp)

        elseif ut == Enum.UserInputType.MouseButton1 then
            table.insert(macroEvents, {time=t, type="MU", btn=0, x=x, y=y})
            logAdd(("%.2f  MouseUp L"):format(t))
        elseif ut == Enum.UserInputType.MouseButton2 then
            table.insert(macroEvents, {time=t, type="MU", btn=1, x=x, y=y})
            logAdd(("%.2f  MouseUp R"):format(t))
        elseif ut == Enum.UserInputType.MouseButton3 then
            table.insert(macroEvents, {time=t, type="MU", btn=2, x=x, y=y})
            logAdd(("%.2f  MouseUp M"):format(t))

        elseif ut == Enum.UserInputType.Keyboard then
            table.insert(macroEvents, {time=t, type="KU", key=inp.KeyCode.Name})
            logAdd(("%.2f  KeyUp [%s]"):format(t, inp.KeyCode.Name))
        end
    end))

    logAdd("⏺ Recording started")
end

local function stopRecording()
    if not recording then return end
    recording = false
    for _, c in ipairs(recConns) do c:Disconnect() end
    recConns = {}
    logAdd(("■ Stopped — %d events captured"):format(#macroEvents))
end

-- ════════════════════════════════════════════════════════════════════
--  Fire a single event
-- ════════════════════════════════════════════════════════════════════
local function fireEv(ev)
    pcall(function()
        local t = ev.type

        -- ── TOUCH ──────────────────────────────────────────────────
        if t == "TD" then
            -- SendTouchEvent(touchId, x, y, began, game, 1)
            VirtualInputManager:SendTouchEvent(ev.slot, ev.x, ev.y, true, game)

        elseif t == "TM" then
            VirtualInputManager:SendTouchEvent(ev.slot, ev.x, ev.y, true, game)

        elseif t == "TU" then
            VirtualInputManager:SendTouchEvent(ev.slot, ev.x, ev.y, false, game)

        -- ── MOUSE ──────────────────────────────────────────────────
        elseif t == "MD" then
            VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, ev.btn, true,  game, 1)

        elseif t == "MU" then
            VirtualInputManager:SendMouseButtonEvent(ev.x, ev.y, ev.btn, false, game, 1)

        elseif t == "MM" then
            VirtualInputManager:SendMouseMoveEvent(ev.dx or 0, ev.dy or 0, game)

        elseif t == "MW" then
            VirtualInputManager:SendMouseWheelEvent(ev.x or 0, ev.y or 0,
                ev.delta > 0, game)

        -- ── KEYBOARD ───────────────────────────────────────────────
        elseif t == "KD" then
            local kc = Enum.KeyCode[ev.key]
            if kc then VirtualInputManager:SendKeyEvent(true,  kc, false, game) end

        elseif t == "KU" then
            local kc = Enum.KeyCode[ev.key]
            if kc then VirtualInputManager:SendKeyEvent(false, kc, false, game) end
        end
    end)
end

-- ════════════════════════════════════════════════════════════════════
--  Playback engine
-- ════════════════════════════════════════════════════════════════════
local onPlayDone = nil   -- callback when fully done

local function stopPlayback(quiet)
    playing = false
    paused  = false
    if playThread then
        pcall(task.cancel, playThread)
        playThread = nil
    end
    if not quiet then logAdd("■ Playback stopped") end
end

local function startPlayback()
    if recording then stopRecording() end
    if playing   then stopPlayback(true) end
    if #macroEvents == 0 then logAdd("⚠ Nothing recorded"); return end

    playing      = true
    paused       = false
    currentLoop  = 0
    local infinite = (loopCount == 0)

    playThread = task.spawn(function()
        while playing do
            currentLoop = currentLoop + 1
            local loopStr = infinite and "∞" or (currentLoop.."/"..loopCount)
            logAdd(("▶ Loop %s"):format(loopStr))

            local events  = macroEvents   -- snapshot
            local total   = #events
            local start   = tick()
            local speed   = speedMult
            local i       = 1

            while i <= total and playing do
                -- pause gate
                while paused and playing do task.wait(0.03) end
                if not playing then break end

                local ev = events[i]
                -- how long should have passed since loop start at this speed
                local targetT = ev.time / speed
                local elapsed = tick() - start
                local waitT   = targetT - elapsed

                if waitT > 0.001 then
                    task.wait(waitT)
                end
                if not playing then break end

                fireEv(ev)
                i = i + 1
            end

            -- loop end
            if not playing then break end

            if not infinite and currentLoop >= loopCount then
                playing = false
                logAdd(("✓ Done — %d loop%s"):format(loopCount, loopCount==1 and "" or "s"))
                if onPlayDone then onPlayDone() end
                return
            end

            -- tiny gap between loops so game state can settle
            task.wait(0.05)
        end

        logAdd("■ Playback ended")
        if onPlayDone then onPlayDone() end
    end)
end

local function pauseResume()
    if not playing then return end
    paused = not paused
    logAdd(paused and "⏸ Paused" or "▶ Resumed")
end

local function clearMacro()
    if recording then stopRecording() end
    if playing   then stopPlayback()  end
    macroEvents = {}
    eventLog    = {}
    logAdd("🗑 Cleared")
end

-- ════════════════════════════════════════════════════════════════════
--  GUI
-- ════════════════════════════════════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = "MacroMasterV2"
ScreenGui.ResetOnSpawn    = false
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset  = true
ScreenGui.Parent          = LocalPlayer:WaitForChild("PlayerGui")

local C = Color3.fromRGB

local function mkFrame(par, size, pos, bg, bgT, r, z)
    local f = Instance.new("Frame")
    f.Size                   = size
    f.Position               = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3       = bg  or C(14,4,7)
    f.BackgroundTransparency = bgT or 0
    f.BorderSizePixel        = 0
    f.ZIndex                 = z   or 4
    f.Parent                 = par
    if r then Instance.new("UICorner",f).CornerRadius = UDim.new(0,r) end
    return f
end

local function mkLbl(par, text, pos, size, fs, fc, ax, z)
    local l = Instance.new("TextLabel")
    l.Size               = size or UDim2.new(1,0,0,20)
    l.Position           = pos  or UDim2.new(0,0,0,0)
    l.Text               = text
    l.TextColor3         = fc   or C(230,190,200)
    l.BackgroundTransparency = 1
    l.Font               = Enum.Font.Fondamento
    l.TextSize           = fs   or 12
    l.TextXAlignment     = ax   or Enum.TextXAlignment.Left
    l.BorderSizePixel    = 0
    l.ZIndex             = z    or 6
    l.Parent             = par
    return l
end

local function mkBtn(par, text, pos, size, bg, tc, fs, r, z)
    local b = Instance.new("TextButton")
    b.Size               = size or UDim2.new(0,70,0,32)
    b.Position           = pos  or UDim2.new(0,0,0,0)
    b.Text               = text
    b.BackgroundColor3   = bg   or C(120,0,0)
    b.TextColor3         = tc   or C(255,255,255)
    b.Font               = Enum.Font.Fondamento
    b.TextSize           = fs   or 13
    b.BorderSizePixel    = 0
    b.AutoButtonColor    = true
    b.ZIndex             = z    or 7
    b.Parent             = par
    Instance.new("UICorner",b).CornerRadius = UDim.new(0, r or 8)
    return b
end

local function mkSec(par, text, y)
    local l = mkLbl(par, text,
        UDim2.new(0,8,0,y), UDim2.new(1,-16,0,13),
        9, C(200,80,100), Enum.TextXAlignment.Left, 6)
    l.Font = Enum.Font.GothamBold
    return l
end

-- ── Main frame ───────────────────────────────────────────────────
local PW, PH = 320, 560
local Main = mkFrame(ScreenGui,
    UDim2.new(0,PW,0,PH),
    UDim2.new(0.5,-PW/2,0.5,-PH/2),
    C(12,3,6), 0, 16, 4)
Main.ClipsDescendants = true

-- title bar
local TBar = mkFrame(Main, UDim2.new(1,0,0,38),
    UDim2.new(0,0,0,0), C(150,0,0), 0, 16, 5)
mkLbl(TBar,"⏺  MacroMaster v2",
    UDim2.new(0,10,0,0),UDim2.new(1,-46,1,0),
    14,C(255,255,255),Enum.TextXAlignment.Left,6)

-- minimize
local minBtn = mkBtn(TBar,"−",
    UDim2.new(1,-34,0,5),UDim2.new(0,26,0,26),
    C(110,0,0),C(255,255,255),15,7,8)
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    for _, ch in ipairs(Main:GetChildren()) do
        if ch ~= TBar and ch:IsA("GuiObject") then ch.Visible = not minimized end
    end
    minBtn.Text = minimized and "+" or "−"
    Main.Size   = minimized
        and UDim2.new(0,PW,0,40)
        or  UDim2.new(0,PW,0,PH)
end)

-- drag
local drag={active=false,inp=nil,start=Vector2.new(),pos=Main.Position}
TBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then
        drag.active=true;drag.inp=i
        drag.start=Vector2.new(i.Position.X,i.Position.Y)
        drag.pos=Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if not drag.active or i~=drag.inp then return end
    local dx=i.Position.X-drag.start.X
    local dy=i.Position.Y-drag.start.Y
    Main.Position=UDim2.new(drag.pos.X.Scale,drag.pos.X.Offset+dx,
                             drag.pos.Y.Scale,drag.pos.Y.Offset+dy)
end)
UserInputService.InputEnded:Connect(function(i)
    if i==drag.inp then drag.active=false;drag.inp=nil end
end)

-- ── Status bar ───────────────────────────────────────────────────
local StatusF = mkFrame(Main,UDim2.new(1,-16,0,30),UDim2.new(0,8,0,44),
    C(22,5,10),0,8,5)
local StatusLbl = mkLbl(StatusF,"● IDLE",
    UDim2.new(0,8,0,0),UDim2.new(0.58,0,1,0),
    12,C(180,100,110),Enum.TextXAlignment.Left,6)
local CountLbl = mkLbl(StatusF,"0 events",
    UDim2.new(0.6,0,0,0),UDim2.new(0.4,-6,1,0),
    11,C(140,80,90),Enum.TextXAlignment.Right,6)

-- ── Loop count ───────────────────────────────────────────────────
mkSec(Main,"LOOP COUNT",82)
local LOOP_LABELS={"1","5","10","15","50","100","∞"}
local loopBtns={}
local loopRow=mkFrame(Main,UDim2.new(1,-16,0,32),UDim2.new(0,8,0,96),C(0,0,0),1,0,5)
local lbW = (PW-16)/#LOOP_OPTIONS - 3
for i=1,#LOOP_OPTIONS do
    local b=mkBtn(loopRow,LOOP_LABELS[i],
        UDim2.new(0,(i-1)*(lbW+3),0,0),
        UDim2.new(0,lbW,0,30),
        i==loopIdx and C(160,0,0) or C(35,10,15),
        C(255,255,255),12,6,7)
    loopBtns[i]=b
    b.MouseButton1Click:Connect(function()
        loopIdx  = i
        loopCount= LOOP_OPTIONS[i]
        for j,ob in ipairs(loopBtns) do
            ob.BackgroundColor3=(j==i) and C(160,0,0) or C(35,10,15)
        end
    end)
end

-- ── Main buttons ─────────────────────────────────────────────────
mkSec(Main,"CONTROLS",136)

local CtrlF=mkFrame(Main,UDim2.new(1,-16,0,76),UDim2.new(0,8,0,152),C(0,0,0),1,0,5)
local cbW=(PW-16)/3-4

-- row 1
local RecBtn  = mkBtn(CtrlF,"⏺ Record",
    UDim2.new(0,0,0,0),UDim2.new(0,cbW,0,34),
    C(160,0,0),C(255,255,255),12,8)
local StopBtn = mkBtn(CtrlF,"⏹ Stop",
    UDim2.new(0,cbW+4,0,0),UDim2.new(0,cbW,0,34),
    C(60,20,0),C(255,210,170),12,8)
local PlayBtn = mkBtn(CtrlF,"▶ Play",
    UDim2.new(0,(cbW+4)*2,0,0),UDim2.new(0,cbW,0,34),
    C(0,90,30),C(180,255,200),12,8)

-- row 2
local PauseBtn = mkBtn(CtrlF,"⏸ Pause",
    UDim2.new(0,0,0,40),UDim2.new(0,cbW,0,34),
    C(70,50,0),C(255,240,160),12,8)
local ClearBtn = mkBtn(CtrlF,"🗑 Clear",
    UDim2.new(0,cbW+4,0,40),UDim2.new(0,cbW,0,34),
    C(35,10,25),C(255,120,140),12,8)
local ReplayBtn= mkBtn(CtrlF,"↩ Replay",
    UDim2.new(0,(cbW+4)*2,0,40),UDim2.new(0,cbW,0,34),
    C(0,45,90),C(140,200,255),12,8)

-- ── Speed ────────────────────────────────────────────────────────
mkSec(Main,"PLAYBACK SPEED",237)
local speedBtns={}
local speedRow=mkFrame(Main,UDim2.new(1,-16,0,30),UDim2.new(0,8,0,252),C(0,0,0),1,0,5)
local sbW=(PW-16)/#SPEED_OPTIONS-3
for i=1,#SPEED_OPTIONS do
    local b=mkBtn(speedRow,SPEED_LABELS[i],
        UDim2.new(0,(i-1)*(sbW+3),0,0),
        UDim2.new(0,sbW,0,28),
        i==speedIdx and C(0,60,130) or C(15,20,45),
        C(200,225,255),11,6,7)
    speedBtns[i]=b
    b.MouseButton1Click:Connect(function()
        speedIdx  = i
        speedMult = SPEED_OPTIONS[i]
        for j,ob in ipairs(speedBtns) do
            ob.BackgroundColor3=(j==i) and C(0,60,130) or C(15,20,45)
        end
    end)
end
speedMult = SPEED_OPTIONS[speedIdx]

-- ── Hotkeys ──────────────────────────────────────────────────────
mkSec(Main,"HOTKEYS",292)
local hkF=mkFrame(Main,UDim2.new(1,-16,0,52),UDim2.new(0,8,0,308),C(20,5,8),0,8,5)
local hkData={{"F1","Record"},{"F2","Stop"},{"F3","Play / auto-loop"},{"F4","Pause/Resume"}}
for i,h in ipairs(hkData) do
    local row=mkFrame(hkF,UDim2.new(1,-6,0,12),UDim2.new(0,3,0,(i-1)*13),C(0,0,0),1,0,6)
    mkLbl(row,h[1],UDim2.new(0,0,0,0),UDim2.new(0,26,1,0),9,C(255,70,70),Enum.TextXAlignment.Left,7)
    mkLbl(row,h[2],UDim2.new(0,28,0,0),UDim2.new(1,-28,1,0),9,C(170,130,140),Enum.TextXAlignment.Left,7)
end

-- ── Event log ────────────────────────────────────────────────────
mkSec(Main,"EVENT LOG",370)
local LogOuter=mkFrame(Main,UDim2.new(1,-16,0,160),UDim2.new(0,8,0,386),C(7,2,4),0,8,5)
LogOuter.ClipsDescendants=true

local LogScroll=Instance.new("ScrollingFrame")
LogScroll.Size                = UDim2.new(1,0,1,0)
LogScroll.CanvasSize          = UDim2.new(0,0,0,0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogScroll.ScrollBarThickness  = 4
LogScroll.ScrollBarImageColor3= C(160,0,0)
LogScroll.BackgroundTransparency=1
LogScroll.BorderSizePixel     = 0
LogScroll.ZIndex              = 6
LogScroll.Parent              = LogOuter

local LogLayout=Instance.new("UIListLayout")
LogLayout.SortOrder   = Enum.SortOrder.LayoutOrder
LogLayout.Padding     = UDim.new(0,1)
LogLayout.Parent      = LogScroll

local logEntryFrames={}

local function refreshLog()
    for _,e in ipairs(logEntryFrames) do e:Destroy() end
    logEntryFrames={}
    for i,txt in ipairs(eventLog) do
        local e=Instance.new("TextLabel")
        e.Size                   = UDim2.new(1,-4,0,13)
        e.BackgroundTransparency = 1
        e.Text                   = txt
        e.TextColor3             = C(150,110,120)
        e.Font                   = Enum.Font.RobotoMono
        e.TextSize               = 10
        e.TextXAlignment         = Enum.TextXAlignment.Left
        e.LayoutOrder            = i
        e.ZIndex                 = 7
        e.Parent                 = LogScroll
        table.insert(logEntryFrames,e)
    end
    task.defer(function()
        LogScroll.CanvasPosition=Vector2.new(0,
            math.max(0,LogScroll.AbsoluteCanvasSize.Y-LogScroll.AbsoluteSize.Y))
    end)
end

logRefreshFn = refreshLog   -- hook into logger

-- ── Status updater ───────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
    CountLbl.Text = #macroEvents.." events"
    if recording then
        StatusLbl.Text       = "⏺ REC  "..("%.1f"):format(ts()).."s"
        StatusLbl.TextColor3 = C(255,60,60)
        RecBtn.BackgroundColor3 = C(200,0,0)
    elseif playing and paused then
        StatusLbl.Text       = "⏸ PAUSED"
        StatusLbl.TextColor3 = C(255,220,60)
        RecBtn.BackgroundColor3 = C(160,0,0)
    elseif playing then
        local ls = (loopCount==0) and "∞" or (currentLoop.."/"..loopCount)
        StatusLbl.Text       = "▶ LOOP "..ls
        StatusLbl.TextColor3 = C(60,220,120)
        RecBtn.BackgroundColor3 = C(160,0,0)
    else
        StatusLbl.Text       = "● IDLE"
        StatusLbl.TextColor3 = C(160,100,110)
        RecBtn.BackgroundColor3 = C(160,0,0)
    end
    PlayBtn.BackgroundColor3  = playing and C(0,120,40) or C(0,90,30)
    PauseBtn.BackgroundColor3 = paused  and C(120,90,0) or C(70,50,0)
end)

-- ════════════════════════════════════════════════════════════════════
--  Button wiring
-- ════════════════════════════════════════════════════════════════════
RecBtn.MouseButton1Click:Connect(function()
    if recording then
        stopRecording()
    else
        if playing then stopPlayback() end
        startRecording()
    end
end)

StopBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    if playing   then stopPlayback()  end
end)

-- PLAY — auto loops (infinite by default), just starts and keeps going
PlayBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    startPlayback()   -- always restarts, always auto-loops per loopCount
end)

PauseBtn.MouseButton1Click:Connect(function()
    pauseResume()
end)

ClearBtn.MouseButton1Click:Connect(function()
    clearMacro()
end)

ReplayBtn.MouseButton1Click:Connect(function()
    if recording then stopRecording() end
    startPlayback()
end)

-- ════════════════════════════════════════════════════════════════════
--  Keyboard hotkeys
-- ════════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if inp.KeyCode == Enum.KeyCode.F1 then RecBtn.MouseButton1Click:Fire()
    elseif inp.KeyCode == Enum.KeyCode.F2 then StopBtn.MouseButton1Click:Fire()
    elseif inp.KeyCode == Enum.KeyCode.F3 then PlayBtn.MouseButton1Click:Fire()
    elseif inp.KeyCode == Enum.KeyCode.F4 then PauseBtn.MouseButton1Click:Fire()
    end
end)

-- ════════════════════════════════════════════════════════════════════
logAdd("✓ MacroMaster v2 ready — F1 record · F3 play (auto-loops)")
refreshLog()
print("[MacroMaster v2] Loaded. F1=Record  F2=Stop  F3=Play  F4=Pause")
