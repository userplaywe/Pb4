-- Luau | Roblox executor | Practical Basketball | Unified Elite Suite v4: full taxonomy build

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- RE-EXECUTION GUARD / CLEANUP
-- ============================================================================
local env = (getgenv and getgenv()) or _G
if env.LunyxPB_Unload then pcall(env.LunyxPB_Unload) end

local Connections, Cleanups = {}, {}
local function Bind(conn) table.insert(Connections, conn) return conn end
local function OnUnload(fn) table.insert(Cleanups, fn) end

local Unloaded = false
local function Unload()
    Unloaded = true
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    for _, fn in ipairs(Cleanups) do pcall(fn) end
    table.clear(Connections)
    table.clear(Cleanups)
    env.LunyxPB_Unload = nil
end
env.LunyxPB_Unload = Unload

-- ============================================================================
-- CONFIG (taxonomy-mapped, 1:1 with the requested feature list)
-- ============================================================================
local Config = {
    Offense = {
        AutoTime = true,            -- meter/timing solver (was AutoGreen)
        ReleaseLead = 0.032, MatchPing = true, PingMultiplier = 1.0,
        AutoTune = true, CorrectionSize = 0.003, PrecisionWindow = 0.965,
        AutoShoot = false,
        AutoLob = false, LobRange = 22.0,
        AutoTricky = false, TrickyRange = 7.0,      -- FILL: confirm trick-finish modifier key in ACTIONS.Tricky
        AutoClutch = true, ClutchClockThreshold = 24.0, ClutchScoreMargin = 3,
        SmartJelly = true, JellyContestRange = 5.0,
        ShotGlide = true, ShotGlideForce = 14.0,
        ShotFeedback = true,
        LogShots = false,
        ContestBillboard = true,
    },
    Defense = {
        AutoGuard = true, StopAtRim = true, RimStopDistance = 6.0, ManualOverride = true,
        AutoBlock = true, BlockRange = 16.0, JumpDelay = 0.08, IgnorePumpFakes = true,
        OneHandBlock = false,                        -- FILL: confirm alt-contest key/remote arg
        AutoRebound = true, ReboundRange = 26.0,
        AutoRunUp = true, RunUpSpeedBoost = 6.0,
        AutoIntercept = true, InterceptRange = 18.0, InterceptMinBallSpeed = 25.0,
        OffBallDefense = true,
        StickyGuard = false, StickyRadius = 3.0,
        ScreenAvoidance = true, ScreenCheckRadius = 4.0,
        DefenseStrafe = true,
        CourtLines = false,                           -- FILL: real court corner CFrames below
        BlockGlide = true, BlockGlideForce = 16.0,
        ReboundGlide = true, ReboundGlideForce = 20.0,
        ReachGlide = true, ReachGlideForce = 10.0,
    },
    Handles = {
        AutoAnkleBreaker = false, AnkleBreakerRange = 5.0,
        DribbleCombos = false, ComboChainDelay = 0.28,
        MoveBinds = true,
        DribbleGlide = true, DribbleGlideForce = 18.0,
        DribbleBoost = false, DribbleBoostMultiplier = 1.15,
        PostGlide = false, PostGlideForce = 8.0,
        PostBoost = false, PostBoostMultiplier = 1.1,
    },
    Movement = {
        Speed = true, SpeedValue = 28.5,
        LegitSpeed = false, LegitSpeedValue = 19.0,     -- wins over Speed when true, ramps instead of snapping
        SpeedGlide = false, SpeedGlideForce = 6.0,
        SprintBoost = false, SprintBoostAdd = 4.0,       -- FILL: confirm sprint input (assumed LeftShift / R2)
        AutoCrab = false, CrabCooldown = 1.2,
        InfiniteStamina = true,
        AntiStun = true,
        BallGhost = false,
        StayInBounds = false,
        BoundsMinX = -100, BoundsMaxX = 100, BoundsMinZ = -60, BoundsMaxZ = 60, -- FILL: real court bounds
    },
    Extras = {
        PassLink = false, PassLeadTime = 0.25,
        AutoJoinSpot = false, SpotId = 0,                -- FILL: real spot/court id
        BurstAllCourts = false, BurstCooldown = 0.5,
    },
}

-- FILL: fill with real {id=, x=, z=} entries per court if BurstAllCourts is used
Config.Extras.CourtSpots = {}

local Telemetry = {
    ShotsTaken = 0, GreensHit = 0, LastDeviation = 0.0, CalibratedOffset = 0.0,
    CurrentPingMs = 0, LastStealTime = 0, LastBlockTime = 0, LastDribbleTick = 0,
    GuardingTarget = nil, OffBallTarget = nil, ClutchActive = false,
    LastCrabTick = 0, LastRunUpTick = 0,
}

local MAX_OFFSET = 0.08

local DribbleMoves = {
    { Name = "Crossover",        Code = "Cross",      Key = Enum.KeyCode.One },
    { Name = "Between The Legs", Code = "BTL",        Key = Enum.KeyCode.Two },
    { Name = "Behind The Back",  Code = "BTB",        Key = Enum.KeyCode.Three },
    { Name = "Hesitation",       Code = "Hesi",       Key = Enum.KeyCode.Four },
    { Name = "Spin Move",        Code = "Spin",       Key = Enum.KeyCode.Five },
    { Name = "Half Spin",        Code = "HalfSpin",   Key = Enum.KeyCode.Six },
    { Name = "In & Out",         Code = "InOut",      Key = Enum.KeyCode.Seven },
    { Name = "Stepback",         Code = "Stepback",   Key = Enum.KeyCode.Eight },
    { Name = "Snatchback",       Code = "Snatch",     Key = Enum.KeyCode.Nine },
    { Name = "Shamgod",          Code = "Shamgod",    Key = Enum.KeyCode.Zero },
    { Name = "Ankle Breaker",    Code = "Ankle",      Key = Enum.KeyCode.Z },
    { Name = "Crab",             Code = "Crab",       Key = Enum.KeyCode.X },
    { Name = "Killer Combo",     Code = "ComboChain", Key = Enum.KeyCode.C },
}

-- ============================================================================
-- PLATFORM + SHARED INPUT STATE
-- ============================================================================
local function IsPadMode()
    return UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

local function IsTouchMode()
    local l = UserInputService:GetLastInputType()
    if l == Enum.UserInputType.Touch then return true end
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
        and not UserInputService.MouseEnabled and not l.Name:find("Gamepad")
end

local MenuOpen, TouchPassHeld, SelectedMove = false, false, 1
local Toast = function(_) end
local ToggleMenu = function() end
OnUnload(function() TouchPassHeld = false end)

-- ============================================================================
-- LAZY REMOTES
-- FILL: confirm every name below against the game's real remotes (RemoteSpy)
-- ============================================================================
local RemoteNames = {
    Shoot = "ShootEvent", Pass = "PassEvent", Block = "BlockEvent", Steal = "StealEvent",
    Rebound = "ReboundEvent", Dribble = "DribbleEvent", Sprint = "SprintEvent",
    Queue = "JoinCourtEvent", Intercept = "InterceptEvent",
}
local RemoteCache, RemoteLookupT = {}, {}

local function Fire(key, ...)
    local r = RemoteCache[key]
    if not (r and r.Parent) then
        if tick() - (RemoteLookupT[key] or 0) < 2 then return end
        RemoteLookupT[key] = tick()
        r = ReplicatedStorage:FindFirstChild(RemoteNames[key], true)
        RemoteCache[key] = r
    end
    if r and r:IsA("RemoteEvent") then pcall(r.FireServer, r, ...) end
end

-- ============================================================================
-- HELPERS & CACHES
-- ============================================================================
local function GetPingSeconds()
    local ok, item = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"] end)
    local ms = (ok and item) and item:GetValue() or 40
    Telemetry.CurrentPingMs = math.floor(ms)
    return (ms / 1000) * Config.Offense.PingMultiplier
end

local function GetCharacter(plr)
    plr = plr or LocalPlayer
    local char = plr.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return nil end
    return char, hum, root
end

local Cache = { Ball = nil, BallT = 0, Rims = {}, RimT = -10, Meter = nil, Fill = nil, MeterT = 0,
                Handler = nil, HandlerChar = nil, HandlerT = 0 }

local function GetBall()
    local b = Cache.Ball
    if b and b.Parent then return b end
    if tick() - Cache.BallT < 0.25 then return nil end
    Cache.BallT = tick()
    for _, obj in ipairs(Workspace:GetChildren()) do
        local n = obj.Name:lower()
        if n:find("ball") then
            if obj:IsA("BasePart") then Cache.Ball = obj return obj end
            if obj:IsA("Model") then
                local p = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                if p then Cache.Ball = p return p end
            end
        end
    end
    Cache.Ball = nil
    return nil
end

local function RefreshRims()
    if tick() - Cache.RimT < 3 then return end
    Cache.RimT = tick()
    table.clear(Cache.Rims)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if n:find("rim") or n:find("hoop") then table.insert(Cache.Rims, obj) end
        end
    end
end

local function GetNearestRim(pos)
    RefreshRims()
    local nearest, minDist = nil, math.huge
    for _, r in ipairs(Cache.Rims) do
        if r.Parent then
            local d = (r.Position - pos).Magnitude
            if d < minDist then minDist, nearest = d, r end
        end
    end
    return nearest, minDist
end

local function GetBallHandler()
    if tick() - Cache.HandlerT < 0.05 then return Cache.Handler, Cache.HandlerChar end
    Cache.HandlerT = tick()
    Cache.Handler, Cache.HandlerChar = nil, nil

    local ball = GetBall()
    if not ball then return nil, nil end

    for _, c in ipairs(ball:GetChildren()) do
        if c:IsA("WeldConstraint") or c:IsA("Motor6D") or c:IsA("Weld") then
            local other = (c.Part0 == ball) and c.Part1 or c.Part0
            local model = other and other:FindFirstAncestorOfClass("Model")
            local plr = model and Players:GetPlayerFromCharacter(model)
            if plr then Cache.Handler, Cache.HandlerChar = plr, model return plr, model end
        end
    end

    local minDist = 5.0
    for _, plr in ipairs(Players:GetPlayers()) do
        local char, _, root = GetCharacter(plr)
        if root then
            local d = (root.Position - ball.Position).Magnitude
            if d < minDist then minDist = d Cache.Handler, Cache.HandlerChar = plr, char end
        end
    end
    return Cache.Handler, Cache.HandlerChar
end

local function GetOpponents()
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Team ~= LocalPlayer.Team then table.insert(out, plr) end
    end
    if #out == 0 then -- no team service in use: fall back to "everyone else"
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then table.insert(out, plr) end
        end
    end
    return out
end

local function GetTeammates()
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Team == LocalPlayer.Team then table.insert(out, plr) end
    end
    return out
end

local function GetNearestTeammate()
    local _, _, myRoot = GetCharacter()
    if not myRoot then return nil end
    local pool = GetTeammates()
    if #pool == 0 then pool = GetOpponents() end -- degrade gracefully with no team data
    local nearest, minDist = nil, math.huge
    for _, plr in ipairs(pool) do
        local _, _, root = GetCharacter(plr)
        if root then
            local d = (root.Position - myRoot.Position).Magnitude
            if d < minDist then minDist, nearest = d, plr end
        end
    end
    return nearest
end

-- openest teammate = fewest opponents within 6 studs of them, nearest as tiebreak
local function GetOpenestTeammate()
    local teammates, opponents = GetTeammates(), GetOpponents()
    if #teammates == 0 then return GetNearestTeammate() end
    local _, _, myRoot = GetCharacter()
    local best, bestScore = nil, math.huge
    for _, plr in ipairs(teammates) do
        local _, _, root = GetCharacter(plr)
        if root then
            local contest = 0
            for _, opp in ipairs(opponents) do
                local _, _, oroot = GetCharacter(opp)
                if oroot and (oroot.Position - root.Position).Magnitude < 6.0 then contest += 1 end
            end
            local dist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
            local score = contest * 1000 + dist
            if score < bestScore then bestScore, best = score, plr end
        end
    end
    return best
end

local function Throttle(state, key, interval)
    local now = tick()
    if now - (state[key] or 0) < interval then return false end
    state[key] = now
    return true
end
local Timers = {}

local ControlsModule
local function GetControls()
    if ControlsModule ~= nil then return ControlsModule or nil end
    ControlsModule = false
    pcall(function()
        local ps = LocalPlayer:WaitForChild("PlayerScripts", 2)
        ControlsModule = require(ps:WaitForChild("PlayerModule", 2)):GetControls()
    end)
    return ControlsModule or nil
end

local function IsManualMovementActive()
    if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.A)
        or UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.D) then
        return true
    end
    local c = GetControls()
    if c then
        local ok, v = pcall(c.GetMoveVector, c)
        if ok and typeof(v) == "Vector3" and v.Magnitude > 0.15 then return true end
    end
    if UserInputService.GamepadEnabled then
        local ok, states = pcall(UserInputService.GetGamepadState, UserInputService, Enum.UserInputType.Gamepad1)
        if ok and states then
            for _, s in ipairs(states) do
                if s.KeyCode == Enum.KeyCode.Thumbstick1 and s.Position.Magnitude > 0.2 then return true end
            end
        end
    end
    return false
end

local function SprintHeld()
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then return true end
    if UserInputService.GamepadEnabled then
        local ok, down = pcall(UserInputService.IsGamepadButtonDown, UserInputService,
            Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2)
        if ok and down then return true end
    end
    return false
end

-- ============================================================================
-- ACTION LAYER
-- FILL: if touch shoot/steal/tricky do nothing, dump real buttons:
--   for _, g in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
--       if g:IsA("GuiButton") then print(g:GetFullName()) end end
-- ============================================================================
local ACTIONS = {
    Shoot  = { Key = Enum.KeyCode.E,          Hints = { "shoot", "shot" } },
    Steal  = { Key = Enum.KeyCode.F,          Hints = { "steal" } },
    Jump   = { Key = Enum.KeyCode.Space,      Hints = {} },
    Tricky = { Key = Enum.KeyCode.LeftControl, Hints = { "tricky", "trick" } }, -- FILL real modifier
    Reach  = { Key = Enum.KeyCode.Q,          Hints = { "reach", "swipe" } },    -- one-hand block
}
local ActionButtons = {}

local function FindActionButton(name)
    local b = ActionButtons[name]
    if b and b.Parent then return b end
    if not Throttle(Timers, "btn_" .. name, 1) then return nil end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, g in ipairs(pg:GetDescendants()) do
        if g:IsA("GuiButton") and g.Visible
            and not g:FindFirstAncestor("LunyxPB_Unified") and not g:FindFirstAncestor("LunyxPB_Overlay") then
            local label = (g.Name .. " " .. (g:IsA("TextButton") and g.Text or "")):lower()
            for _, hint in ipairs(ACTIONS[name].Hints) do
                if label:find(hint, 1, true) then ActionButtons[name] = g return g end
            end
        end
    end
    return nil
end

local function PressButton(btn, down)
    if not firesignal then return false end
    return (pcall(function()
        firesignal(down and btn.MouseButton1Down or btn.MouseButton1Up)
        if not down then
            firesignal(btn.MouseButton1Click)
            firesignal(btn.Activated)
        end
    end))
end

local function SendAction(name, down)
    local a = ACTIONS[name]
    if not a then return end
    if IsTouchMode() or IsPadMode() then
        if name == "Jump" then
            if down then
                local _, hum = GetCharacter()
                if hum then hum.Jump = true end
            end
            return
        end
        if IsTouchMode() then
            local btn = FindActionButton(name)
            if btn and PressButton(btn, down) then return end
        end
    end
    pcall(function() VirtualInputManager:SendKeyEvent(down, a.Key, false, game) end)
end

local function Tap(name, hold)
    SendAction(name, true)
    task.delay(hold or 0.04, function() SendAction(name, false) end)
end

local function PassHeld()
    if TouchPassHeld then return true end
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return true end
    if UserInputService.GamepadEnabled then
        local ok, down = pcall(UserInputService.IsGamepadButtonDown, UserInputService,
            Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL1)
        if ok and down then return true end
    end
    return false
end

-- ============================================================================
-- SHARED ANIMATION EFFECTS: one track scan drives every Glide/Boost toggle
-- ============================================================================
local AnimGlides = {
    { Keywords = { "shoot", "jump", "fade", "dunk", "layup" },
      On = function() return Config.Offense.ShotGlide end, Force = function() return Config.Offense.ShotGlideForce end, NeedBall = true },
    { Keywords = { "cross", "btb", "hesi", "spin", "btl", "inout", "step", "snatch", "sham" },
      On = function() return Config.Handles.DribbleGlide end, Force = function() return Config.Handles.DribbleGlideForce end, NeedBall = true },
    { Keywords = { "post" },
      On = function() return Config.Handles.PostGlide end, Force = function() return Config.Handles.PostGlideForce end, NeedBall = true },
    { Keywords = { "block" },
      On = function() return Config.Defense.BlockGlide end, Force = function() return Config.Defense.BlockGlideForce end, NeedBall = false },
    { Keywords = { "rebound", "board" },
      On = function() return Config.Defense.ReboundGlide end, Force = function() return Config.Defense.ReboundGlideForce end, NeedBall = false },
    { Keywords = { "reach", "steal", "swipe" },
      On = function() return Config.Defense.ReachGlide end, Force = function() return Config.Defense.ReachGlideForce end, NeedBall = false },
}

local AnimBoosts = {
    { Keywords = { "cross", "btb", "hesi", "spin", "btl" },
      On = function() return Config.Handles.DribbleBoost end, Mult = function() return Config.Handles.DribbleBoostMultiplier end },
    { Keywords = { "post" },
      On = function() return Config.Handles.PostBoost end, Mult = function() return Config.Handles.PostBoostMultiplier end },
}

local function ApplyAnimationEffects(root, hum, hasBall)
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local name = (track.Animation and track.Animation.Name or ""):lower()
        for _, g in ipairs(AnimGlides) do
            if (not g.NeedBall or hasBall) and g.On() then
                for _, kw in ipairs(g.Keywords) do
                    if name:find(kw, 1, true) then
                        local look, v = root.CFrame.LookVector, root.AssemblyLinearVelocity
                        local f = g.Force()
                        root.AssemblyLinearVelocity = Vector3.new(look.X * f, v.Y, look.Z * f)
                        break
                    end
                end
            end
        end
        for _, b in ipairs(AnimBoosts) do
            if b.On() then
                for _, kw in ipairs(b.Keywords) do
                    if name:find(kw, 1, true) then
                        local target = hum.WalkSpeed * b.Mult()
                        if math.abs(hum.WalkSpeed - target) > 0.5 then hum.WalkSpeed = target end
                        break
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 1. OFFENSE
-- ============================================================================
local MeterSolver = { Active = false, LastProgress = 0, Velocity = 0, Released = false, Holding = false, HoldStart = 0 }

local function FindShotMeterUI()
    if Cache.Meter and Cache.Meter.Parent and Cache.Meter.Visible and Cache.Fill and Cache.Fill.Parent then
        return Cache.Meter, Cache.Fill
    end
    if tick() - Cache.MeterT < 0.1 then return nil end
    Cache.MeterT = tick()
    Cache.Meter, Cache.Fill = nil, nil

    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("Frame") and gui.Visible and gui.AbsoluteSize.Y > 10
            and not gui:FindFirstAncestor("LunyxPB_Unified") and not gui:FindFirstAncestor("LunyxPB_Overlay") then
            local n = gui.Name:lower()
            local pn = gui.Parent and gui.Parent.Name:lower() or ""
            local isMeter = n:find("meter") or n:find("shot")
                or (n:find("bar") and (pn:find("meter") or pn:find("shot")))
            if isMeter then
                local fill = gui:FindFirstChild("Fill") or gui:FindFirstChildWhichIsA("Frame")
                if fill then Cache.Meter, Cache.Fill = gui, fill return gui, fill end
            end
        end
    end
    return nil
end

local function ReleaseShot()
    if MeterSolver.Released then return end
    MeterSolver.Released = true
    MeterSolver.Holding = false
    Telemetry.ShotsTaken += 1
    SendAction("Shoot", false)
    Fire("Shoot", "Release", Telemetry.CalibratedOffset)
end

local function UpdateAutoTime(dt)
    if not Config.Offense.AutoTime then return end
    local container, fill = FindShotMeterUI()

    if not container then
        MeterSolver.Active, MeterSolver.Released, MeterSolver.LastProgress = false, false, 0
        if MeterSolver.Holding and tick() - MeterSolver.HoldStart > 1.5 then
            MeterSolver.Holding = false
            SendAction("Shoot", false)
        end
        return
    end

    if not MeterSolver.Active then MeterSolver.Active, MeterSolver.Released = true, false end

    local vertical = container.AbsoluteSize.Y >= container.AbsoluteSize.X
    local progress
    if vertical then
        progress = fill.Size.Y.Scale
        if progress == 0 and container.AbsoluteSize.Y > 0 then progress = fill.AbsoluteSize.Y / container.AbsoluteSize.Y end
    else
        progress = fill.Size.X.Scale
        if progress == 0 and container.AbsoluteSize.X > 0 then progress = fill.AbsoluteSize.X / container.AbsoluteSize.X end
    end
    progress = math.clamp(progress, 0, 1)

    if dt > 0 then MeterSolver.Velocity = (progress - MeterSolver.LastProgress) / dt end
    MeterSolver.LastProgress = progress

    -- clutch tightens the window instead of the lead: fewer early releases when it matters
    local window = Config.Offense.PrecisionWindow + (Telemetry.ClutchActive and 0.01 or 0)
    local lead = Config.Offense.ReleaseLead + (Config.Offense.MatchPing and GetPingSeconds() or 0) + Telemetry.CalibratedOffset
    local predicted = progress + (MeterSolver.Velocity > 0 and MeterSolver.Velocity * lead or lead * 1.5)

    if predicted >= window and not MeterSolver.Released then
        Telemetry.LastDeviation = predicted - window
        ReleaseShot()
    end
end

-- FILL: confirm attribute names against the game's clock/score source (may live on a BoolValue/IntValue instead)
local function UpdateClutch()
    if not Config.Offense.AutoClutch then Telemetry.ClutchActive = false return end
    local clock = Workspace:GetAttribute("GameClock") or Workspace:GetAttribute("TimeLeft")
    local myScore = LocalPlayer:GetAttribute("Score") or 0
    local oppScore = Workspace:GetAttribute("OpponentScore") or myScore
    local margin = math.abs(myScore - oppScore)
    Telemetry.ClutchActive = (typeof(clock) == "number" and clock <= Config.Offense.ClutchClockThreshold)
        and margin <= Config.Offense.ClutchScoreMargin
end

local function UpdateContestBillboard(hasBall, root)
    local name = "LunyxContestBoard"
    local bb = Workspace:FindFirstChild(name)
    if not Config.Offense.ContestBillboard or not MeterSolver.Active or not hasBall then
        if bb then bb.Enabled = false end
        return
    end
    if not bb then
        bb = Instance.new("BillboardGui")
        bb.Name = name
        bb.Size = UDim2.fromOffset(100, 24)
        bb.StudsOffset = Vector3.new(0, 4, 0)
        bb.AlwaysOnTop = true
        bb.Parent = Workspace
        local lbl = Instance.new("TextLabel")
        lbl.Name = "Label"
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 0.3
        lbl.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 13
        lbl.Parent = bb
        OnUnload(function() bb:Destroy() end)
    end
    bb.Adornee = root
    bb.Enabled = true
    local nearest = math.huge
    for _, opp in ipairs(GetOpponents()) do
        local _, _, oroot = GetCharacter(opp)
        if oroot then nearest = math.min(nearest, (oroot.Position - root.Position).Magnitude) end
    end
    local contestPct = nearest == math.huge and 0 or math.clamp(100 - (nearest / 10) * 100, 0, 100)
    local lbl = bb:FindFirstChild("Label")
    lbl.Text = string.format("CONTEST %d%%", contestPct)
    lbl.TextColor3 = contestPct > 60 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(0, 255, 140)
end

local function UpdateOffense()
    local _, hum, root = GetCharacter()
    if not root then return end

    local handler = GetBallHandler()
    local hasBall = (handler == LocalPlayer)

    UpdateClutch()
    UpdateContestBillboard(hasBall, root)
    ApplyAnimationEffects(root, hum, hasBall)

    -- auto lob: alone on a break, teammate ahead near the rim, no contest on them
    if Config.Offense.AutoLob and hasBall then
        local rim = GetNearestRim(root.Position)
        if rim then
            local best, bestD = nil, math.huge
            for _, plr in ipairs(GetTeammates()) do
                local _, _, troot = GetCharacter(plr)
                if troot then
                    local dRim = (troot.Position - rim.Position).Magnitude
                    if dRim < Config.Offense.LobRange and dRim < bestD then
                        local contested = false
                        for _, opp in ipairs(GetOpponents()) do
                            local _, _, oroot = GetCharacter(opp)
                            if oroot and (oroot.Position - troot.Position).Magnitude < 6.0 then contested = true break end
                        end
                        if not contested then best, bestD = plr, dRim end
                    end
                end
            end
            if best and Throttle(Timers, "lob", 0.6) then Fire("Pass", best, "Lob") end
        end
    end

    -- auto layup/dunk approach + smart jelly finish selection
    if Config.Offense.AutoLayupDunk ~= false and hasBall and not IsManualMovementActive() then
        local rim, d = GetNearestRim(root.Position)
        if rim and d <= 14.0 and d > 5.5 then
            if Config.Offense.SmartJelly and Throttle(Timers, "jelly", 0.5) then
                local contested = false
                for _, opp in ipairs(GetOpponents()) do
                    local _, _, oroot = GetCharacter(opp)
                    if oroot and (oroot.Position - rim.Position).Magnitude < Config.Offense.JellyContestRange then contested = true break end
                end
                if contested then Fire("Dribble", "Jelly") end
            end
            if Config.Offense.AutoTricky and d <= Config.Offense.TrickyRange then
                SendAction("Tricky", true)
                task.delay(0.1, function() SendAction("Tricky", false) end)
            end
            hum:MoveTo(rim.Position + (root.Position - rim.Position).Unit * 4.8)
        end
    end

    -- auto shoot: press once, released by AutoTime (or failsafe)
    if Config.Offense.AutoShoot and hasBall and not MeterSolver.Active and not MeterSolver.Released and not MeterSolver.Holding then
        MeterSolver.Holding, MeterSolver.HoldStart = true, tick()
        SendAction("Shoot", true)
    end

    -- pass link: open-man targeting with velocity lead, replaces raw auto pass
    if Config.Extras.PassLink and hasBall and PassHeld() and Throttle(Timers, "pass", 0.4) then
        local target = GetOpenestTeammate()
        if target then
            local _, _, troot = GetCharacter(target)
            if troot then
                local lead = troot.AssemblyLinearVelocity * Config.Extras.PassLeadTime
                Fire("Pass", target, troot.Position + lead)
            end
        end
    end
end

local function BindShotFeedback()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end
    Bind(pg.DescendantAdded:Connect(function(obj)
        if not obj:IsA("TextLabel") then return end
        task.defer(function()
            if Unloaded or not obj.Parent or not Config.Offense.ShotFeedback then return end
            local txt = obj.Text:lower()
            if txt:find("green") or txt:find("excellent") then
                Telemetry.GreensHit += 1
                if Config.Offense.LogShots then print(("[Lunyx] GREEN shot #%d"):format(Telemetry.ShotsTaken)) end
            elseif Config.Offense.AutoTune then
                if txt:find("early") then
                    Telemetry.CalibratedOffset = math.max(-MAX_OFFSET, Telemetry.CalibratedOffset - Config.Offense.CorrectionSize)
                    if Config.Offense.LogShots then print(("[Lunyx] EARLY, offset=%.4f"):format(Telemetry.CalibratedOffset)) end
                elseif txt:find("late") then
                    Telemetry.CalibratedOffset = math.min(MAX_OFFSET, Telemetry.CalibratedOffset + Config.Offense.CorrectionSize)
                    if Config.Offense.LogShots then print(("[Lunyx] LATE, offset=%.4f"):format(Telemetry.CalibratedOffset)) end
                end
            end
        end)
    end))
end

-- ============================================================================
-- 2. DEFENSE
-- ============================================================================
local Ring = Instance.new("Part")
Ring.Name = "LunyxGuardRing"
Ring.Shape = Enum.PartType.Cylinder
Ring.Anchored = true
Ring.CanCollide = false
Ring.CanQuery = false
Ring.CanTouch = false
Ring.Material = Enum.Material.Neon
Ring.Transparency = 1
Ring.Parent = Workspace
OnUnload(function() Ring:Destroy() end)

local CourtLineParts = {}
-- FILL: real court corner CFrames per side; placeholders draw nothing useful until set
local CourtBoundsFill = {
    { from = Vector3.new(0,0,0), to = Vector3.new(0,0,0) }, -- three point line, one side
}
local function BuildCourtLines()
    for _, p in ipairs(CourtLineParts) do p:Destroy() end
    table.clear(CourtLineParts)
    if not Config.Defense.CourtLines then return end
    for _, seg in ipairs(CourtBoundsFill) do
        if seg.from ~= seg.to then
            local mid = (seg.from + seg.to) / 2
            local len = (seg.to - seg.from).Magnitude
            local p = Instance.new("Part")
            p.Anchored, p.CanCollide, p.CanQuery, p.Material = true, false, false, Enum.Material.Neon
            p.Color = Color3.fromRGB(0, 200, 255)
            p.Size = Vector3.new(len, 0.1, 0.3)
            p.CFrame = CFrame.new(mid, seg.to)
            p.Parent = Workspace
            table.insert(CourtLineParts, p)
        end
    end
end
OnUnload(function() for _, p in ipairs(CourtLineParts) do p:Destroy() end end)

local ShotTrackers = {}

local function IsGenuineShot(char, hum)
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local name = (track.Animation and track.Animation.Name or ""):lower()
            if name:find("shoot") or name:find("jump") or name:find("fade") or name:find("dunk") or name:find("layup") then
                return true
            end
        end
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    return root ~= nil and root.AssemblyLinearVelocity.Y > 3.0
end

-- off-ball: pick an unguarded opponent (not the handler) to stick to
local function PickOffBallTarget(handler)
    local best, bestDist = nil, math.huge
    local _, _, myRoot = GetCharacter()
    if not myRoot then return nil end
    for _, opp in ipairs(GetOpponents()) do
        if opp ~= handler then
            local _, _, oroot = GetCharacter(opp)
            if oroot then
                local d = (oroot.Position - myRoot.Position).Magnitude
                if d < bestDist then bestDist, best = d, opp end
            end
        end
    end
    return best
end

-- screen avoidance: nudge the guard destination around any body between self and target
local function ScreenAdjustedDestination(myRoot, dest)
    if not Config.Defense.ScreenAvoidance then return dest end
    local dir = (dest - myRoot.Position)
    if dir.Magnitude < 0.1 then return dest end
    dir = dir.Unit
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local _, _, oroot = GetCharacter(plr)
            if oroot then
                local toObstacle = oroot.Position - myRoot.Position
                local along = toObstacle:Dot(dir)
                if along > 0.5 and along < dir.Magnitude and (toObstacle - dir * along).Magnitude < Config.Defense.ScreenCheckRadius then
                    local lateral = Vector3.new(-dir.Z, 0, dir.X) * Config.Defense.ScreenCheckRadius * 1.5
                    return dest + lateral
                end
            end
        end
    end
    return dest
end

local function UpdateDefense()
    local _, myHum, myRoot = GetCharacter()
    if not myRoot then return end

    local ball = GetBall()
    local handler, handlerChar = GetBallHandler()
    local D = Config.Defense

    if ball and not handler then
        local d = (ball.Position - myRoot.Position).Magnitude
        if D.AutoRebound and d <= D.ReboundRange and ball.Position.Y > 7.0 and Throttle(Timers, "rebound", 0.5) then
            Tap("Jump")
            Fire("Rebound")
        end
        -- auto intercept: ball moving fast with no current handler, lead to its predicted point
        if D.AutoIntercept then
            local speed = ball.AssemblyLinearVelocity.Magnitude
            if speed >= D.InterceptMinBallSpeed and d <= D.InterceptRange and Throttle(Timers, "intercept", 0.2) then
                local lead = ball.Position + ball.AssemblyLinearVelocity * 0.15
                myHum:MoveTo(lead)
                Fire("Intercept")
            end
        end
    end

    if not handler or handler == LocalPlayer or not handlerChar then
        table.clear(ShotTrackers)
        Telemetry.GuardingTarget, Telemetry.OffBallTarget = nil, nil
        Ring.Transparency = 1
        -- off-ball positioning when nobody on the other team has the rock through you
        if D.OffBallDefense and handler ~= LocalPlayer then
            local target = PickOffBallTarget(handler)
            Telemetry.OffBallTarget = target
            if target and not (D.ManualOverride and IsManualMovementActive()) and Throttle(Timers, "offball", 0.3) then
                local _, _, troot = GetCharacter(target)
                if troot then
                    local rim = GetNearestRim(myRoot.Position)
                    local offset = rim and (rim.Position - troot.Position).Unit * 3.0 or Vector3.new(0, 0, 3)
                    myHum:MoveTo(ScreenAdjustedDestination(myRoot, troot.Position + offset))
                end
            end
        end
        return
    end

    local hHum = handlerChar:FindFirstChildOfClass("Humanoid")
    local hRoot = handlerChar:FindFirstChild("HumanoidRootPart")
    if not hHum or not hRoot then return end

    Telemetry.GuardingTarget = handler
    local dist = (myRoot.Position - hRoot.Position).Magnitude

    Ring.Transparency = 0.3
    Ring.Color = Color3.fromRGB(0, 255, 140)
    Ring.Size = Vector3.new(0.15, 9, 9)
    Ring.CFrame = CFrame.new(hRoot.Position - Vector3.new(0, 2.85, 0)) * CFrame.Angles(0, 0, math.rad(90))

    if D.AutoGuard then
        local manual = D.ManualOverride and IsManualMovementActive()
        local rim, rimDist = GetNearestRim(hRoot.Position)
        local atRim = D.StopAtRim and rim and rimDist <= D.RimStopDistance
        if not manual and not atRim then
            local closeRadius = D.StickyGuard and D.StickyRadius or 3.8
            local dest
            if D.DefenseStrafe and rim then
                -- stay on the line between handler and own rim instead of beelining to them
                local toRim = (rim.Position - hRoot.Position)
                dest = hRoot.Position + toRim.Unit * closeRadius
            else
                dest = hRoot.Position + hRoot.CFrame.LookVector * closeRadius
            end
            dest = ScreenAdjustedDestination(myRoot, dest)
            if D.StickyGuard and dist <= D.StickyRadius * 1.5 then
                myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.new(dest, hRoot.Position), 0.35)
            else
                myHum:MoveTo(Vector3.new(dest.X, myRoot.Position.Y, dest.Z))
            end
        end
    end

    if D.AutoBlock and dist <= D.BlockRange then
        if IsGenuineShot(handlerChar, hHum) then
            local tr = ShotTrackers[handler]
            if not tr then tr = { StartTime = tick() } ShotTrackers[handler] = tr end
            local need = D.IgnorePumpFakes and D.JumpDelay or 0
            if tick() - tr.StartTime >= need and tick() - Telemetry.LastBlockTime > 0.8 then
                Telemetry.LastBlockTime = tick()
                if D.OneHandBlock then
                    SendAction("Reach", true)
                    task.delay(0.12, function() SendAction("Reach", false) end)
                    Fire("Block", "OneHand")
                else
                    Tap("Jump")
                    Fire("Block")
                end
            end
        else
            ShotTrackers[handler] = nil
        end
    end

    -- auto run up: ball just flipped to your side with the lane open, crash the glass/break early
    if D.AutoRunUp and hasBallThisFrame == nil then end -- no-op placeholder removed below
end

-- separate pass: run-up needs "my team has ball, I'm not the handler" which the block above
-- already exits early on, so it's handled as its own light pass instead of being wedged in.
local function UpdateRunUp()
    if not Config.Defense.AutoRunUp then return end
    local _, hum, root = GetCharacter()
    if not hum or not root then return end
    local handler = GetBallHandler()
    if not handler or handler == LocalPlayer then return end
    if table.find(GetTeammates(), handler) then
        local rim = GetNearestRim(root.Position)
        if rim and (rim.Position - root.Position).Magnitude > 20.0 and Throttle(Timers, "runup", 1.0) then
            hum.WalkSpeed += Config.Defense.RunUpSpeedBoost
            task.delay(1.5, function() if not Unloaded then hum.WalkSpeed -= Config.Defense.RunUpSpeedBoost end end)
        end
    end
end

-- ============================================================================
-- 3. HANDLES & PASSING + MOVEMENT (combined update: both read character/ball state once)
-- ============================================================================
local function ExecuteDribbleMove(index)
    local move = DribbleMoves[index]
    if not move then return end
    Fire("Dribble", move.Code)
    if not UserInputService.KeyboardEnabled or IsPadMode() then Toast(move.Name) end
end

local function CycleMove(dir)
    SelectedMove = ((SelectedMove - 1 + dir) % #DribbleMoves) + 1
    Toast(string.format("[%d/%d] %s", SelectedMove, #DribbleMoves, DribbleMoves[SelectedMove].Name))
end

Bind(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not Config.Handles.MoveBinds then return end
    local t, kc = input.UserInputType, input.KeyCode
    if t == Enum.UserInputType.Keyboard then
        for idx, move in ipairs(DribbleMoves) do
            if kc == move.Key then ExecuteDribbleMove(idx) break end
        end
    elseif t.Name:find("Gamepad") and not MenuOpen then
        if kc == Enum.KeyCode.DPadLeft then CycleMove(-1)
        elseif kc == Enum.KeyCode.DPadRight then CycleMove(1)
        elseif kc == Enum.KeyCode.DPadUp then ExecuteDribbleMove(SelectedMove) end
    end
end))

Bind(UserInputService.JumpRequest:Connect(function()
    -- stay-in-bounds note: jump boost deliberately skips if clamp would immediately undo it
    local _, _, root = GetCharacter()
    if root and Config.Movement.InfiniteStamina then end -- infinite jumps removed from new taxonomy; no-op kept for binding parity
end))

local BallGhostApplied = false

local function UpdateHandlesAndMovement()
    local char, hum, root = GetCharacter()
    if not char then return end

    local handler = GetBallHandler()
    local hasBall = (handler == LocalPlayer)

    -- ball ghost: drop collision on the ball while you're the handler so contact pokes can't strip it
    local ball = GetBall()
    if ball then
        if Config.Movement.BallGhost and hasBall then
            if not BallGhostApplied then ball.CanCollide, ball.CanTouch = false, false BallGhostApplied = true end
        elseif BallGhostApplied then
            ball.CanCollide, ball.CanTouch = true, true
            BallGhostApplied = false
        end
    end

    -- ankle breaker: defender close and roughly planted (low lateral velocity) -> break them off
    if Config.Handles.AutoAnkleBreaker and hasBall and Throttle(Timers, "ankle", 0.6) then
        for _, opp in ipairs(GetOpponents()) do
            local _, _, oroot = GetCharacter(opp)
            if oroot and (oroot.Position - root.Position).Magnitude < Config.Handles.AnkleBreakerRange
                and oroot.AssemblyLinearVelocity.Magnitude < 4.0 then
                Fire("Dribble", "Ankle")
                break
            end
        end
    end

    -- dribble combos (chained, replaces old crossover-when-guarded)
    if Config.Handles.DribbleCombos and hasBall and tick() - Telemetry.LastDribbleTick >= Config.Handles.ComboChainDelay then
        for _, plr in ipairs(GetOpponents()) do
            local _, _, oroot = GetCharacter(plr)
            if oroot and (oroot.Position - root.Position).Magnitude < 7.5 then
                Telemetry.LastDribbleTick = tick()
                Fire("Dribble", DribbleMoves[math.random(1, #DribbleMoves)].Code)
                break
            end
        end
    end

    -- auto crab: juke move on a cooldown while guarded, distinct from the combo chain above
    if Config.Movement.AutoCrab and hasBall and tick() - Telemetry.LastCrabTick >= Config.Movement.CrabCooldown then
        for _, plr in ipairs(GetOpponents()) do
            local _, _, oroot = GetCharacter(plr)
            if oroot and (oroot.Position - root.Position).Magnitude < 6.0 then
                Telemetry.LastCrabTick = tick()
                Fire("Dribble", "Crab")
                break
            end
        end
    end

    -- speed: legit mode ramps and caps lower, otherwise snap to configured value
    if Config.Movement.LegitSpeed then
        local target = Config.Movement.LegitSpeedValue
        hum.WalkSpeed = hum.WalkSpeed + (target - hum.WalkSpeed) * 0.15
    elseif Config.Movement.Speed then
        if hum.WalkSpeed < Config.Movement.SpeedValue then hum.WalkSpeed = Config.Movement.SpeedValue end
    end

    if Config.Movement.SprintBoost and SprintHeld() and Throttle(Timers, "sprintboost", 0.5) then
        hum.WalkSpeed += Config.Movement.SprintBoostAdd
        Fire("Sprint", true)
        task.delay(0.6, function() if not Unloaded then hum.WalkSpeed -= Config.Movement.SprintBoostAdd end end)
    end

    if Config.Movement.SpeedGlide and IsManualMovementActive() then
        local look, v = root.CFrame.LookVector, root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(look.X * Config.Movement.SpeedGlideForce, v.Y, look.Z * Config.Movement.SpeedGlideForce)
    end

    if Config.Movement.StayInBounds then
        local p = root.Position
        local cx = math.clamp(p.X, Config.Movement.BoundsMinX, Config.Movement.BoundsMaxX)
        local cz = math.clamp(p.Z, Config.Movement.BoundsMinZ, Config.Movement.BoundsMaxZ)
        if cx ~= p.X or cz ~= p.Z then root.CFrame = root.CFrame + Vector3.new(cx - p.X, 0, cz - p.Z) end
    end

    -- state sweeps at 4Hz
    if Throttle(Timers, "statesweep", 0.25) then
        if Config.Movement.InfiniteStamina then
            local stam = char:FindFirstChild("Stamina", true) or LocalPlayer:FindFirstChild("Stamina", true)
            if stam and (stam:IsA("NumberValue") or stam:IsA("IntValue")) then stam.Value = 100 end
            char:SetAttribute("Stamina", 100)
        end
        if Config.Movement.AntiStun then
            char:SetAttribute("Stunned", false)
            char:SetAttribute("IsStunned", false)
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BoolValue") then
                    local n = v.Name:lower()
                    if n:find("stun") or n:find("debounce") then v.Value = false end
                end
            end
        end
    end
end

-- ============================================================================
-- 4. EXTRAS: auto join spot / burst all courts
-- ============================================================================
local function UpdateExtras()
    if Config.Extras.AutoJoinSpot and Config.Extras.SpotId > 0 and Throttle(Timers, "joinspot", 3) then
        Fire("Queue", Config.Extras.SpotId)
    end
    if Config.Extras.BurstAllCourts and #Config.Extras.CourtSpots > 0
        and Throttle(Timers, "burst", Config.Extras.BurstCooldown) then
        local spot = Config.Extras.CourtSpots[((tick() // Config.Extras.BurstCooldown) % #Config.Extras.CourtSpots) + 1]
        if spot and spot.id then Fire("Queue", spot.id) end
    end
end

Bind(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if not Unloaded then
        Cache.Ball, Cache.Handler = nil, nil
        MeterSolver.Active, MeterSolver.Released, MeterSolver.Holding = false, false, false
        BallGhostApplied = false
    end
end))

-- ============================================================================
-- 5. UI: reflection-built from Config, one generator for every tab/row
-- ============================================================================
local function Round(n, places) local m = 10 ^ places return math.floor(n * m + 0.5) / m end

local function IsPointer(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function MakeDraggable(frame, handle)
    local dragging, startInput, startPos = false, nil, nil
    Bind(handle.InputBegan:Connect(function(i)
        if IsPointer(i) then
            dragging, startInput, startPos = true, i.Position, frame.Position
            local c
            c = i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false c:Disconnect() end
            end)
        end
    end))
    Bind(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

-- step bounds per numeric field: {step, min, max}. anything not listed gets a safe generic range.
local STEP_RANGES = {
    ReleaseLead = {0.005,0,0.15}, PingMultiplier = {0.05,0.1,3}, CorrectionSize = {0.001,0.001,0.02},
    PrecisionWindow = {0.01,0.85,1}, LobRange = {1,5,40}, TrickyRange = {0.5,2,15}, ClutchClockThreshold = {1,0,60},
    ClutchScoreMargin = {1,0,20}, JellyContestRange = {0.5,1,15}, ShotGlideForce = {1,2,35},
    RimStopDistance = {0.5,2,15}, BlockRange = {1,6,25}, JumpDelay = {0.02,0,0.4}, ReboundRange = {1,10,35},
    RunUpSpeedBoost = {0.5,1,20}, InterceptRange = {1,5,30}, InterceptMinBallSpeed = {1,5,60},
    StickyRadius = {0.25,1,8}, ScreenCheckRadius = {0.25,1,10}, BlockGlideForce = {1,2,35},
    ReboundGlideForce = {1,2,35}, ReachGlideForce = {1,2,35}, AnkleBreakerRange = {0.5,2,12},
    ComboChainDelay = {0.05,0.15,1}, DribbleGlideForce = {1,5,35}, DribbleBoostMultiplier = {0.01,1,1.6},
    PostGlideForce = {1,2,25}, PostBoostMultiplier = {0.01,1,1.6}, SpeedValue = {1,16,45},
    LegitSpeedValue = {1,14,24}, SpeedGlideForce = {1,2,20}, SprintBoostAdd = {0.5,1,15},
    CrabCooldown = {0.1,0.3,3}, PassLeadTime = {0.01,0,0.6}, BurstCooldown = {0.1,0.2,3},
    SpotId = {1,0,999999}, BoundsMinX = {5,-500,500}, BoundsMaxX = {5,-500,500},
    BoundsMinZ = {5,-500,500}, BoundsMaxZ = {5,-500,500},
}

local LABELS -- forward decl, filled after DribbleMoves section since it's referenced in UI build only

local function PrettyLabel(key)
    local out = key:gsub("(%l)(%u)", "%1 %2")
    return out
end

local function AddToggle(parent, label, tbl, key)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -6, 0, 26)
    btn.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    btn.Font = Enum.Font.Code
    btn.TextSize = 11
    btn.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local function refresh()
        btn.Text = string.format(" [%s] %s", tbl[key] and "ON " or "OFF", label)
        btn.TextColor3 = tbl[key] and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(175, 175, 190)
    end
    refresh()
    btn.MouseButton1Click:Connect(function() tbl[key] = not tbl[key] refresh() end)
    btn.Parent = parent
end

local function AddStep(parent, label, tbl, key)
    local range = STEP_RANGES[key] or {1, 0, 100}
    local step, minV, maxV = range[1], range[2], range[3]
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -6, 0, 26)
    row.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -66, 1, 0)
    lbl.Position = UDim2.new(0, 6, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(185, 215, 255)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local function refresh() lbl.Text = string.format("%s: %.3f", label, tbl[key]) end
    refresh()

    local function mk(text, x, delta)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(26, 22)
        b.Position = UDim2.new(1, x, 0.5, -11)
        b.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
        b.TextColor3 = Color3.fromRGB(0, 255, 140)
        b.Font = Enum.Font.Code
        b.TextSize = 14
        b.Text = text
        b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function()
            tbl[key] = Round(math.clamp(tbl[key] + delta, minV, maxV), 4)
            refresh()
        end)
    end
    mk("-", -60, -step)
    mk("+", -30, step)
end

-- reflection: walk a config section in key order (as defined above), skip tables/arrays
local function BuildSection(scroll, section)
    for key, value in pairs(section) do
        if typeof(value) == "boolean" then
            AddToggle(scroll, PrettyLabel(key), section, key)
        elseif typeof(value) == "number" then
            AddStep(scroll, PrettyLabel(key), section, key)
        end
        -- strings/tables (CourtSpots, etc.) are data, not toggles - skipped by design
    end
end

local function BuildUI()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end
    local old = pg:FindFirstChild("LunyxPB_Unified")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "LunyxPB_Unified"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 40
    gui.Parent = pg
    OnUnload(function() gui:Destroy() end)

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 560, 0, 420)
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(35, 35, 45)

    local uiscale = Instance.new("UIScale", main)
    local function Rescale()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local vp = cam.ViewportSize
        uiscale.Scale = math.clamp(math.min(vp.X / 600, vp.Y / 460), 0.5, 1)
    end
    Rescale()
    local cam = Workspace.CurrentCamera
    if cam then Bind(cam:GetPropertyChangedSignal("ViewportSize"):Connect(Rescale)) end

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    header.BorderSizePixel = 0
    header.Parent = main
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)
    MakeDraggable(main, header)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -140, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "LUNYX // PB ELITE v4  [RShift | L3+R3]"
    title.TextColor3 = Color3.fromRGB(0, 255, 140)
    title.Font = Enum.Font.Code
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local function HeaderButton(text, x, w, bg, fg)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, 22)
        b.Position = UDim2.new(1, x, 0, 7)
        b.BackgroundColor3 = bg
        b.TextColor3 = fg
        b.Font = Enum.Font.Code
        b.TextSize = 11
        b.Text = text
        b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        return b
    end
    local hideBtn = HeaderButton("HIDE", -124, 44, Color3.fromRGB(26, 26, 36), Color3.fromRGB(190, 190, 205))
    local unloadBtn = HeaderButton("UNLOAD", -72, 64, Color3.fromRGB(60, 20, 26), Color3.fromRGB(255, 120, 130))
    unloadBtn.MouseButton1Click:Connect(Unload)

    local readout = Instance.new("TextLabel")
    readout.Size = UDim2.new(1, -20, 0, 24)
    readout.Position = UDim2.new(0, 10, 0, 44)
    readout.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    readout.TextColor3 = Color3.fromRGB(215, 215, 225)
    readout.Font = Enum.Font.Code
    readout.TextSize = 11
    readout.Parent = main
    Instance.new("UICorner", readout).CornerRadius = UDim.new(0, 4)

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 115, 1, -80)
    sidebar.Position = UDim2.new(0, 10, 0, 74)
    sidebar.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main
    Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 6)
    local sLayout = Instance.new("UIListLayout", sidebar)
    sLayout.Padding = UDim.new(0, 5)
    sLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local area = Instance.new("Frame")
    area.Size = UDim2.new(1, -140, 1, -80)
    area.Position = UDim2.new(0, 130, 0, 74)
    area.BackgroundTransparency = 1
    area.Parent = main

    local tabs, first, firstButton = {}, true, nil
    local ON_BG, OFF_BG = Color3.fromRGB(0, 255, 140), Color3.fromRGB(22, 22, 30)

    local function Select(name)
        for n, t in pairs(tabs) do
            local sel = (n == name)
            t.Scroll.Visible = sel
            t.Button.BackgroundColor3 = sel and ON_BG or OFF_BG
            t.Button.TextColor3 = sel and Color3.fromRGB(12, 12, 16) or Color3.fromRGB(160, 160, 175)
        end
    end

    local function CreateTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -8, 0, 32)
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.Text = name
        btn.Parent = sidebar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.CanvasSize = UDim2.new()
        scroll.ScrollBarThickness = 3
        scroll.Parent = area
        Instance.new("UIListLayout", scroll).Padding = UDim.new(0, 6)

        tabs[name] = { Button = btn, Scroll = scroll }
        btn.MouseButton1Click:Connect(function() Select(name) end)
        if first then first, firstButton = false, btn Select(name) else scroll.Visible = false end
        return scroll
    end

    local offenseTab = CreateTab("Offense")
    local defenseTab = CreateTab("Defense")
    local handlesTab = CreateTab("Handles")
    local movementTab = CreateTab("Movement")
    local extrasTab = CreateTab("Extras")

    BuildSection(offenseTab, Config.Offense)
    BuildSection(defenseTab, Config.Defense)
    BuildSection(handlesTab, Config.Handles)

    local moveHeader = Instance.new("TextLabel")
    moveHeader.Size = UDim2.new(1, -6, 0, 20)
    moveHeader.BackgroundTransparency = 1
    moveHeader.Text = "-- MOVE BINDS (toggle above gates these) --"
    moveHeader.TextColor3 = Color3.fromRGB(0, 200, 255)
    moveHeader.Font = Enum.Font.Code
    moveHeader.TextSize = 11
    moveHeader.TextXAlignment = Enum.TextXAlignment.Left
    moveHeader.Parent = handlesTab
    for i, move in ipairs(DribbleMoves) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 24)
        b.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
        b.TextColor3 = Color3.fromRGB(160, 230, 255)
        b.Font = Enum.Font.Code
        b.TextSize = 11
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = string.format("  [%s] %s", move.Key.Name, move.Name)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function() ExecuteDribbleMove(i) end)
        b.Parent = handlesTab
    end

    BuildSection(movementTab, Config.Movement)
    BuildSection(extrasTab, Config.Extras)

    local function SetMenu(open)
        MenuOpen = open
        main.Visible = open
        if open and IsPadMode() and firstButton then
            GuiService.SelectedObject = firstButton
        else
            local sel = GuiService.SelectedObject
            if sel and sel:IsDescendantOf(main) then GuiService.SelectedObject = nil end
        end
    end
    ToggleMenu = function() SetMenu(not MenuOpen) end
    hideBtn.MouseButton1Click:Connect(function() SetMenu(false) end)
    OnUnload(function()
        ToggleMenu = function() end
        MenuOpen = false
        local sel = GuiService.SelectedObject
        if sel and sel:IsDescendantOf(main) then GuiService.SelectedObject = nil end
    end)

    Bind(UserInputService.InputBegan:Connect(function(input, gpe)
        local kc = input.KeyCode
        if not gpe and kc == Enum.KeyCode.RightShift then ToggleMenu() return end
        if kc == Enum.KeyCode.ButtonL3 or kc == Enum.KeyCode.ButtonR3 then
            local pad = input.UserInputType
            local ok1, l3 = pcall(UserInputService.IsGamepadButtonDown, UserInputService, pad, Enum.KeyCode.ButtonL3)
            local ok2, r3 = pcall(UserInputService.IsGamepadButtonDown, UserInputService, pad, Enum.KeyCode.ButtonR3)
            if ok1 and ok2 and l3 and r3 then ToggleMenu() end
        end
    end))

    Bind(RunService.Heartbeat:Connect(function()
        if not main.Visible or not Throttle(Timers, "hud", 0.2) then return end
        local pct = Telemetry.ShotsTaken > 0 and math.floor(Telemetry.GreensHit / Telemetry.ShotsTaken * 100) or 0
        readout.Text = string.format(" Ping: %dms | Shots: %d (%d%% G) | Off: %+.3f | Clutch: %s | Guard: %s",
            Telemetry.CurrentPingMs, Telemetry.ShotsTaken, pct, Telemetry.CalibratedOffset,
            Telemetry.ClutchActive and "ON" or "off",
            Telemetry.GuardingTarget and Telemetry.GuardingTarget.Name or (Telemetry.OffBallTarget and Telemetry.OffBallTarget.Name or "-"))
    end))

    SetMenu(true)
end

-- ============================================================================
-- 6. OVERLAY: toast + touch controls
-- ============================================================================
local function BuildOverlay()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end
    local old = pg:FindFirstChild("LunyxPB_Overlay")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "LunyxPB_Overlay"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 50
    gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
    gui.Parent = pg
    OnUnload(function() gui:Destroy() end)

    local GREEN = Color3.fromRGB(0, 255, 140)
    local DARK = Color3.fromRGB(12, 12, 16)

    local toast = Instance.new("TextLabel")
    toast.Size = UDim2.fromOffset(240, 26)
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 0, 12)
    toast.BackgroundColor3 = DARK
    toast.BackgroundTransparency = 0.2
    toast.TextColor3 = GREEN
    toast.Font = Enum.Font.Code
    toast.TextSize = 12
    toast.Visible = false
    toast.Parent = gui
    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 6)
    local toastId = 0
    Toast = function(text)
        toastId += 1
        local mine = toastId
        toast.Text = text
        toast.Visible = true
        task.delay(1.2, function()
            if mine == toastId and toast.Parent then toast.Visible = false end
        end)
    end

    local touch = Instance.new("Frame")
    touch.Size = UDim2.fromScale(1, 1)
    touch.BackgroundTransparency = 1
    touch.Parent = gui

    local function MakeBtn(text, pos, size, radius)
        local b = Instance.new("TextButton")
        b.Size = size
        b.Position = pos
        b.BackgroundColor3 = DARK
        b.BackgroundTransparency = 0.25
        b.TextColor3 = GREEN
        b.Font = Enum.Font.Code
        b.TextSize = 12
        b.Text = text
        b.Selectable = false
        b.Parent = touch
        Instance.new("UICorner", b).CornerRadius = radius
        local s = Instance.new("UIStroke", b)
        s.Color = GREEN
        s.Transparency = 0.5
        return b
    end

    local menuBtn = MakeBtn("MENU", UDim2.new(0, 12, 0.38, 0), UDim2.fromOffset(56, 40), UDim.new(0, 8))
    local passBtn = MakeBtn("PASS", UDim2.new(1, -76, 0.38, 0), UDim2.fromOffset(60, 60), UDim.new(1, 0))
    local movesBtn = MakeBtn("MOVES", UDim2.new(1, -76, 0.38, 70), UDim2.fromOffset(60, 40), UDim.new(0, 8))

    menuBtn.MouseButton1Click:Connect(function() ToggleMenu() end)

    Bind(passBtn.InputBegan:Connect(function(i)
        if IsPointer(i) then
            TouchPassHeld = true
            passBtn.BackgroundColor3 = Color3.fromRGB(0, 90, 55)
        end
    end))
    Bind(passBtn.InputEnded:Connect(function(i)
        if IsPointer(i) then
            TouchPassHeld = false
            passBtn.BackgroundColor3 = DARK
        end
    end))

    local grid = Instance.new("Frame")
    grid.AnchorPoint = Vector2.new(1, 0)
    grid.Position = UDim2.new(1, -144, 0.38, 0)
    grid.Size = UDim2.fromOffset(214, 174)
    grid.BackgroundColor3 = DARK
    grid.BackgroundTransparency = 0.2
    grid.Visible = false
    grid.Parent = touch
    Instance.new("UICorner", grid).CornerRadius = UDim.new(0, 8)
    local pad = Instance.new("UIPadding", grid)
    pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.fromOffset(66, 30)
    gl.CellPadding = UDim2.fromOffset(4, 4)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    for i, move in ipairs(DribbleMoves) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        b.TextColor3 = Color3.fromRGB(160, 230, 255)
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.Text = move.Code
        b.Selectable = false
        b.Parent = grid
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function() ExecuteDribbleMove(i) end)
    end
    movesBtn.MouseButton1Click:Connect(function() grid.Visible = not grid.Visible end)

    local function RefreshPlatform()
        local show = IsTouchMode()
        touch.Visible = show
        if not show then
            TouchPassHeld = false
            passBtn.BackgroundColor3 = DARK
            grid.Visible = false
        end
    end
    Bind(UserInputService.LastInputTypeChanged:Connect(RefreshPlatform))
    RefreshPlatform()
end

-- ============================================================================
-- INITIALIZE
-- ============================================================================
BindShotFeedback()
BuildCourtLines()
BuildUI()
BuildOverlay()

Bind(RunService.RenderStepped:Connect(function(dt)
    if Unloaded then return end
    local ok, err = pcall(UpdateAutoTime, dt)
    if not ok then warn("[Lunyx] autotime:", err) end
end))

Bind(RunService.Heartbeat:Connect(function()
    if Unloaded then return end
    for name, fn in pairs({
        offense = UpdateOffense, defense = UpdateDefense, runup = UpdateRunUp,
        handles = UpdateHandlesAndMovement, extras = UpdateExtras,
    }) do
        local ok, err = pcall(fn)
        if not ok and Throttle(Timers, "err_" .. name, 5) then warn("[Lunyx] " .. name .. ":", err) end
    end
end))