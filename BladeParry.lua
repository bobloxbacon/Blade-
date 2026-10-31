-- BLADE PARRY | Mobile-friendly auto-parry
-- Based on the common workspace.Balls / realBall / target layout.
-- This is not affiliated with Blade Ball or Roblox.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local ok, VirtualInput = pcall(function()
    return game:GetService("VirtualInputManager")
end)

local old = player:WaitForChild("PlayerGui"):FindFirstChild("BladeParryUI")
if old then old:Destroy() end
if getgenv then
    local env = getgenv()
    if env.BladeParryStop then pcall(env.BladeParryStop) end
end

local running, enabled = true, false
local lastParry = 0
local cooldown = 0.22
local lead = 0.30
local emergencyDistance = 10
local statusMessage = "Waiting for ball"
local connection

local C = {
    bg = Color3.fromRGB(20, 21, 30), panel = Color3.fromRGB(30, 31, 43),
    text = Color3.fromRGB(246, 245, 243), muted = Color3.fromRGB(157, 160, 176),
    red = Color3.fromRGB(255, 91, 87), green = Color3.fromRGB(113, 225, 169),
    border = Color3.fromRGB(63, 62, 77)
}
local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
end
local function label(parent, text, size, pos, textSize, color, font)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Size, x.Position = size, pos
    x.Text, x.TextSize, x.TextColor3 = text, textSize, color
    x.Font = font or Enum.Font.Gotham
    x.TextXAlignment = Enum.TextXAlignment.Left
    x.Parent = parent
    return x
end
local function button(parent, text, size, pos)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos
    b.BackgroundColor3, b.TextColor3 = C.panel, C.text
    b.BorderSizePixel = 0
    b.Text, b.TextSize, b.Font = text, 16, Enum.Font.GothamBold
    b.AutoButtonColor = true
    b.Parent = parent
    round(b, 10)
    return b
end

local gui = Instance.new("ScreenGui")
gui.Name = "BladeParryUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(300, 238)
panel.Position = UDim2.new(0.5, -150, 0.38, -90)
panel.BackgroundColor3 = C.bg
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = gui
round(panel, 16)
local stroke = Instance.new("UIStroke")
stroke.Color, stroke.Thickness = C.border, 1
stroke.Parent = panel

local accent = Instance.new("Frame")
accent.Size = UDim2.new(0, 4, 0, 30)
accent.Position = UDim2.fromOffset(16, 17)
accent.BackgroundColor3, accent.BorderSizePixel = C.red, 0
accent.Parent = panel
round(accent, 2)
label(panel, "BLADE / PARRY", UDim2.fromOffset(190, 22), UDim2.fromOffset(29, 14), 17, C.text, Enum.Font.GothamBlack)
label(panel, "AUTO DEFENSE", UDim2.fromOffset(170, 17), UDim2.fromOffset(30, 36), 11, C.muted, Enum.Font.GothamBold)
local close = button(panel, "×", UDim2.fromOffset(36, 34), UDim2.new(1, -50, 0, 15))
close.TextSize = 22

local toggle = button(panel, "ENABLE AUTO PARRY", UDim2.new(1, -32, 0, 48), UDim2.fromOffset(16, 65))
toggle.BackgroundColor3 = C.red
toggle.TextColor3 = C.bg

local dot = Instance.new("Frame")
dot.Size, dot.Position = UDim2.fromOffset(8, 8), UDim2.fromOffset(18, 129)
dot.BackgroundColor3, dot.BorderSizePixel, dot.Parent = C.muted, 0, panel
round(dot, 4)
local status = label(panel, "OFF  ·  Tap enable to start", UDim2.fromOffset(245, 23), UDim2.fromOffset(33, 121), 13, C.muted)

label(panel, "REACTION WINDOW", UDim2.fromOffset(160, 20), UDim2.fromOffset(17, 155), 11, C.muted, Enum.Font.GothamBold)
local minus = button(panel, "−", UDim2.fromOffset(42, 35), UDim2.fromOffset(16, 180))
local value = label(panel, "", UDim2.fromOffset(130, 35), UDim2.fromOffset(62, 180), 17, C.text, Enum.Font.GothamBold)
value.TextXAlignment = Enum.TextXAlignment.Center
local plus = button(panel, "+", UDim2.fromOffset(42, 35), UDim2.fromOffset(197, 180))
local function renderLead() value.Text = string.format("%.2f s", lead) end
renderLead()
minus.MouseButton1Click:Connect(function() lead = math.max(0.10, math.floor((lead - 0.05) * 100 + 0.5) / 100); renderLead() end)
plus.MouseButton1Click:Connect(function() lead = math.min(0.70, math.floor((lead + 0.05) * 100 + 0.5) / 100); renderLead() end)

local function paint()
    toggle.Text = enabled and "AUTO PARRY  /  ON" or "ENABLE AUTO PARRY"
    toggle.BackgroundColor3 = enabled and C.green or C.red
    dot.BackgroundColor3 = enabled and C.green or C.muted
    status.Text = enabled and statusMessage or "OFF  ·  Tap enable to start"
end
toggle.MouseButton1Click:Connect(function()
    if not ok or not VirtualInput then
        status.Text = "Input unavailable in this executor"
        return
    end
    enabled = not enabled
    paint()
end)

-- Drag from the title area on touch or mouse, without stealing button taps.
local dragging, dragStart, startPosition = false, nil, nil
panel.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
        and input.Position.Y - panel.AbsolutePosition.Y < 60 then
        dragging, dragStart, startPosition = true, input.Position, panel.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
local dragConnection = UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end
end)
local function stop()
    running, enabled = false, false
    if connection then connection:Disconnect() end
    if dragConnection then dragConnection:Disconnect() end
    gui:Destroy()
end
close.MouseButton1Click:Connect(stop)
if getgenv then getgenv().BladeParryStop = stop end

local function readVelocity(ball)
    local mover = ball:FindFirstChild("zoomies")
    if mover then
        local success, velocity = pcall(function() return mover.VectorVelocity end)
        if success and typeof(velocity) == "Vector3" then return velocity end
    end
    return ball.AssemblyLinearVelocity
end

local lastStatus = ""
connection = RunService.Heartbeat:Connect(function()
    if not running or not enabled then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local folder = workspace:FindFirstChild("Balls")
    if not root then
        statusMessage = "Waiting for character"
    elseif not folder then
        statusMessage = "Ball folder not found"
    else
        local real, target = nil, nil
        for _, candidate in ipairs(folder:GetChildren()) do
            if candidate:IsA("BasePart") and candidate:GetAttribute("realBall") == true then
                real = candidate
                target = candidate:GetAttribute("target")
                break
            end
        end
        if not real then
            statusMessage = "Waiting for ball"
        elseif target == nil then
            statusMessage = "Target data not found"
        elseif target ~= player.Name and target ~= player.UserId and target ~= tostring(player.UserId) then
            statusMessage = "Tracking  ·  Not targeting you"
        else
            local offset = root.Position - real.Position
            local distance = offset.Magnitude
            local relativeVelocity = readVelocity(real) - root.AssemblyLinearVelocity
            local closingSpeed = distance > 0 and relativeVelocity:Dot(offset.Unit) or 0
            statusMessage = string.format("Targeted  ·  %.0f studs", distance)
            if closingSpeed > 0 and os.clock() - lastParry >= cooldown then
                local eta = distance / closingSpeed
                if distance <= emergencyDistance or eta <= lead then
                    lastParry = os.clock()
                    local sent = pcall(function()
                        VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                        VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                    end)
                    if not sent then
                        enabled = false
                        paint()
                        status.Text = "Input blocked by executor"
                        return
                    end
                end
            end
        end
    end
    if statusMessage ~= lastStatus then
        status.Text = statusMessage
        lastStatus = statusMessage
    end
end)

