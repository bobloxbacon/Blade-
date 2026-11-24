-- Samurai DUELS | Delta Mobile Script v2
-- Game: Samurai DUELS (Place ID: 72248722616845)
-- Executor: Delta | Mobile optimized
-- Fixed: AutoSwing (no freeze), AutoParry (animation + proximity hybrid)
-- New: Swing-TP (teleport behind enemy on swing release), Kill Aura, Aimbot (enemies only)

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService    = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Camera          = workspace.CurrentCamera

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hum  = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")

-- ══════════════════════════════════════════
--              CONFIG
-- ══════════════════════════════════════════
local CFG = {
    -- features
    AutoParry    = false,
    AutoSwing    = false,
    SwingTP      = false,  -- teleport to enemy on swing release
    KillAura     = false,
    Aimbot       = false,
    ESP          = false,
    InfStamina   = false,
    AntiRagdoll  = false,

    -- values
    WalkSpeed       = 32,
    AutoSwingDelay  = 0.3,   -- charge hold time before release (longer = more damage)
    SwingTPOffset   = 5,     -- studs behind enemy to land
    KillAuraRange   = 12,    -- studs, keeps hitting everyone in range
    KillAuraCooldown= 0.4,   -- seconds between aura hits
    AimbotSmoothing = 0.15,  -- 0=snap 1=very slow
    ESPDistance     = 500,

    -- team check
    TeamCheck    = true,     -- aimbot/kill aura skip teammates
}

-- ══════════════════════════════════════════
--              REMOTE SCANNER
-- ══════════════════════════════════════════
local scannedRemotes                            = {}
local chargeRemote, releaseRemote, parryRemote

local scanHook = nil

local function scanRemotes()
    scannedRemotes = {}
    if scanHook then return end -- already hooked
    scanHook = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self:IsA("RemoteEvent") then
            local name = self.Name
            if not scannedRemotes[name] then
                scannedRemotes[name] = self
                print("[olliE SCANNER] " .. name)
                -- auto-assign on discovery
                local n = name:lower()
                if n:find("charge") or n:find("startswing") or n:find("hold") then
                    chargeRemote = self
                    print("[olliE] chargeRemote => " .. name)
                elseif n:find("release") or n:find("swing") or n:find("slash") then
                    releaseRemote = self
                    print("[olliE] releaseRemote => " .. name)
                elseif n:find("parry") or n:find("block") or n:find("deflect") or n:find("counter") then
                    parryRemote = self
                    print("[olliE] parryRemote => " .. name)
                end
            end
        end
        return scanHook(self, ...)
    end)
    print("[olliE] Scanner hooked — play normally to populate remotes")
end

-- ══════════════════════════════════════════
--              UTILITIES
-- ══════════════════════════════════════════
local function isEnemy(player)
    if not CFG.TeamCheck then return true end
    if player.Team and lp.Team then
        return player.Team ~= lp.Team
    end
    return true -- no teams = everyone is enemy
end

local function getEnemies()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and p.Character
            and p.Character:FindFirstChild("HumanoidRootPart")
            and p.Character:FindFirstChild("Humanoid")
            and p.Character.Humanoid.Health > 0
            and isEnemy(p) then
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
        if v.Name:lower():find("stamina") and (v:IsA("NumberValue") or v:IsA("IntValue")) then
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

-- ══════════════════════════════════════════
--              AIMBOT
--  locks camera/lookvector onto closest enemy
--  only fires when CFG.Aimbot = true
-- ══════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    if not CFG.Aimbot then return end
    local enemy, dist = getClosest()
    if not enemy then return end
    local eRoot = enemy.Character.HumanoidRootPart
    local targetPos = eRoot.Position + Vector3.new(0, 1.5, 0) -- aim chest height
    local currentCF = Camera.CFrame
    local targetCF  = CFrame.lookAt(currentCF.Position, targetPos)
    -- smooth lerp so it doesn't snap robotically
    Camera.CFrame = currentCF:Lerp(targetCF, CFG.AimbotSmoothing)
    -- also face character toward enemy
    local dir = (eRoot.Position - root.Position) * Vector3.new(1, 0, 1)
    if dir.Magnitude > 0.1 then
        root.CFrame = CFrame.lookAt(root.Position, root.Position + dir.Unit)
    end
end)

-- ══════════════════════════════════════════
--              AUTO PARRY
--  dual-mode: animation hook + proximity burst
--  parry fires when enemy within 20 studs AND
--  their animator plays any swing/attack track
-- ══════════════════════════════════════════
local function setupParryWatch(player)
    player.CharacterAdded:Connect(function(c)
        task.wait(1)
        local animator = c:WaitForChild("Humanoid"):WaitForChild("Animator")
        animator.AnimationPlayed:Connect(function(track)
            if not CFG.AutoParry then return end
            local n = track.Name:lower()
            if n:find("swing") or n:find("attack") or n:find("slash")
               or n:find("charge") or n:find("hit") or n:find("strike") then
                local d = (c:FindFirstChild("HumanoidRootPart") and
                    c.HumanoidRootPart.Position - root.Position).Magnitude or 999
                if d < 25 then
                    task.wait(0.06)
                    if parryRemote then
                        parryRemote:FireServer()
                    else
                        -- fallback: simulate parry key (usually Q or F on most games)
                        local vim = game:GetService("VirtualInputManager")
                        vim:SendKeyEvent(true,  Enum.KeyCode.Q, false, game)
                        task.wait(0.05)
                        vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
                    end
                end
            end
        end)
    end)
end

-- also hook already-loaded chars
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= lp then setupParryWatch(p) end
end
Players.PlayerAdded:Connect(function(p) setupParryWatch(p) end)

-- ══════════════════════════════════════════
--              AUTO SWING + SWING TP
--  AutoSwing: fires swing on cooldown, non-blocking
--  SwingTP: on release, teleport BEHIND enemy
--           so their swing hits us (they miss)
--           and we're in position to counter
-- ══════════════════════════════════════════
local swinging   = false
local swingCooldown = 0

RunService.Heartbeat:Connect(function(dt)
    swingCooldown = math.max(0, swingCooldown - dt)
    if not CFG.AutoSwing then return end
    if swingCooldown > 0 then return end
    local enemy, dist = getClosest()
    if not enemy or dist > 20 then return end
    if swinging then return end

    swinging = true
    task.spawn(function()
        -- charge phase
        if chargeRemote then
            chargeRemote:FireServer()
        else
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        end

        task.wait(CFG.AutoSwingDelay)

        -- swing TP: before release, snap behind enemy
        if CFG.SwingTP and enemy.Character and enemy.Character:FindFirstChild("HumanoidRootPart") then
            local eRoot = enemy.Character.HumanoidRootPart
            local behindOffset = eRoot.CFrame.LookVector * CFG.SwingTPOffset
            local landPos = eRoot.Position - behindOffset + Vector3.new(0, 0.5, 0)
            root.CFrame = CFrame.new(landPos, eRoot.Position)
        end

        -- release swing
        if releaseRemote then
            releaseRemote:FireServer()
        else
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end

        swingCooldown = 0.7
        task.wait(0.7)
        swinging = false
    end)
end)

-- ══════════════════════════════════════════
--              KILL AURA
--  teleports to each enemy in range briefly,
--  fires swing, returns — enemies only
-- ══════════════════════════════════════════
local auraCooldowns = {}

RunService.Heartbeat:Connect(function()
    if not CFG.KillAura then return end
    local now = tick()
    for _, p in ipairs(getEnemies()) do
        if not auraCooldowns[p.Name] or (now - auraCooldowns[p.Name]) >= CFG.KillAuraCooldown then
            local eChar = p.Character
            if eChar and eChar:FindFirstChild("HumanoidRootPart") then
                local d = (eChar.HumanoidRootPart.Position - root.Position).Magnitude
                if d <= CFG.KillAuraRange then
                    auraCooldowns[p.Name] = now
                    task.spawn(function()
                        -- brief snap to attack pos
                        local eRoot = eChar.HumanoidRootPart
                        local attackPos = eRoot.Position + (eRoot.CFrame.LookVector * -3) + Vector3.new(0, 0.5, 0)
                        local savedPos = root.CFrame
                        root.CFrame = CFrame.new(attackPos, eRoot.Position)

                        -- fire swing
                        if chargeRemote then chargeRemote:FireServer() end
                        task.wait(0.1)
                        if releaseRemote then releaseRemote:FireServer() end

                        task.wait(0.1)
                        root.CFrame = savedPos
                    end)
                end
            end
        end
    end
end)

-- ══════════════════════════════════════════
--              ESP
-- ══════════════════════════════════════════
local espFolder = Instance.new("Folder", game.CoreGui)
espFolder.Name  = "SamuraiESP"
local espBillboards = {}

local function makeESP(player)
    if espBillboards[player.Name] then return end
    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop = true
    bb.Size        = UDim2.new(0, 120, 0, 50)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.Parent      = espFolder
    espBillboards[player.Name] = bb

    local lbl = Instance.new("TextLabel", bb)
    lbl.Size                 = UDim2.new(1, 0, 0.75, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3           = Color3.fromRGB(255, 80, 80)
    lbl.TextStrokeTransparency = 0
    lbl.Font                 = Enum.Font.GothamBold
    lbl.TextSize             = 13

    local bar = Instance.new("Frame", bb)
    bar.Size            = UDim2.new(1, 0, 0, 4)
    bar.Position        = UDim2.new(0, 0, 1, 2)
    bar.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    bar.BorderSizePixel = 0

    RunService.Heartbeat:Connect(function()
        if not CFG.ESP then bb.Enabled = false return end
        local c = player.Character
        if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChild("Humanoid") then
            local d = (c.HumanoidRootPart.Position - root.Position).Magnitude
            if d <= CFG.ESPDistance then
                bb.Enabled = true
                bb.Adornee = c.HumanoidRootPart
                local h = c.Humanoid
                lbl.Text = string.format("%s\nHP:%d  %.0fm", player.Name, math.floor(h.Health), d)
                local r = math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1)
                bar.Size = UDim2.new(r, 0, 0, 4)
                bar.BackgroundColor3 = Color3.fromHSV(r * 0.33, 1, 1)
            else
                bb.Enabled = false
            end
        else
            bb.Enabled = false
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= lp then makeESP(p) end
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() task.wait(1) makeESP(p) end)
end)

-- ══════════════════════════════════════════
--              MOBILE UI
-- ══════════════════════════════════════════
-- destroy old UI if reinjecting
local oldGui = game.CoreGui:FindFirstChild("olliE_UI")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui", game.CoreGui)
gui.Name          = "olliE_UI"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true

local FULL_H = 490
local MIN_H  = 36

local main = Instance.new("Frame", gui)
main.Size            = UDim2.new(0, 230, 0, FULL_H)
main.Position        = UDim2.new(0, 8, 0.5, -(FULL_H/2))
main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
main.BorderSizePixel = 0
main.Active          = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", main)
stroke.Color     = Color3.fromRGB(160, 50, 255)
stroke.Thickness = 1.5

-- titlebar
local titleBar = Instance.new("Frame", main)
titleBar.Size            = UDim2.new(1, 0, 0, MIN_H)
titleBar.BackgroundColor3 = Color3.fromRGB(22, 8, 38)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size                 = UDim2.new(0.78, 0, 1, 0)
titleLbl.Position             = UDim2.new(0.04, 0, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text                 = "⚔️ olliE v2 | Samurai"
titleLbl.TextColor3           = Color3.fromRGB(210, 160, 255)
titleLbl.Font                 = Enum.Font.GothamBold
titleLbl.TextSize             = 12
titleLbl.TextXAlignment       = Enum.TextXAlignment.Left

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size            = UDim2.new(0, 28, 0, 22)
minBtn.Position        = UDim2.new(1, -32, 0.5, -11)
minBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 255)
minBtn.Text            = "—"
minBtn.TextColor3      = Color3.fromRGB(255, 255, 255)
minBtn.Font            = Enum.Font.GothamBold
minBtn.TextSize        = 13
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- scrollable content
local scrollFrame = Instance.new("ScrollingFrame", main)
scrollFrame.Size             = UDim2.new(1, 0, 1, -MIN_H)
scrollFrame.Position         = UDim2.new(0, 0, 0, MIN_H)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 0
scrollFrame.CanvasSize       = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

local contentLayout = Instance.new("UIListLayout", scrollFrame)
contentLayout.Padding            = UDim.new(0, 5)
contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
contentLayout.SortOrder          = Enum.SortOrder.LayoutOrder
Instance.new("UIPadding", scrollFrame).PaddingTop = UDim.new(0, 8)

-- section header factory
local function makeHeader(parent, text, order)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size                 = UDim2.new(0.92, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text                 = text
    lbl.TextColor3           = Color3.fromRGB(160, 100, 255)
    lbl.Font                 = Enum.Font.GothamBold
    lbl.TextSize             = 11
    lbl.TextXAlignment       = Enum.TextXAlignment.Left
    lbl.LayoutOrder          = order
end

-- toggle factory
local function makeToggle(parent, label, cfgKey, order)
    local row = Instance.new("Frame", parent)
    row.Size            = UDim2.new(0.92, 0, 0, 36)
    row.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
    row.BorderSizePixel = 0
    row.LayoutOrder     = order
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel", row)
    lbl.Size                 = UDim2.new(0.65, 0, 1, 0)
    lbl.Position             = UDim2.new(0.04, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                 = label
    lbl.TextColor3           = Color3.fromRGB(210, 210, 230)
    lbl.Font                 = Enum.Font.Gotham
    lbl.TextSize             = 11
    lbl.TextXAlignment       = Enum.TextXAlignment.Left

    local btn = Instance.new("TextButton", row)
    btn.Size            = UDim2.new(0, 44, 0, 22)
    btn.Position        = UDim2.new(1, -50, 0.5, -11)
    btn.BackgroundColor3 = CFG[cfgKey] and Color3.fromRGB(120, 50, 220) or Color3.fromRGB(45, 45, 58)
    btn.Text            = CFG[cfgKey] and "ON" or "OFF"
    btn.TextColor3      = Color3.fromRGB(255, 255, 255)
    btn.Font            = Enum.Font.GothamBold
    btn.TextSize        = 10
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

    btn.MouseButton1Click:Connect(function()
        CFG[cfgKey] = not CFG[cfgKey]
        TweenService:Create(btn, TweenInfo.new(0.12), {
            BackgroundColor3 = CFG[cfgKey] and Color3.fromRGB(130, 60, 240) or Color3.fromRGB(45, 45, 58)
        }):Play()
        btn.Text = CFG[cfgKey] and "ON" or "OFF"
    end)
end

-- build toggles
makeHeader(scrollFrame, "— COMBAT —", 1)
makeToggle(scrollFrame, "⚡ Auto Parry",      "AutoParry",   2)
makeToggle(scrollFrame, "🗡️ Auto Swing",      "AutoSwing",   3)
makeToggle(scrollFrame, "🌀 Swing TP",        "SwingTP",     4)
makeToggle(scrollFrame, "💀 Kill Aura",       "KillAura",    5)
makeToggle(scrollFrame, "🎯 Aimbot (enemies)","Aimbot",      6)
makeHeader(scrollFrame, "— PLAYER —", 7)
makeToggle(scrollFrame, "👁️ ESP",             "ESP",         8)
makeToggle(scrollFrame, "💨 Inf Stamina",     "InfStamina",  9)
makeToggle(scrollFrame, "🛡️ Anti Ragdoll",   "AntiRagdoll", 10)
makeToggle(scrollFrame, "🔒 Team Check",      "TeamCheck",   11)

-- speed section
makeHeader(scrollFrame, "— SPEED —", 12)

local speedLbl = Instance.new("TextLabel", scrollFrame)
speedLbl.Size                 = UDim2.new(0.92, 0, 0, 18)
speedLbl.BackgroundTransparency = 1
speedLbl.Text                 = "WalkSpeed: " .. CFG.WalkSpeed
speedLbl.TextColor3           = Color3.fromRGB(180, 180, 200)
speedLbl.Font                 = Enum.Font.Gotham
speedLbl.TextSize             = 11
speedLbl.LayoutOrder          = 13

local speedRow = Instance.new("Frame", scrollFrame)
speedRow.Size            = UDim2.new(0.92, 0, 0, 32)
speedRow.BackgroundTransparency = 1
speedRow.LayoutOrder     = 14
local spL = Instance.new("UIListLayout", speedRow)
spL.FillDirection        = Enum.FillDirection.Horizontal
spL.HorizontalAlignment  = Enum.HorizontalAlignment.Center
spL.Padding              = UDim.new(0, 5)

for _, v in ipairs({16, 24, 32, 50, 75}) do
    local sb = Instance.new("TextButton", speedRow)
    sb.Size            = UDim2.new(0, 38, 0, 28)
    sb.BackgroundColor3 = v == CFG.WalkSpeed and Color3.fromRGB(120, 50, 220) or Color3.fromRGB(38, 38, 52)
    sb.Text            = tostring(v)
    sb.TextColor3      = Color3.fromRGB(255, 255, 255)
    sb.Font            = Enum.Font.GothamBold
    sb.TextSize        = 11
    sb.BorderSizePixel = 0
    Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 5)
    sb.MouseButton1Click:Connect(function()
        CFG.WalkSpeed = v
        speedLbl.Text = "WalkSpeed: " .. v
        for _, c in ipairs(speedRow:GetChildren()) do
            if c:IsA("TextButton") then
                c.BackgroundColor3 = tonumber(c.Text) == v
                    and Color3.fromRGB(120, 50, 220)
                    or  Color3.fromRGB(38, 38, 52)
            end
        end
    end)
end

-- scan button
makeHeader(scrollFrame, "— TOOLS —", 15)

local scanBtn = Instance.new("TextButton", scrollFrame)
scanBtn.Size            = UDim2.new(0.92, 0, 0, 34)
scanBtn.BackgroundColor3 = Color3.fromRGB(30, 110, 70)
scanBtn.Text            = "🔍 Scan Remotes (passive)"
scanBtn.TextColor3      = Color3.fromRGB(255, 255, 255)
scanBtn.Font            = Enum.Font.GothamBold
scanBtn.TextSize        = 11
scanBtn.BorderSizePixel = 0
scanBtn.LayoutOrder     = 16
Instance.new("UICorner", scanBtn).CornerRadius = UDim.new(0, 8)
scanBtn.MouseButton1Click:Connect(function()
    scanRemotes()
    scanBtn.Text            = "✅ Hook Active"
    scanBtn.BackgroundColor3 = Color3.fromRGB(20, 80, 50)
end)

-- ══════════════════════════════════════════
--         MINIMIZE
-- ══════════════════════════════════════════
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    scrollFrame.Visible = not minimized
    TweenService:Create(main, TweenInfo.new(0.2), {
        Size = minimized and UDim2.new(0, 230, 0, MIN_H) or UDim2.new(0, 230, 0, FULL_H)
    }):Play()
    minBtn.Text = minimized and "+" or "—"
end)

-- ══════════════════════════════════════════
--         DRAG (touch)
-- ══════════════════════════════════════════
local dragging, dragStart, startPos = false, nil, nil

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = main.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)

-- ══════════════════════════════════════════
--         CHARACTER REFRESH
-- ══════════════════════════════════════════
lp.CharacterAdded:Connect(function(c)
    char = c
    hum  = c:WaitForChild("Humanoid")
    root = c:WaitForChild("HumanoidRootPart")
    if CFG.AntiRagdoll then patchRagdoll(c) end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then makeESP(p) end
    end
end)

if CFG.AntiRagdoll then patchRagdoll(char) end

print("[olliE v2] loaded — ⚔️ Samurai DUELS | drag titlebar to move")