-- blade ball | delta | full rebuild — zero lag, features live
-- file: bb_delta.lua | runtime: roblox lua 5.1 / delta

-- ══════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local cam  = workspace.CurrentCamera

-- ══════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════
local CFG = {
    AutoParry      = true,
    ParryRadius    = 28,
    ParryDelay     = 0.06,
    AutoDash       = true,
    DashAwayRange  = 14,
    InfiniteJump   = true,
    AntiKnockback  = true,
    SpeedHack      = false,
    SpeedValue     = 28,
    BallTP         = false,
    SilentAim      = true,
    SilentAimRange = 60,
    HighlightBall  = true,
    HighlightColor = Color3.fromRGB(255, 50, 50),
}

-- ══════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════
local function getRoot()
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    return char and char:FindFirstChildOfClass("Humanoid")
end
local function alive()
    local h = getHum()
    return h and h.Health > 0
end
local function safefire(r, ...)
    if r then pcall(r.FireServer, r, ...) end
end

-- ══════════════════════════════════════
--  BALL CACHE — event-driven, zero per-frame scan
-- ══════════════════════════════════════
local ball = nil
local ballHL = nil  -- highlight instance

local function isBall(v)
    if not v:IsA("BasePart") then return false end
    local n = v.Name:lower()
    return n:find("ball") or n:find("projectile")
end

local function attachHL(part)
    if ballHL then ballHL:Destroy() end
    if not CFG.HighlightBall then return end
    local h = Instance.new("Highlight")
    h.FillColor      = CFG.HighlightColor
    h.OutlineColor   = CFG.HighlightColor
    h.FillTransparency    = 0.55
    h.OutlineTransparency = 0
    h.Adornee = part
    h.Parent  = part
    ballHL = h
end

-- seed existing ball
for _, v in ipairs(workspace:GetDescendants()) do
    if isBall(v) then ball = v; attachHL(v); break end
end

workspace.DescendantAdded:Connect(function(v)
    if isBall(v) then
        ball = v
        attachHL(v)
    end
end)
workspace.DescendantRemoving:Connect(function(v)
    if v == ball then
        ball = nil
        if ballHL then ballHL:Destroy(); ballHL = nil end
    end
end)

-- ══════════════════════════════════════
--  REMOTE CACHE
-- ══════════════════════════════════════
local parryRemote, dashRemote

local function findRemote(keyword)
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name:lower():find(keyword:lower()) then
            return v
        end
    end
end

task.spawn(function()
    -- wait for remotes to exist
    task.wait(2)
    parryRemote = findRemote("parry")
    dashRemote  = findRemote("dash")

    -- live-watch for late-added remotes
    ReplicatedStorage.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") then
            if not parryRemote and v.Name:lower():find("parry") then parryRemote = v end
            if not dashRemote  and v.Name:lower():find("dash")  then dashRemote  = v end
        end
    end)
end)

-- ══════════════════════════════════════
--  SILENT AIM
-- ══════════════════════════════════════
local function nearestEnemy()
    local root = getRoot()
    if not root then return nil end
    local best, bd = nil, CFG.SilentAimRange
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local d = (root.Position - r.Position).Magnitude
                if d < bd then bd = d; best = r end
            end
        end
    end
    return best
end

pcall(function()
    local mt  = getrawmetatable(lp:GetMouse())
    local old = mt.__index
    setreadonly(mt, false)
    mt.__index = function(self, k)
        if CFG.SilentAim and k == "Hit" then
            local t = nearestEnemy()
            if t then return CFrame.new(t.Position) end
        end
        return old(self, k)
    end
    setreadonly(mt, true)
end)

-- ══════════════════════════════════════
--  COOLDOWN TOKENS
-- ══════════════════════════════════════
local tParry = 0
local tDash  = 0
local parried = false

-- ══════════════════════════════════════
--  SINGLE HEARTBEAT — all features, one connection
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not alive() then return end
    local root = getRoot()
    if not root then return end
    local now = tick()

    -- AUTO PARRY
    if CFG.AutoParry and parryRemote and ball and not parried then
        if now - tParry > 0.65 then
            local d = (root.Position - ball.Position).Magnitude
            if d <= CFG.ParryRadius then
                parried = true
                task.delay(CFG.ParryDelay, function()
                    safefire(parryRemote)
                    tParry = tick()
                    task.delay(0.25, function() parried = false end)
                end)
            end
        end
    end

    -- AUTO DASH
    if CFG.AutoDash and dashRemote and ball then
        if now - tDash > 1.1 then
            local d = (root.Position - ball.Position).Magnitude
            if d <= CFG.DashAwayRange then
                local dir = (root.Position - ball.Position).Unit
                safefire(dashRemote, dir)
                tDash = tick()
            end
        end
    end

    -- BALL TP
    if CFG.BallTP and ball then
        root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 5, 0))
    end

    -- ANTI-KNOCKBACK
    if CFG.AntiKnockback then
        local bv = root:FindFirstChildOfClass("BodyVelocity")
        if bv then bv.Velocity = Vector3.zero end
    end

    -- SPEED HACK
    if CFG.SpeedHack then
        local h = getHum()
        if h then h.WalkSpeed = CFG.SpeedValue end
    end
end)

-- ══════════════════════════════════════
--  INFINITE JUMP
-- ══════════════════════════════════════
UserInputService.JumpRequest:Connect(function()
    if CFG.InfiniteJump then
        local h = getHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- ══════════════════════════════════════
--  RESPAWN RELINK
-- ══════════════════════════════════════
lp.CharacterAdded:Connect(function(c)
    char = c
    c:WaitForChild("HumanoidRootPart", 8)
    if CFG.SpeedHack then
        local h = c:WaitForChild("Humanoid", 4)
        if h then h.WalkSpeed = CFG.SpeedValue end
    end
end)

-- ══════════════════════════════════════
--  GUI — lean, manual drag, gethui() parent
-- ═════���════════════════════════════════
local GUI_W, GUI_H = 210, 46 + (8 * 34) + 10

local sg = Instance.new("ScreenGui")
sg.Name = "bb_" .. math.random(1e4, 9e4)
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
pcall(function() sg.Parent = gethui() end)
if not sg.Parent then
    pcall(function() sg.Parent = game:GetService("CoreGui") end)
end
if not sg.Parent then sg.Parent = lp.PlayerGui end

-- main frame
local mf = Instance.new("Frame")
mf.Size            = UDim2.new(0, GUI_W, 0, GUI_H)
mf.Position        = UDim2.new(0, 12, 0, 80)
mf.BackgroundColor3= Color3.fromRGB(12, 12, 16)
mf.BorderSizePixel = 0
mf.ClipsDescendants= true
mf.Parent          = sg
Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 8)

-- drop shadow
local sh = Instance.new("Frame")
sh.Size             = UDim2.new(1, 6, 1, 6)
sh.Position         = UDim2.new(0, -3, 0, -3)
sh.BackgroundColor3 = Color3.new(0,0,0)
sh.BackgroundTransparency = 0.6
sh.BorderSizePixel  = 0
sh.ZIndex           = 0
sh.Parent           = mf
Instance.new("UICorner", sh).CornerRadius = UDim.new(0, 10)

-- title bar
local tb = Instance.new("Frame")
tb.Size            = UDim2.new(1, 0, 0, 38)
tb.BackgroundColor3= Color3.fromRGB(20, 20, 30)
tb.BorderSizePixel = 0
tb.Parent          = mf

local tl = Instance.new("TextLabel")
tl.Size             = UDim2.new(1, -8, 1, 0)
tl.Position         = UDim2.new(0, 8, 0, 0)
tl.BackgroundTransparency = 1
tl.TextColor3       = Color3.fromRGB(255, 55, 55)
tl.Font             = Enum.Font.GothamBold
tl.TextSize         = 14
tl.Text             = "⚔  BLADE BALL  •  DELTA"
tl.TextXAlignment   = Enum.TextXAlignment.Left
tl.Parent           = tb

-- manual drag (no .Draggable lag)
do
    local drag, dragStart, frameStart = false, nil, nil
    tb.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag = true
            dragStart  = i.Position
            frameStart = mf.Position
        end
    end)
    tb.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = i.Position - dragStart
            mf.Position = UDim2.new(
                frameStart.X.Scale,
                frameStart.X.Offset + delta.X,
                frameStart.Y.Scale,
                frameStart.Y.Offset + delta.Y
            )
        end
    end)
end

-- toggle builder
local yy = 42
local function mkToggle(label, key)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, -12, 0, 28)
    row.Position         = UDim2.new(0, 6, 0, yy)
    row.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    row.BorderSizePixel  = 0
    row.Parent           = mf
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
    yy = yy + 32

    local lbl = Instance.new("TextLabel")
    lbl.Size              = UDim2.new(1, -50, 1, 0)
    lbl.Position          = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3        = Color3.fromRGB(210, 210, 220)
    lbl.Font              = Enum.Font.Gotham
    lbl.TextSize          = 12
    lbl.Text              = label
    lbl.TextXAlignment    = Enum.TextXAlignment.Left
    lbl.Parent            = row

    -- pill toggle
    local pill = Instance.new("Frame")
    pill.Size             = UDim2.new(0, 36, 0, 18)
    pill.Position         = UDim2.new(1, -44, 0.5, -9)
    pill.BorderSizePixel  = 0
    pill.BackgroundColor3 = CFG[key]
        and Color3.fromRGB(60, 200, 90)
        or  Color3.fromRGB(80, 30, 30)
    pill.Parent = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size             = UDim2.new(0, 14, 0, 14)
    knob.Position         = CFG[key]
        and UDim2.new(1, -16, 0.5, -7)
        or  UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.BorderSizePixel  = 0
    knob.Parent           = pill
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text              = ""
    btn.Parent            = row

    btn.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        local on = CFG[key]
        pill.BackgroundColor3 = on
            and Color3.fromRGB(60, 200, 90)
            or  Color3.fromRGB(80, 30, 30)
        knob.Position = on
            and UDim2.new(1, -16, 0.5, -7)
            or  UDim2.new(0, 2, 0.5, -7)
    end)
end

mkToggle("Auto Parry",     "AutoParry")
mkToggle("Auto Dash",      "AutoDash")
mkToggle("Infinite Jump",  "InfiniteJump")
mkToggle("Anti-Knockback", "AntiKnockback")
mkToggle("Speed Hack",     "SpeedHack")
mkToggle("Ball TP",        "BallTP")
mkToggle("Silent Aim",     "SilentAim")
mkToggle("Highlight Ball", "HighlightBall")

-- credit strip
local cr = Instance.new("TextLabel")
cr.Size              = UDim2.new(1, 0, 0, 18)
cr.Position          = UDim2.new(0, 0, 1, -20)
cr.BackgroundTransparency = 1
cr.TextColor3        = Color3.fromRGB(70, 70, 90)
cr.Font              = Enum.Font.Gotham
cr.TextSize          = 10
cr.Text              = "absolute ollie  •  built by olivia"
cr.Parent            = mf
