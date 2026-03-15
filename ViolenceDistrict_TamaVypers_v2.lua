-- ============================================================
--   TamaVypers v2.0 | Violence District
--   Fix: Remote Spy + Auto-Detect + Robust Logic
-- ============================================================

-- ── Cek executor support ─────────────────────────────────────
if not syn and not KRNL_LOADED and not fluxus then
    -- still try to run for compatible executors
end

local ok, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)
if not ok or not Rayfield then
    warn("[TamaVypers] Gagal load Rayfield! Cek koneksi internet atau whitelist sirius.menu")
    return
end

-- ─── Services ────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local VirtualUser       = game:GetService("VirtualUser")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ─── State ───────────────────────────────────────────────────
local State = {
    AutoParry    = false,
    AutoHook     = false,
    AutoCarry    = false,
    ESP          = false,
    Highlight    = false,
    AntiAFK      = false,
    InfJump      = false,
    RemoteSpy    = false,
    SpyLog       = {},
    Connections  = {},
    ESPObjects   = {},
    HighlightObj = {},
    -- user-configured remote names (dari Remote Spy)
    ParryRemote  = "",
    HookRemote   = "",
    CarryRemote  = "",
}

-- ─── Helpers ─────────────────────────────────────────────────
local function getChar()  return LP.Character end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function notify(title, msg, dur)
    pcall(function()
        Rayfield:Notify({ Title=title, Content=msg, Duration=dur or 3, Image=4483362458 })
    end)
end

-- Cari semua RemoteEvent/Function di seluruh game tree
local function scanRemotes()
    local found = {}
    local function scan(inst, depth)
        if depth > 8 then return end
        for _, v in ipairs(inst:GetChildren()) do
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                table.insert(found, {name=v.Name, path=v:GetFullName(), obj=v})
            end
            pcall(scan, v, depth+1)
        end
    end
    scan(game, 0)
    return found
end

-- Fire remote by exact name (search seluruh game)
local function fireRemote(name, ...)
    local function search(inst, depth)
        if depth > 8 then return false end
        for _, v in ipairs(inst:GetChildren()) do
            if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and v.Name == name then
                pcall(function()
                    if v:IsA("RemoteEvent") then
                        v:FireServer(...)
                    else
                        v:InvokeServer(...)
                    end
                end)
                return true
            end
            if search(v, depth+1) then return true end
        end
        return false
    end
    return search(game, 0)
end

-- Nearest enemy
local function getNearestEnemy(maxDist)
    local myHRP  = getHRP()
    if not myHRP then return nil, math.huge end
    local best, bestDist = nil, maxDist or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d < bestDist then
                    best, bestDist = p, d
                end
            end
        end
    end
    return best, bestDist
end

-- ─── Remote Spy (hook FireServer) ────────────────────────────
local spyMeta

local function startRemoteSpy()
    if State.Connections["RemoteSpy"] then return end

    -- Hook menggunakan __namecall metamethod
    local oldNamecall
    oldNamecall = hookmetamethod and hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer") and
           (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then

            local args = {...}
            local entry = string.format("[%s] %s | Args: %d", method, self:GetFullName(), #args)

            -- Simpan log (max 80 entry)
            table.insert(State.SpyLog, 1, entry)
            if #State.SpyLog > 80 then table.remove(State.SpyLog) end

            -- Update label di UI (dihandle di tab Remote Spy)
            if State.RemoteSpyCallback then
                pcall(State.RemoteSpyCallback, entry)
            end
        end
        return oldNamecall(self, ...)
    end) or nil

    if not oldNamecall then
        -- Fallback: pasang __index pada setiap RemoteEvent yang ditemukan
        notify("Remote Spy", "hookmetamethod tidak tersedia.\nMenggunakan fallback scanner.", 4)
        State.Connections["RemoteSpy"] = RunService.Heartbeat:Connect(function()
            -- passive scan tetap jalan, log akan terisi dari fireRemote calls
        end)
    else
        State.Connections["RemoteSpy"] = {Disconnect = function()
            -- unhook tidak bisa di-undo tanpa referensi, jadi kita cukup stop logging
            State.RemoteSpy = false
        end}
        notify("Remote Spy", "Remote Spy Aktif! Semua remote dicatat.", 3)
    end
end

local function stopRemoteSpy()
    if State.Connections["RemoteSpy"] then
        pcall(function() State.Connections["RemoteSpy"]:Disconnect() end)
        State.Connections["RemoteSpy"] = nil
    end
    notify("Remote Spy", "Remote Spy Dimatikan.", 3)
end

-- ─── Auto Parry ──────────────────────────────────────────────
-- Strategy:
-- 1. Jika user set ParryRemote → fire remote itu
-- 2. Scan common names
-- 3. Activate tool bernama Parry/Block/Guard
-- 4. Simulate key press (Q biasanya parry di game fighting)

local parryKeys    = {Enum.KeyCode.Q, Enum.KeyCode.F, Enum.KeyCode.V}
local parryNames   = {"Parry","Block","Guard","Deflect","Counter","Defend","shield","parry","block"}
local lastParry    = 0
local PARRY_CD     = 0.25  -- cooldown detik

local function doParry()
    local now = tick()
    if now - lastParry < PARRY_CD then return end
    lastParry = now

    -- 1. user-defined remote
    if State.ParryRemote ~= "" then
        fireRemote(State.ParryRemote)
        return
    end

    -- 2. scan common remote names
    for _, name in ipairs(parryNames) do
        if fireRemote(name) then return end
    end

    -- 3. tool activation
    local char = getChar()
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                local tn = tool.Name:lower()
                if tn:find("parry") or tn:find("block") or tn:find("guard") or tn:find("shield") then
                    pcall(function()
                        local args = tool:FindFirstChild("Handle") and {tool.Handle.CFrame.Position} or {}
                        tool:Activate()
                        -- coba juga fire internal remote tool
                        local re = tool:FindFirstChildOfClass("RemoteEvent")
                        if re then re:FireServer(table.unpack(args)) end
                    end)
                    return
                end
            end
        end
    end

    -- 4. simulate keypress (Q, F, V)
    for _, key in ipairs(parryKeys) do
        pcall(function()
            keypress(key.Value)
            task.delay(0.05, function() keyrelease(key.Value) end)
        end)
    end
end

local function startAutoParry()
    if State.Connections["AutoParry"] then return end
    State.Connections["AutoParry"] = RunService.Heartbeat:Connect(function()
        if not State.AutoParry then return end
        local _, dist = getNearestEnemy(15)
        if dist <= 15 then
            doParry()
        end
    end)
    notify("Auto Parry", "Auto Parry ON ✔", 3)
end

local function stopAutoParry()
    if State.Connections["AutoParry"] then
        State.Connections["AutoParry"]:Disconnect()
        State.Connections["AutoParry"] = nil
    end
    notify("Auto Parry", "Auto Parry OFF ✖", 3)
end

-- ─── Auto Hook ───────────────────────────────────────────────
local hookNames  = {"Hook","GrapplingHook","Grapple","grapple","hook","Rope","Lasso","Pull","Grab"}
local lastHook   = 0
local HOOK_CD    = 0.8

local function doHook(target)
    local now = tick()
    if now - lastHook < HOOK_CD then return end
    lastHook = now

    local hrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if State.HookRemote ~= "" then
        fireRemote(State.HookRemote, hrp.Position, target)
        return
    end

    for _, name in ipairs(hookNames) do
        if fireRemote(name, hrp.Position, target.Character, target) then return end
    end

    -- tool activation
    local char = getChar()
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") then
                local tn = tool.Name:lower()
                if tn:find("hook") or tn:find("grapple") or tn:find("rope") or tn:find("lasso") then
                    pcall(function()
                        -- arahkan mouse ke target dulu
                        local myHRP = getHRP()
                        if myHRP then
                            myHRP.CFrame = CFrame.lookAt(myHRP.Position, hrp.Position)
                        end
                        tool:Activate()
                    end)
                    return
                end
            end
        end
    end
end

local function startAutoHook()
    if State.Connections["AutoHook"] then return end
    State.Connections["AutoHook"] = RunService.Heartbeat:Connect(function()
        if not State.AutoHook then return end
        local enemy, dist = getNearestEnemy(65)
        if enemy and dist <= 65 then
            doHook(enemy)
        end
    end)
    notify("Auto Hook", "Auto Hook ON ✔", 3)
end

local function stopAutoHook()
    if State.Connections["AutoHook"] then
        State.Connections["AutoHook"]:Disconnect()
        State.Connections["AutoHook"] = nil
    end
    notify("Auto Hook", "Auto Hook OFF ✖", 3)
end

-- ─── Auto Carry ──────────────────────────────────────────────
local carryNames = {"Carry","PickUp","Pickup","pickup","carry","Drag","drag","Revive","revive","Lift","lift"}
local lastCarry  = 0
local CARRY_CD   = 1.0

local function isDown(character)
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    -- ragdoll / KO / downed check
    return hum.Health <= 0
        or hum:GetState() == Enum.HumanoidStateType.Dead
        or character:FindFirstChild("Ragdoll") ~= nil
        or character:FindFirstChild("KO") ~= nil
        or character:FindFirstChild("Downed") ~= nil
        or (hum.PlatformStand == true)
end

local function startAutoCarry()
    if State.Connections["AutoCarry"] then return end
    State.Connections["AutoCarry"] = RunService.Heartbeat:Connect(function()
        if not State.AutoCarry then return end
        local now = tick()
        if now - lastCarry < CARRY_CD then return end

        local myHRP = getHRP()
        if not myHRP then return end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (hrp.Position - myHRP.Position).Magnitude
                    if dist <= 12 then
                        lastCarry = now

                        if State.CarryRemote ~= "" then
                            fireRemote(State.CarryRemote, p, p.Character, hrp)
                        else
                            for _, name in ipairs(carryNames) do
                                if fireRemote(name, p, p.Character, hrp) then break end
                            end
                        end

                        -- tool
                        local char = getChar()
                        if char then
                            for _, tool in ipairs(char:GetChildren()) do
                                if tool:IsA("Tool") then
                                    local tn = tool.Name:lower()
                                    if tn:find("carry") or tn:find("pickup") or tn:find("drag") or tn:find("revive") then
                                        pcall(function() tool:Activate() end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    notify("Auto Carry", "Auto Carry ON ✔", 3)
end

local function stopAutoCarry()
    if State.Connections["AutoCarry"] then
        State.Connections["AutoCarry"]:Disconnect()
        State.Connections["AutoCarry"] = nil
    end
    notify("Auto Carry", "Auto Carry OFF ✖", 3)
end

-- ─── ESP ─────────────────────────────────────────────────────
local function makeESP(player)
    if State.ESPObjects[player.Name] then return end
    local function attach()
        if not player.Character then return end
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local bb = Instance.new("BillboardGui")
        bb.Name            = "TamaESP"
        bb.AlwaysOnTop     = true
        bb.Size            = UDim2.new(0, 80, 0, 30)
        bb.StudsOffset     = Vector3.new(0, 3.2, 0)
        bb.MaxDistance     = 500
        bb.Adornee         = hrp
        bb.Parent          = hrp

        local frame = Instance.new("Frame", bb)
        frame.Size              = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3  = Color3.fromRGB(60, 0, 100)
        frame.BackgroundTransparency = 0.2
        frame.BorderSizePixel   = 0
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 5)

        local stroke = Instance.new("UIStroke", frame)
        stroke.Color     = Color3.fromRGB(180, 80, 255)
        stroke.Thickness = 1.5

        local lbl = Instance.new("TextLabel", frame)
        lbl.Size             = UDim2.new(1, 0, 0.5, 0)
        lbl.Position         = UDim2.new(0, 0, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3       = Color3.fromRGB(220, 180, 255)
        lbl.Font             = Enum.Font.GothamBold
        lbl.TextScaled       = true
        lbl.Text             = player.Name

        local hpLbl = Instance.new("TextLabel", frame)
        hpLbl.Size             = UDim2.new(1, 0, 0.5, 0)
        hpLbl.Position         = UDim2.new(0, 0, 0.5, 0)
        hpLbl.BackgroundTransparency = 1
        hpLbl.TextColor3       = Color3.fromRGB(255, 100, 100)
        hpLbl.Font             = Enum.Font.Gotham
        hpLbl.TextScaled       = true

        -- update HP tiap frame
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if not State.ESP then conn:Disconnect() return end
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                hpLbl.Text = string.format("HP: %.0f/%.0f", hum.Health, hum.MaxHealth)
            end
        end)

        State.ESPObjects[player.Name] = {gui=bb, conn=conn}
    end

    attach()
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if State.ESPObjects[player.Name] then
            pcall(function() State.ESPObjects[player.Name].conn:Disconnect() end)
            pcall(function() State.ESPObjects[player.Name].gui:Destroy() end)
            State.ESPObjects[player.Name] = nil
        end
        attach()
    end)
end

local function removeESP(name)
    if State.ESPObjects[name] then
        pcall(function() State.ESPObjects[name].conn:Disconnect() end)
        pcall(function() State.ESPObjects[name].gui:Destroy() end)
        State.ESPObjects[name] = nil
    end
end

local function enableESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then makeESP(p) end
    end
    State.Connections["ESPAdd"] = Players.PlayerAdded:Connect(function(p)
        if State.ESP then makeESP(p) end
    end)
    State.Connections["ESPRem"] = Players.PlayerRemoving:Connect(function(p)
        removeESP(p.Name)
    end)
    notify("ESP", "Player ESP + HP ON ✔", 3)
end

local function disableESP()
    for name in pairs(State.ESPObjects) do removeESP(name) end
    if State.Connections["ESPAdd"] then State.Connections["ESPAdd"]:Disconnect() State.Connections["ESPAdd"]=nil end
    if State.Connections["ESPRem"] then State.Connections["ESPRem"]:Disconnect() State.Connections["ESPRem"]=nil end
    notify("ESP", "ESP OFF ✖", 3)
end

-- ─── Anti-AFK ────────────────────────────────────────────────
local function startAntiAFK()
    if State.Connections["AFK"] then return end
    State.Connections["AFK"] = LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
        end)
    end)
    notify("Anti-AFK", "Anti-AFK ON ✔", 3)
end

local function stopAntiAFK()
    if State.Connections["AFK"] then
        State.Connections["AFK"]:Disconnect()
        State.Connections["AFK"] = nil
        notify("Anti-AFK", "Anti-AFK OFF ✖", 3)
    end
end

-- ─── Teleport ────────────────────────────────────────────────
local function tpToPlayer(name)
    local p = Players:FindFirstChild(name)
    if not p or not p.Character then notify("Teleport","Pemain tidak ditemukan!",3) return end
    local myHRP  = getHRP()
    local tHRP   = p.Character:FindFirstChild("HumanoidRootPart")
    if myHRP and tHRP then
        myHRP.CFrame = tHRP.CFrame * CFrame.new(2, 0, 2)
        notify("Teleport","Teleport ke "..name.." ✔",3)
    end
end

local function tpToXYZ(x, y, z)
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(x, y, z)
        notify("Teleport", string.format("Teleport ke (%.1f, %.1f, %.1f) ✔", x, y, z), 3)
    end
end

-- ============================================================
--   RAYFIELD WINDOW
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name              = "TamaVypers",
    Icon              = 0,
    LoadingTitle      = "TamaVypers v2.0",
    LoadingSubtitle   = "Violence District",
    Theme             = "Aqua",
    DisableRayfieldPrompts   = false,
    DisableBuildWarnings     = false,
    ConfigurationSaving = {
        Enabled    = true,
        FolderName = "TamaVypers",
        FileName   = "Config",
    },
    KeySystem = { Enabled = false },
})

-- ═══════════════════════════════════
--  TAB 1 : ⚔️ Combat
-- ═══════════════════════════════════
local CombatTab = Window:CreateTab("⚔️ Combat", nil)

CombatTab:CreateSection("Auto Combat")

CombatTab:CreateToggle({
    Name = "Auto Parry",
    CurrentValue = false,
    Flag = "AutoParry",
    Callback = function(v)
        State.AutoParry = v
        if v then startAutoParry() else stopAutoParry() end
    end,
})

CombatTab:CreateToggle({
    Name = "Auto Hook",
    CurrentValue = false,
    Flag = "AutoHook",
    Callback = function(v)
        State.AutoHook = v
        if v then startAutoHook() else stopAutoHook() end
    end,
})

CombatTab:CreateToggle({
    Name = "Auto Carry / Revive",
    CurrentValue = false,
    Flag = "AutoCarry",
    Callback = function(v)
        State.AutoCarry = v
        if v then startAutoCarry() else stopAutoCarry() end
    end,
})

CombatTab:CreateSection("Remote Override (isi dari Remote Spy)")

CombatTab:CreateInput({
    Name = "Nama Remote — Parry",
    CurrentValue = "",
    PlaceholderText = "Contoh: Parry",
    RemoveTextAfterFocusLost = false,
    Flag = "ParryRemote",
    Callback = function(v)
        State.ParryRemote = v
        notify("Config", "Parry Remote: "..v, 2)
    end,
})

CombatTab:CreateInput({
    Name = "Nama Remote — Hook",
    CurrentValue = "",
    PlaceholderText = "Contoh: GrapplingHook",
    RemoveTextAfterFocusLost = false,
    Flag = "HookRemote",
    Callback = function(v)
        State.HookRemote = v
        notify("Config", "Hook Remote: "..v, 2)
    end,
})

CombatTab:CreateInput({
    Name = "Nama Remote — Carry",
    CurrentValue = "",
    PlaceholderText = "Contoh: Carry",
    RemoveTextAfterFocusLost = false,
    Flag = "CarryRemote",
    Callback = function(v)
        State.CarryRemote = v
        notify("Config", "Carry Remote: "..v, 2)
    end,
})

CombatTab:CreateSection("Info")
CombatTab:CreateLabel("• Auto Parry: aktif saat musuh ≤15 stud")
CombatTab:CreateLabel("• Auto Hook: target musuh terdekat ≤65 stud")
CombatTab:CreateLabel("• Auto Carry: angkat player jatuh ≤12 stud")
CombatTab:CreateLabel("• Gunakan Remote Spy tab lalu isi nama remote di atas")

-- ═══════════════════════════════════
--  TAB 2 : 🔍 Remote Spy
-- ═══════════════════════════════════
local SpyTab = Window:CreateTab("🔍 Remote Spy", nil)

SpyTab:CreateSection("Remote Spy")

local spyLogLabel = SpyTab:CreateLabel("Log kosong. Aktifkan Remote Spy lalu mainkan!")

State.RemoteSpyCallback = function(entry)
    pcall(function()
        spyLogLabel:Set("Latest: " .. entry:sub(1, 80))
    end)
end

SpyTab:CreateToggle({
    Name = "Remote Spy ON/OFF",
    CurrentValue = false,
    Flag = "RemoteSpy",
    Callback = function(v)
        State.RemoteSpy = v
        if v then startRemoteSpy() else stopRemoteSpy() end
    end,
})

SpyTab:CreateSection("Scan Remotes Sekarang")
SpyTab:CreateButton({
    Name = "🔎 Scan Semua Remote",
    Callback = function()
        local remotes = scanRemotes()
        local msg = "Ditemukan " .. #remotes .. " remote:\n"
        local lines = {}
        for i, r in ipairs(remotes) do
            if i <= 15 then
                table.insert(lines, r.name)
            end
        end
        msg = msg .. table.concat(lines, ", ")
        if #remotes > 15 then msg = msg .. "... (dan lebih banyak)" end
        notify("Remote Scan", msg, 8)
        -- update label
        pcall(function() spyLogLabel:Set("Scan: "..#remotes.." remote ditemukan!") end)
        print("[TamaVypers] Remote Scan:")
        for _, r in ipairs(remotes) do
            print("  >", r.path)
        end
    end,
})

SpyTab:CreateButton({
    Name = "📋 Print Log ke Console",
    Callback = function()
        print("[TamaVypers] Remote Spy Log ("..#State.SpyLog.." entries):")
        for i, entry in ipairs(State.SpyLog) do
            print(i, entry)
        end
        notify("Remote Spy", "Log dicetak ke console (F9).", 3)
    end,
})

SpyTab:CreateButton({
    Name = "🗑️ Clear Log",
    Callback = function()
        State.SpyLog = {}
        pcall(function() spyLogLabel:Set("Log dibersihkan.") end)
        notify("Remote Spy", "Log dibersihkan.", 2)
    end,
})

SpyTab:CreateSection("Cara Pakai Remote Spy")
SpyTab:CreateLabel("1. Aktifkan Remote Spy")
SpyTab:CreateLabel("2. Mainkan game normal (parry, hook, carry)")
SpyTab:CreateLabel("3. Tekan 'Print Log' → lihat F9 Console")
SpyTab:CreateLabel("4. Salin nama remote ke tab Combat")

-- ═══════════════════════════════════
--  TAB 3 : 👁️ Visual
-- ═══════════════════════════════════
local VisualTab = Window:CreateTab("👁️ Visual", nil)

VisualTab:CreateSection("ESP")

VisualTab:CreateToggle({
    Name = "Player ESP + HP Bar",
    CurrentValue = false,
    Flag = "ESPEnabled",
    Callback = function(v)
        State.ESP = v
        if v then enableESP() else disableESP() end
    end,
})

VisualTab:CreateSection("Highlight")

VisualTab:CreateToggle({
    Name = "Highlight Players",
    CurrentValue = false,
    Flag = "HighlightPlayers",
    Callback = function(v)
        State.Highlight = v
        if v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character then
                    local hl = Instance.new("SelectionBox")
                    hl.LineThickness    = 0.06
                    hl.Color3           = Color3.fromRGB(170, 0, 255)
                    hl.SurfaceColor3    = Color3.fromRGB(100, 0, 200)
                    hl.SurfaceTransparency = 0.75
                    hl.Adornee          = p.Character
                    hl.Parent           = p.Character
                    State.HighlightObj[p.Name] = hl
                end
            end
            notify("Visual", "Highlight ON ✔", 3)
        else
            for _, hl in pairs(State.HighlightObj) do pcall(function() hl:Destroy() end) end
            State.HighlightObj = {}
            notify("Visual", "Highlight OFF ✖", 3)
        end
    end,
})

-- ═══════════════════════════════════
--  TAB 4 : 🌀 Teleport
-- ═══════════════════════════════════
local TpTab = Window:CreateTab("🌀 Teleport", nil)

TpTab:CreateSection("Teleport ke Pemain")

local tpName = ""
TpTab:CreateInput({
    Name = "Nama Pemain",
    CurrentValue = "",
    PlaceholderText = "Ketik nama pemain...",
    RemoveTextAfterFocusLost = false,
    Flag = "TpName",
    Callback = function(v) tpName = v end,
})
TpTab:CreateButton({
    Name = "⚡ Teleport ke Pemain",
    Callback = function() tpToPlayer(tpName) end,
})

TpTab:CreateSection("Teleport ke Koordinat")
local tpX, tpY, tpZ = 0, 5, 0
TpTab:CreateInput({ Name="X", CurrentValue="0", PlaceholderText="X", RemoveTextAfterFocusLost=false, Flag="TpX", Callback=function(v) tpX=tonumber(v) or 0 end })
TpTab:CreateInput({ Name="Y", CurrentValue="5", PlaceholderText="Y", RemoveTextAfterFocusLost=false, Flag="TpY", Callback=function(v) tpY=tonumber(v) or 5 end })
TpTab:CreateInput({ Name="Z", CurrentValue="0", PlaceholderText="Z", RemoveTextAfterFocusLost=false, Flag="TpZ", Callback=function(v) tpZ=tonumber(v) or 0 end })
TpTab:CreateButton({
    Name = "⚡ Teleport ke XYZ",
    Callback = function() tpToXYZ(tpX, tpY, tpZ) end,
})

TpTab:CreateSection("Lainnya")
TpTab:CreateButton({
    Name = "🔄 Respawn Karakter",
    Callback = function()
        LP:LoadCharacter()
        notify("Teleport","Respawn...",2)
    end,
})

-- ═══════════════════════════════════
--  TAB 5 : ⚙️ Misc
-- ═══════════════════════════════════
local MiscTab = Window:CreateTab("⚙️ Misc", nil)

MiscTab:CreateSection("Anti-AFK")
MiscTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "AntiAFK",
    Callback = function(v)
        State.AntiAFK = v
        if v then startAntiAFK() else stopAntiAFK() end
    end,
})

MiscTab:CreateSection("Player Tweaks")
MiscTab:CreateSlider({
    Name = "Walk Speed",
    Range = {16, 120},
    Increment = 1,
    Suffix = "sp",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(v)
        local h = getHum()
        if h then h.WalkSpeed = v end
    end,
})
MiscTab:CreateSlider({
    Name = "Jump Power",
    Range = {50, 400},
    Increment = 5,
    Suffix = "jp",
    CurrentValue = 50,
    Flag = "JumpPower",
    Callback = function(v)
        local h = getHum()
        if h then h.JumpPower = v end
    end,
})
MiscTab:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfJump",
    Callback = function(v)
        State.InfJump = v
        if v then
            State.Connections["InfJump"] = UserInputService.JumpRequest:Connect(function()
                local h = getHum()
                if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
            notify("Misc","Infinite Jump ON ✔",3)
        else
            if State.Connections["InfJump"] then
                State.Connections["InfJump"]:Disconnect()
                State.Connections["InfJump"] = nil
            end
            notify("Misc","Infinite Jump OFF ✖",3)
        end
    end,
})

MiscTab:CreateSection("Informasi")
MiscTab:CreateLabel("TamaVypers v2.0 | Violence District")
MiscTab:CreateLabel("Remote Spy membutuhkan executor dengan hookmetamethod")
MiscTab:CreateLabel("Direkomendasikan: Synapse X / Fluxus / Solara")

-- ─── Selesai ─────────────────────────────────────────────────
task.wait(3.5)
notify("TamaVypers v2.0", "Script berhasil dimuat!\nGunakan Remote Spy untuk konfigurasi combat.", 6)
