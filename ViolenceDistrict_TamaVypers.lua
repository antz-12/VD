-- ============================================================
--   TamaVypers | Violence District Script
--   UI: Rayfield Library (sirius.menu)
--   Author: TamaVypers
-- ============================================================

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- ─── Services ───────────────────────────────────────────────
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local Workspace      = game:GetService("Workspace")

local LocalPlayer   = Players.LocalPlayer
local Camera        = Workspace.CurrentCamera

-- ─── State Variables ────────────────────────────────────────
local AutoParry      = false
local AutoHook       = false
local AutoCarry      = false
local ESPEnabled     = false
local AntiAFKEnabled = false

local ESPObjects     = {}
local Connections    = {}

-- ─── Utilities ──────────────────────────────────────────────
local function getCharacter()
    return LocalPlayer.Character
end

local function getHRP()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function notify(title, content, duration)
    Rayfield:Notify({
        Title    = title,
        Content  = content,
        Duration = duration or 3,
        Image    = 4483362458,
    })
end

-- ─── Anti-AFK ───────────────────────────────────────────────
local function startAntiAFK()
    if Connections["AntiAFK"] then return end
    local VirtualUser = game:GetService("VirtualUser")
    Connections["AntiAFK"] = Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
    notify("Anti-AFK", "Anti-AFK Aktif!", 3)
end

local function stopAntiAFK()
    if Connections["AntiAFK"] then
        Connections["AntiAFK"]:Disconnect()
        Connections["AntiAFK"] = nil
        notify("Anti-AFK", "Anti-AFK Dimatikan.", 3)
    end
end

-- ─── Auto Parry ─────────────────────────────────────────────
-- Detects incoming attacks by monitoring nearby enemy animations or hit events
local function startAutoParry()
    if Connections["AutoParry"] then return end

    Connections["AutoParry"] = RunService.Heartbeat:Connect(function()
        if not AutoParry then return end

        local char = getCharacter()
        if not char then return end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local enemyHRP = player.Character:FindFirstChild("HumanoidRootPart")
                local myHRP    = getHRP()
                if enemyHRP and myHRP then
                    local dist = (enemyHRP.Position - myHRP.Position).Magnitude
                    if dist <= 12 then
                        -- Try to fire Parry RemoteEvent / trigger block action
                        local function tryFire(name)
                            local re = workspace:FindFirstChild(name, true)
                                    or game:GetService("ReplicatedStorage"):FindFirstChild(name, true)
                            if re and re:IsA("RemoteEvent") then
                                pcall(function() re:FireServer() end)
                            end
                        end
                        tryFire("Parry")
                        tryFire("Block")
                        tryFire("Guard")

                        -- Attempt via tool activation if Parry is a tool
                        for _, tool in ipairs(char:GetChildren()) do
                            if tool:IsA("Tool") and (string.lower(tool.Name):find("parry") or string.lower(tool.Name):find("block")) then
                                local handle = tool:FindFirstChild("Handle")
                                if handle then
                                    pcall(function()
                                        tool:Activate()
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    notify("Auto Parry", "Auto Parry Aktif!", 3)
end

local function stopAutoParry()
    if Connections["AutoParry"] then
        Connections["AutoParry"]:Disconnect()
        Connections["AutoParry"] = nil
        notify("Auto Parry", "Auto Parry Dimatikan.", 3)
    end
end

-- ─── Auto Hook ──────────────────────────────────────────────
-- Fires hook remote or activates hook tool toward nearest enemy
local function startAutoHook()
    if Connections["AutoHook"] then return end

    Connections["AutoHook"] = RunService.Heartbeat:Connect(function()
        if not AutoHook then return end

        local myHRP = getHRP()
        if not myHRP then return end

        local nearest, nearDist = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local d = (hrp.Position - myHRP.Position).Magnitude
                    if d < nearDist then
                        nearest  = player
                        nearDist = d
                    end
                end
            end
        end

        if nearest and nearDist <= 60 then
            local char = getCharacter()

            -- Try RemoteEvent approach
            local function tryHook(name)
                local re = game:GetService("ReplicatedStorage"):FindFirstChild(name, true)
                        or workspace:FindFirstChild(name, true)
                if re and re:IsA("RemoteEvent") then
                    pcall(function()
                        re:FireServer(nearest.Character.HumanoidRootPart.Position)
                    end)
                end
            end
            tryHook("Hook")
            tryHook("GrapplingHook")
            tryHook("Grapple")

            -- Tool-based hook
            if char then
                for _, tool in ipairs(char:GetChildren()) do
                    if tool:IsA("Tool") and (string.lower(tool.Name):find("hook") or string.lower(tool.Name):find("grapple")) then
                        pcall(function() tool:Activate() end)
                    end
                end
            end
        end
    end)
    notify("Auto Hook", "Auto Hook Aktif!", 3)
end

local function stopAutoHook()
    if Connections["AutoHook"] then
        Connections["AutoHook"]:Disconnect()
        Connections["AutoHook"] = nil
        notify("Auto Hook", "Auto Hook Dimatikan.", 3)
    end
end

-- ─── Auto Carry ─────────────────────────────────────────────
-- Automatically fires carry/grab remote toward nearest downed player
local function startAutoCarry()
    if Connections["AutoCarry"] then return end

    Connections["AutoCarry"] = RunService.Heartbeat:Connect(function()
        if not AutoCarry then return end

        local myHRP = getHRP()
        if not myHRP then return end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum then
                    local isDown = hum.Health <= 0
                               or hum:FindFirstChild("Ragdoll") ~= nil
                               or (hum.FloorMaterial ~= Enum.Material.Air and hum.MoveDirection == Vector3.new(0,0,0))
                    local dist = (hrp.Position - myHRP.Position).Magnitude

                    if dist <= 10 then
                        local function tryCarry(name)
                            local re = game:GetService("ReplicatedStorage"):FindFirstChild(name, true)
                                    or workspace:FindFirstChild(name, true)
                            if re and re:IsA("RemoteEvent") then
                                pcall(function() re:FireServer(player) end)
                            end
                        end
                        tryCarry("Carry")
                        tryCarry("PickUp")
                        tryCarry("Grab")
                    end
                end
            end
        end
    end)
    notify("Auto Carry", "Auto Carry Aktif!", 3)
end

local function stopAutoCarry()
    if Connections["AutoCarry"] then
        Connections["AutoCarry"]:Disconnect()
        Connections["AutoCarry"] = nil
        notify("Auto Carry", "Auto Carry Dimatikan.", 3)
    end
end

-- ─── ESP ────────────────────────────────────────────────────
local function createESPBox(player)
    local billboard = Instance.new("BillboardGui")
    billboard.Name          = "TamaESP"
    billboard.AlwaysOnTop   = true
    billboard.Size          = UDim2.new(0, 60, 0, 20)
    billboard.StudsOffset   = Vector3.new(0, 3, 0)
    billboard.ResetOnSpawn  = false

    local nameLabel = Instance.new("TextLabel", billboard)
    nameLabel.Size            = UDim2.new(1, 0, 1, 0)
    nameLabel.BackgroundColor3= Color3.fromRGB(80, 0, 120)
    nameLabel.BackgroundTransparency = 0.3
    nameLabel.TextColor3      = Color3.fromRGB(220, 180, 255)
    nameLabel.TextScaled      = true
    nameLabel.Font            = Enum.Font.GothamBold
    nameLabel.Text            = player.Name
    nameLabel.BorderSizePixel = 0

    local corner = Instance.new("UICorner", nameLabel)
    corner.CornerRadius = UDim.new(0, 4)

    ESPObjects[player.Name] = billboard

    local function attach()
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            billboard.Adornee = player.Character.HumanoidRootPart
            billboard.Parent  = player.Character.HumanoidRootPart
        end
    end
    attach()
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        attach()
    end)
end

local function removeESP(playerName)
    if ESPObjects[playerName] then
        ESPObjects[playerName]:Destroy()
        ESPObjects[playerName] = nil
    end
end

local function enableESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            createESPBox(player)
        end
    end
    Connections["ESPAdded"] = Players.PlayerAdded:Connect(function(p)
        if ESPEnabled then createESPBox(p) end
    end)
    Connections["ESPRemoved"] = Players.PlayerRemoving:Connect(function(p)
        removeESP(p.Name)
    end)
    notify("ESP", "ESP Aktif! Nama musuh terlihat.", 3)
end

local function disableESP()
    for name, _ in pairs(ESPObjects) do
        removeESP(name)
    end
    if Connections["ESPAdded"]   then Connections["ESPAdded"]:Disconnect()   Connections["ESPAdded"]   = nil end
    if Connections["ESPRemoved"] then Connections["ESPRemoved"]:Disconnect() Connections["ESPRemoved"] = nil end
    notify("ESP", "ESP Dimatikan.", 3)
end

-- ─── Teleport ───────────────────────────────────────────────
local function teleportToPlayer(targetName)
    local target = Players:FindFirstChild(targetName)
    if not target or not target.Character then
        notify("Teleport", "Pemain tidak ditemukan atau belum spawn.", 3)
        return
    end
    local myHRP     = getHRP()
    local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
    if myHRP and targetHRP then
        myHRP.CFrame = targetHRP.CFrame + Vector3.new(2, 0, 2)
        notify("Teleport", "Teleport ke " .. targetName .. " berhasil!", 3)
    end
end

local function teleportToPosition(x, y, z)
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(x, y, z)
        notify("Teleport", string.format("Teleport ke (%.1f, %.1f, %.1f)", x, y, z), 3)
    end
end

-- ─── Rayfield Window ────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name             = "TamaVypers",
    Icon             = 0,
    LoadingTitle     = "TamaVypers",
    LoadingSubtitle  = "Violence District • by TamaVypers",
    Theme            = "Aqua",          -- closest to aquatic purple in Rayfield
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = false,

    ConfigurationSaving = {
        Enabled  = true,
        FolderName = "TamaVypers",
        FileName   = "VD_Config",
    },
    Discord = {
        Enabled    = false,
    },
    KeySystem = {
        Enabled = false,
    },
})

-- ─── Tab: Combat ────────────────────────────────────────────
local CombatTab = Window:CreateTab("⚔️ Combat", 4483362458)

CombatTab:CreateSection("Auto Combat")

CombatTab:CreateToggle({
    Name          = "Auto Parry",
    CurrentValue  = false,
    Flag          = "AutoParry",
    Callback      = function(val)
        AutoParry = val
        if val then startAutoParry() else stopAutoParry() end
    end,
})

CombatTab:CreateToggle({
    Name          = "Auto Hook",
    CurrentValue  = false,
    Flag          = "AutoHook",
    Callback      = function(val)
        AutoHook = val
        if val then startAutoHook() else stopAutoHook() end
    end,
})

CombatTab:CreateToggle({
    Name          = "Auto Carry",
    CurrentValue  = false,
    Flag          = "AutoCarry",
    Callback      = function(val)
        AutoCarry = val
        if val then startAutoCarry() else stopAutoCarry() end
    end,
})

CombatTab:CreateSection("Info")
CombatTab:CreateLabel("Auto Parry: Block saat musuh mendekat (≤12 stud)")
CombatTab:CreateLabel("Auto Hook: Kait musuh terdekat (≤60 stud)")
CombatTab:CreateLabel("Auto Carry: Ambil ally/musuh jatuh (≤10 stud)")

-- ─── Tab: Visual (ESP) ───────────────────────────────────────
local VisualTab = Window:CreateTab("👁️ Visual", 4483362458)

VisualTab:CreateSection("ESP")

VisualTab:CreateToggle({
    Name          = "Player ESP",
    CurrentValue  = false,
    Flag          = "ESPEnabled",
    Callback      = function(val)
        ESPEnabled = val
        if val then enableESP() else disableESP() end
    end,
})

VisualTab:CreateSection("Highlight")

local HighlightObjects = {}
VisualTab:CreateToggle({
    Name         = "Highlight Players",
    CurrentValue = false,
    Flag         = "HighlightESP",
    Callback     = function(val)
        if val then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local hl = Instance.new("SelectionBox")
                    hl.LineThickness = 0.05
                    hl.Color3        = Color3.fromRGB(160, 0, 255)
                    hl.SurfaceColor3 = Color3.fromRGB(100, 0, 200)
                    hl.SurfaceTransparency = 0.7
                    hl.Adornee       = p.Character
                    hl.Parent        = p.Character
                    HighlightObjects[p.Name] = hl
                end
            end
            notify("Highlight", "Highlight Player Aktif!", 3)
        else
            for _, hl in pairs(HighlightObjects) do
                pcall(function() hl:Destroy() end)
            end
            HighlightObjects = {}
            notify("Highlight", "Highlight Dimatikan.", 3)
        end
    end,
})

-- ─── Tab: Teleport ───────────────────────────────────────────
local TpTab = Window:CreateTab("🌀 Teleport", 4483362458)

TpTab:CreateSection("Teleport ke Pemain")

local tpPlayerName = ""
TpTab:CreateInput({
    Name          = "Nama Pemain",
    CurrentValue  = "",
    PlaceholderText = "Masukkan nama pemain...",
    RemoveTextAfterFocusLost = false,
    Flag          = "TpPlayerInput",
    Callback      = function(val)
        tpPlayerName = val
    end,
})

TpTab:CreateButton({
    Name     = "Teleport ke Pemain",
    Callback = function()
        if tpPlayerName ~= "" then
            teleportToPlayer(tpPlayerName)
        else
            notify("Teleport", "Masukkan nama pemain terlebih dahulu!", 3)
        end
    end,
})

TpTab:CreateSection("Teleport ke Koordinat")

local tpX, tpY, tpZ = 0, 5, 0
TpTab:CreateInput({
    Name          = "X Koordinat",
    CurrentValue  = "0",
    PlaceholderText = "X...",
    RemoveTextAfterFocusLost = false,
    Flag          = "TpX",
    Callback      = function(val) tpX = tonumber(val) or 0 end,
})
TpTab:CreateInput({
    Name          = "Y Koordinat",
    CurrentValue  = "5",
    PlaceholderText = "Y...",
    RemoveTextAfterFocusLost = false,
    Flag          = "TpY",
    Callback      = function(val) tpY = tonumber(val) or 5 end,
})
TpTab:CreateInput({
    Name          = "Z Koordinat",
    CurrentValue  = "0",
    PlaceholderText = "Z...",
    RemoveTextAfterFocusLost = false,
    Flag          = "TpZ",
    Callback      = function(val) tpZ = tonumber(val) or 0 end,
})
TpTab:CreateButton({
    Name     = "Teleport ke Koordinat",
    Callback = function()
        teleportToPosition(tpX, tpY, tpZ)
    end,
})

TpTab:CreateSection("Spawn Point")
TpTab:CreateButton({
    Name     = "Kembali ke Spawn",
    Callback = function()
        LocalPlayer:LoadCharacter()
        notify("Teleport", "Respawn...", 2)
    end,
})

-- ─── Tab: Misc ───────────────────────────────────────────────
local MiscTab = Window:CreateTab("⚙️ Misc", 4483362458)

MiscTab:CreateSection("Anti-AFK")

MiscTab:CreateToggle({
    Name          = "Anti-AFK",
    CurrentValue  = false,
    Flag          = "AntiAFK",
    Callback      = function(val)
        AntiAFKEnabled = val
        if val then startAntiAFK() else stopAntiAFK() end
    end,
})

MiscTab:CreateSection("Player Tweaks")

MiscTab:CreateSlider({
    Name         = "Walk Speed",
    Range        = {16, 100},
    Increment    = 1,
    Suffix       = "SP",
    CurrentValue = 16,
    Flag         = "WalkSpeed",
    Callback     = function(val)
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = val end
    end,
})

MiscTab:CreateSlider({
    Name         = "Jump Power",
    Range        = {50, 300},
    Increment    = 5,
    Suffix       = "JP",
    CurrentValue = 50,
    Flag         = "JumpPower",
    Callback     = function(val)
        local hum = getHumanoid()
        if hum then hum.JumpPower = val end
    end,
})

MiscTab:CreateToggle({
    Name         = "Infinite Jump",
    CurrentValue = false,
    Flag         = "InfJump",
    Callback     = function(val)
        if val then
            Connections["InfJump"] = UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid()
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
            notify("Misc", "Infinite Jump Aktif!", 3)
        else
            if Connections["InfJump"] then
                Connections["InfJump"]:Disconnect()
                Connections["InfJump"] = nil
            end
            notify("Misc", "Infinite Jump Dimatikan.", 3)
        end
    end,
})

MiscTab:CreateSection("Tentang")
MiscTab:CreateLabel("TamaVypers v1.0 | Violence District")
MiscTab:CreateLabel("UI: Rayfield by Sirius")

-- ─── Init Notify ────────────────────────────────────────────
task.wait(3)
notify(
    "TamaVypers Loaded!",
    "Script berhasil dimuat. Selamat bermain di Violence District!",
    5
)
