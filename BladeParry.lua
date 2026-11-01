-- blade ball | delta mobile | tuned for blade ball
-- file: BladeParry.lua
-- runtime: Roblox Lua 5.1

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local cam = workspace.CurrentCamera

local enabled = true
local toggleKey = Enum.KeyCode.RightShift

local function log(msg)
    if rconsoleprint then
        rconsoleprint("[bb_delta] " .. tostring(msg) .. "\n")
    else
        print("[bb_delta] " .. tostring(msg))
    end
end

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

local function safeFire(remote, ...)
    if not remote then return end
    pcall(function()
        remote:FireServer(...)
    end)
end

local CFG = {
    AutoParry = true,
    ParryRadius = 26,
    ParryDelay = 0.06,
    AutoDash = true,
    DashAwayRange = 14,
    InfiniteJump = true,
    AntiKnockback = true,
    SpeedHack = false,
    SpeedValue = 28,
    BallTP = false,
    SilentAim = true,
    SilentAimRange = 60,
    HighlightBall = true,
    HighlightColor = Color3.fromRGB(255, 60, 60),
}

local parryRemote = nil
local dashRemote = nil
local ball = nil
local ballHighlight = nil

local lastParry = 0
local lastDash = 0
local parried = false

local function isBall(v)
    if not v or not v:IsA("BasePart") then
        return false
    end

    local name = v.Name:lower()
    if v:GetAttribute("realBall") == true then
        return true
    end

    return name:find("ball") ~= nil or name:find("projectile") ~= nil
end

local function getBall()
    local folder = workspace:FindFirstChild("Balls")
    if folder then
        for _, v in ipairs(folder:GetChildren()) do
            if isBall(v) then
                return v
            end
        end
    end

    for _, v in ipairs(workspace:GetDescendants()) do
        if isBall(v) then
            return v
        end
    end

    return nil
end

local function updateBallHighlight(target)
    if not CFG.HighlightBall or not target then
        if ballHighlight then
            ballHighlight:Destroy()
            ballHighlight = nil
        end
        return
    end

    if ballHighlight then
        if ballHighlight.Adornee ~= target then
            ballHighlight.Adornee = target
        end
        return
    end

    local h = Instance.new("Highlight")
    h.Name = "bb_delta_ball"
    h.FillColor = CFG.HighlightColor
    h.OutlineColor = CFG.HighlightColor
    h.FillTransparency = 0.5
    h.OutlineTransparency = 0
    h.Adornee = target
    h.Parent = target
    ballHighlight = h
end

local function findRemote(keyword)
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name:lower():find(keyword:lower()) then
            return v
        end
    end
end

local function refreshRemotes()
    if not parryRemote then
        parryRemote = findRemote("parry")
    end
    if not dashRemote then
        dashRemote = findRemote("dash")
    end
end

task.spawn(function()
    task.wait(1)
    refreshRemotes()

    ReplicatedStorage.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") then
            if not parryRemote and v.Name:lower():find("parry") then
                parryRemote = v
            end
            if not dashRemote and v.Name:lower():find("dash") then
                dashRemote = v
            end
        end
    end)

    log("Remote scan ready.")
end)

local function nearestEnemy()
    local root = getRoot()
    if not root then return nil end

    local closest, closestDist = nil, CFG.SilentAimRange
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local d = (root.Position - r.Position).Magnitude
                if d < closestDist then
                    closestDist = d
                    closest = r
                end
            end
        end
    end
    return closest
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
            local target = nearestEnemy()
            if target then
                return CFrame.new(target.Position)
            end
        end
        return oldIndex(self, key)
    end
    setreadonly(mt, true)
end)

local function toggleEnabled()
    enabled = not enabled
    log(enabled and "Delta enabled" or "Delta disabled")
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == toggleKey then
        toggleEnabled()
    end
end)

RunService.Heartbeat:Connect(function()
    if not enabled or not alive() then return end

    local root = getRoot()
    if not root then return end

    local b = getBall()
    if b then
        ball = b
        updateBallHighlight(b)
    else
        ball = nil
        if ballHighlight then
            ballHighlight:Destroy()
            ballHighlight = nil
        end
    end

    local now = tick()

    -- Auto parry
    if CFG.AutoParry and parryRemote and ball and not parried then
        if now - lastParry > 0.65 then
            local d = (root.Position - ball.Position).Magnitude
            if d <= CFG.ParryRadius then
                parried = true
                task.delay(CFG.ParryDelay, function()
                    safeFire(parryRemote)
                    lastParry = tick()
                    task.delay(0.25, function()
                        parried = false
                    end)
                end)
            end
        end
    end

    -- Auto dash
    if CFG.AutoDash and dashRemote and ball then
        if now - lastDash > 1.1 then
            local d = (root.Position - ball.Position).Magnitude
            if d <= CFG.DashAwayRange then
                local awayDir = (root.Position - ball.Position).Unit
                safeFire(dashRemote, awayDir)
                lastDash = tick()
            end
        end
    end

    -- Anti knockback
    if CFG.AntiKnockback then
        local bv = root:FindFirstChildOfClass("BodyVelocity")
        if bv then
            bv.Velocity = Vector3.zero
        end
    end

    -- Speed hack
    if CFG.SpeedHack then
        local h = getHum()
        if h then
            h.WalkSpeed = CFG.SpeedValue
        end
    end

    -- Ball TP
    if CFG.BallTP and ball then
        root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 4, 0))
    end
end)

UserInputService.JumpRequest:Connect(function()
    if not enabled or not CFG.InfiniteJump then return end
    local h = getHum()
    if h then
        h:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

lp.CharacterAdded:Connect(function(c)
    char = c
    c:WaitForChild("HumanoidRootPart", 6)
    if CFG.SpeedHack then
        local h = c:WaitForChild("Humanoid", 4)
        if h then
            h.WalkSpeed = CFG.SpeedValue
        end
    end
end)

-- Advanced mobile UI
local gui = Instance.new("ScreenGui")
gui.Name = "bb_delta_ui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function()
    gui.Parent = game:GetService("CoreGui")
end)
if not gui.Parent then
    gui.Parent = lp.PlayerGui
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 220, 0, 365)
main.Position = UDim2.new(0, 12, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
main.BorderSizePixel = 0
main.Parent = gui
local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = main

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
topBar.BorderSizePixel = 0
topBar.Parent = main
local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 12)
topCorner.Parent = topBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -72, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "BLADE BALL DELTA"
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(255, 75, 75)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
closeBtn.BackgroundColor3 = Color3.fromRGB(90, 30, 30)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = topBar
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeBtn

closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
end)

local yPos = 52
local function makeToggle(label, key)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -14, 0, 28)
    row.Position = UDim2.new(0, 7, 0, yPos)
    row.BackgroundColor3 = Color3.fromRGB(24, 24, 31)
    row.BorderSizePixel = 0
    row.Parent = main
    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 6)
    rowCorner.Parent = row

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, -50, 1, 0)
    text.Position = UDim2.new(0, 8, 0, 0)
    text.BackgroundTransparency = 1
    text.Text = label
    text.Font = Enum.Font.Gotham
    text.TextSize = 12
    text.TextColor3 = Color3.fromRGB(230, 230, 240)
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.Parent = row

    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 34, 0, 18)
    pill.Position = UDim2.new(1, -40, 0.5, -9)
    pill.BackgroundColor3 = CFG[key] and Color3.fromRGB(70, 200, 90) or Color3.fromRGB(90, 35, 35)
    pill.BorderSizePixel = 0
    pill.Parent = row
    local pillCorner = Instance.new("UICorner")
    pillCorner.CornerRadius = UDim.new(1, 0)
    pillCorner.Parent = pill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.Position = CFG[key] and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = pill
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = row

    btn.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        local on = CFG[key]
        pill.BackgroundColor3 = on and Color3.fromRGB(70, 200, 90) or Color3.fromRGB(90, 35, 35)
        knob.Position = on and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
    end)

    yPos = yPos + 33
end

makeToggle("Auto Parry", "AutoParry")
makeToggle("Auto Dash", "AutoDash")
makeToggle("Infinite Jump", "InfiniteJump")
makeToggle("Anti-Knockback", "AntiKnockback")
makeToggle("Speed Hack", "SpeedHack")
makeToggle("Ball TP", "BallTP")
makeToggle("Silent Aim", "SilentAim")
makeToggle("Highlight Ball", "HighlightBall")

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(1, 0, 0, 18)
statusText.Position = UDim2.new(0, 0, 1, -22)
statusText.BackgroundTransparency = 1
statusText.Text = "absolute ollie  •  delta"
statusText.Font = Enum.Font.Gotham
statusText.TextSize = 10
statusText.TextColor3 = Color3.fromRGB(120, 120, 130)
statusText.Parent = main

-- Dragging
local dragging = false
local dragStart = nil
local startPos = nil

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)

topBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

log("Blade Ball Delta loaded. RightShift toggles. Mobile UI ready.")