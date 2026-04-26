if not game:IsLoaded() then game.Loaded:Wait() end
pcall(function() game:GetService("Players").RespawnTime = 0 end)

-- ── Services ──────────────────────────────────────────────────────────────
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UserInputService= game:GetService("UserInputService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TweenService    = game:GetService("TweenService")
local HttpService     = game:GetService("HttpService")
local Workspace       = game:GetService("Workspace")
local LocalPlayer     = Players.LocalPlayer
local PlayerGui       = LocalPlayer:WaitForChild("PlayerGui")

-- ── Anti-sync patch ───────────────────────────────────────────────────────
do
    local Sync = require(game.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Synchronizer"))
    for name, fn in pairs(Sync) do
        if typeof(fn) ~= "function" or isexecutorclosure(fn) then continue end
        local ok, ups = pcall(debug.getupvalues, fn)
        if not ok then continue end
        for idx, val in pairs(ups) do
            if typeof(val) == "function" and not isexecutorclosure(val) then
                local ok2, innerUps = pcall(debug.getupvalues, val)
                if ok2 then
                    local hasBoolean = false
                    for _, v in pairs(innerUps) do
                        if typeof(v) == "boolean" then hasBoolean = true; break end
                    end
                    if hasBoolean then
                        debug.setupvalue(fn, idx, newcclosure(function() end))
                    end
                end
            end
        end
    end
end

-- ── Hitbox removal ────────────────────────────────────────────────────────
-- Disable CanCollide / CanQuery / CanTouch on other players' characters and on any clone models.
local function stripHitbox(part)
    if not part or not part:IsA("BasePart") then return end
    pcall(function()
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
    end)
end

local function removeHitboxesFromModel(model)
    if not model then return end
    for _, d in ipairs(model:GetDescendants()) do
        stripHitbox(d)
    end
    model.DescendantAdded:Connect(function(d)
        stripHitbox(d)
    end)
end

local function setupPlayerHitboxRemoval(player)
    if player == LocalPlayer then return end
    if player.Character then
        removeHitboxesFromModel(player.Character)
    end
    player.CharacterAdded:Connect(function(char)
        removeHitboxesFromModel(char)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    setupPlayerHitboxRemoval(p)
end
Players.PlayerAdded:Connect(setupPlayerHitboxRemoval)

local LocalCloneName = tostring(LocalPlayer.UserId).."_Clone"
local function processWorkspaceChild(child)
    if child:IsA("Model") and tostring(child.Name):match("_Clone$") then
        -- Nao tocar no clone do LocalPlayer (usado pelo Quantum Cloner / instantClone)
        if child.Name == LocalCloneName then return end
        removeHitboxesFromModel(child)
    end
end
for _, c in ipairs(Workspace:GetChildren()) do
    processWorkspaceChild(c)
end
Workspace.ChildAdded:Connect(processWorkspaceChild)

-- ── Config ────────────────────────────────────────────────────────────────
local CONFIG_FILE = "XiUtils_v1.json"
local DefaultConfig = {
    AutoTP       = true,
    MinGenForTp  = 0,
    TpDelay      = 0.00,
    TpAfterFPS   = false,
    FPSThreshold = 200,
    FPSWait      = 0.00,
    TpKey        = "T",
    CloneKey     = "]",
    Tool         = "Flying Carpet",
    AutoTPPriority = true,
    GuiPosX = nil,
    GuiPosY = nil,
    Minimized = false,
}
local Config = DefaultConfig

if isfile and isfile(CONFIG_FILE) then
    pcall(function()
        local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
        if ok and type(decoded) == "table" then
            for k, v in pairs(DefaultConfig) do
                if decoded[k] == nil then decoded[k] = v end
            end
            Config = decoded
        end
    end)
end

local function SaveConfig()
    if writefile then
        pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
    end
end

-- ── State ─────────────────────────────────────────────────────────────────
local State = { isTpMoving = false }
local _allBrainrots = {}
local SharedState = {
    AllAnimalsCache   = {},
    SelectedPetData   = nil,
}

-- ── Decrypted remote helper ───────────────────────────────────────────────
local Decrypted = setmetatable({}, {
    __index = function(S, ez)
        local Netty = ReplicatedStorage.Packages.Net
        local prefix, path
        if     ez:sub(1,3) == "RE/" then prefix = "RE/"; path = ez:sub(4)
        elseif ez:sub(1,3) == "RF/" then prefix = "RF/"; path = ez:sub(4)
        else return nil end
        local Remote
        for i, v in Netty:GetChildren() do
            if v.Name == ez then Remote = Netty:GetChildren()[i + 1]; break end
        end
        if Remote and not rawget(Decrypted, ez) then rawset(Decrypted, ez, Remote) end
        return rawget(Decrypted, ez)
    end
})

-- ── Priority list ─────────────────────────────────────────────────────────
local DEFAULT_PRIORITY_LIST = {
   "Strawberry Elephant","Meowl","Skibidi Toilet","Headless Horseman",
   "Dragon Gingerini","Dragon Cannelloni","Ketupat Bros","Hydra Dragon Cannelloni",
   "La Supreme Combinasion","Love Love Bear","Ginger Gerat","Cerberus",
   "Capitano Moby","La Casa Boo","Burguro and Fryuro","Spooky and Pumpky",
   "Cooki and Milki","Rosey and Teddy","Popcuru and Fizzuru","Reinito Sleighito",
   "Fragrama and Chocrama","Garama and Madundung","Ketchuru and Musturu",
   "La Secret Combinasion","Tralaledon","Tictac Sahur","Ketupat Kepat",
   "Tang Tang Keletang","Orcaledon","La Ginger Sekolah","Los Spaghettis",
   "Lavadorito Spinito","Swaggy Bros","La Taco Combinasion","Los Primos",
   "Chillin Chili","Tuff Toucan","W or L","Chipso and Queso"
}

local PRIORITY_LIST
if type(Config.PriorityList) == "table" and #Config.PriorityList > 0 then
    PRIORITY_LIST = {}
    for _, n in ipairs(Config.PriorityList) do
        if type(n) == "string" then table.insert(PRIORITY_LIST, n) end
    end
else
    PRIORITY_LIST = {}
    for _, n in ipairs(DEFAULT_PRIORITY_LIST) do table.insert(PRIORITY_LIST, n) end
    Config.PriorityList = PRIORITY_LIST
    SaveConfig()
end

-- ── Bases ─────────────────────────────────────────────────────────────────
local BASES_LOW = {
    [1]=Vector3.new(-485.19,-6.15, 194.93), [5]=Vector3.new(-335.23,-6.15, 194.93),
    [2]=Vector3.new(-485.19,-6.15,  88.21), [6]=Vector3.new(-335.23,-6.15, 138.95),
    [3]=Vector3.new(-485.19,-6.15, -18.85), [7]=Vector3.new(-335.23,-6.15,  32.11),
    [4]=Vector3.new(-484.64,-6.15, -74.87), [8]=Vector3.new(-335.23,-6.15, -74.80),
}
local BASES_LOW_ALT = {
    [1]=Vector3.new(-485.19,-6.15, 194.93), [5]=Vector3.new(-335.23,-6.15, 194.93),
    [2]=Vector3.new(-485.19,-6.15, 138.95), [6]=Vector3.new(-335.23,-6.15,  88.21),
    [3]=Vector3.new(-485.19,-6.15,  32.11), [7]=Vector3.new(-335.23,-6.15, -18.85),
    [4]=Vector3.new(-484.64,-6.15, -74.87), [8]=Vector3.new(-335.23,-6.15, -74.80),
}
local BASES_HIGH = {
    [1]=Vector3.new(-485.19, 13.8, 194.82), [5]=Vector3.new(-335.23, 13.8, 194.69),
    [2]=Vector3.new(-485.19, 13.8,  87.78), [6]=Vector3.new(-335.23, 13.8, 139.59),
    [3]=Vector3.new(-485.19, 13.8, -19.30), [7]=Vector3.new(-335.23, 13.8,  32.54),
    [4]=Vector3.new(-485.19, 13.8, -74.34), [8]=Vector3.new(-335.23, 13.8, -74.34),
}
local BASES_HIGH_ALT = {
    [1]=Vector3.new(-485.19, 13.8, 194.82), [5]=Vector3.new(-335.23, 13.8, 194.69),
    [2]=Vector3.new(-485.19, 13.8, 139.49), [6]=Vector3.new(-335.23, 13.8,  87.78),
    [3]=Vector3.new(-485.19, 13.8,  32.54), [7]=Vector3.new(-335.23, 13.8, -19.30),
    [4]=Vector3.new(-485.19, 13.8, -74.34), [8]=Vector3.new(-335.23, 13.8, -74.34),
}
local CLONE_POSITIONS_FLOOR = {
    Vector3.new(-476,-4,221), Vector3.new(-476,-4,114),
    Vector3.new(-476,-4,7),   Vector3.new(-476,-4,-100),
    Vector3.new(-342,-4,-100),Vector3.new(-342,-4,6),
    Vector3.new(-342,-4,114), Vector3.new(-342,-4,220)
}
local FACE_TARGETS = {
    Vector3.new(-519,-3,221), Vector3.new(-519,-3,114),
    Vector3.new(-518,-3,7),   Vector3.new(-519,-3,-100),
    Vector3.new(-301,-3,-100),Vector3.new(-301,-3,7),
    Vector3.new(-302,-3,114), Vector3.new(-300,-3,220)
}

-- ── Helper functions ──────────────────────────────────────────────────────
local function getControls()
    local ps = LocalPlayer:WaitForChild("PlayerScripts")
    return require(ps:WaitForChild("PlayerModule")):GetControls()
end

local function getClosestBaseIdx(pos)
    local closest, dist = 1, math.huge
    for i, basePos in pairs(BASES_LOW) do
        local d = (Vector2.new(pos.X,pos.Z)-Vector2.new(basePos.X,basePos.Z)).Magnitude
        if d < dist then dist=d; closest=i end
    end
    return closest
end

local function findAdorneeGlobal(animalData)
    if not animalData then return nil end
    local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    local base = podium:FindFirstChild("Base")
    if not base then return nil end
    local spawn = base:FindFirstChild("Spawn")
    if spawn then return spawn end
    return base:FindFirstChildWhichIsA("BasePart") or base
end

local function walkForward(seconds)
    local char = LocalPlayer.Character
    local hum  = char:FindFirstChild("Humanoid")
    local hrp  = char:FindFirstChild("HumanoidRootPart")
    local Ctrl = getControls()
    local lookVector = hrp.CFrame.LookVector
    Ctrl:Disable()
    local startTime = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if os.clock()-startTime >= seconds then
            conn:Disconnect(); hum:Move(Vector3.zero,false); Ctrl:Enable(); return
        end
        hum:Move(lookVector,false)
    end)
end

local function instantClone()
    if _G.isCloning then return end
    _G.isCloning = true
    local ok, err = pcall(function()
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum) then error("No character") end
        local cloner = LocalPlayer.Backpack:FindFirstChild("Quantum Cloner")
                    or char:FindFirstChild("Quantum Cloner")
        if not cloner then error("No Quantum Cloner") end
        pcall(function() hum:EquipTool(cloner) end)
        task.wait(0.05)
        cloner:Activate()
        task.wait(0.05)
        local cloneName = tostring(LocalPlayer.UserId).."_Clone"
        for _=1,100 do
            if Workspace:FindFirstChild(cloneName) then break end
            task.wait(0.1)
        end
        if not Workspace:FindFirstChild(cloneName) then error("") end
        local toolsFrames = LocalPlayer.PlayerGui:FindFirstChild("ToolsFrames")
        local qcFrame  = toolsFrames and toolsFrames:FindFirstChild("QuantumCloner")
        local tpButton = qcFrame and qcFrame:FindFirstChild("TeleportToClone")
        if not tpButton then error("Teleport button missing") end
        tpButton.Visible = true
        if firesignal then
            firesignal(tpButton.MouseButton1Up)
        else
            local vim   = cloneref and cloneref(game:GetService("VirtualInputManager")) or game:GetService("VirtualInputManager")
            local inset = (cloneref and cloneref(game:GetService("GuiService")) or game:GetService("GuiService")):GetGuiInset()
            local pos   = tpButton.AbsolutePosition+(tpButton.AbsoluteSize/2)+inset
            vim:SendMouseButtonEvent(pos.X,pos.Y,0,true,game,1)
            task.wait()
            vim:SendMouseButtonEvent(pos.X,pos.Y,0,false,game,1)
        end
    end)
    _G.isCloning = false
end

_G._isTargetPlotUnlocked = function(plotName)
    local ok, res = pcall(function()
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return false end
        local targetPlot = plots:FindFirstChild(plotName)
        if not targetPlot then return false end
        local unlockFolder = targetPlot:FindFirstChild("Unlock")
        if not unlockFolder then return true end
        local unlockItems = {}
        for _, item in pairs(unlockFolder:GetChildren()) do
            local pos = nil
            if item:IsA("Model") then pcall(function() pos=item:GetPivot().Position end)
            elseif item:IsA("BasePart") then pos=item.Position end
            if pos then table.insert(unlockItems,{Object=item,Height=pos.Y}) end
        end
        table.sort(unlockItems,function(a,b) return a.Height<b.Height end)
        if #unlockItems==0 then return true end
        local floor1Door = unlockItems[1].Object
        for _,desc in ipairs(floor1Door:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then return false end
        end
        for _,child in ipairs(floor1Door:GetChildren()) do
            if child:IsA("ProximityPrompt") and child.Enabled then return false end
        end
        return true
    end)
    return ok and res or false
end

-- ── FPS tracker ───────────────────────────────────────────────────────────
local CurrentFPS = 60
RunService.Heartbeat:Connect(function(dt)
    CurrentFPS = math.floor(1/dt)
end)

-- ── Helper: localiza o Carpet fisico no mapa ─────────────────────────────
local _lastCarpetX = nil
local _fakeCarpetCache = nil

local function _extractPartFromCarpet(carpet)
    if not carpet then return nil end
    if carpet:IsA("Model") then
        if carpet.PrimaryPart then return carpet.PrimaryPart end
        for _, c in ipairs(carpet:GetChildren()) do if c:IsA("BasePart") then return c end end
        for _, d in ipairs(carpet:GetDescendants()) do if d:IsA("BasePart") then return d end end
    elseif carpet:IsA("BasePart") then
        return carpet
    end
    return nil
end

local function findFlyingCarpet()
    local map = Workspace:FindFirstChild("Map")

    if map then
        local carpet = map:FindFirstChild("Carpet")
        local part = _extractPartFromCarpet(carpet)
        if part then
            _lastCarpetX = part.Position.X
            return part
        end
    end

    local searchRoots = {}
    if map then table.insert(searchRoots, map) end
    for _, name in ipairs({"Events", "Event", "CyberEvent", "EventMap", "Temp", "Maps"}) do
        local f = Workspace:FindFirstChild(name)
        if f then table.insert(searchRoots, f) end
    end

    local altNames = {
        "CyberCarpet", "CyberConveyor", "CyberRoad", "GlitchCarpet",
        "Highway", "Road", "Conveyor", "RedCarpet", "Carpet"
    }
    for _, root in ipairs(searchRoots) do
        for _, n in ipairs(altNames) do
            local c = root:FindFirstChild(n)
            local part = _extractPartFromCarpet(c)
            if part then
                _lastCarpetX = part.Position.X
                return part
            end
        end
    end

    for _, root in ipairs(searchRoots) do
        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("Model") or desc:IsA("BasePart") then
                local lname = desc.Name:lower()
                if lname:find("carpet") or lname:find("highway")
                   or lname == "conveyor" or lname == "cyberconveyor" then
                    local part = _extractPartFromCarpet(desc)
                    if part then
                        _lastCarpetX = part.Position.X
                        return part
                    end
                end
            end
        end
    end

    local fallbackX = _lastCarpetX or -410
    if _fakeCarpetCache and _fakeCarpetCache.Parent then
        _fakeCarpetCache.Position = Vector3.new(fallbackX, 0, 0)
        return _fakeCarpetCache
    end
    local fake = Instance.new("Part")
    fake.Name = "_CarpetFallbackRef"
    fake.Anchored = true
    fake.CanCollide = false
    fake.Transparency = 1
    fake.Size = Vector3.new(1, 1, 1)
    fake.Position = Vector3.new(fallbackX, 0, 0)
    fake.Parent = Workspace
    _fakeCarpetCache = fake
    return fake
end

task.spawn(function()
    for _ = 1, 30 do
        local p = (function()
            local m = Workspace:FindFirstChild("Map")
            if not m then return nil end
            local c = m:FindFirstChild("Carpet")
            return _extractPartFromCarpet(c)
        end)()
        if p then _lastCarpetX = p.Position.X; return end
        task.wait(0.5)
    end
end)

local function findClaimModel(podium)
    if not podium or not podium.Parent then return nil end
    local claim = podium:FindFirstChild("Claim")
    if claim and claim:IsA("Model") then
        if claim.PrimaryPart then return claim.PrimaryPart end
        for _, c in ipairs(claim:GetChildren()) do if c:IsA("BasePart") then return c end end
    end
    return nil
end

local function getTargetPodiumAndSafePosition(animalData, fallbackPos)
    if not animalData or not animalData.plot then return nil, fallbackPos end
    local plots = Workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild(animalData.plot)
    local podiums = plot and plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil, fallbackPos end
    local safeName = (fallbackPos and fallbackPos.Y > 8.8) and "13" or "3"
    local safePod = podiums:FindFirstChild(safeName)
    local safeBase = safePod and safePod:FindFirstChild("Base")
    local safeSpawn = safeBase and safeBase:FindFirstChild("Spawn")
    return safePod, (safeSpawn and safeSpawn:IsA("BasePart") and safeSpawn.Position) or fallbackPos
end

-- ── Main TP function ──────────────────────────────────────────────────────
local function runAutoSnipe()
    if State.isTpMoving then return end

    local targetPetData = nil
    local cache = SharedState.AllAnimalsCache
    if Config.AutoTPPriority then
        if cache and type(cache) == "table" then
            for _, pName in ipairs(PRIORITY_LIST) do
                local searchName = pName:lower()
                for _, a in ipairs(cache) do
                    if a and a.name and a.name:lower() == searchName and a.owner ~= LocalPlayer.Name then
                        targetPetData = a; break
                    end
                end
                if targetPetData then break end
            end
            if not targetPetData then
                for _, a in ipairs(cache) do
                    if a and a.owner ~= LocalPlayer.Name then targetPetData = a; break end
                end
            end
        end
    else
        if SharedState.SelectedPetData then
            targetPetData = SharedState.SelectedPetData.animalData
        end
    end
    if not targetPetData then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChild("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    State.isTpMoving = true

    local targetPart = findAdorneeGlobal(targetPetData)
    if not targetPart then State.isTpMoving = false; return end

    local exactPos   = targetPart.Position
    local carpetName = Config.Tool
    local carpet     = LocalPlayer.Backpack:FindFirstChild(carpetName) or char:FindFirstChild(carpetName)

    -- ── LEFA: Selecao de base por posicao ────────────────────────────────
    local isSecondFloor = exactPos.Y > 10
    local plotIndex = getClosestBaseIdx(exactPos)
    local targetBasePos
    local isAlt = false

    if isSecondFloor then
        local posStd = BASES_HIGH[plotIndex]
        local posAlt = BASES_HIGH_ALT[plotIndex]
        local dStd = (hrp.Position - posStd).Magnitude
        local dAlt = (hrp.Position - posAlt).Magnitude
        isAlt = dAlt < dStd
        targetBasePos = isAlt and posAlt or posStd
    else
        local posLow = BASES_LOW[plotIndex]
        local posLowAlt = BASES_LOW_ALT[plotIndex]
        local dLow    = (hrp.Position - posLow).Magnitude
        local dLowAlt = (hrp.Position - posLowAlt).Magnitude
        isAlt = dLowAlt < dLow
        targetBasePos = isAlt and posLowAlt or posLow
    end

    -- ── LEFA: Direcao e rotacao (Z-fixo) ─────────────────────────────────
    local targetPodium = getTargetPodiumAndSafePosition(targetPetData, targetBasePos)
    local claimPart    = findClaimModel(targetPodium)

    local directionToPet = targetBasePos - hrp.Position
    if directionToPet.Magnitude > 0 then
        directionToPet = Vector3.new(directionToPet.X, 0, directionToPet.Z).Unit
    else
        directionToPet = Vector3.new(0, 0, -1)
    end

    local dirBehind
    if claimPart then
        local df = claimPart.Position - targetBasePos
        if df.Magnitude > 0 then
            dirBehind = -Vector3.new(df.X, 0, df.Z).Unit
        else
            dirBehind = -directionToPet
        end
    else
        dirBehind = -directionToPet
    end

    -- LEFA: Simplifica para Z-only
    dirBehind = Vector3.new(0, 0, dirBehind.Z >= 0 and 1 or -1)
    local faceDir   = -dirBehind
    local facingRot = CFrame.lookAt(Vector3.zero, faceDir)

    -- ── LEFA: behindPos diferente por andar ──────────────────────────────
    -- 1o andar: dirBehind * 4
    -- 2o andar: dirBehind * 3 + faceDir * 1.8
    local behindPos
    if isSecondFloor then
        behindPos = targetBasePos + (dirBehind * 3) + (faceDir * 1.8)
    else
        behindPos = targetBasePos + (dirBehind * 4)
    end
    local rpPre = RaycastParams.new()
    rpPre.FilterDescendantsInstances = {char}
    rpPre.FilterType = Enum.RaycastFilterType.Exclude
    local resPre = Workspace:Raycast(
        Vector3.new(behindPos.X, targetBasePos.Y + 10, behindPos.Z),
        Vector3.new(0, -1000, 0),
        rpPre
    )
    if not resPre then State.isTpMoving = false; return end
    local finalHeight = resPre.Position.Y + 5.5
    local finalPos    = Vector3.new(behindPos.X, finalHeight, behindPos.Z)

    hrp.CFrame = CFrame.new(hrp.Position) * facingRot

    -- ── TITANZ: Sequencia de TP (carpet → jump → Y=35 → intermediario → final)
    if hrp.Position.Y > 25 and targetBasePos.Y > 25 then
        -- Ja em altitude alta: TP direto
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(finalPos) * facingRot
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    else
        -- 1) Equipa carpet
        if carpet then hum:EquipTool(carpet) end
        if not char.Parent or not hrp.Parent then State.isTpMoving = false; return end

        -- Reaplicar facing apos equip
        hrp.CFrame = CFrame.new(hrp.Position) * facingRot

        -- 2) Impulso (ChangeState Jumping)
        if hum and hum.Parent then hum:ChangeState(Enum.HumanoidStateType.Jumping) end

        -- 3) TP para Y=35 (intermediario alto)
        task.wait(0.01)
        if not char.Parent or not hrp.Parent then State.isTpMoving = false; return end
        hrp.CFrame = CFrame.new(hrp.Position.X, 35, hrp.Position.Z) * facingRot

        -- 4) Aguarda
        task.wait(0.10)
        if not char.Parent or not hrp.Parent then State.isTpMoving = false; return end

        -- 5) TP intermediario (X do carpet, Y atual, Z atras do pet)
        local positionBehindPet = targetBasePos + (dirBehind * 30)
        local carpetPart = findFlyingCarpet()
        if not carpetPart then State.isTpMoving = false; return end

        if not char.Parent or not hrp.Parent then State.isTpMoving = false; return end
        local carpetPosAtHeight = Vector3.new(carpetPart.Position.X, hrp.Position.Y, positionBehindPet.Z)
        hrp.CFrame = CFrame.new(carpetPosAtHeight) * facingRot

        -- 6) Aguarda
        task.wait(0.20)

        -- 7) TP final
        if not char.Parent or not hrp.Parent then State.isTpMoving = false; return end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(finalPos) * facingRot
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end

    -- ── LEFA: Pos-TP (posicionamento + clone por tipo de base) ───────────

    if isSecondFloor then
        -- 2o andar: TP para base lateral + clone
        for i = 1, 10 do
            hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
            if (hrp.Position - targetBasePos).Magnitude > 3 then
                hrp.CFrame = CFrame.new(targetBasePos, targetBasePos + faceDir)
                task.wait(0.05)
            end
        end
        task.wait(0.05)
        do
            local newPos = hrp.Position + faceDir * 1
            hrp.CFrame = CFrame.new(newPos, newPos + faceDir)
        end
        task.wait(0.06)
        -- Aguarda estabilizacao da posicao no servidor antes de clonar
        task.wait(0.15)
        hum.AutoRotate = false
        instantClone()
        while _G.isCloning do task.wait() end
        hum.AutoRotate = true
    else
        local baseOpen = _G._isTargetPlotUnlocked(targetPetData.plot)
        if baseOpen then
            -- Base aberta: TP para area dos lasers (centro da base)
            local bestSpot = CLONE_POSITIONS_FLOOR[1]
            local minDst = math.huge
            for _, v in ipairs(CLONE_POSITIONS_FLOOR) do
                local d = (targetPart.Position - v).Magnitude
                if d < minDst then minDst = d; bestSpot = v end
            end
            for i = 1, 4 do
                if (hrp.Position - bestSpot).Magnitude > 3 then
                    hrp.CFrame = CFrame.new(bestSpot)
                    task.wait(0.03)
                end
            end
            -- Virar para o FACE_TARGET mais proximo
            local bestFace = FACE_TARGETS[1]
            local minFaceDist = math.huge
            for _, v in ipairs(FACE_TARGETS) do
                local d = (hrp.Position - v).Magnitude
                if d < minFaceDist then minFaceDist = d; bestFace = v end
            end
            hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(bestFace.X, hrp.Position.Y, bestFace.Z))
            task.wait(0.01)
            -- Aguarda estabilizacao da posicao no servidor
            task.wait(0.15)
            -- Movimentacao antes do instantClone (walkForward)
            walkForward(0.10)
            task.wait(0.10)
        else
            -- Base fechada: TP para base lateral + clone
            for i = 1, 10 do
                hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
                if (hrp.Position - targetBasePos).Magnitude > 3 then
                    hrp.CFrame = CFrame.new(targetBasePos, targetBasePos + faceDir)
                    task.wait(0.05)
                end
            end
            task.wait(0.05)
            do
                local newPos = hrp.Position + faceDir * 1
                hrp.CFrame = CFrame.new(newPos, newPos + faceDir)
            end
            task.wait(0.02)
            -- Aguarda estabilizacao da posicao no servidor
            task.wait(0.15)
            instantClone()
            while _G.isCloning do task.wait() end
        end
    end
    task.wait(0.04)

    if carpet then hum:EquipTool(carpet) end

    -- ── LEFA: Posicionamento final no pet ────────────────────────────────
    local verticalDiff = targetPart.Position.Y - hrp.Position.Y

    if verticalDiff > 2 then
        local airPos = Vector3.new(targetPart.Position.X, targetPart.Position.Y - 5, targetPart.Position.Z)
        local plat = Instance.new("Part")
        plat.Name = "BullysTempPlatform"; plat.Size = Vector3.new(3, 1, 3)
        plat.Position = airPos - Vector3.new(0, 5, 0)
        plat.Color = Color3.new(1, 0, 0); plat.Material = Enum.Material.Neon
        plat.Anchored = true; plat.CanCollide = true; plat.Transparency = 0.3
        plat.Parent = Workspace
        RunService.Heartbeat:Wait()
        for i = 1, 10 do
            if not LocalPlayer:GetAttribute("Stealing") then
                hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
                hrp.CFrame = CFrame.new(airPos, airPos + faceDir)
                task.wait(0.05)
            end
        end
        task.spawn(function()
            local start = tick()
            while tick() - start < 20 do
                if LocalPlayer:GetAttribute("Stealing") then break end
                task.wait(0.1)
            end
            if plat and plat.Parent then plat:Destroy() end
        end)
    else
        for i = 1, 10 do
            if LocalPlayer:GetAttribute("Stealing") then break end
            hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
            if (hrp.Position - targetPart.Position).Magnitude > 3 then
                hrp.CFrame = CFrame.new(targetPart.Position, targetPart.Position + faceDir)
                task.wait(0.05)
            end
            task.wait(0.05)
        end
    end

    State.isTpMoving = false
end
local allAnimalsCache = {}
local lastAnimalData  = {}

task.spawn(function()
    local Packages    = ReplicatedStorage:WaitForChild("Packages")
    local Datas       = ReplicatedStorage:WaitForChild("Datas")
    local Shared      = ReplicatedStorage:WaitForChild("Shared")
    local Utils       = ReplicatedStorage:WaitForChild("Utils")
    local Synchronizer  = require(Packages:WaitForChild("Synchronizer"))
    local AnimalsData   = require(Datas:WaitForChild("Animals"))
    local AnimalsShared = require(Shared:WaitForChild("Animals"))
    local NumberUtils   = require(Utils:WaitForChild("NumberUtils"))

    do
        local ALLOWED_RARITIES = {Secret = true, OG = true, Og = true}
        local tempList = {}
        local seen = {}
        for petName, data in pairs(AnimalsData) do
            local rarity = data.Rarity or ""
            if ALLOWED_RARITIES[rarity] and not petName:find("Lucky Block") then
                local displayName = data.DisplayName or petName
                if not seen[displayName:lower()] then
                    seen[displayName:lower()] = true
                    table.insert(tempList, displayName)
                end
            end
        end
        table.sort(tempList)
        _allBrainrots = tempList
    end

    local function isMyBaseAnimal(animalData)
        if not animalData or not animalData.plot then return false end
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return false end
        local plot = plots:FindFirstChild(animalData.plot)
        if not plot then return false end
        local ok, ch = pcall(function() return Synchronizer:Get(plot.Name) end)
        if not (ok and ch) then return false end
        local owner = ch:Get("Owner")
        if not owner then return false end
        if typeof(owner)=="Instance" and owner:IsA("Player") then return owner.UserId==LocalPlayer.UserId end
        if typeof(owner)=="table" and owner.UserId then return owner.UserId==LocalPlayer.UserId end
        return false
    end

    local function getAnimalHash(al)
        if not al then return "" end
        local h = ""
        for slot, d in pairs(al) do
            if type(d)=="table" then h=h..tostring(slot)..tostring(d.Index)..tostring(d.Mutation) end
        end
        return h
    end

    local function scanSinglePlot(plot)
        pcall(function()
            local ok, ch = pcall(function() return Synchronizer:Get(plot.Name) end)
            if not (ok and ch) then return end
            local al   = ch:Get("AnimalList")
            local hash = getAnimalHash(al)
            if lastAnimalData[plot.Name]==hash then return end
            lastAnimalData[plot.Name] = hash
            for i=#allAnimalsCache,1,-1 do
                if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end
            end
            local owner = ch:Get("Owner")
            if not owner or not Players:FindFirstChild(owner.Name) then return end
            local ownerName = owner.Name or "Unknown"
            if not al then return end
            for slot, ad in pairs(al) do
                if type(ad)=="table" then
                    local aName, aInfo = ad.Index, AnimalsData[ad.Index]
                    if aInfo then
                        local mut = ad.Mutation or "None"
                        if mut=="Yin Yang" then mut="YinYang" end
                        local gv = AnimalsShared:GetGeneration(aName, ad.Mutation, ad.Traits, nil)
                        local gt = "$"..NumberUtils:ToString(gv).."/s"
                        table.insert(allAnimalsCache, {
                            name=aInfo.DisplayName or aName, genText=gt, genValue=gv,
                            mutation=mut, owner=ownerName,
                            plot=plot.Name, slot=tostring(slot),
                            uid=plot.Name.."_"..tostring(slot)
                        })
                    end
                end
            end
            table.sort(allAnimalsCache, function(a,b) return a.genValue>b.genValue end)
        end)
    end

    local function setupPlotListener(plot)
        local ch, retries = nil, 0
        while not ch and retries<50 do
            local ok, r = pcall(function() return Synchronizer:Get(plot.Name) end)
            if ok and r then ch=r; break else retries=retries+1; task.wait(0.1) end
        end
        if not ch then return end
        scanSinglePlot(plot)
        plot.DescendantAdded:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
        plot.DescendantRemoving:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
        task.spawn(function() while plot.Parent do task.wait(5); scanSinglePlot(plot) end end)
    end

    local plots = Workspace:WaitForChild("Plots", 8)
    if plots then
        for _, p in ipairs(plots:GetChildren()) do setupPlotListener(p) end
        plots.ChildAdded:Connect(function(p) task.wait(0.5); setupPlotListener(p) end)
        plots.ChildRemoved:Connect(function(p)
            lastAnimalData[p.Name] = nil
            for i=#allAnimalsCache,1,-1 do
                if allAnimalsCache[i].plot==p.Name then table.remove(allAnimalsCache,i) end
            end
        end)
    end

    while true do
        SharedState.AllAnimalsCache = allAnimalsCache
        task.wait(0.5)
    end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────
local function parseMinGen(str)
    if not str or type(str)~="string" then return 0 end
    str = str:gsub("%s",""):lower()
    if str=="" then return 0 end
    local num, suffix = str:match("^([%d%.]+)([kmb]?)$")
    if not num then return 0 end
    num = tonumber(num); if not num or num<0 then return 0 end
    if suffix=="k" then return num*1e3
    elseif suffix=="m" then return num*1e6
    elseif suffix=="b" then return num*1e9
    end
    return num
end

-- ── Auto TP: dispara UMA VEZ ao entrar no jogo ────────────────────────────
task.spawn(function()
    if not Config.AutoTP then return end

    local timeout = tick() + 60
    while (not SharedState.AllAnimalsCache or #SharedState.AllAnimalsCache == 0) and tick() < timeout do
        task.wait(0.05)
    end
    if not SharedState.AllAnimalsCache or #SharedState.AllAnimalsCache == 0 then return end

    local minGen = parseMinGen(tostring(Config.MinGenForTp))
    if minGen > 0 then
        local topGen = 0
        for _, a in ipairs(SharedState.AllAnimalsCache) do
            if a.owner ~= LocalPlayer.Name then
                topGen = math.max(topGen, a.genValue or 0)
            end
        end
        if topGen < minGen then return end
    end

    if (Config.TpDelay or 0) > 0 then
        task.wait(Config.TpDelay)
    end

    if Config.TpAfterFPS then
        local threshold = Config.FPSThreshold or 200
        local fpstimeout = tick() + 30
        while CurrentFPS < threshold and tick() < fpstimeout do
            task.wait(0.1)
        end
        if CurrentFPS < threshold then return end
        task.wait(Config.FPSWait or 0)
    end

    runAutoSnipe()
end)

-- ── Key bindings ──────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if UserInputService:GetFocusedTextBox() then return end

    if input.KeyCode == (Enum.KeyCode[Config.TpKey] or Enum.KeyCode.T) then
        runAutoSnipe()
    end

    if input.KeyCode == (Enum.KeyCode[Config.CloneKey] or Enum.KeyCode.V) then
        instantClone()
    end
end)

-- ── Cores da Interface (estilo lefa) ──────────────────────────────────────
local ACCENT   = Color3.fromRGB(210, 80, 120)
local ACCENT2  = Color3.fromRGB(255, 200, 218)
local BG       = Color3.fromRGB(248, 155, 178)
local BG2      = Color3.fromRGB(235, 130, 158)
local ROW_BG   = Color3.fromRGB(252, 175, 195)
local TEXT_W   = Color3.fromRGB(90, 20, 45)
local TEXT_D   = Color3.fromRGB(130, 50, 75)
local ON_COLOR = Color3.fromRGB(210, 80, 120)
local OFF_COL  = Color3.fromRGB(255, 200, 218)
local SUCCESS  = Color3.fromRGB(180, 60, 100)
local ERR      = Color3.fromRGB(185, 50, 85)

-- ── Priority List GUI ─────────────────────────────────────────────────────
local _priorityGui = nil

local PR = {
    bg      = Color3.fromRGB(248, 155, 178),
    bg2     = Color3.fromRGB(238, 135, 162),
    row     = Color3.fromRGB(242, 145, 170),
    rowSel  = Color3.fromRGB(255, 185, 205),
    line    = Color3.fromRGB(215, 105, 140),
    text    = Color3.fromRGB(90, 20, 45),
    dim     = Color3.fromRGB(160, 70, 100),
    accent  = Color3.fromRGB(200, 60, 100),
}
local PR_PAD    = 12
local PR_BTN_H  = 32
local PR_BORDER = 3
local PR_CORNER = 5

local PinkRainbow = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 130, 170)),
    ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 180, 210)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 100, 150)),
    ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 160, 195)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 130, 170)),
})

local function prHover(btn, base, hover)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = hover}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = base}):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.05), {BackgroundTransparency = 0.2}):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundTransparency = 0}):Play()
    end)
end

local function getBrainrotViewportClone(petName)
    if not petName or petName == "" then return nil end
    local modelsFolder = ReplicatedStorage:FindFirstChild("Models")
    if not modelsFolder then return nil end
    local animalsFolder = modelsFolder:FindFirstChild("Animals")
    if not animalsFolder then return nil end
    local srcModel = animalsFolder:FindFirstChild(petName)
    if not srcModel then return nil end

    local newVp = Instance.new("ViewportFrame")
    newVp.BackgroundTransparency = 1
    newVp.BorderSizePixel = 0
    newVp.ImageColor3 = Color3.fromRGB(255, 255, 255)
    newVp.Visible = true

    local worldModel = Instance.new("WorldModel", newVp)
    worldModel.Name = "BrainrotWorldModel"

    local clonedModel = srcModel:Clone()
    clonedModel.Parent = worldModel

    local animsRoot      = ReplicatedStorage:FindFirstChild("Animations")
    local animalsAnims   = animsRoot and animsRoot:FindFirstChild("Animals")
    local thisAnimFolder = animalsAnims and animalsAnims:FindFirstChild(petName)
    local idleAnim       = thisAnimFolder and thisAnimFolder:FindFirstChild("Idle")
    if idleAnim and idleAnim:IsA("Animation") then
        local animator
        for _, d in ipairs(clonedModel:GetDescendants()) do
            if d:IsA("Animator") then animator = d; break end
        end
        if not animator then
            local ac = Instance.new("AnimationController", clonedModel)
            ac.Name = "BrainrotAC"
            animator = Instance.new("Animator", ac)
        end
        if animator then
            local track = animator:LoadAnimation(idleAnim)
            if track then
                track.Looped = false
                local goingForward = true
                local function playDir()
                    if goingForward then track.TimePosition = 0; track:AdjustSpeed(1)
                    else track.TimePosition = track.Length; track:AdjustSpeed(-1) end
                    track:Play()
                end
                track.Stopped:Connect(function() goingForward = not goingForward; playDir() end)
                playDir()
            end
        end
    end

    local cam = Instance.new("Camera", newVp)
    cam.Name = "BrainrotCamera"
    local cf, size = clonedModel:GetBoundingBox()
    clonedModel:PivotTo(cf * CFrame.Angles(0, math.rad(180), 0))
    cf = clonedModel:GetPivot()
    local maxSize = math.max(size.X, size.Y, size.Z)
    local dist    = math.max(maxSize * 0.8, 1.5)
    local camPos  = cf.Position + (cf.LookVector*(dist*1.2)) + (cf.RightVector*(dist*0.5)) + (cf.UpVector*(dist*0.4))
    cam.CFrame    = CFrame.new(camPos, cf.Position + cf.UpVector*(maxSize*0.2))
    newVp.CurrentCamera = cam
    return newVp
end

local function createPriorityGUI()
    if _priorityGui and _priorityGui.Parent then
        _priorityGui:Destroy()
        _priorityGui = nil
        return
    end

    local popW, popH = 400, 580
    local borderOuterW = popW + PR_BORDER * 2
    local borderOuterH = popH + PR_BORDER * 2

    _priorityGui = Instance.new("ScreenGui")
    _priorityGui.Name = "LefaPriorityGUI"
    _priorityGui.ResetOnSpawn = false
    _priorityGui.DisplayOrder = 100
    _priorityGui.Parent = PlayerGui

    local borderFrame = Instance.new("Frame", _priorityGui)
    borderFrame.Size = UDim2.new(0, borderOuterW, 0, borderOuterH)
    borderFrame.Position = UDim2.new(0.5, -borderOuterW/2, 0.5, -borderOuterH/2)
    borderFrame.BackgroundColor3 = Color3.fromRGB(255, 200, 220)
    borderFrame.BorderSizePixel = 0
    Instance.new("UICorner", borderFrame).CornerRadius = UDim.new(0, PR_CORNER + 2)
    local borderGrad = Instance.new("UIGradient", borderFrame)
    borderGrad.Color = PinkRainbow
    borderGrad.Rotation = 0

    local inner = Instance.new("Frame", borderFrame)
    inner.Name = "Inner"
    inner.Size = UDim2.new(1, -PR_BORDER*2, 1, -PR_BORDER*2)
    inner.Position = UDim2.new(0, PR_BORDER, 0, PR_BORDER)
    inner.BackgroundColor3 = PR.bg
    inner.BorderSizePixel = 0
    Instance.new("UICorner", inner).CornerRadius = UDim.new(0, PR_CORNER)
    local innerStroke = Instance.new("UIStroke", inner)
    innerStroke.Thickness = 1.2
    innerStroke.Color = PR.line

    local headerH = 44
    local popTitle = Instance.new("TextLabel", inner)
    popTitle.Size = UDim2.new(1, 0, 0, headerH)
    popTitle.BackgroundTransparency = 1
    popTitle.Text = "Priority List Editor"
    popTitle.Font = Enum.Font.GothamBold
    popTitle.TextSize = 18
    popTitle.TextColor3 = PR.text
    popTitle.TextXAlignment = Enum.TextXAlignment.Center

    local allNamesSet = {}
    local allNames    = {}
    for _, name in ipairs(_allBrainrots) do
        if not allNamesSet[name] then
            allNamesSet[name] = true
            table.insert(allNames, name)
        end
    end
    for _, name in ipairs(PRIORITY_LIST) do
        if not allNamesSet[name] then
            allNamesSet[name] = true
            table.insert(allNames, name)
        end
    end
    table.sort(allNames, function(a, b) return a:lower() < b:lower() end)

    local priorityList = {}
    for _, n in ipairs(PRIORITY_LIST) do table.insert(priorityList, n) end
    local prioritySet = {}
    for _, n in ipairs(priorityList) do prioritySet[n] = true end

    local BR_TAB_H = 36
    local scrollTop = headerH + BR_TAB_H + PR_PAD * 2
    local closeH    = PR_BTN_H + 10
    local scrollH   = popH - scrollTop - closeH - PR_PAD

    local tabs = Instance.new("Frame", inner)
    tabs.Size = UDim2.new(1, -PR_PAD*2, 0, BR_TAB_H)
    tabs.Position = UDim2.new(0, PR_PAD, 0, headerH + 4)
    tabs.BackgroundTransparency = 1

    local tabPrioBtn = Instance.new("TextButton", tabs)
    tabPrioBtn.Size = UDim2.new(0.5, -4, 1, 0)
    tabPrioBtn.BackgroundColor3 = PR.rowSel
    tabPrioBtn.Text = "Priority List"
    tabPrioBtn.Font = Enum.Font.GothamBold
    tabPrioBtn.TextSize = 14
    tabPrioBtn.TextColor3 = PR.text
    tabPrioBtn.AutoButtonColor = false
    tabPrioBtn.BorderSizePixel = 0
    Instance.new("UICorner", tabPrioBtn).CornerRadius = UDim.new(0, PR_CORNER)
    local prioStroke = Instance.new("UIStroke", tabPrioBtn)
    prioStroke.Color = PR.line; prioStroke.Thickness = 1

    local tabAllBtn = Instance.new("TextButton", tabs)
    tabAllBtn.Size = UDim2.new(0.5, -4, 1, 0)
    tabAllBtn.Position = UDim2.new(0.5, 4, 0, 0)
    tabAllBtn.BackgroundColor3 = PR.row
    tabAllBtn.Text = "All Brainrots"
    tabAllBtn.Font = Enum.Font.GothamBold
    tabAllBtn.TextSize = 14
    tabAllBtn.TextColor3 = PR.dim
    tabAllBtn.AutoButtonColor = false
    tabAllBtn.BorderSizePixel = 0
    Instance.new("UICorner", tabAllBtn).CornerRadius = UDim.new(0, PR_CORNER)
    local allStroke = Instance.new("UIStroke", tabAllBtn)
    allStroke.Color = PR.line; allStroke.Thickness = 1

    local function makeScroll(parent, visible)
        local s = Instance.new("ScrollingFrame", parent)
        s.Size = UDim2.new(1, -PR_PAD*2, 0, scrollH)
        s.Position = UDim2.new(0, PR_PAD, 0, scrollTop)
        s.BackgroundColor3 = PR.bg2
        s.BorderSizePixel = 0
        s.ScrollBarThickness = 6
        s.ScrollBarImageColor3 = PR.accent
        s.CanvasSize = UDim2.new(0, 0, 0, 0)
        s.AutomaticCanvasSize = Enum.AutomaticSize.Y
        s.ClipsDescendants = true
        s.Visible = visible
        Instance.new("UICorner", s).CornerRadius = UDim.new(0, PR_CORNER)
        local st = Instance.new("UIStroke", s)
        st.Color = PR.line; st.Thickness = 1
        local layout = Instance.new("UIListLayout", s)
        layout.Padding = UDim.new(0, 4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.VerticalAlignment = Enum.VerticalAlignment.Top
        local pad = Instance.new("UIPadding", s)
        pad.PaddingTop = UDim.new(0, 4)
        pad.PaddingLeft = UDim.new(0, 4)
        pad.PaddingRight = UDim.new(0, 4)
        return s
    end

    local priorityScroll = makeScroll(inner, true)
    local leftScroll     = makeScroll(inner, false)

    local closeBtn = Instance.new("TextButton", inner)
    closeBtn.Size = UDim2.new(1, -PR_PAD*2, 0, PR_BTN_H)
    closeBtn.Position = UDim2.new(0, PR_PAD, 1, -PR_PAD - PR_BTN_H)
    closeBtn.BackgroundColor3 = PR.row
    closeBtn.Text = "Close"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = PR.text
    closeBtn.BorderSizePixel = 0
    closeBtn.AutoButtonColor = false
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, PR_CORNER)
    Instance.new("UIStroke", closeBtn).Color = PR.line
    prHover(closeBtn, PR.row, PR.rowSel)

    local function savePriority()
        PRIORITY_LIST = priorityList
        local copy = {}
        for _, n in ipairs(priorityList) do table.insert(copy, n) end
        Config.PriorityList = copy
        SaveConfig()
    end

    local refreshAllList, refreshPriorityList

    local function removeFromPriority(name)
        for i = #priorityList, 1, -1 do
            if priorityList[i] == name then table.remove(priorityList, i) end
        end
        prioritySet[name] = nil
        savePriority()
        refreshPriorityList()
        refreshAllList()
    end

    local function addToPriority(name)
        if prioritySet[name] then return end
        table.insert(priorityList, name)
        prioritySet[name] = true
        savePriority()
        refreshPriorityList()
        refreshAllList()
    end

    local function makeVpIcon(parent, name, posX)
        local iconSz = 44
        local vp = getBrainrotViewportClone(name)
        if vp then
            vp.Name = "BrainrotIcon"
            vp.BackgroundTransparency = 0.4
            vp.BackgroundColor3 = PR.bg2
            Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 4)
            vp.AnchorPoint = Vector2.new(0, 0)
            vp.Position = UDim2.new(0, posX, 0.5, 0)
            vp.Size = UDim2.new(0, iconSz, 0, iconSz)
            vp.Parent = parent
        end
        return vp and iconSz or 0
    end

    refreshAllList = function()
        for _, c in ipairs(leftScroll:GetChildren()) do
            if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
        end
        for _, name in ipairs(allNames) do
            local row = Instance.new("Frame", leftScroll)
            row.Size = UDim2.new(1, -8, 0, 52)
            row.BackgroundColor3 = PR.row
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            Instance.new("UIStroke", row).Color = PR.line

            local iconW = makeVpIcon(row, name, 4)
            local lblOff = (iconW > 0 and iconW + 12 or 12)
            local lblW   = 44 + (iconW > 0 and iconW + 8 or 8)

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -lblW, 1, 0)
            lbl.Position = UDim2.new(0, lblOff, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = name
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.TextColor3 = prioritySet[name] and PR.dim or PR.text

            local btn = Instance.new("TextButton", row)
            btn.Size = UDim2.new(0, 40, 0, 40)
            btn.Position = UDim2.new(1, -44, 0, 6)
            btn.BackgroundColor3 = PR.rowSel
            btn.Text = prioritySet[name] and "-" or "+"
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 16
            btn.TextColor3 = prioritySet[name] and Color3.fromRGB(200, 60, 90) or PR.accent
            btn.BorderSizePixel = 0
            btn.AutoButtonColor = false
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            prHover(btn, PR.rowSel, PR.bg2)

            btn.MouseButton1Click:Connect(function()
                if prioritySet[name] then removeFromPriority(name)
                else addToPriority(name) end
            end)
        end
    end

    refreshPriorityList = function()
        for _, c in ipairs(priorityScroll:GetChildren()) do
            if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
        end
        for i, name in ipairs(priorityList) do
            local row = Instance.new("Frame", priorityScroll)
            row.Size = UDim2.new(1, -8, 0, 52)
            row.BackgroundColor3 = PR.row
            row.BorderSizePixel = 0
            row.LayoutOrder = i
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            Instance.new("UIStroke", row).Color = PR.line

            local idxLbl = Instance.new("TextLabel", row)
            idxLbl.Size = UDim2.new(0, 24, 1, 0)
            idxLbl.Position = UDim2.new(0, 4, 0, 0)
            idxLbl.BackgroundTransparency = 1
            idxLbl.Text = tostring(i)
            idxLbl.Font = Enum.Font.GothamBold
            idxLbl.TextSize = 13
            idxLbl.TextColor3 = PR.dim
            idxLbl.TextXAlignment = Enum.TextXAlignment.Center

            local iconW = makeVpIcon(row, name, 28)
            local lblOff = (iconW > 0 and (28 + iconW + 4) or 28)
            local lblW   = 114 + (iconW > 0 and iconW + 4 or 0)

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -lblW, 1, 0)
            lbl.Position = UDim2.new(0, lblOff, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = name
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.TextColor3 = PR.text

            local upBtn = Instance.new("TextButton", row)
            upBtn.Size = UDim2.new(0, 32, 0, 40)
            upBtn.Position = UDim2.new(1, -114, 0, 6)
            upBtn.BackgroundColor3 = PR.rowSel
            upBtn.Text = "↑"
            upBtn.Font = Enum.Font.GothamBold
            upBtn.TextSize = 14
            upBtn.TextColor3 = PR.accent
            upBtn.BorderSizePixel = 0
            upBtn.AutoButtonColor = false
            Instance.new("UICorner", upBtn).CornerRadius = UDim.new(0, 4)
            prHover(upBtn, PR.rowSel, PR.bg2)

            local downBtn = Instance.new("TextButton", row)
            downBtn.Size = UDim2.new(0, 32, 0, 40)
            downBtn.Position = UDim2.new(1, -76, 0, 6)
            downBtn.BackgroundColor3 = PR.rowSel
            downBtn.Text = "↓"
            downBtn.Font = Enum.Font.GothamBold
            downBtn.TextSize = 14
            downBtn.TextColor3 = PR.accent
            downBtn.BorderSizePixel = 0
            downBtn.AutoButtonColor = false
            Instance.new("UICorner", downBtn).CornerRadius = UDim.new(0, 4)
            prHover(downBtn, PR.rowSel, PR.bg2)

            local remBtn = Instance.new("TextButton", row)
            remBtn.Size = UDim2.new(0, 32, 0, 40)
            remBtn.Position = UDim2.new(1, -38, 0, 6)
            remBtn.BackgroundColor3 = PR.rowSel
            remBtn.Text = "X"
            remBtn.Font = Enum.Font.GothamBold
            remBtn.TextSize = 12
            remBtn.TextColor3 = Color3.fromRGB(200, 60, 90)
            remBtn.BorderSizePixel = 0
            remBtn.AutoButtonColor = false
            Instance.new("UICorner", remBtn).CornerRadius = UDim.new(0, 4)
            prHover(remBtn, PR.rowSel, PR.bg2)

            upBtn.MouseButton1Click:Connect(function()
                if i <= 1 then return end
                priorityList[i], priorityList[i-1] = priorityList[i-1], priorityList[i]
                savePriority(); refreshPriorityList()
            end)
            downBtn.MouseButton1Click:Connect(function()
                if i >= #priorityList then return end
                priorityList[i], priorityList[i+1] = priorityList[i+1], priorityList[i]
                savePriority(); refreshPriorityList()
            end)
            remBtn.MouseButton1Click:Connect(function()
                removeFromPriority(name)
            end)
        end
    end

    tabPrioBtn.MouseButton1Click:Connect(function()
        tabPrioBtn.BackgroundColor3 = PR.rowSel; tabPrioBtn.TextColor3 = PR.text
        tabAllBtn.BackgroundColor3 = PR.row;     tabAllBtn.TextColor3 = PR.dim
        priorityScroll.Visible = true; leftScroll.Visible = false
    end)
    tabAllBtn.MouseButton1Click:Connect(function()
        tabAllBtn.BackgroundColor3 = PR.rowSel; tabAllBtn.TextColor3 = PR.text
        tabPrioBtn.BackgroundColor3 = PR.row;   tabPrioBtn.TextColor3 = PR.dim
        leftScroll.Visible = true; priorityScroll.Visible = false
    end)

    closeBtn.MouseButton1Click:Connect(function()
        _priorityGui:Destroy(); _priorityGui = nil
    end)

    refreshPriorityList()
    refreshAllList()

    task.spawn(function()
        local t = 0
        while borderGrad and borderGrad.Parent do
            t = (t + 0.5) % 360
            borderGrad.Rotation = t
            RunService.Heartbeat:Wait()
        end
    end)
end


-- ── UTILS GUI ─────────────────────────────────────────────────────────────
local GUI_W = 280

local sg = Instance.new("ScreenGui")
sg.Name = "XiUtils"; sg.ResetOnSpawn = false; sg.DisplayOrder = 10
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; sg.Parent = PlayerGui

local frame = Instance.new("Frame", sg)
frame.Size = UDim2.new(0, GUI_W, 0, 10)
do
    local savedX = Config.GuiPosX
    local savedY = Config.GuiPosY
    if savedX and savedY then
        frame.Position = UDim2.new(0, savedX, 0, savedY)
    else
        frame.Position = UDim2.new(0.5, -GUI_W/2, 0.5, -200)
    end
end
frame.BackgroundColor3 = Color3.fromRGB(248, 155, 178)
frame.BorderSizePixel = 0
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 5)
local mainStroke = Instance.new("UIStroke", frame)
mainStroke.Color = Color3.fromRGB(215, 105, 140)
mainStroke.Thickness = 1

local _sliderDragging = false
do
    local drag, dragStart, startPos
    frame.InputBegan:Connect(function(i)
        if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and not _sliderDragging then
            drag = true; dragStart = i.Position; startPos = frame.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    drag = false
                    Config.GuiPosX = frame.AbsolutePosition.X
                    Config.GuiPosY = frame.AbsolutePosition.Y
                    SaveConfig()
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local mainLayout = Instance.new("UIListLayout", frame)
mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainLayout.Padding = UDim.new(0, 0)

local mainPad = Instance.new("UIPadding", frame)
mainPad.PaddingBottom = UDim.new(0, 10)

local rowOrder = 0
local function nextOrder() rowOrder = rowOrder + 1; return rowOrder end

local header = Instance.new("Frame", frame)
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Color3.fromRGB(225, 110, 145)
header.BorderSizePixel = 0
header.LayoutOrder = nextOrder()
local headerCorner = Instance.new("UICorner", header)
headerCorner.CornerRadius = UDim.new(0, 5)
local headerFix = Instance.new("Frame", header)
headerFix.Size = UDim2.new(1, 0, 0.5, 0)
headerFix.Position = UDim2.new(0, 0, 0.5, 0)
headerFix.BackgroundColor3 = Color3.fromRGB(225, 110, 145)
headerFix.BorderSizePixel = 0

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size = UDim2.new(1, 0, 1, 0)
titleLbl.Position = UDim2.new(0, 0, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "discord.gg/lefahub"
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 16
titleLbl.TextColor3 = Color3.fromRGB(255, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Center
titleLbl.ZIndex = 1

-- ── Minimize button ───────────────────────────────────────────────────────
local minimizeBtn = Instance.new("TextButton", header)
minimizeBtn.Size = UDim2.new(0, 28, 0, 28)
minimizeBtn.Position = UDim2.new(1, -36, 0.5, -14)
minimizeBtn.BackgroundTransparency = 1
minimizeBtn.Text = Config.Minimized and "+" or "-"
minimizeBtn.Font = Enum.Font.GothamBlack
minimizeBtn.TextSize = 20
minimizeBtn.TextColor3 = Color3.fromRGB(255, 230, 240)
minimizeBtn.AutoButtonColor = false
minimizeBtn.BorderSizePixel = 0
minimizeBtn.ZIndex = 2

local _guiMinimized = Config.Minimized or false
local _guiRows = {} -- preenchido depois que as rows forem criadas

local function applyMinimizedState(minimized)
    minimizeBtn.Text = minimized and "+" or "-"
    mainPad.PaddingBottom = minimized and UDim.new(0, 0) or UDim.new(0, 10)
    for _, row in ipairs(_guiRows) do
        row.Visible = not minimized
    end
    frame.Size = UDim2.new(0, GUI_W, 0, mainLayout.AbsoluteContentSize.Y + (minimized and 0 or 10))
end

minimizeBtn.MouseButton1Click:Connect(function()
    _guiMinimized = not _guiMinimized
    Config.Minimized = _guiMinimized
    SaveConfig()
    applyMinimizedState(_guiMinimized)
end)

local function makeSep()
    local sep = Instance.new("Frame", frame)
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.BackgroundTransparency = 1
    sep.BorderSizePixel = 0
    sep.LayoutOrder = nextOrder()
    table.insert(_guiRows, sep)
    local inner = Instance.new("Frame", sep)
    inner.Size = UDim2.new(1, -20, 1, 0)
    inner.Position = UDim2.new(0, 10, 0, 0)
    inner.BackgroundColor3 = Color3.fromRGB(225, 110, 145)
    inner.BorderSizePixel = 0
    return sep
end

local function makeRow(labelText)
    local r = Instance.new("Frame", frame)
    r.Size = UDim2.new(1, 0, 0, 38)
    r.BackgroundTransparency = 1
    r.BorderSizePixel = 0
    r.LayoutOrder = nextOrder()
    table.insert(_guiRows, r)

    local lbl = Instance.new("TextLabel", r)
    lbl.Size = UDim2.new(0.58, 0, 1, 0)
    lbl.Position = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = Color3.fromRGB(90, 20, 45)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    return r
end

local function makeToggle(parent, state, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0, 58, 0, 26)
    btn.Position = UDim2.new(1, -70, 0.5, -13)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

    local cur = state
    local function refresh()
        btn.BackgroundColor3 = cur and Color3.fromRGB(210, 80, 120) or Color3.fromRGB(255, 200, 218)
        btn.TextColor3 = cur and Color3.fromRGB(255, 230, 240) or Color3.fromRGB(180, 100, 130)
        btn.Text = cur and "ON" or "OFF"
    end
    refresh()
    btn.MouseButton1Click:Connect(function() cur = not cur; refresh(); callback(cur) end)
    return btn, refresh
end

local function makeValueBox(parent, value, callback)
    local box = Instance.new("TextBox", parent)
    box.Size = UDim2.new(0, 58, 0, 26)
    box.Position = UDim2.new(1, -70, 0.5, -13)
    box.BackgroundColor3 = Color3.fromRGB(235, 130, 158)
    box.Text = tostring(value or "")
    box.PlaceholderText = "0"
    box.Font = Enum.Font.GothamBold
    box.TextSize = 12
    box.TextColor3 = Color3.fromRGB(90, 20, 45)
    box.PlaceholderColor3 = Color3.fromRGB(200, 140, 160)
    box.ClearTextOnFocus = false
    box.BorderSizePixel = 0
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    box.FocusLost:Connect(function() callback(box.Text) end)
    return box
end

local function makeKeybindBtn(parent, key, callback)
    local listening = false
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0, 58, 0, 26)
    btn.Position = UDim2.new(1, -70, 0.5, -13)
    btn.BackgroundColor3 = Color3.fromRGB(235, 130, 158)
    btn.Text = key or "T"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = Color3.fromRGB(90, 20, 45)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    btn.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true; btn.Text = "..."
        local conn
        conn = UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.Keyboard then
                local name = inp.KeyCode.Name
                btn.Text = name; callback(name)
                conn:Disconnect(); listening = false
            end
        end)
        task.delay(5, function()
            if listening then
                listening = false; btn.Text = Config.TpKey or "T"; conn:Disconnect()
            end
        end)
    end)
    return btn
end

local function makeSliderRow(labelText, minV, maxV, curV, fmt, callback)
    local r = Instance.new("Frame", frame)
    r.Size = UDim2.new(1, 0, 0, 52)
    r.BackgroundTransparency = 1
    r.BorderSizePixel = 0
    r.LayoutOrder = nextOrder()
    table.insert(_guiRows, r)

    local lbl = Instance.new("TextLabel", r)
    lbl.Size = UDim2.new(0.55, 0, 0, 22)
    lbl.Position = UDim2.new(0, 14, 0, 5)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = Color3.fromRGB(90, 20, 45)
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local valLbl = Instance.new("TextLabel", r)
    valLbl.Size = UDim2.new(0.4, 0, 0, 22)
    valLbl.Position = UDim2.new(0.58, 0, 0, 5)
    valLbl.BackgroundTransparency = 1
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 13
    valLbl.TextColor3 = Color3.fromRGB(130, 50, 75)
    valLbl.TextXAlignment = Enum.TextXAlignment.Right

    local trackBg = Instance.new("Frame", r)
    trackBg.Size = UDim2.new(1, -28, 0, 4)
    trackBg.Position = UDim2.new(0, 14, 0, 36)
    trackBg.BackgroundColor3 = Color3.fromRGB(225, 110, 145)
    trackBg.BorderSizePixel = 0
    Instance.new("UICorner", trackBg).CornerRadius = UDim.new(0, 3)

    local fill = Instance.new("Frame", trackBg)
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(200, 70, 110)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

    local knob = Instance.new("Frame", trackBg)
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 220, 232)
    knob.BorderSizePixel = 0
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 3)

    local function update(v)
        v = math.clamp(v, minV, maxV)
        local t = (v - minV) / (maxV - minV)
        fill.Size = UDim2.new(t, 0, 1, 0)
        knob.Position = UDim2.new(t, 0, 0.5, 0)
        valLbl.Text = string.format(fmt, v)
        callback(v)
    end

    local dragging = false
    local function drag(px)
        local l = trackBg.AbsolutePosition.X
        local w = trackBg.AbsoluteSize.X
        update(minV + math.clamp((px - l) / w, 0, 1) * (maxV - minV))
    end

    trackBg.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; _sliderDragging = true; drag(i.Position.X)
        end
    end)
    knob.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; _sliderDragging = true
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false; _sliderDragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            drag(i.Position.X)
        end
    end)
    task.defer(function() update(curV) end)
    return r
end

-- ── Rows ────────────────────────────────────────────────────────────

-- Auto TP
do
    local r = makeRow("Auto TP:")
    makeToggle(r, Config.AutoTP, function(v) Config.AutoTP = v; SaveConfig() end)
    makeSep()
end

-- Edit Priority List
do
    local r = Instance.new("Frame", frame)
    r.Size = UDim2.new(1, 0, 0, 38)
    r.BackgroundTransparency = 1
    r.BorderSizePixel = 0
    r.LayoutOrder = nextOrder()
    table.insert(_guiRows, r)

    local btn = Instance.new("TextButton", r)
    btn.Size = UDim2.new(1, -20, 0, 28)
    btn.Position = UDim2.new(0, 10, 0.5, -14)
    btn.BackgroundColor3 = Color3.fromRGB(235, 130, 158)
    btn.Text = "☰  Edit Priority List"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.TextColor3 = Color3.fromRGB(90, 20, 45)
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local bStroke = Instance.new("UIStroke", btn)
    bStroke.Color = Color3.fromRGB(215, 105, 140); bStroke.Thickness = 1
    btn.MouseButton1Click:Connect(function() createPriorityGUI() end)
    makeSep()
end

-- TP Keybind
do
    local r = makeRow("TP Keybind:")
    makeKeybindBtn(r, Config.TpKey, function(k) Config.TpKey = k; SaveConfig() end)
    makeSep()
end

-- Min TP Gen
do
    local r = makeRow("Min TP Gen (m/s):")
    makeValueBox(r, Config.MinGenForTp or "", function(txt)
        local raw = txt:gsub("%s", "")
        Config.MinGenForTp = raw == "" and 0 or raw
        SaveConfig()
    end)
    makeSep()
end

-- TP Delay
do
    makeSliderRow("TP Delay:", 0.00, 1.00, Config.TpDelay or 0.17, "%.2fs", function(v)
        Config.TpDelay = math.floor(v * 100) / 100; SaveConfig()
    end)
    makeSep()
end

-- TP After FPS
do
    local r = makeRow("TP After FPS:")
    makeToggle(r, Config.TpAfterFPS, function(v) Config.TpAfterFPS = v; SaveConfig() end)
    makeSep()
end

-- FPS Threshold
do
    makeSliderRow("FPS Threshold:", 50, 1000, Config.FPSThreshold or 200, "%.0f fps", function(v)
        Config.FPSThreshold = math.floor(v); SaveConfig()
    end)
    makeSep()
end

-- FPS Wait
do
    makeSliderRow("FPS Wait:", 0.00, 1.00, Config.FPSWait or 0.00, "%.2fs", function(v)
        Config.FPSWait = math.floor(v * 100) / 100; SaveConfig()
    end)
end

mainLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    frame.Size = UDim2.new(0, GUI_W, 0, mainLayout.AbsoluteContentSize.Y + (_guiMinimized and 0 or 10))
end)
task.defer(function()
    -- Aplica estado salvo DEPOIS que todas as rows existem
    applyMinimizedState(_guiMinimized)
end)
