-- Samurai DUELS | Delta Mobile Script
-- Game: Samurai DUELS (Place ID: 72248722616845)
-- Executor: Delta | Mobile optimized
-- Features: Remote Scanner, Auto-Parry, Auto-Swing, Speed, Inf-Stamina, 
--            Anti-Ragdoll, ESP, Mobile UI (draggable, minimizable)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")

-- ══════════════════════════════════════════
--              CONFIG
-- ══════════════════════════════════════════
local CFG = {
    AutoParry       = false,
    AutoSwing       = false,
    WalkSpeed       = 32,
    InfStamina      = false,
    AntiRagdoll     = false,
    ESP             = false,
    AutoSwingDelay  = 0.05,
    ESPDistance     = 500,
}

-- ══════════════════════════════════════════
--              REMOTE SCANNER
-- ══════════════════════════════════════════
local scannedRemotes = {}
local chargeRemote, releaseRemote, parryRemote

local function scanRemotes()
    scannedRemotes = {}
    local orig = nil
    orig = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self:IsA("RemoteEvent") then
            local name = self.Name
            if not scannedRemotes[name] then
                scannedRemotes[name] = self
                print("[olliE SCANNER] Remote fired: " .. name)
            end
        end
        return orig(self, ...)
    end)
    print("[olliE] Remote scanner active — play the game to populate remotes")
    task.wait(15)
    -- auto-assign likely remotes after scan window
    for name, remote in pairs(scannedRemotes) do
        local n = name:lower()
        if n:find("charge") or n:find("startswing") then
            chargeRemote = remote
            print("[olliE] chargeRemote assigned: " .. name)
        elseif n:find("release") or n:find("swing") or n:find("attack") then
            releaseRemote = remote
            print("[olliE] releaseRemote assigned: " .. name)
        elseif n:find("parry") or n:find("block") or n:find("deflect") then
            parryRemote = remote
            print("[olliE] parryRemote assigned: " .. name)
        end
    end
    print("[olliE] Scan complete — " .. tostring(#scannedRemotes) .. " remotes found")
end

-- ══════════════════════════════════════════
--              UTILITIES
-- ══════════════════════════════════════════
local function getEnemies()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(list, p)
        end
    end
    return list
end

local function getClosest()
    local closest, dist = nil, math.huge
    for _, p in ipairs(getEnemies()) do
        local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
        if d < dist then closest, dist = p, d end
    end
    return closest, dist
end

-- ══════════════════════════════════════════
--              WALKSPEED
-- ══════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if hum and hum.Parent then
        hum.WalkSpeed = CFG.WalkSpeed
    end
end)

-- ══════════════════════════════════════════
--              INF STAMINA
-- ══════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not CFG.InfStamina then return end
    for _, v in ipairs(char:GetDescendants()) do
        if v.Name:lower():find("stamina") and v:IsA("NumberValue") then
            v.Value = v.MaxValue or 100
        end
    end
    local s = lp:FindFirstChild("Stamina", true)
    if s then s.Value = 100 end
end)

-- ══════════════════════════════════════════
--              ANTI RAGDOLL
-- ══════════════════════════════════════════
local function patchRagdoll(c)
    for _, v in ipairs(c:GetDescendants()) do
        if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then
            v.Enabled = false
        end
    end
    c.DescendantAdded:Connect(function(v)
        if v:IsA("BallSocketConstraint") or v:IsA("HingeConstraint") then
            task.wait()
            v.Enabled = false
        end
    end)
end

RunService.Heartbeat:Connect(function()
    if CFG.AntiRagdoll then patchRagdoll(char) end
end)

-- ══════════════════════════════════════════
--              AUTO PARRY
-- ══════════════════════════════════════════
local function watchSwing(enemy)
    if not enemy.Character then return end
    local animator = enemy.Character:FindFirstChildOfClass("Animator")
    if not animator then return end
    animator.AnimationPlayed:Connect(function(track)
        local n = track.Name:lower()
        if n:find("swing") or n:find("attack") or n:find("slash") or n:find("charge") then
            task.wait(0.08)
            if CFG.AutoParry and parryRemote then
                parryRemote:FireServer()
            end
        end
    end)
end

for _, p in ipairs(getEnemies()) do watchSwing(p) end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() task.wait(1) watchSwing(p) end)
end)

-- ══════════════════════════════════════════
--              AUTO SWING
-- ══════════════════════════════════════════
local swinging = false
RunService.Heartbeat:Connect(function()
    if not CFG.AutoSwing then return end
    local enemy, dist = getClosest()
    if enemy and dist < 15 and not swinging then
        swinging = true
        if chargeRemote and releaseRemote then
            chargeRemote:FireServer()
            task.wait(CFG.AutoSwingDelay)
            releaseRemote:FireServer()
        else
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            task.wait(CFG.AutoSwingDelay)
            vim:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end
        task.wait(0.6)
        swinging = false
    end
end)

-- ══════════════════════════════════════════
--              ESP
-- ══════════════════════════════════════════
local espFolder = Instance.new("Folder", game.CoreGui)
espFolder.Name = "SamuraiESP"

local function makeESP(player)
    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop = true
    bb.Size = UDim2.new(0, 110, 0, 45)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.Parent = espFolder

    local lbl = Instance.new("TextLabel", bb)
    lbl.Size = UDim2.new(1, 0, 0.75, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
    lbl.TextStrokeTransparency = 0
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13

    local bar = Instance.new("Frame", bb)
    bar.Size = UDim2.new(1, 0, 0, 4)
    bar.Position = UDim2.new(0, 0, 1, 2)
    bar.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    bar.BorderSizePixel = 0

    RunService.Heartbeat:Connect(function()
        if not CFG.ESP then bb.Enabled = false return end
        local c = player.Character
        if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChild("Humanoid") then
            local d = (c.HumanoidRootPart.Position - root.Position).Magnitude
            bb.Enabled = d <= CFG.ESPDistance
            bb.Adornee = c.HumanoidRootPart
            local h = c.Humanoid
            lbl.Text = string.format("%s\nHP:%d  D:%dm", player.Name, math.floor(h.Health), math.floor(d))
            local r = h.Health / h.MaxHealth
            bar.Size = UDim2.new(r, 0, 0, 4)
            bar.BackgroundColor3 = Color3.fromHSV(r * 0.33, 1, 1)
        else
            bb.Enabled = false
        end
    end)
end

for _, p in ipairs(getEnemies()) do makeESP(p) end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() task.wait(1) makeESP(p) end)
end)

-- ══════════════════════════════════════════
--              MOBILE UI
-- ══════════════════════════════════════════
local gui = Instance.new("ScreenGui", game.CoreGui)
gui.Name = "olliE_UI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

-- Main frame
local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 220, 0, 320)
main.Position = UDim2.new(0, 10, 0.5, -160)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = false -- manual drag below for mobile

Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(180, 60, 255)
stroke.Thickness = 1.5

-- Title bar
local titleBar = Instance.new("Frame", main)
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 10, 40)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size = UDim2.new(0.75, 0, 1, 0)
titleLbl.Position = UDim2.new(0.05, 0, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "⚔️ olliE | Samurai"
titleLbl.TextColor3 = Color3.fromRGB(220, 180, 255)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize button
local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0, 30, 0, 24)
minBtn.Position = UDim2.new(1, -34, 0.5, -12)
minBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 255)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- Content frame
local content = Instance.new("Frame", main)
content.Size = UDim2.new(1, 0, 1, -36)
content.Position = UDim2.new(0, 0, 0, 36)
content.BackgroundTransparency = 1

local layout = Instance.new("UIListLayout", content)
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
Instance.new("UIPadding", content).PaddingTop = UDim.new(0, 8)

-- Toggle factory
local function makeToggle(parent, label, cfgKey)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(0.92, 0, 0, 38)
    row.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
    row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.65, 0, 1, 0)
    lbl.Position = UDim2.new(0.04, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(220, 220, 240)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0, 46, 0, 24)
    btn.Position = UDim2.new(1, -54, 0.5, -12)
    btn.BackgroundColor3 = CFG[cfgKey] and Color3.fromRGB(120, 60, 220) or Color3.fromRGB(50, 50, 60)
    btn.Text = CFG[cfgKey] and "ON" or "OFF"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    btn.MouseButton1Click:Connect(function()
        CFG[cfgKey] = not CFG[cfgKey]
        btn.BackgroundColor3 = CFG[cfgKey] and Color3.fromRGB(120, 60, 220) or Color3.fromRGB(50, 50, 60)
        btn.Text = CFG[cfgKey] and "ON" or "OFF"
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = CFG[cfgKey] and Color3.fromRGB(150, 80, 255) or Color3.fromRGB(50, 50, 60)
        }):Play()
    end)
end

makeToggle(content, "⚡ Auto Parry",    "AutoParry")
makeToggle(content, "🗡️ Auto Swing",    "AutoSwing")
makeToggle(content, "👁️ ESP",           "ESP")
makeToggle(content, "💨 Inf Stamina",   "InfStamina")
makeToggle(content, "🛡️ Anti Ragdoll", "AntiRagdoll")

-- Speed slider label
local speedLbl = Instance.new("TextLabel", content)
speedLbl.Size = UDim2.new(0.92, 0, 0, 20)
speedLbl.BackgroundTransparency = 1
speedLbl.Text = "Speed: " .. CFG.WalkSpeed
speedLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
speedLbl.Font = Enum.Font.Gotham
speedLbl.TextSize = 11

-- Speed buttons
local speedRow = Instance.new("Frame", content)
speedRow.Size = UDim2.new(0.92, 0, 0, 34)
speedRow.BackgroundTransparency = 1
local spLayout = Instance.new("UIListLayout", speedRow)
spLayout.FillDirection = Enum.FillDirection.Horizontal
spLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
spLayout.Padding = UDim.new(0, 6)

for _, v in ipairs({16, 24, 32, 50}) do
    local sb = Instance.new("TextButton", speedRow)
    sb.Size = UDim2.new(0, 44, 0, 30)
    sb.BackgroundColor3 = v == CFG.WalkSpeed and Color3.fromRGB(120, 60, 220) or Color3.fromRGB(40, 40, 55)
    sb.Text = tostring(v)
    sb.TextColor3 = Color3.fromRGB(255, 255, 255)
    sb.Font = Enum.Font.GothamBold
    sb.TextSize = 12
    sb.BorderSizePixel = 0
    Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 6)
    sb.MouseButton1Click:Connect(function()
        CFG.WalkSpeed = v
        speedLbl.Text = "Speed: " .. v
        for _, c in ipairs(speedRow:GetChildren()) do
            if c:IsA("TextButton") then
                c.BackgroundColor3 = tonumber(c.Text) == v
                    and Color3.fromRGB(120, 60, 220)
                    or  Color3.fromRGB(40, 40, 55)
            end
        end
    end)
end

-- Scan button
local scanBtn = Instance.new("TextButton", content)
scanBtn.Size = UDim2.new(0.92, 0, 0, 36)
scanBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
scanBtn.Text = "🔍 Scan Remotes (15s)"
scanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
scanBtn.Font = Enum.Font.GothamBold
scanBtn.TextSize = 12
scanBtn.BorderSizePixel = 0
Instance.new("UICorner", scanBtn).CornerRadius = UDim.new(0, 8)
scanBtn.MouseButton1Click:Connect(function()
    scanBtn.Text = "⏳ Scanning..."
    scanBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 30)
    task.spawn(function()
        scanRemotes()
        scanBtn.Text = "✅ Scan Done"
        scanBtn.BackgroundColor3 = Color3.fromRGB(30, 100, 50)
    end)
end)

-- ══════════════════════════════════════════
--         MINIMIZE LOGIC
-- ══════════════════════════════════════════
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    main.Size = minimized and UDim2.new(0, 220, 0, 36) or UDim2.new(0, 220, 0, 320)
    minBtn.Text = minimized and "+" or "—"
end)

-- ══════════════════════════════════════════
--         DRAG (mobile touch)
-- ══════════════════════════════════════════
local dragging, dragStart, startPos = false, nil, nil

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ══════════════════════════════════════════
--         CHARACTER REFRESH
-- ══════════════════════════════════════════
lp.CharacterAdded:Connect(function(c)
    char = c
    hum = c:WaitForChild("Humanoid")
    root = c:WaitForChild("HumanoidRootPart")
    if CFG.AntiRagdoll then patchRagdoll(c) end
    for _, p in ipairs(getEnemies()) do makeESP(p) end
end)

print("[olliE] Samurai DUELS mobile script loaded — drag titlebar to move")