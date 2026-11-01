-- blade ball | delta | all faults patched
-- file: BladeParry.lua | runtime: Roblox Lua 5.1

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()

-- ══════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════
local CFG = {
    AutoParry      = true,
    ParryRadius    = 26,
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
    HighlightColor = Color3.fromRGB(255, 60, 60),
}

local enabled = true

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
local function safeFire(r, ...)
    if r then pcall(r.FireServer, r, ...) end
end

-- ══════════════════════════════════════
--  FAULT 1 FIX — event-driven ball cache
--  zero GetDescendants calls in Heartbeat
-- ══════════════════════════════════════
local ball          = nil
local ballHighlight = nil

local function isBall(v)
    if not v or not v:IsA("BasePart") then return false end
    if v:GetAttribute("realBall") == true then return true end
    local n = v.Name:lower()
    return n:find("ball") ~= nil or n:find("projectile") ~= nil
end

-- FAULT 8 FIX — destroy highlight when flag is off regardless of ball state
local function syncHighlight()
    if not CFG.HighlightBall or not ball then
        if ballHighlight then
            ballHighlight:Destroy()
            ballHighlight = nil
        end
        return
    end
    if ballHighlight then
        if ballHighlight.Adornee ~= ball then
            ballHighlight.Adornee = ball
        end
        return
    end
    local h = Instance.new("Highlight")
    h.Name               = "bb_hl"
    h.FillColor          = CFG.HighlightColor
    h.OutlineColor       = CFG.HighlightColor
    h.FillTransparency   = 0.5
    h.OutlineTransparency= 0
    h.Adornee            = ball
    h.Parent             = ball
    ballHighlight        = h
end

-- seed existing ball on inject
for _, v in ipairs(workspace:GetDescendants()) do
    if isBall(v) then ball = v; break end
end
syncHighlight()

workspace.DescendantAdded:Connect(function(v)
    if isBall(v) then
        ball = v
        syncHighlight()
    end
end)

workspace.DescendantRemoving:Connect(function(v)
    if v == ball then
        ball = nil
        if ballHighlight then ballHighlight:Destroy(); ballHighlight = nil end
    end
end)

-- ══════════════════════════════════════
--  REMOTE CACHE
-- ══════════════════════════════════════
local parryRemote, dashRemote

local function findRemote(kw)
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name:lower():find(kw:lower()) then
            return v
        end
    end
end

task.spawn(function()
    task.wait(1)
    parryRemote = findRemote("parry")
    dashRemote  = findRemote("dash")

    ReplicatedStorage.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") then
            if not parryRemote and v.Name:lower():find("parry") then parryRemote = v end
            if not dashRemote  and v.Name:lower():find("dash")  then dashRemote  = v end
        end
    end)
end)

-- ══════════════════════════════════════
--  FAULT 2 FIX — silent aim oldIndex type guard
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
    local mouse = lp:GetMouse()
    if not mouse then return end
    local mt = getrawmetatable(mouse)
    if not mt then return end
    local oldIndex = mt.__index
    setreadonly(mt, false)
    mt.__index = function(self, key)
        if CFG.SilentAim and key == "Hit" then
            local t = nearestEnemy()
            if t then return CFrame.new(t.Position) end
        end
        -- FAULT 2: handle table or function __index
        if type(oldIndex) == "function" then
            return oldIndex(self, key)
        else
            return rawget(oldIndex, key)
        end
    end
    setreadonly(mt, true)
end)

-- ══════════════════════════════════════
--  COOLDOWNS
-- ══════════════════════════════════════
local lastParry = 0
local lastDash  = 0
local parried   = false

-- ══════════════════════════════════════
--  SINGLE HEARTBEAT
-- ══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not enabled or not alive() then return end
    local root = getRoot()
    if not root then return end
    local now = tick()

    -- AUTO PARRY
    if CFG.AutoParry and parryRemote and ball and not parried then
        if now - lastParry > 0.65 then
            local d = (root.Position - ball.Position).Magnitude
            if d <= CFG.ParryRadius then
                parried = true
                task.delay(CFG.ParryDelay, function()
                    safeFire(parryRemote)
                    lastParry = tick()
                    task.delay(0.25, function() parried = false end)
                end)
            end
        end
    end

    -- AUTO DASH
    if CFG.AutoDash and dashRemote and ball then
        if now - lastDash > 1.1 then
            local d = (root.Position - ball.Position).Magnitude
            if d <= CFG.DashAwayRange then
                safeFire(dashRemote, (root.Position - ball.Position).Unit)
                lastDash = tick()
            end
        end
    end

    -- FAULT 7 FIX — anti-knockback covers BodyVelocity AND LinearVelocity
    if CFG.AntiKnockback then
        local bv = root:FindFirstChildOfClass("BodyVelocity")
        if bv then bv.Velocity = Vector3.zero end
        local lv = root:FindFirstChildOfClass("LinearVelocity")
        if lv then lv.VectorVelocity = Vector3.zero end
    end

    -- SPEED
    if CFG.SpeedHack then
        local h = getHum()
        if h then h.WalkSpeed = CFG.SpeedValue end
    end

    -- BALL TP
    if CFG.BallTP and ball then
        root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 4, 0))
    end
end)

-- INFINITE JUMP
UserInputService.JumpRequest:Connect(function()
    if not enabled or not CFG.InfiniteJump then return end
    local h = getHum()
    if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

-- RESPAWN RELINK
lp.CharacterAdded:Connect(function(c)
    char = c
    c:WaitForChild("HumanoidRootPart", 6)
    if CFG.SpeedHack then
        local h = c:WaitForChild("Humanoid", 4)
        if h then h.WalkSpeed = CFG.SpeedValue end
    end
end)

-- ══════════════════════════════════════
--  GUI
--  FAULT 3 FIX — randomised name
--  FAULT 4 FIX — gethui() first
--  FAULT 5 FIX — mobile enable/disable button
--  FAULT 6 FIX — minimise/restore instead of destroy
-- ══════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name           = "bb_" .. math.random(1e4, 9e4)   -- FAULT 3
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true

-- FAULT 4: gethui() → CoreGui → PlayerGui cascade
pcall(function() sg.Parent = gethui() end)
if not sg.Parent then pcall(function() sg.Parent = game:GetService("CoreGui") end) end
if not sg.Parent then sg.Parent = lp.PlayerGui end

-- ── MINIMISE BUTTON (always visible) ──────────────────────────
local minBtn = Instance.new("TextButton")
minBtn.Size            = UDim2.new(0, 36, 0, 36)
minBtn.Position        = UDim2.new(0, 12, 0, 60)
minBtn.BackgroundColor3= Color3.fromRGB(26, 26, 34)
minBtn.Text            = "⚔"
minBtn.TextColor3      = Color3.fromRGB(255, 75, 75)
minBtn.Font            = Enum.Font.GothamBold
minBtn.TextSize        = 18
minBtn.BorderSizePixel = 0
minBtn.Visible         = false   -- hidden while panel open
minBtn.ZIndex          = 10
minBtn.Parent          = sg
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 8)

-- ── MAIN PANEL ────────────────────────────────────────────────
local ROWS   = 8
local PANEL_H= 52 + (ROWS * 33) + 28

local main = Instance.new("Frame")
main.Size            = UDim2.new(0, 220, 0, PANEL_H)
main.Position        = UDim2.new(0, 12, 0, 60)
main.BackgroundColor3= Color3.fromRGB(18, 18, 25)
main.BorderSizePixel = 0
main.Parent          = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

-- top bar
local topBar = Instance.new("Frame")
topBar.Size            = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3= Color3.fromRGB(26, 26, 34)
topBar.BorderSizePixel = 0
topBar.Parent          = main
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 12)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size             = UDim2.new(1, -80, 1, 0)
titleLbl.Position         = UDim2.new(0, 10, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text             = "BLADE BALL  •  DELTA"
titleLbl.Font             = Enum.Font.GothamBold
titleLbl.TextSize         = 13
titleLbl.TextColor3       = Color3.fromRGB(255, 75, 75)
titleLbl.TextXAlignment   = Enum.TextXAlignment.Left
titleLbl.Parent           = topBar

-- FAULT 6 FIX — minimise restores to floating button
local hideBtn = Instance.new("TextButton")
hideBtn.Size            = UDim2.new(0, 26, 0, 26)
hideBtn.Position        = UDim2.new(1, -32, 0.5, -13)
hideBtn.BackgroundColor3= Color3.fromRGB(70, 70, 90)
hideBtn.Text            = "—"
hideBtn.TextColor3      = Color3.new(1,1,1)
hideBtn.Font            = Enum.Font.GothamBold
hideBtn.TextSize        = 14
hideBtn.BorderSizePixel = 0
hideBtn.Parent          = topBar
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)

hideBtn.MouseButton1Click:Connect(function()
    main.Visible   = false
    minBtn.Visible = true
end)
minBtn.MouseButton1Click:Connect(function()
    main.Visible   = true
    minBtn.Visible = false
end)

-- FAULT 5 FIX — on/off toggle button in top bar (mobile-friendly)
local onOffBtn = Instance.new("TextButton")
onOffBtn.Size            = UDim2.new(0, 26, 0, 26)
onOffBtn.Position        = UDim2.new(1, -62, 0.5, -13)
onOffBtn.BackgroundColor3= Color3.fromRGB(60, 200, 90)
onOffBtn.Text            = "ON"
onOffBtn.TextColor3      = Color3.new(1,1,1)
onOffBtn.Font            = Enum.Font.GothamBold
onOffBtn.TextSize        = 10
onOffBtn.BorderSizePixel = 0
onOffBtn.Parent          = topBar
Instance.new("UICorner", onOffBtn).CornerRadius = UDim.new(0, 6)

onOffBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    onOffBtn.Text            = enabled and "ON"  or "OFF"
    onOffBtn.BackgroundColor3= enabled
        and Color3.fromRGB(60, 200, 90)
        or  Color3.fromRGB(180, 50, 50)
end)

-- ── DRAG (touch + mouse) ──────────────────────────────────────
do
    local drag, ds, sp = false, nil, nil
    local function onPress(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; ds = i.Position; sp = main.Position
        end
    end
    local function onRelease(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            drag = false
        end
    end
    topBar.InputBegan:Connect(onPress)
    topBar.InputEnded:Connect(onRelease)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (
            i.UserInputType == Enum.UserInputType.MouseMovement or
            i.UserInputType == Enum.UserInputType.Touch
        ) then
            local d = i.Position - ds
            main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X,
                                      sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
end

-- ── TOGGLES ───────────────────────────────────────────────────
local yPos = 50
local function makeToggle(label, key)
    local row = Instance.new("Frame")
    row.Size            = UDim2.new(1, -14, 0, 28)
    row.Position        = UDim2.new(0, 7, 0, yPos)
    row.BackgroundColor3= Color3.fromRGB(24, 24, 31)
    row.BorderSizePixel = 0
    row.Parent          = main
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size              = UDim2.new(1, -50, 1, 0)
    lbl.Position          = UDim2.new(0, 8, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text              = label
    lbl.Font              = Enum.Font.Gotham
    lbl.TextSize          = 12
    lbl.TextColor3        = Color3.fromRGB(230, 230, 240)
    lbl.TextXAlignment    = Enum.TextXAlignment.Left
    lbl.Parent            = row

    local pill = Instance.new("Frame")
    pill.Size            = UDim2.new(0, 34, 0, 18)
    pill.Position        = UDim2.new(1, -40, 0.5, -9)
    pill.BackgroundColor3= CFG[key]
        and Color3.fromRGB(70, 200, 90) or Color3.fromRGB(90, 35, 35)
    pill.BorderSizePixel = 0
    pill.Parent          = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size            = UDim2.new(0, 12, 0, 12)
    knob.Position        = CFG[key]
        and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    knob.BackgroundColor3= Color3.new(1,1,1)
    knob.BorderSizePixel = 0
    knob.Parent          = pill
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text               = ""
    btn.Parent             = row

    btn.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        local on = CFG[key]
        pill.BackgroundColor3 = on
            and Color3.fromRGB(70, 200, 90) or Color3.fromRGB(90, 35, 35)
        knob.Position = on
            and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
        -- FAULT 8: sync highlight immediately on toggle
        if key == "HighlightBall" then syncHighlight() end
    end)

    yPos = yPos + 33
end

makeToggle("Auto Parry",     "AutoParry")
makeToggle("Auto Dash",      "AutoDash")
makeToggle("Infinite Jump",  "InfiniteJump")
makeToggle("Anti-Knockback", "AntiKnockback")
makeToggle("Speed Hack",     "SpeedHack")
makeToggle("Ball TP",        "BallTP")
makeToggle("Silent Aim",     "SilentAim")
makeToggle("Highlight Ball", "HighlightBall")

local credit = Instance.new("TextLabel")
credit.Size              = UDim2.new(1, 0, 0, 18)
credit.Position          = UDim2.new(0, 0, 1, -22)
credit.BackgroundTransparency = 1
credit.Text              = "absolute ollie  •  built by olivia"
credit.Font              = Enum.Font.Gotham
credit.TextSize          = 10
credit.TextColor3        = Color3.fromRGB(90, 90, 110)
credit.Parent            = main