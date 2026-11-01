-- blade ball | delta executor | auto-parry + utility suite
-- file: bb_delta.lua | runtime: roblox lua 5.1 / delta api

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local cam = workspace.CurrentCamera

-- ══════════════════════════════════════
--  CONFIG BLOCK — tune here only
-- ══════════════════════════════════════
local CFG = {
    AutoParry      = true,
    ParryRadius    = 26,
    ParryDelay     = 0.08,
    AutoDash       = true,
    DashAwayRange  = 12,
    BallTP         = false,
    SpeedHack      = false,
    SpeedValue     = 28,
    InfiniteJump   = true,
    AntiKnockback  = true,
    SilentAim      = true,
    SilentAimRange = 60,
    HighlightBall  = true,
    HighlightColor = Color3.fromRGB(255, 60, 60),
    GUIOpen        = true,
}

-- ══════════════════════════════════════
--  DETECTION HARDENING
-- ══════════════════════════════════════
local rc = (rconsoleprint and true) or false
local _fire   = pcall
local _hookfn = hookfunction or function() end
local _newccl  = newcclosure or function(f) return f end

local function safefire(remote, ...)
    pcall(function(...)
        remote:FireServer(...)
    end, ...)
end

local function getRemote(tbl, keyword)
    for _, v in pairs(tbl:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name:lower():find(keyword:lower()) then
            return v
        end
    end
end

-- ══════════════════════════════════════
--  REMOTE RESOLUTION
-- ══════════════════════════════════════
local remotes    = ReplicatedStorage:WaitForChild("Events", 6)
              or  ReplicatedStorage
local parryRemote, dashRemote

task.spawn(function()
    parryRemote = getRemote(ReplicatedStorage, "parry")
    dashRemote  = getRemote(ReplicatedStorage, "dash")
end)

-- ══════════════════════════════════════
--  BALL DETECTION
-- ══════════════════════════════════════
local function getBall()
    for _, v in pairs(workspace:GetDescendants()) do
        local n = v.Name:lower()
        if v:IsA("BasePart") and (n:find("ball") or n:find("projectile")) then
            return v
        end
    end
end

local function distTo(part)
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not part then return math.huge end
    return (root.Position - part.Position).Magnitude
end

-- ══════════════════════════════════════
--  AUTO PARRY
-- ══════════════════════════════════════
local parried   = false
local parryCool = 0

RunService.Heartbeat:Connect(function()
    if not CFG.AutoParry or not parryRemote then return end
    if tick() - parryCool < 0.65 then return end

    local ball = getBall()
    if not ball then parried = false return end

    local d = distTo(ball)
    if d <= CFG.ParryRadius and not parried then
        parried = true
        task.delay(CFG.ParryDelay, function()
            safefire(parryRemote)
            parryCool = tick()
            task.delay(0.3, function() parried = false end)
        end)
    end
end)

-- ══════════════════════════════════════
--  AUTO DASH (away from ball)
-- ══════════════════════════════════════
local dashCool = 0

RunService.Heartbeat:Connect(function()
    if not CFG.AutoDash or not dashRemote then return end
    if tick() - dashCool < 1.2 then return end

    local ball = getBall()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not ball or not root then return end

    if distTo(ball) <= CFG.DashAwayRange then
        local awayDir = (root.Position - ball.Position).Unit
        safefire(dashRemote, awayDir)
        dashCool = tick()
    end
end)

-- ══════════════════════════════════════
--  INFINITE JUMP
-- ══════════════════════════════════════
UserInputService.JumpRequest:Connect(function()
    if not CFG.InfiniteJump then return end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- ══════════════════════════════════════
--  ANTI-KNOCKBACK
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not CFG.AntiKnockback then return end
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and root:FindFirstChild("RootAttachment") then
        local bp = root:FindFirstChildOfClass("BodyVelocity")
        if bp then bp.Velocity = Vector3.zero end
    end
end)

-- ══════════════════════════════════════
--  SPEED HACK
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not CFG.SpeedHack then return end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = CFG.SpeedValue end
end)

-- ══════════════════════════════════════
--  BALL TP
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not CFG.BallTP then return end
    local ball = getBall()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not ball or not root then return end
    local offset = CFrame.new(ball.Position + Vector3.new(0, 4, 0))
    root.CFrame = offset
end)

-- ══════════════════════════════════════
--  SILENT AIM (sword)
-- ══════════════════════════════════════
local function nearestEnemy()
    local closest, dist = nil, CFG.SilentAimRange
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local er = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if er and hum and hum.Health > 0 then
                local d = (root.Position - er.Position).Magnitude
                if d < dist then dist = d; closest = er end
            end
        end
    end
    return closest
end

if CFG.SilentAim then
    local oldIndex = _newccl(function(self, key)
        if key == "Hit" then
            local t = nearestEnemy()
            if t then return CFrame.new(t.Position) end
        end
        return self[key]
    end)
    pcall(function()
        local mt = getrawmetatable(lp:GetMouse())
        local old = mt.__index
        setreadonly(mt, false)
        mt.__index = function(self, key)
            if CFG.SilentAim and key == "Hit" then
                local t = nearestEnemy()
                if t then return CFrame.new(t.Position) end
            end
            return old(self, key)
        end
        setreadonly(mt, true)
    end)
end

-- ══════════════════════════════════════
--  BALL HIGHLIGHT
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not CFG.HighlightBall then return end
    local ball = getBall()
    if not ball then return end
    if not ball:FindFirstChildOfClass("SelectionBox") then
        local sb = Instance.new("SelectionBox")
        sb.Color3 = CFG.HighlightColor
        sb.LineThickness = 0.06
        sb.SurfaceTransparency = 0.5
        sb.SurfaceColor3 = CFG.HighlightColor
        sb.Adornee = ball
        sb.Parent = cam
    end
end)

-- ══════════════════════════════════════
--  CHARACTER RESPAWN RELINK
-- ══════════════════════════════════════
lp.CharacterAdded:Connect(function(c)
    char = c
    char:WaitForChild("HumanoidRootPart", 6)
end)

-- ══════════════════════════════════════
--  DELTA-COMPAT GUI
-- ══════════════════════════════════════
if not CFG.GUIOpen then return end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "bbdelta_ui_" .. tostring(math.random(1000,9999))
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = lp.PlayerGui end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 220, 0, 360)
main.Position = UDim2.new(0, 18, 0.5, -180)
main.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = ScreenGui

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
title.TextColor3 = Color3.fromRGB(255, 60, 60)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Text = " ⚔ BLADE BALL | DELTA"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

local yOff = 42
local function mkToggle(label, cfgKey)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 30)
    btn.Position = UDim2.new(0, 8, 0, yOff)
    btn.BackgroundColor3 = CFG[cfgKey]
        and Color3.fromRGB(40, 90, 40) or Color3.fromRGB(60, 30, 30)
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.Text = (CFG[cfgKey] and "✓ " or "✗ ") .. label
    btn.Parent = main
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    yOff = yOff + 34

    btn.MouseButton1Click:Connect(function()
        CFG[cfgKey] = not CFG[cfgKey]
        btn.BackgroundColor3 = CFG[cfgKey]
            and Color3.fromRGB(40, 90, 40) or Color3.fromRGB(60, 30, 30)
        btn.Text = (CFG[cfgKey] and "✓ " or "✗ ") .. label
    end)
end

mkToggle("Auto Parry",      "AutoParry")
mkToggle("Auto Dash",       "AutoDash")
mkToggle("Infinite Jump",   "InfiniteJump")
mkToggle("Anti-Knockback",  "AntiKnockback")
mkToggle("Speed Hack",      "SpeedHack")
mkToggle("Ball TP",         "BallTP")
mkToggle("Silent Aim",      "SilentAim")
mkToggle("Highlight Ball",  "HighlightBall")

local credit = Instance.new("TextLabel")
credit.Size = UDim2.new(1, 0, 0, 20)
credit.Position = UDim2.new(0, 0, 1, -22)
credit.BackgroundTransparency = 1
credit.TextColor3 = Color3.fromRGB(100, 100, 120)
credit.Font = Enum.Font.Gotham
credit.TextSize = 11
credit.Text = "absolute ollie, built by olivia"
credit.Parent = main
