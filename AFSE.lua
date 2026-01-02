-- [[ AFSE FINAL ]]
-- Auto Train (1–6) + Smart Best-Area TP + Auto Chikara + Scan World
-- xan.bar UI

-------------------------------------------------
-- SERVICES
-------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvent")

-- Disable Roblox pause menu overlay
task.spawn(function()
    -- Disable modal dialogs (pause menu)
    UserInputService.ModalEnabled = false
    
    -- Hide the pause menu
    local pauseMenu = CoreGui:FindFirstChild("PauseMenu")
    if pauseMenu then
        pauseMenu.Enabled = false
    end
    
    -- Also try to disable via StarterGui
    StarterGui:SetCore("TopbarEnabled", false)
    
    -- Monitor for pause menu creation and disable it
    CoreGui.ChildAdded:Connect(function(child)
        if child.Name == "PauseMenu" then
            child.Enabled = false
        end
    end)
end)

-------------------------------------------------
-- UI (xan.bar)
-------------------------------------------------

local UI = loadstring(game:HttpGet("https://xan.bar/init.lua"))()

local Window = UI.New({
    Title = "AFSE",
    Subtitle = "Smart Auto Training",
    Theme = "Default",
    Size = UDim2.new(0, 580, 0, 420),
    ShowUserInfo = true
})

local TrainingTab = Window:AddTab("Training", UI.Icons.Aimbot)
local QuestTab = Window:AddTab("Quests", UI.Icons.Hubs)
local TeleportsTab = Window:AddTab("Teleports", UI.Icons.World)
local MiscTab = Window:AddTab("Misc", UI.Icons.Misc)

-- Allowed usernames for Debug tab access
local AllowedDebugUsers = {
    "zunx_alt2",
    "zunx_o7"
}

-- Only create Debug tab if user is allowed
local DebugTab = nil
local currentUsername = LocalPlayer.Name
for _, allowedUser in ipairs(AllowedDebugUsers) do
    if currentUsername == allowedUser then
        DebugTab = Window:AddTab("Debug", UI.Icons.Settings)
        break
    end
end

-------------------------------------------------
-- FLAGS
-------------------------------------------------
local IsScanningWorld = false

local Flags = {
    [1] = false, -- Strength
    [2] = false, -- Durability
    [3] = false, -- Chakra
    [4] = false, -- Sword
    [5] = false, -- Agility
    [6] = false, -- Speed
    Speed = 0.25
}

local MiscFlags = {
    AutoChikara = false,
    AutoPickupFruit = false,
    AutoSkillEnabled = false,
    AutoSkillKeys = {} -- Keys to spam (e.g., {"t", "r", "q"})
}

local QuestFlags = {
    AutoQuest = false,
    SelectedQuest = "Boom",
    -- Kill Quest settings (used when quest type is KillPlayer)
    PowerThreshold = 50, -- Target players with power below this % of your power
    FarmDistance = 6, -- How far below target to farm (hardcoded, slider removed)
    FarmMethod = "Fist" -- Fist or Sword
}

-- Track currently equipped weapon for kill quest
local CurrentEquippedWeapon = nil

-- Track last notification time for no players found
local LastNoPlayersNotifyTime = 0

-------------------------------------------------
-- FOLDERS
-------------------------------------------------

local MapAreas = workspace
    :WaitForChild("Map")
    :WaitForChild("TrainingAreas")

local ScriptableAreas = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("TrainingAreas")

local QuestFolder = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("NPC")
    :WaitForChild("Quest")

local ChikaraFolder = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("ChikaraBoxes")

local GachaFolder = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("NPC")
    :WaitForChild("Gacha")

local ChampionsFolder = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("NPC")
    :WaitForChild("Shops")
    :WaitForChild("Champions")

local SpecialFolder = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("NPC")
    :WaitForChild("Shops")
    :WaitForChild("Special")

local FruitsFolder = workspace
    :WaitForChild("Scriptable")
    :WaitForChild("Fruits")

-------------------------------------------------
-- UTILS
-------------------------------------------------

local function getHRP()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-------------------------------------------------
-- DEBUG SCREEN (INITIALIZED EARLY)
-------------------------------------------------

local DebugLogs = {}
local DebugScreen, DebugLogLabel, DebugScrollingFrame
local DebugToggleRef = nil

-- Log type colors for RichText
local LogColors = {
    INFO = "rgb(140,140,145)",
    WARN = "rgb(230,180,80)",
    ERROR = "rgb(230,90,90)",
    SUCCESS = "rgb(90,200,120)",
}

local function addDebugLog(message, logType)
    logType = logType or "INFO"
    local timestamp = os.date("%H:%M:%S")

    -- Plain text for clipboard
    local plainEntry = string.format("[%s] [%s] %s", timestamp, logType, tostring(message))
    table.insert(DebugLogs, plainEntry)

    -- Update the label with RichText coloring
    if DebugLogLabel then
        local coloredLines = {}
        for _, log in ipairs(DebugLogs) do
            -- Extract log type from the entry
            local logTypeMatch = log:match("%[%d+:%d+:%d+%] %[(%w+)%]")
            local color = LogColors[logTypeMatch] or LogColors.INFO
            table.insert(coloredLines, string.format('<font color="%s">%s</font>', color, log))
        end
        DebugLogLabel.Text = table.concat(coloredLines, "\n")

        -- Update canvas size after a short delay to let AutomaticSize calculate
        task.spawn(function()
            task.wait(0.05)
            if DebugLogLabel and DebugScrollingFrame then
                local labelHeight = DebugLogLabel.AbsoluteSize.Y
                DebugScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, labelHeight + 20)

                -- Auto scroll to bottom
                if DebugScreen and DebugScreen.Visible then
                    DebugScrollingFrame.CanvasPosition = Vector2.new(0, labelHeight)
                end
            end
        end)
    end
end

-------------------------------------------------
-- STREAM ENTIRE WORLD (CRITICAL)
-------------------------------------------------

-- Find one model in a folder (recursively searches nested folders)
local function findOneModel(folder)
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then
            return child
        elseif child:IsA("Folder") then
            -- Recursively search nested folders
            local model = findOneModel(child)
            if model then
                return model
            end
        end
    end
    return nil
end

local function scanWorld()
    local hrp = getHRP()
    local startCF = hrp.CFrame

    IsScanningWorld = true
    addDebugLog("World scan started.", "INFO")
    
    -- Count all models in MapAreas (direct children only, not their children)
    local itemCount = 0
    for _, obj in ipairs(MapAreas:GetChildren()) do
        if obj:IsA("Model") then
            itemCount = itemCount + 1
        end
    end
    local estimatedDuration = math.max(2, (itemCount * 0.3) + 1)
    
    -- Show loading screen
    UI.Loading({
        Title = "Scanning World",
        Subtitle = "Discovering training areas...",
        Duration = estimatedDuration,
        Fullscreen = true
    })

    -- TP to all models in MapAreas (direct children only)
    for _, obj in ipairs(MapAreas:GetChildren()) do
        if obj:IsA("Model") then
            hrp.CFrame = obj:GetPivot() + Vector3.new(0, 10, 0)
            task.wait(0.3)
        end
    end

    IsScanningWorld = false
    hrp.CFrame = startCF

    addDebugLog("World scan finished.", "INFO")
end

-------------------------------------------------
-- NUMBER PARSER
-------------------------------------------------

local MULT = { 
    k=1e3,      -- thousand
    m=1e6,      -- million
    b=1e9,      -- billion
    t=1e12,     -- trillion
    qa=1e15,    -- quadrillion
    qd=1e15,    -- quadrillion (alternative)
    qn=1e18,    -- quintillion
    qi=1e18,    -- quintillion (alternative)
    sx=1e21,    -- sextillion
    sp=1e24,    -- septillion
    oc=1e27,    -- octillion
    no=1e30,    -- nonillion
    dc=1e33     -- decillion
}

local function parseNumber(txt)
    local n, s = txt:lower():match("([%d%.]+)%s*(%a*)")
    return tonumber(n) * (MULT[s] or 1)
end

-- Format number for display (e.g., 1000000 -> "1M", 100 -> "100")
local function formatNumber(num)
    if num >= 1e33 then return string.format("%.0fdc", num / 1e33)
    elseif num >= 1e30 then return string.format("%.0fno", num / 1e30)
    elseif num >= 1e27 then return string.format("%.0foc", num / 1e27)
    elseif num >= 1e24 then return string.format("%.0fsp", num / 1e24)
    elseif num >= 1e21 then return string.format("%.0fsx", num / 1e21)
    elseif num >= 1e18 then return string.format("%.0fqn", num / 1e18)
    elseif num >= 1e15 then return string.format("%.0fqd", num / 1e15)
    elseif num >= 1e12 then return string.format("%.0ft", num / 1e12)
    elseif num >= 1e9 then return string.format("%.0fb", num / 1e9)
    elseif num >= 1e6 then return string.format("%.0fm", num / 1e6)
    elseif num >= 1e3 then return string.format("%.0fk", num / 1e3)
    else return string.format("%.0f", num)
    end
end

-- Get stat name from stat number
local function getStatName(stat)
    local statNames = {
        [1] = "Strength",
        [2] = "Durability",
        [3] = "Chakra",
        [4] = "Sword",
        [5] = "Agility",
        [6] = "Speed"
    }
    return statNames[stat] or "Unknown"
end

-------------------------------------------------
-- TRAINING PAD DATA
-------------------------------------------------

local LAST_AREA = {}
local TP_DISTANCE = 12
local TP_RANGE = 200  -- Only teleport if you're REALLY far away (like walked to another area)
local HasInitialTP = {}  -- Track if we've done the initial teleport for each stat

-------------------------------------------------
-- AREA DATA (hardcoded - use Scan World in Debug to update)
-------------------------------------------------
-- Format: { Req = requirement, CFrame = CFrame.new(x, y, z) }

local Areas = {
    [1] = { -- Strength
        {Index = 1, Req = 100, CFrame = CFrame.new(-6, 66, 133) },
        {Index = 2, Req = 10e3, CFrame = CFrame.new(1340, 139, -138) },
        {Index = 3, Req = 100e3, CFrame = CFrame.new(-1257, 59, 485) },
        {Index = 4, Req = 1e6, CFrame = CFrame.new(-907, 48, 174) },
        {Index = 5, Req = 10e6, CFrame = CFrame.new(-2259, 614, 537) },
        {Index = 6, Req = 100e6, CFrame = CFrame.new(-41, 84, -1308) },
        {Index = 7, Req = 1e9, CFrame = CFrame.new(718, 144, 929) },
        {Index = 8, Req = 100e9, CFrame = CFrame.new(1855, 146, 92) },
        {Index = 9, Req = 5e12, CFrame = CFrame.new(629, 617, 424) },
        {Index = 10, Req = 250e12, CFrame = CFrame.new(4280, 80, -600) },
        {Index = 11, Req = 150e15, CFrame = CFrame.new(796, 216, -1004) },
        {Index = 12, Req = 25e18, CFrame = CFrame.new(3873, 118, 880) },
        {Index = 13, Req = 10e21, CFrame = CFrame.new(3860, 724, -1185) },
    },
    [2] = { -- Durability
        {Index = 1, Req = 100, CFrame = CFrame.new(72, 83, 880) },
        {Index = 2, Req = 10e3, CFrame = CFrame.new(-1653, 58, -542) },
        {Index = 3, Req = 100e3, CFrame = CFrame.new(-80, 61, 2029) },
        {Index = 4, Req = 1e6, CFrame = CFrame.new(-624, 191, 735) },
        {Index = 5, Req = 10e6, CFrame = CFrame.new(-1063, 88, -928) },
        {Index = 6, Req = 100e6, CFrame = CFrame.new(-338, 59, -1651) },
        {Index = 7, Req = 1e9, CFrame = CFrame.new(2465, 1439, -371) },
        {Index = 8, Req = 100e9, CFrame = CFrame.new(-2754, -231, 352) },
        {Index = 9, Req = 5e12, CFrame = CFrame.new(2176, 454, 575) },
        {Index = 10, Req = 250e12, CFrame = CFrame.new(1664, 500, -1329) },
        {Index = 11, Req = 150e15, CFrame = CFrame.new(190, 785, -703) },
        {Index = 12, Req = 25e18, CFrame = CFrame.new(2561, 183, 1558) },
        {Index = 13, Req = 10e21, CFrame = CFrame.new(1687, 2479, -35) },
    },
    [3] = { -- Chakra
        {Index = 1, Req = 100, CFrame = CFrame.new(-8, 71, -124) },
        {Index = 2, Req = 10e3, CFrame = CFrame.new(1423, 144, -587) },
        {Index = 3, Req = 100e3, CFrame = CFrame.new(912, 138, 784) },
        {Index = 4, Req = 1e6, CFrame = CFrame.new(1621, 446, 639) },
        {Index = 5, Req = 10e6, CFrame = CFrame.new(335, -153, -1831) },
        {Index = 6, Req = 100e6, CFrame = CFrame.new(1026, 255, -627) },
        {Index = 7, Req = 1e9, CFrame = CFrame.new(3053, 108, 1105) },
        {Index = 8, Req = 100e9, CFrame = CFrame.new(1496, 486, 1892) },
        {Index = 9, Req = 5e12, CFrame = CFrame.new(-9, 72, -479) },
        {Index = 10, Req = 250e12, CFrame = CFrame.new(-396, 1230, 669) },
        {Index = 11, Req = 150e15, CFrame = CFrame.new(-742, 2687, 593) },
        {Index = 12, Req = 25e18, CFrame = CFrame.new(3243, -455, -245) },
        {Index = 13, Req = 10e21, CFrame = CFrame.new(329, 287, 1893) },
    },
    [5] = { -- Agility
        {Index = 1, Req = 100, CFrame = CFrame.new(42, 86, 451) },
        {Index = 2, Req = 10e3, CFrame = CFrame.new(-435, 133, -79) },
        {Index = 3, Req = 100e3, CFrame = CFrame.new(3482, 66, 146) },
        {Index = 4, Req = 5e6, CFrame = CFrame.new(4109, 70, 842) },
    },
    [6] = { -- Speed
        {Index = 1, Req = 100, CFrame = CFrame.new(-107, 66, -505) },
        {Index = 2, Req = 10e3, CFrame = CFrame.new(-435, 133, -79) },
        {Index = 3, Req = 100e3, CFrame = CFrame.new(3482, 66, 146) },
        {Index = 4, Req = 5e6, CFrame = CFrame.new(4109, 70, 852) },
    },
}

-------------------------------------------------
-- CHIKARA TABLE (hardcoded - use Scan World to update)
-------------------------------------------------
-- Format: {Index = index, CFrame = CFrame.new(x, y, z) }

local Chikara = {
    {Index = 1, CFrame = CFrame.new(3104, 144, 262) },
    {Index = 2, CFrame = CFrame.new(3081, 60, 1224) },
    {Index = 3, CFrame = CFrame.new(-423, 130, -213) },
    {Index = 4, CFrame = CFrame.new(1022, 234, 885) },
    {Index = 5, CFrame = CFrame.new(-423, 157, -1393) },
    {Index = 6, CFrame = CFrame.new(-964, 100, 367) },
    {Index = 7, CFrame = CFrame.new(1366, 232, -764) },
    {Index = 8, CFrame = CFrame.new(-1127, 97, -127) },
    {Index = 9, CFrame = CFrame.new(-1125, 182, -1308) },
    {Index = 10, CFrame = CFrame.new(4295, 60, -519) },
    {Index = 11, CFrame = CFrame.new(3650, 145, -988) },
    {Index = 12, CFrame = CFrame.new(3672, 60, -1422) },
    {Index = 13, CFrame = CFrame.new(69, 115, 2153) },
}

-------------------------------------------------
-- TELEPORTS TABLE (hardcoded - use Scan World to update)
-------------------------------------------------
-- Format: {Index = index, Name = name, CFrame = CFrame.new(x, y, z) }

local Teleports = {
    Gachas = {
        {Index = 1, Name = "G1", CFrame = CFrame.new(-15, 63, -452) },
        {Index = 2, Name = "G2", CFrame = CFrame.new(-1103, 64, -129) },
        {Index = 3, Name = "G3", CFrame = CFrame.new(314, -147, -2088) },
        {Index = 4, Name = "G4", CFrame = CFrame.new(-354, 122, -1202) },
        {Index = 5, Name = "G5", CFrame = CFrame.new(-2258, 618, 515) },
        {Index = 6, Name = "G6", CFrame = CFrame.new(1253, 152, -88) },
    },
    Champions = {
        {Index = 1, Name = "1", CFrame = CFrame.new(39, 105, 38) },
        {Index = 2, Name = "2", CFrame = CFrame.new(518, 62, -286) },
    },
    Specials = {
        {Index = 1, Name = "Stands", CFrame = CFrame.new(143, 63, -223) },
        {Index = 2, Name = "Kagunes", CFrame = CFrame.new(1700, 140, -163) },
        {Index = 3, Name = "Quirks", CFrame = CFrame.new(331, 62, -84) },
        {Index = 4, Name = "Grimoires", CFrame = CFrame.new(1048, 238, -975) },
    },
    Quests = {
        {Index = 1, Name = "Boom", CFrame = CFrame.new(-38, 80, 7) },
        {Index = 2, Name = "Giovanni", CFrame = CFrame.new(149, 62, -226) },
        {Index = 3, Name = "Sword Master", CFrame = CFrame.new(328, 69, -1992) },
        {Index = 4, Name = "Ghoul", CFrame = CFrame.new(1701, 142, -169) },
        {Index = 5, Name = "Reindeer", CFrame = CFrame.new(-32, 104, 44) },
        {Index = 6, Name = "Santa", CFrame = CFrame.new(4312, 60, -343) },
    },
}

-- Check if an area with this requirement already exists
local function areaExists(stat, req)
    if not Areas[stat] then return false end
    for _, area in ipairs(Areas[stat]) do
        if area.Req == req then
            return true
        end
    end
    return false
end

-------------------------------------------------
-- TP TO BEST AREA
-------------------------------------------------

local function tpToBest(stat)
    if stat == 4 then return end -- sword

    local stats = LocalPlayer:FindFirstChild("Stats")
    if not stats then
        addDebugLog("Stats not found", "ERROR")
        return
    end

    local statObj = stats:GetChildren()[stat]
    if not statObj then
        addDebugLog(string.format("Stat %d not found", stat), "ERROR")
        return
    end

    local current = statObj.Value
    local best

    for _, a in ipairs(Areas[stat]) do
        if a.Req <= current and (not best or a.Req > best.Req) then
            best = a
        end
    end

    if not best then
        addDebugLog(string.format("No suitable area for %s (current: %s)", getStatName(stat), formatNumber(current)), "WARN")
        return
    end

    local hrp = getHRP()
    if LAST_AREA[stat] and LAST_AREA[stat].CFrame then
        -- Check if the best area changed (stats increased, need better area)
        local bestAreaChanged = (best.Req ~= LAST_AREA[stat].Req)
        
        if not bestAreaChanged then
            -- Same area, only teleport if we're more than TP_RANGE away
            local distanceFromLastArea = (hrp.Position - LAST_AREA[stat].CFrame.Position).Magnitude
            if distanceFromLastArea <= TP_RANGE then
                return
            end
        end
        -- If best area changed, we'll teleport to the new area (fall through)
    end

    addDebugLog(string.format("TP to %s %s (current: %s)", formatNumber(best.Req), getStatName(stat), formatNumber(current)), "INFO")
    hrp.CFrame = best.CFrame + Vector3.new(0, 5, 0)
    LAST_AREA[stat] = best
    HasInitialTP[stat] = true
end

-------------------------------------------------
-- STAT CHANGE → INSTANT PAD UPGRADE
-------------------------------------------------

local function hookStatChanges()
    local stats = LocalPlayer:WaitForChild("Stats")
    for stat, _ in pairs(Areas) do
        local obj = stats:GetChildren()[stat]
        if obj then
            obj.Changed:Connect(function()
                if Flags[stat] then
                    tpToBest(stat)
                end
            end)
        end
    end
end

hookStatChanges()

-------------------------------------------------
-- AUTO TRAIN LOOP (ACTUAL TRAINING)
-------------------------------------------------

task.spawn(function()
    while task.wait(0.1) do
        for stat = 1, 6 do
            if Flags[stat] then
                if stat == 4 then
                    -- Sword (stat 4) - no areas, just fire Remote
                    Remote:FireServer("Train", stat)
                else
                    -- Other stats - check for area and TP if needed
                    local best = LAST_AREA[stat]
                    if best and best.CFrame then
                        -- Check if we need to teleport (tpToBest will handle the distance check)
                        tpToBest(stat)

                        -- Always train regardless of distance
                        Remote:FireServer("Train", stat)
                    else
                        -- No area found yet, do initial teleport
                        if not HasInitialTP[stat] then
                            tpToBest(stat)
                        end
                        -- Still try to train
                        Remote:FireServer("Train", stat)
                    end
                end
            else
                -- When toggle is turned off, reset so next enable will TP
                HasInitialTP[stat] = nil
            end
        end
    end
end)

-------------------------------------------------
-- AUTO CHIKARA
-------------------------------------------------

task.spawn(function()
    while task.wait(0.1) do
        if not MiscFlags.AutoChikara then 
            continue 
        end

        local hrp = getHRP()
        if not hrp then continue end

        -- Check if folder is empty
        local crateCount = 0
        for _, crate in ipairs(ChikaraFolder:GetChildren()) do
            if crate.Name == "ChikaraCrate" then
                crateCount = crateCount + 1
            end
        end

        if crateCount == 0 then
            -- No crates available, wait and notify
            UI.Notify({
                Title = "Chikara Collection",
                Content = "Waiting for crates to spawn...",
                Style = "Default",
                Duration = 15
            })
            task.wait(15)
            continue
        end

        -- Loop through all crates in folder and click them one at a time
        for _, crate in ipairs(ChikaraFolder:GetChildren()) do
            if not MiscFlags.AutoChikara then break end -- Stop if toggle is off
            
            if crate.Name == "ChikaraCrate" then
                -- Find click detector directly on crate or in ClickBox
                local cd = crate:FindFirstChildOfClass("ClickDetector")
                local clickBox = nil
                if not cd then
                    clickBox = crate:FindFirstChild("ClickBox")
                    if clickBox then
                        cd = clickBox:FindFirstChildOfClass("ClickDetector")
                    end
                end
                
                if cd then
                    fireclickdetector(cd)
                    
                    -- Wait a bit to see if crate was collected
                    task.wait(0.5)
                    
                    -- Check if crate still exists (not collected/destroyed)
                    local stillExists = false
                    if crate.Parent then
                        -- Check if crate still exists in the folder
                        for _, child in ipairs(ChikaraFolder:GetChildren()) do
                            if child == crate then
                                stillExists = true
                                break
                            end
                        end
                    end
                    
                    -- If crate still exists, wait 2 seconds and fire again
                    if stillExists then
                        task.wait(2)
                        -- Re-find click detector in case it was recreated
                        local newCd = crate:FindFirstChildOfClass("ClickDetector")
                        if not newCd then
                            local newClickBox = crate:FindFirstChild("ClickBox")
                            if newClickBox then
                                newCd = newClickBox:FindFirstChildOfClass("ClickDetector")
                            end
                        end
                        if newCd then
                            fireclickdetector(newCd)
                        end
                    end
                    
                    -- Show notification for cooldown
                    UI.Notify({
                        Title = "Chikara Collection",
                        Content = "Waiting for cooldown...",
                        Style = "Default",
                        Duration = 11
                    })
                    task.wait(11) -- Wait for chikara collection cooldown
                end
            end
        end
    end
end)

-------------------------------------------------
-- AUTO PICK UP FRUIT
-------------------------------------------------

task.spawn(function()
    while task.wait(0.3) do
        if not MiscFlags.AutoPickupFruit then continue end

        for _, fruit in ipairs(FruitsFolder:GetChildren()) do
            if not fruit:IsA("Model") then continue end

            local root = fruit:FindFirstChildWhichIsA("BasePart")
            if not root then continue end

            local hrp = getHRP()
            local distance = (hrp.Position - root.Position).Magnitude

            -- TP to fruit if not already close
            if distance > 10 then
                hrp.CFrame = root.CFrame + Vector3.new(0, 0, 2)
                task.wait(0.2)
            end
        end
    end
end)

-------------------------------------------------
-- GACHA NAME MAPPING
-------------------------------------------------

-- Gacha name mapping (for UI display)
local GachaNameMap = {
    ["G1"] = "Justsu Levelling",
    ["G2"] = "Nen Levelling",
    ["G3"] = "Soul Levelling",
    ["G4"] = "Nichiyin Levelling",
    ["G5"] = "Seiyen Levelling",
    ["G6"] = "Hero Levelling"
}

-------------------------------------------------
-- AUTO QUEST SYSTEM
-------------------------------------------------

-- Map dropdown names to NPCData keys (dynamically built from Teleports.Quests)
local QuestNameMap = {}
local QuestDropdownOptions = {}
for _, quest in ipairs(Teleports.Quests) do
    QuestNameMap[quest.Name] = quest.Name
    table.insert(QuestDropdownOptions, quest.Name)
end

-- Find quest in player's Quests folder using NPCData quest number
local function findQuest(questName)
    local npcData = LocalPlayer:FindFirstChild("NPCData")
    if not npcData then
        addDebugLog("NPCData folder not found", "ERROR")
        return nil
    end
    
    -- Get the quest number from NPCData
    local questNumberValue = npcData:FindFirstChild(questName)
    if not questNumberValue or not (questNumberValue:IsA("IntValue") or questNumberValue:IsA("NumberValue")) then
        addDebugLog("Quest number not found in NPCData for: " .. questName, "ERROR")
        return nil
    end
    
    local questNumber = questNumberValue.Value
    local fullQuestName = questName .. tostring(questNumber)
    
    local quests = LocalPlayer:FindFirstChild("Quests")
    if not quests then
        addDebugLog("Quests folder not found", "ERROR")
        return nil
    end
    
    -- Find the quest with the exact name
    local quest = quests:FindFirstChild(fullQuestName)
    if not quest then
        addDebugLog("Quest not found: " .. fullQuestName, "WARN")
        return nil
    end
    
    return quest
end

-- Get stat number from requirement key
local function getStatFromKey(key)
    -- Map requirement keys to stat numbers
    -- This might need adjustment based on actual game structure
    -- Assuming keys are "1", "2", "3" etc. and map to stats
    local keyNum = tonumber(key)
    if keyNum then
        -- Common mapping: 1=Strength, 2=Durability, 3=Chakra, 4=Sword, 5=Agility, 6=Speed
        return keyNum
    end
    return nil
end

-- Check if all quest requirements are met
local function checkQuestComplete(quest)
    if not quest then return false end
    
    local completed = quest:FindFirstChild("Completed")
    if completed and completed.Value then
        return true
    end
    
    local requirements = quest:FindFirstChild("Requirements")
    local progress = quest:FindFirstChild("Progress")
    
    if not requirements or not progress then
        return false
    end
    
    -- Check all requirements
    for _, reqValue in ipairs(requirements:GetChildren()) do
        if reqValue:IsA("NumberValue") or reqValue:IsA("IntValue") then
            local key = reqValue.Name
            local progValue = progress:FindFirstChild(key)
            if not progValue or progValue.Value < reqValue.Value then
                return false
            end
        end
    end
    
    return true
end

-- Get next stat that needs training
local function getNextStatToTrain(quest)
    if not quest then return nil end
    
    local requirements = quest:FindFirstChild("Requirements")
    local progress = quest:FindFirstChild("Progress")
    
    if not requirements or not progress then
        return nil
    end
    
    -- Check requirements in order (sorted by key)
    local reqKeys = {}
    for _, reqValue in ipairs(requirements:GetChildren()) do
        if reqValue:IsA("NumberValue") or reqValue:IsA("IntValue") then
            table.insert(reqKeys, reqValue.Name)
        end
    end
    table.sort(reqKeys)
    
    for _, key in ipairs(reqKeys) do
        local reqValue = requirements:FindFirstChild(key)
        local progValue = progress:FindFirstChild(key)
        
        if reqValue and (reqValue:IsA("NumberValue") or reqValue:IsA("IntValue")) then
            local current = progValue and progValue.Value or 0
            local required = reqValue.Value
            
            if current < required then
                local stat = getStatFromKey(key)
                if stat then
                    return stat, current, required
                end
            end
        end
    end
    
    return nil
end

-- Click NPC (for starting or completing quests)
local function clickNPC(questName)
    local npc = QuestFolder:FindFirstChild(questName)
    if not npc then
        addDebugLog("Quest NPC not found: " .. questName, "ERROR")
        return false
    end
    
    local clickBox = npc:FindFirstChild("ClickBox")
    if not clickBox then
        addDebugLog("ClickBox not found for: " .. questName, "ERROR")
        return false
    end
    
    local clickDetector = clickBox:FindFirstChildOfClass("ClickDetector")
    if not clickDetector then
        addDebugLog("ClickDetector not found for: " .. questName, "ERROR")
        return false
    end
    
    -- First try: Fire click detector without teleporting
    fireclickdetector(clickDetector)
    task.wait(0.2)
    
    -- Check if NPC still exists (if interaction worked, NPC might change state)
    -- If NPC still exists, teleport and fire again to ensure it works
    local stillExists = false
    if npc.Parent and clickBox.Parent == npc then
        stillExists = true
    end
    
    -- If still exists, teleport and fire again
    if stillExists then
        local root = npc:FindFirstChildWhichIsA("BasePart")
        if root then
            getHRP().CFrame = root.CFrame + Vector3.new(0, 0, 4)
            task.wait(0.3)
            
            -- Re-find click detector and fire again
            local newClickBox = npc:FindFirstChild("ClickBox")
            if newClickBox then
                local newClickDetector = newClickBox:FindFirstChildOfClass("ClickDetector")
                if newClickDetector then
                    fireclickdetector(newClickDetector)
                end
            end
        end
    end
    
    return true
end

-- Complete quest by clicking NPC
local function completeQuest(questName)
    if clickNPC(questName) then
        addDebugLog("Completed quest: " .. questName, "SUCCESS")
        return true
    end
    return false
end

-- Start quest by clicking NPC
local function startQuest(questName)
    if clickNPC(questName) then
        addDebugLog("Clicked NPC to start quest: " .. questName, "INFO")
        return true
    end
    return false
end

-- Get quest type from quest folder
local function getQuestType(quest)
    if not quest then return nil end

    -- First check for explicit QuestType StringValue
    local questType = quest:FindFirstChild("QuestType")
    if questType and questType:IsA("StringValue") then
        return questType.Value
    end

    -- Otherwise, detect from Requirements folder structure
    local requirements = quest:FindFirstChild("Requirements")
    if requirements then
        -- Check if there's a "Kill" requirement -> KillPlayer
        if requirements:FindFirstChild("Kill") then
            return "KillPlayer"
        end

        -- Check if requirements are numbered (1, 2, 3, 4, 5, 6) -> GainStat
        for _, child in ipairs(requirements:GetChildren()) do
            local num = tonumber(child.Name)
            if num and num >= 1 and num <= 6 then
                return "GainStat"
            end
        end
    end

    return "GainStat" -- Default to GainStat if not specified
end

-- Get local player's total power
local function getLocalPlayerPower()
    local otherData = LocalPlayer:FindFirstChild("OtherData")
    if otherData then
        local totalPower = otherData:FindFirstChild("TotalPower")
        if totalPower and (totalPower:IsA("NumberValue") or totalPower:IsA("IntValue")) then
            return totalPower.Value
        end
    end
    return 0
end

-- Get another player's total power
local function getPlayerPower(player)
    local otherData = player:FindFirstChild("OtherData")
    if otherData then
        local totalPower = otherData:FindFirstChild("TotalPower")
        if totalPower and (totalPower:IsA("NumberValue") or totalPower:IsA("IntValue")) then
            return totalPower.Value
        end
    end
    return 0
end

-- Check if player is in safezone
local function isPlayerInSafezone(player)
    local char = player.Character
    if not char then return true end -- Assume safezone if no character

    local pvpFolder = workspace:FindFirstChild("Scriptable")
    if pvpFolder then
        pvpFolder = pvpFolder:FindFirstChild("Characters")
        if pvpFolder then
            local playerFolder = pvpFolder:FindFirstChild(player.Name)
            if playerFolder then
                local pvp = playerFolder:FindFirstChild("PVPFolder")
                if pvp then
                    local safezone = pvp:FindFirstChild("Safezone")
                    if safezone and safezone:IsA("BoolValue") then
                        return safezone.Value
                    end
                end
            end
        end
    end
    return true -- Assume safezone if can't determine
end

-- Find valid kill targets based on power threshold
local function findKillTargets()
    local targets = {}
    local myPower = getLocalPlayerPower()
    local threshold = myPower * (QuestFlags.PowerThreshold / 100)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local playerPower = getPlayerPower(player)
            local inSafezone = isPlayerInSafezone(player)

            if playerPower <= threshold and not inSafezone then
                local char = player.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        table.insert(targets, {
                            Player = player,
                            Power = playerPower,
                            HRP = hrp
                        })
                    end
                end
            end
        end
    end

    -- Sort by power (lowest first - easiest targets)
    table.sort(targets, function(a, b) return a.Power < b.Power end)

    return targets
end

-- Track which stats were enabled by auto quest
local AutoQuestEnabledStats = {}
-- Store original Flags state before auto quest takes over
local OriginalFlagsState = {}
-- Current quest being tracked
local CurrentQuest = nil
-- Quest progress change connections
local QuestProgressConnections = {}
-- Force quest re-check flag
local ForceQuestRecheck = false

-- Clean up quest progress connections
local function cleanupQuestConnections()
    for _, conn in pairs(QuestProgressConnections) do
        if conn then
            conn:Disconnect()
        end
    end
    QuestProgressConnections = {}
end

-- Check and update quest progress when a stat requirement is met
local function checkQuestProgressUpdate(quest)
    if not quest or not QuestFlags.AutoQuest then return end
    
    -- Check if quest is already completed
    if checkQuestComplete(quest) then
        -- Disable all auto-quest enabled stats
        for stat, _ in pairs(AutoQuestEnabledStats) do
            if Flags[stat] then
                Flags[stat] = false
            end
            AutoQuestEnabledStats[stat] = nil
        end
        
        local questName = QuestNameMap[QuestFlags.SelectedQuest]
        addDebugLog("All requirements met, completing quest: " .. questName, "INFO")
        completeQuest(questName)
        return
    end
    
    -- Get next stat to train
    local stat, current, required = getNextStatToTrain(quest)
    if stat then
        -- Disable other auto-quest enabled stats that are no longer needed
        for otherStat, _ in pairs(AutoQuestEnabledStats) do
            if otherStat ~= stat then
                -- Check if this stat's requirement is already met
                local requirements = quest:FindFirstChild("Requirements")
                local progress = quest:FindFirstChild("Progress")
                if requirements and progress then
                    local reqKey = tostring(otherStat)
                    local reqValue = requirements:FindFirstChild(reqKey)
                    local progValue = progress:FindFirstChild(reqKey)
                    if reqValue and progValue and progValue.Value >= reqValue.Value then
                        -- This stat is done, disable it
                        if Flags[otherStat] then
                            Flags[otherStat] = false
                        end
                        AutoQuestEnabledStats[otherStat] = nil
                    end
                end
            end
        end
        
        -- Enable training for this stat if not already enabled
        if not Flags[stat] then
            Flags[stat] = true
            AutoQuestEnabledStats[stat] = true
            -- Only TP to best area if not sword (stat 4 has no areas)
            if stat ~= 4 then
                tpToBest(stat)
            end
            addDebugLog(string.format("Auto Quest: Training stat %d (current: %s, required: %s)", 
                stat, tostring(current), tostring(required)), "INFO")
        end
    else
        -- No more stats to train, check if complete
        if checkQuestComplete(quest) then
            local questName = QuestNameMap[QuestFlags.SelectedQuest]
            addDebugLog("All requirements met, completing quest: " .. questName, "INFO")
            completeQuest(questName)
        end
    end
end

-- Hook into quest progress changes
local function hookQuestProgress(quest)
    if not quest then return end
    
    cleanupQuestConnections()
    CurrentQuest = quest
    
    local progress = quest:FindFirstChild("Progress")
    if not progress then return end
    
    -- Monitor each progress value change
    for _, progValue in ipairs(progress:GetChildren()) do
        if progValue:IsA("NumberValue") or progValue:IsA("IntValue") then
            local conn = progValue.Changed:Connect(function()
                if QuestFlags.AutoQuest and CurrentQuest == quest then
                    checkQuestProgressUpdate(quest)
                end
            end)
            table.insert(QuestProgressConnections, conn)
        end
    end
    
    -- Also monitor Completed status
    local completed = quest:FindFirstChild("Completed")
    if completed then
        local conn = completed.Changed:Connect(function()
            if QuestFlags.AutoQuest and CurrentQuest == quest then
                checkQuestProgressUpdate(quest)
            end
        end)
        table.insert(QuestProgressConnections, conn)
    end
end

-- Current quest type being handled
local CurrentQuestType = nil

-- Handle GainIncrement quest type
local function handleGainIncrementQuest(quest)
    if not quest then return end

    local progress = quest:FindFirstChild("Progress")
    local requirements = quest:FindFirstChild("Requirements")

    if not progress or not requirements then return end

    -- Check if quest is complete
    local isComplete = true
    for _, reqValue in ipairs(requirements:GetChildren()) do
        if reqValue:IsA("NumberValue") or reqValue:IsA("IntValue") then
            local key = reqValue.Name
            local progValue = progress:FindFirstChild(key)
            if not progValue or progValue.Value < reqValue.Value then
                isComplete = false
                break
            end
        end
    end

    if isComplete then
        local questName = QuestNameMap[QuestFlags.SelectedQuest]
        addDebugLog("GainIncrement quest complete, turning in: " .. questName, "SUCCESS")
        completeQuest(questName)
        return true
    end

    -- Fire the remote to increment progress
    -- The game increments progress each time you fire
    Remote:FireServer("Train", 1) -- Just fire any train action
    return false
end

-- Auto Quest Loop (now mainly for initial setup and periodic checks)
task.spawn(function()
    while task.wait(1) do
        if not QuestFlags.AutoQuest then
            -- Disable all auto-quest enabled stats when auto quest is off
            for stat, _ in pairs(AutoQuestEnabledStats) do
                if Flags[stat] then
                    Flags[stat] = false
                end
                AutoQuestEnabledStats[stat] = nil
            end
            cleanupQuestConnections()
            CurrentQuest = nil
            CurrentQuestType = nil
            continue
        end

        -- Read the current selection directly (don't cache it)
        local currentSelection = QuestFlags.SelectedQuest
        local questName = QuestNameMap[currentSelection]

        if not questName then
            addDebugLog("Invalid quest selection: " .. tostring(currentSelection), "ERROR")
            task.wait(5)
            continue
        end

        -- Only log every 5 seconds to reduce spam
        if not _lastQuestLogTime or (tick() - _lastQuestLogTime) > 5 then
            addDebugLog("Looking for quest: " .. questName .. " (Selected: " .. currentSelection .. ")", "INFO")
            _lastQuestLogTime = tick()
        end
        local quest = findQuest(questName)
        if not quest then
            -- Quest not found, click NPC to get the quest
            addDebugLog("Quest not found, clicking NPC to get quest: " .. questName, "INFO")
            if startQuest(questName) then
                -- Wait for quest to appear
                task.wait(1)
                -- Try to find the quest (retry a few times)
                for i = 1, 5 do
                    quest = findQuest(questName)
                    if quest then
                        addDebugLog("Quest found after clicking NPC: " .. (quest and quest.Name or "nil"), "SUCCESS")
                        break
                    end
                    task.wait(1)
                end
                if not quest then
                    addDebugLog("Quest still not found after clicking NPC, waiting...", "WARN")
                    task.wait(3)
                    continue
                end
            else
                addDebugLog("Failed to click NPC: " .. questName, "ERROR")
                task.wait(3)
                continue
            end
        end

        -- Check if selection changed (force recheck)
        if ForceQuestRecheck then
            addDebugLog("Selection changed, forcing quest recheck. Current: " .. (CurrentQuest and CurrentQuest.Name or "nil") .. ", New: " .. quest.Name, "INFO")
            cleanupQuestConnections()
            CurrentQuest = nil
            CurrentQuestType = nil
            ForceQuestRecheck = false
        end

        -- Detect quest type
        local questType = getQuestType(quest)

        -- Hook into quest progress if not already hooked or if quest changed
        if CurrentQuest ~= quest then
            addDebugLog("Hooking into quest: " .. quest.Name .. " (Type: " .. tostring(questType) .. ")", "INFO")
            cleanupQuestConnections()
            hookQuestProgress(quest)
            CurrentQuestType = questType

            -- Handle based on quest type
            if questType == "GainStat" then
                -- Initial check for GainStat (existing behavior)
                checkQuestProgressUpdate(quest)
            elseif questType == "KillPlayer" then
                -- KillPlayer quests are handled by the Kill Quest loop below
                addDebugLog("KillPlayer quest detected - hunting players...", "INFO")
            elseif questType == "GainIncrement" then
                addDebugLog("GainIncrement quest detected - will fire remote to increment", "INFO")
            end
        end

        -- Handle GainIncrement quests continuously
        if CurrentQuestType == "GainIncrement" and CurrentQuest then
            handleGainIncrementQuest(CurrentQuest)
        end
    end
end)

-- Check if KillPlayer quest is complete
local function checkKillQuestComplete(quest)
    if not quest then return false end

    local progress = quest:FindFirstChild("Progress")
    local requirements = quest:FindFirstChild("Requirements")

    if not progress or not requirements then return false end

    local killReq = requirements:FindFirstChild("Kill")
    local killProg = progress:FindFirstChild("Kill")

    if killReq and killProg then
        return killProg.Value >= killReq.Value
    end

    return false
end

-------------------------------------------------
-- KILL QUEST SYSTEM
-------------------------------------------------

-- Current kill target
local CurrentKillTarget = nil

-- Check if sword is equipped
local function isSwordEquipped()
    local scriptable = workspace:FindFirstChild("Scriptable")
    if not scriptable then return false end
    local characters = scriptable:FindFirstChild("Characters")
    if not characters then return false end
    local playerFolder = characters:FindFirstChild(LocalPlayer.Name)
    if not playerFolder then return false end
    local sword = playerFolder:FindFirstChild("SWORD")
    if not sword then return false end
    local active = sword:FindFirstChild("Active")
    if not active or not active:IsA("BoolValue") then return false end
    return active.Value
end

-- Equip weapon by pressing key (1 for fist, 4 for sword)
local function equipWeapon(weaponType)
    if weaponType == "Sword" then
        -- Check if sword is already equipped
        if isSwordEquipped() then
            return
        end
        
        -- Equip sword by pressing 4
        local VirtualInputManager = game:GetService("VirtualInputManager")
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Four, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Four, false, game)
        addDebugLog("Kill Quest: Equipped Sword", "INFO")
    elseif weaponType == "Fist" then
        -- For fist, just press 1 (no way to check if fist is equipped, so just press it)
        local VirtualInputManager = game:GetService("VirtualInputManager")
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
        addDebugLog("Kill Quest: Equipped Fist", "INFO")
    end
end

-- Unequip weapon by pressing the same key again
local function unequipWeapon()
    -- Check if sword is equipped and unequip it
    if isSwordEquipped() then
        local VirtualInputManager = game:GetService("VirtualInputManager")
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Four, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Four, false, game)
        addDebugLog("Kill Quest: Unequipped Sword", "INFO")
    end
end

-- Kill Quest Loop (runs when Auto Quest is on and quest type is KillPlayer)
local CurrentTween = nil
local TweenService = game:GetService("TweenService")
local DesyncLoopRunning = false
local DesyncLoopThread = nil

-- Helper function to check if target is alive
local function isTargetAlive(target)
    if not target or not target.Player then return false end
    if not target.HRP or not target.HRP.Parent then return false end
    
    -- Check health using PVPFolder.NewHealth
    local scriptable = workspace:FindFirstChild("Scriptable")
    if not scriptable then return false end
    local characters = scriptable:FindFirstChild("Characters")
    if not characters then return false end
    local playerFolder = characters:FindFirstChild(target.Player.Name)
    if not playerFolder then return false end
    local pvpFolder = playerFolder:FindFirstChild("PVPFolder")
    if not pvpFolder then return false end
    local newHealth = pvpFolder:FindFirstChild("NewHealth")
    if not newHealth or not (newHealth:IsA("NumberValue") or newHealth:IsA("IntValue")) then return false end
    
    -- Target is dead if health is 0 or less
    return newHealth.Value > 0
end

-- Helper function to tween to position smoothly
local function tweenToPosition(hrp, targetPosition, duration)
    if CurrentTween then
        CurrentTween:Cancel()
        CurrentTween = nil
    end
    
    local tweenInfo = TweenInfo.new(
        duration or 0.5,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out,
        0,
        false,
        0
    )
    
    local targetCFrame = CFrame.new(targetPosition)
    CurrentTween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    CurrentTween:Play()
    
    return CurrentTween
end

task.spawn(function()
    while task.wait(0.1) do
        local char = LocalPlayer.Character
        local hrp = getHRP()
        
        -- Only run when Auto Quest is enabled AND current quest is KillPlayer type
        if not QuestFlags.AutoQuest or CurrentQuestType ~= "KillPlayer" then
            -- Stop desync loop if running
            if DesyncLoopRunning then
                DesyncLoopRunning = false
                if DesyncLoopThread then
                    task.cancel(DesyncLoopThread)
                    DesyncLoopThread = nil
                end
                setfflag("WorldStepMax", "-1") -- Reset to normal
            end
            
            -- Cancel any active tween
            if CurrentTween then
                CurrentTween:Cancel()
                CurrentTween = nil
            end
            
            -- Clean up: restore collision, clear target, unequip weapon
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
                end
            end
            
            -- Unequip weapon if one is equipped
            if CurrentEquippedWeapon then
                unequipWeapon()
            end
            
            CurrentKillTarget = nil
            continue
        end

        -- Start desync loop if not already running
        if not DesyncLoopRunning then
            DesyncLoopRunning = true
            DesyncLoopThread = task.spawn(function()
                while DesyncLoopRunning do
                    setfflag("WorldStepMax", "-99999999999999")
                    task.wait(1)
                end
            end)
        end

        if not hrp or not char then continue end

        -- Check if quest is complete
        if CurrentQuest and checkKillQuestComplete(CurrentQuest) then
            -- Stop desync loop
            if DesyncLoopRunning then
                DesyncLoopRunning = false
                if DesyncLoopThread then
                    task.cancel(DesyncLoopThread)
                    DesyncLoopThread = nil
                end
                setfflag("WorldStepMax", "-1") -- Reset to normal
            end
            
            local questName = QuestNameMap[QuestFlags.SelectedQuest]
            addDebugLog("Kill quest complete, turning in: " .. questName, "SUCCESS")
            completeQuest(questName)
            CurrentKillTarget = nil
            CurrentEquippedWeapon = nil
            
            -- Cancel any active tween
            if CurrentTween then
                CurrentTween:Cancel()
                CurrentTween = nil
            end
            
            -- Restore collision
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
            
            task.wait(1) -- Wait for quest to reset
            continue
        end

        -- Find valid targets (dynamically updated from slider)
        local targets = findKillTargets()

        -- PHASE 1: SEARCHING (no targets found)
        if #targets == 0 then
            -- Restore collision (no noclip while searching)
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
            
            -- Clear current target
            if CurrentKillTarget then
                CurrentKillTarget = nil
                CurrentEquippedWeapon = nil
            end
            
            -- Spam notification while searching
            local now = tick()
            if not LastNoPlayersNotifyTime or (now - LastNoPlayersNotifyTime) > 5 then
                LastNoPlayersNotifyTime = now
                UI.Notify({
                    Title = "Kill Quest",
                    Content = "No players found, searching...",
                    Style = "Default",
                    Duration = 5
                })
                addDebugLog("Kill Quest: No valid targets found (threshold: " .. QuestFlags.PowerThreshold .. "%)", "WARN")
            end
            
            continue
        end

        -- PHASE 2: KILLING (targets found)
        -- Enable NoClip when targets are found
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end

        -- Equip weapon based on method (dynamically updated from dropdown)
        -- Keep checking and equipping to ensure it stays equipped
        equipWeapon(QuestFlags.FarmMethod)

        -- Cycle through all targets, only moving to next if current is dead
        for i, target in ipairs(targets) do
            -- Check if we should continue (quest might have been disabled or completed)
            if not QuestFlags.AutoQuest or CurrentQuestType ~= "KillPlayer" then
                break
            end
            
            if CurrentQuest and checkKillQuestComplete(CurrentQuest) then
                break
            end
            
            -- Check if target is still alive BEFORE tweening
            if not isTargetAlive(target) then
                -- Target is dead, move to next
                if CurrentKillTarget and CurrentKillTarget.Player == target.Player then
                    addDebugLog("Kill Quest: Target " .. target.Player.Name .. " killed, moving to next target", "SUCCESS")
                    CurrentKillTarget = nil
                end
                continue
            end
            
            -- Update current target if changed
            if not CurrentKillTarget or CurrentKillTarget.Player ~= target.Player then
                if CurrentKillTarget then
                    addDebugLog("Kill Quest: Switching target to " .. target.Player.Name .. " (Power: " .. formatNumber(target.Power) .. ")", "INFO")
                else
                    addDebugLog("Kill Quest: Targeting " .. target.Player.Name .. " (Power: " .. formatNumber(target.Power) .. ")", "INFO")
                end
                CurrentKillTarget = target
            end
            
            -- Smoothly tween to position below target (dynamically updated from slider)
            local targetPos = target.HRP.Position
            local farmOffset = Vector3.new(0, -6, 0)
            tweenToPosition(hrp, targetPos + farmOffset, 0.5)
            
            -- Wait for tween to complete
            task.wait(0.6)
            
            -- Keep checking if target is still alive - stay on this target until they die
            while isTargetAlive(target) do
                -- Check if we should continue
                if not QuestFlags.AutoQuest or CurrentQuestType ~= "KillPlayer" then
                    break
                end
                
                if CurrentQuest and checkKillQuestComplete(CurrentQuest) then
                    break
                end
                
                -- Keep weapon equipped
                equipWeapon(QuestFlags.FarmMethod)
                
                -- Update position if target moved
                if target.HRP and target.HRP.Parent then
                    local newTargetPos = target.HRP.Position
                    local newFarmOffset = Vector3.new(0, -QuestFlags.FarmDistance, 0)
                    tweenToPosition(hrp, newTargetPos + newFarmOffset, 0.5)
                    task.wait(0.6)
                else
                    break
                end
            end
            
            -- Target is dead, move to next
            if CurrentKillTarget and CurrentKillTarget.Player == target.Player then
                addDebugLog("Kill Quest: Target " .. target.Player.Name .. " killed, moving to next target", "SUCCESS")
                CurrentKillTarget = nil
            end
        end
    end
end)

-- Auto Skill Loop (independent - just spams keys when enabled)
task.spawn(function()
    while task.wait(0.1) do
        if not MiscFlags.AutoSkillEnabled then continue end
        if #MiscFlags.AutoSkillKeys == 0 then continue end

        local VirtualInputManager = game:GetService("VirtualInputManager")

        -- Spam all configured keys
        for _, key in ipairs(MiscFlags.AutoSkillKeys) do
            local keyCode = Enum.KeyCode[key:upper()]
            if keyCode then
                VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
            end
        end
    end
end)

-------------------------------------------------
-- CREATE DEBUG SCREEN GUI
-------------------------------------------------

-- Create Debug Screen (matching xan.bar theme)
local function createDebugScreen()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AFSE_Debug"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- Main container with shadow
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "DebugFrame"
    mainFrame.Size = UDim2.new(0, 500, 0, 350)
    mainFrame.Position = UDim2.new(0.5, -250, 0.5, -175)
    mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
    mainFrame.BorderSizePixel = 0
    mainFrame.Visible = false
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 12)
    mainCorner.Parent = mainFrame

    -- Subtle border/stroke
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(45, 45, 50)
    mainStroke.Thickness = 1
    mainStroke.Parent = mainFrame

    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 45)
    titleBar.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = titleBar

    -- Bottom cover for title bar corners
    local titleCover = Instance.new("Frame")
    titleCover.Name = "TitleCover"
    titleCover.Size = UDim2.new(1, 0, 0, 15)
    titleCover.Position = UDim2.new(0, 0, 1, -15)
    titleCover.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
    titleCover.BorderSizePixel = 0
    titleCover.Parent = titleBar

    -- Separator line
    local separator = Instance.new("Frame")
    separator.Name = "Separator"
    separator.Size = UDim2.new(1, -24, 0, 1)
    separator.Position = UDim2.new(0, 12, 1, 0)
    separator.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    separator.BorderSizePixel = 0
    separator.Parent = titleBar

    -- Title text
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -100, 1, 0)
    titleLabel.Position = UDim2.new(0, 16, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Debug Console"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = titleBar

    -- Window controls container
    local controlsFrame = Instance.new("Frame")
    controlsFrame.Name = "Controls"
    controlsFrame.Size = UDim2.new(0, 70, 0, 30)
    controlsFrame.Position = UDim2.new(1, -82, 0, 8)
    controlsFrame.BackgroundTransparency = 1
    controlsFrame.Parent = titleBar

    -- Minimize button
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "MinimizeBtn"
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(0, 0, 0, 0)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    minimizeBtn.Text = "—"
    minimizeBtn.TextColor3 = Color3.fromRGB(150, 150, 155)
    minimizeBtn.TextSize = 14
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.Parent = controlsFrame

    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 6)
    minimizeCorner.Parent = minimizeBtn

    -- Close button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 30, 0, 30)
    closeButton.Position = UDim2.new(0, 36, 0, 0)
    closeButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    closeButton.Text = "×"
    closeButton.TextColor3 = Color3.fromRGB(150, 150, 155)
    closeButton.TextSize = 20
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Parent = controlsFrame

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeButton

    -- Hover effects
    closeButton.MouseEnter:Connect(function()
        closeButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)
    closeButton.MouseLeave:Connect(function()
        closeButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        closeButton.TextColor3 = Color3.fromRGB(150, 150, 155)
    end)

    minimizeBtn.MouseEnter:Connect(function()
        minimizeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
        minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)
    minimizeBtn.MouseLeave:Connect(function()
        minimizeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        minimizeBtn.TextColor3 = Color3.fromRGB(150, 150, 155)
    end)

    -- Content area
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, -24, 1, -100)
    contentFrame.Position = UDim2.new(0, 12, 0, 50)
    contentFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 21)
    contentFrame.BorderSizePixel = 0
    contentFrame.Parent = mainFrame

    local contentCorner = Instance.new("UICorner")
    contentCorner.CornerRadius = UDim.new(0, 8)
    contentCorner.Parent = contentFrame

    -- Scrolling frame for logs
    local scrollingFrame = Instance.new("ScrollingFrame")
    scrollingFrame.Name = "ScrollingFrame"
    scrollingFrame.Size = UDim2.new(1, -16, 1, -16)
    scrollingFrame.Position = UDim2.new(0, 8, 0, 8)
    scrollingFrame.BackgroundTransparency = 1
    scrollingFrame.BorderSizePixel = 0
    scrollingFrame.ScrollBarThickness = 4
    scrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 85)
    scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollingFrame.ScrollBarImageTransparency = 0.3
    scrollingFrame.Parent = contentFrame

    -- Log label
    local logLabel = Instance.new("TextLabel")
    logLabel.Name = "LogLabel"
    logLabel.Size = UDim2.new(1, -8, 0, 0)
    logLabel.Position = UDim2.new(0, 0, 0, 0)
    logLabel.BackgroundTransparency = 1
    logLabel.Text = "Waiting for logs..."
    logLabel.TextColor3 = Color3.fromRGB(140, 140, 145)
    logLabel.TextSize = 11
    logLabel.TextWrapped = true
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.Font = Enum.Font.Code
    logLabel.AutomaticSize = Enum.AutomaticSize.Y
    logLabel.RichText = true
    logLabel.Parent = scrollingFrame

    -- Button container
    local buttonFrame = Instance.new("Frame")
    buttonFrame.Name = "ButtonFrame"
    buttonFrame.Size = UDim2.new(1, -24, 0, 36)
    buttonFrame.Position = UDim2.new(0, 12, 1, -46)
    buttonFrame.BackgroundTransparency = 1
    buttonFrame.Parent = mainFrame

    -- Copy button
    local copyButton = Instance.new("TextButton")
    copyButton.Name = "CopyButton"
    copyButton.Size = UDim2.new(0.5, -6, 1, 0)
    copyButton.Position = UDim2.new(0, 0, 0, 0)
    copyButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    copyButton.Text = "Copy Logs"
    copyButton.TextColor3 = Color3.fromRGB(200, 200, 205)
    copyButton.TextSize = 12
    copyButton.Font = Enum.Font.GothamMedium
    copyButton.Parent = buttonFrame

    local copyCorner = Instance.new("UICorner")
    copyCorner.CornerRadius = UDim.new(0, 8)
    copyCorner.Parent = copyButton

    -- Clear button
    local clearButton = Instance.new("TextButton")
    clearButton.Name = "ClearButton"
    clearButton.Size = UDim2.new(0.5, -6, 1, 0)
    clearButton.Position = UDim2.new(0.5, 6, 0, 0)
    clearButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    clearButton.Text = "Clear Logs"
    clearButton.TextColor3 = Color3.fromRGB(200, 200, 205)
    clearButton.TextSize = 12
    clearButton.Font = Enum.Font.GothamMedium
    clearButton.Parent = buttonFrame

    local clearCorner = Instance.new("UICorner")
    clearCorner.CornerRadius = UDim.new(0, 8)
    clearCorner.Parent = clearButton

    -- Button hover effects
    copyButton.MouseEnter:Connect(function()
        copyButton.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    end)
    copyButton.MouseLeave:Connect(function()
        copyButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    end)

    clearButton.MouseEnter:Connect(function()
        clearButton.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    end)
    clearButton.MouseLeave:Connect(function()
        clearButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    end)

    -- Dragging functionality
    local dragging = false
    local dragStart = nil
    local startPos = nil

    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)

    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- Minimize functionality (collapse to title bar only)
    local isMinimized = false
    local originalSize = mainFrame.Size

    minimizeBtn.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        if isMinimized then
            mainFrame.Size = UDim2.new(0, 500, 0, 45)
            contentFrame.Visible = false
            buttonFrame.Visible = false
            separator.Visible = false
        else
            mainFrame.Size = originalSize
            contentFrame.Visible = true
            buttonFrame.Visible = true
            separator.Visible = true
        end
    end)

    -- Close functionality
    closeButton.MouseButton1Click:Connect(function()
        mainFrame.Visible = false
        if DebugToggleRef then
            DebugToggleRef:Set(false)
        end
    end)

    -- Copy logs
    copyButton.MouseButton1Click:Connect(function()
        local allLogs = table.concat(DebugLogs, "\n")
        if allLogs == "" then
            allLogs = "No logs to copy."
        end
        local success, err = pcall(function()
            setclipboard(allLogs)
        end)
        if success then
            copyButton.Text = "Copied!"
            copyButton.TextColor3 = Color3.fromRGB(100, 200, 100)
            task.delay(1.5, function()
                copyButton.Text = "Copy Logs"
                copyButton.TextColor3 = Color3.fromRGB(200, 200, 205)
            end)
            addDebugLog("Logs copied to clipboard!", "SUCCESS")
        else
            addDebugLog("Failed to copy: " .. tostring(err), "ERROR")
        end
    end)

    -- Clear logs
    clearButton.MouseButton1Click:Connect(function()
        DebugLogs = {}
        logLabel.Text = "<font color=\"rgb(100,100,105)\">Logs cleared.</font>"
        scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        scrollingFrame.CanvasPosition = Vector2.new(0, 0)
        task.wait(0.1)
        addDebugLog("Debug console ready.", "INFO")
    end)

    DebugScreen = mainFrame
    DebugLogLabel = logLabel
    DebugScrollingFrame = scrollingFrame

    return mainFrame, screenGui
end

-- Initialize debug screen (called later after UI is ready)
local DebugFrame, DebugGui

-- Override print/warn for debugging
local originalPrint = print
local originalWarn = warn

function print(...)
    local args = {...}
    local message = table.concat(args, " ")
    addDebugLog(message, "INFO")
    originalPrint(...)
end

function warn(...)
    local args = {...}
    local message = table.concat(args, " ")
    addDebugLog(message, "WARN")
    originalWarn(...)
end

-------------------------------------------------
-- UI
-------------------------------------------------

-- Initialize debug screen GUI (only if Debug tab exists)
local DebugFrame, DebugGui
if DebugTab then
    DebugFrame, DebugGui = createDebugScreen()
end

-- Format requirement number for code output
local function formatReqForCode(num)
    if num >= 1e21 then return string.format("%.0fe21", num / 1e21)
    elseif num >= 1e18 then return string.format("%.0fe18", num / 1e18)
    elseif num >= 1e15 then return string.format("%.0fe15", num / 1e15)
    elseif num >= 1e12 then return string.format("%.0fe12", num / 1e12)
    elseif num >= 1e9 then return string.format("%.0fe9", num / 1e9)
    elseif num >= 1e6 then return string.format("%.0fe6", num / 1e6)
    elseif num >= 1e3 then return string.format("%.0fe3", num / 1e3)
    else return string.format("%.0f", num)
    end
end


-- DEBUG TAB UI (only if DebugTab exists)
if DebugTab then
    DebugTab:AddSection("Console")
    local debugToggle = DebugTab:AddToggle("Show Debug Console", {}, function(v)
        if not v then
            DebugFrame.Visible = false
            return
        end
        
        DebugFrame.Visible = v
        if v then
            if DebugLogLabel then
                local coloredLines = {}
                for _, log in ipairs(DebugLogs) do
                    local logTypeMatch = log:match("%[%d+:%d+:%d+%] %[(%w+)%]")
                    local color = LogColors[logTypeMatch] or LogColors.INFO
                    table.insert(coloredLines, string.format('<font color="%s">%s</font>', color, log))
                end
                DebugLogLabel.Text = table.concat(coloredLines, "\n")
                task.spawn(function()
                    task.wait(0.05)
                    if DebugLogLabel and DebugScrollingFrame then
                        local labelHeight = DebugLogLabel.AbsoluteSize.Y
                        DebugScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, labelHeight + 20)
                        DebugScrollingFrame.CanvasPosition = Vector2.new(0, labelHeight)
                    end
                end)
            end
            addDebugLog("Debug console opened.", "INFO")
        end
    end)
    DebugToggleRef = debugToggle

    DebugTab:AddSection("Scan")
    DebugTab:AddButton("Scan World", function()
        local hrp = getHRP()
        local startCF = hrp.CFrame

        -- Temporary storage for scanned areas
        local ScannedAreas = {
            [1] = {}, -- Strength
            [2] = {}, -- Durability
            [3] = {}, -- Chakra
            [5] = {}, -- Agility
            [6] = {}, -- Speed
        }
        local ScannedPads = {}

        IsScanningWorld = true
        addDebugLog("World scan started...", "INFO")

        -- Count models
        local itemCount = 0
        for _, obj in ipairs(MapAreas:GetChildren()) do
            if obj:IsA("Model") then
                itemCount = itemCount + 1
            end
        end
        local estimatedDuration = math.max(2, (itemCount * 0.3) + 1) + 1

        UI.Loading({
            Title = "Scanning World",
            Subtitle = "Discovering training areas...",
            Duration = estimatedDuration,
            Fullscreen = true
        })

        -- TP to all models in MapAreas
        for _, obj in ipairs(MapAreas:GetChildren()) do
            if obj:IsA("Model") then
                hrp.CFrame = obj:GetPivot() + Vector3.new(0, 10, 0)
                task.wait(0.3)
            end
        end

        -- Parse all pads in ScriptableAreas
        for _, pad in ipairs(ScriptableAreas:GetChildren()) do
            if not ScannedPads[pad] then
                ScannedPads[pad] = true

                local stat, req
                for _, d in ipairs(pad:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        local t = d.Text:lower()
                        if t:find("strength") then stat = 1 end
                        if t:find("durability") then stat = 2 end
                        if t:find("chakra") then stat = 3 end
                        if t:find("agility") then stat = 5 end
                        if t:find("speed") then stat = 6 end
                        if t:match("%d") then
                            local parsed = parseNumber(t)
                            if parsed and parsed > 0 then
                                if not req or parsed > req then
                                    req = parsed
                                end
                            end
                        end
                    end
                end

                if stat and req and ScannedAreas[stat] then
                    local padCFrame
                    if pad:IsA("Part") then
                        padCFrame = pad.CFrame
                    elseif pad:IsA("Model") then
                        local part = pad:FindFirstChildOfClass("Part")
                        if part then
                            padCFrame = part.CFrame
                        else
                            padCFrame = pad:GetPivot()
                        end
                    elseif pad:IsA("BasePart") then
                        padCFrame = pad.CFrame
                    end

                    if padCFrame then
                        -- Check for duplicates
                        local exists = false
                        for _, a in ipairs(ScannedAreas[stat]) do
                            if a.Req == req then exists = true; break end
                        end
                        if not exists then
                            table.insert(ScannedAreas[stat], { Req = req, CFrame = padCFrame })
                        end
                    end
                end
            end
        end

        -- Scan Chikara locations
        local ScannedChikara = {}

        for _, crate in ipairs(ChikaraFolder:GetChildren()) do
            if crate.Name == "ChikaraCrate" then
                local root = crate:FindFirstChildWhichIsA("BasePart")
                if root then
                    table.insert(ScannedChikara, {
                        CFrame = root.CFrame
                    })
                end
            end
        end

        -- Scan teleports (Gachas, Champions, Specials, Quests)
        local ScannedTeleports = {
            Gachas = {},
            Champions = {},
            Specials = {},
            Quests = {},
        }

        -- Scan Gachas
        for _, gacha in ipairs(GachaFolder:GetChildren()) do
            if gacha:IsA("Model") then
                local root = gacha:FindFirstChildWhichIsA("BasePart")
                if root then
                    table.insert(ScannedTeleports.Gachas, {
                        Name = gacha.Name,
                        CFrame = root.CFrame + Vector3.new(0, 0, 4)
                    })
                end
            end
        end

        -- Scan Champions
        for _, championFolder in ipairs(ChampionsFolder:GetChildren()) do
            if championFolder:IsA("Folder") then
                for _, champion in ipairs(championFolder:GetChildren()) do
                    if champion:IsA("Model") then
                        local root = champion:FindFirstChildWhichIsA("BasePart")
                        if root then
                            table.insert(ScannedTeleports.Champions, {
                                Name = champion.Name,
                                CFrame = root.CFrame + Vector3.new(0, 0, 4)
                            })
                        end
                    end
                end
            elseif championFolder:IsA("Model") then
                local root = championFolder:FindFirstChildWhichIsA("BasePart")
                if root then
                    table.insert(ScannedTeleports.Champions, {
                        Name = championFolder.Name,
                        CFrame = root.CFrame + Vector3.new(0, 0, 4)
                    })
                end
            end
        end

        -- Scan Specials
        for _, specialFolder in ipairs(SpecialFolder:GetChildren()) do
            if specialFolder:IsA("Folder") then
                local model = nil
                for _, child in ipairs(specialFolder:GetChildren()) do
                    if child:IsA("Model") then
                        model = child
                        break
                    end
                end
                if model then
                    local root = model:FindFirstChildWhichIsA("BasePart")
                    if root then
                        table.insert(ScannedTeleports.Specials, {
                            Name = specialFolder.Name,
                            CFrame = root.CFrame + Vector3.new(0, 0, 4)
                        })
                    end
                end
            end
        end

        -- Scan Quests
        for _, npc in ipairs(QuestFolder:GetChildren()) do
            if npc:IsA("Model") then
                local root = npc:FindFirstChildWhichIsA("BasePart")
                if root then
                    table.insert(ScannedTeleports.Quests, {
                        Name = npc.Name,
                        CFrame = root.CFrame + Vector3.new(0, 0, 4)
                    })
                end
            end
        end

        IsScanningWorld = false
        hrp.CFrame = startCF

        -- Sort all scanned areas
        for stat, areas in pairs(ScannedAreas) do
            table.sort(areas, function(a, b) return a.Req < b.Req end)
        end

        -- Generate copy-paste ready code
        local statNames = {
            [1] = "Strength",
            [2] = "Durability",
            [3] = "Chakra",
            [5] = "Agility",
            [6] = "Speed",
        }

        -- Match scanned areas with hardcoded areas to assign indices
        local IndexedAreas = {}
        local newAreasCount = 0
        for _, stat in ipairs({1, 2, 3, 5, 6}) do
            IndexedAreas[stat] = {}
            
            -- Get hardcoded areas for this stat
            local hardcodedAreas = Areas[stat] or {}
            local lastIndex = 0
            
            -- Find the last index from hardcoded areas
            for _, hardcodedArea in ipairs(hardcodedAreas) do
                if hardcodedArea.Index and hardcodedArea.Index > lastIndex then
                    lastIndex = hardcodedArea.Index
                end
            end
            
            -- Process scanned areas - match with hardcoded or assign new index
            local scannedAreas = ScannedAreas[stat] or {}
            for _, scannedArea in ipairs(scannedAreas) do
                local matchedIndex = nil
                
                -- Try to find matching hardcoded area by Req value (exact match)
                for _, hardcodedArea in ipairs(hardcodedAreas) do
                    if hardcodedArea.Req == scannedArea.Req then
                        matchedIndex = hardcodedArea.Index
                        break
                    end
                end
                
                -- If no match found, it's a new area - assign next index
                if not matchedIndex then
                    lastIndex = lastIndex + 1
                    matchedIndex = lastIndex
                    newAreasCount = newAreasCount + 1
                end
                
                -- Add to indexed areas (only what was scanned)
                table.insert(IndexedAreas[stat], {
                    Index = matchedIndex,
                    Req = scannedArea.Req,
                    CFrame = scannedArea.CFrame
                })
            end
            
            -- Sort by Req
            table.sort(IndexedAreas[stat], function(a, b) return a.Req < b.Req end)
        end

        -- Match scanned chikara with hardcoded chikara to assign indices
        local IndexedChikara = {}
        local newChikaraCount = 0
        local lastChikaraIndex = 0

        -- Find the last index from hardcoded chikara
        for _, hardcodedChikara in ipairs(Chikara) do
            if hardcodedChikara.Index and hardcodedChikara.Index > lastChikaraIndex then
                lastChikaraIndex = hardcodedChikara.Index
            end
        end

        -- Process scanned chikara - match with hardcoded by exact CFrame or assign new index
        for _, scannedChikara in ipairs(ScannedChikara) do
            local matchedIndex = nil
            local scanCF = scannedChikara.CFrame

            -- Try to find matching hardcoded chikara by exact CFrame match
            for _, hardcodedChikara in ipairs(Chikara) do
                local hardcodedCF = hardcodedChikara.CFrame
                -- Compare position components (exact match)
                if math.floor(scanCF.Position.X) == math.floor(hardcodedCF.Position.X) and
                   math.floor(scanCF.Position.Y) == math.floor(hardcodedCF.Position.Y) and
                   math.floor(scanCF.Position.Z) == math.floor(hardcodedCF.Position.Z) then
                    matchedIndex = hardcodedChikara.Index
                    break
                end
            end

            -- If no match found, it's a new chikara location - assign next index
            if not matchedIndex then
                lastChikaraIndex = lastChikaraIndex + 1
                matchedIndex = lastChikaraIndex
                newChikaraCount = newChikaraCount + 1
            end

            -- Add to indexed chikara (only what was scanned)
            table.insert(IndexedChikara, {
                Index = matchedIndex,
                CFrame = scannedChikara.CFrame
            })
        end

        -- Sort by index
        table.sort(IndexedChikara, function(a, b) return a.Index < b.Index end)

        -- Match scanned teleports with hardcoded teleports to assign indices
        local IndexedTeleports = {
            Gachas = {},
            Champions = {},
            Specials = {},
            Quests = {},
        }
        local newTeleportsCount = 0

        for category, scannedList in pairs(ScannedTeleports) do
            local hardcodedList = Teleports[category] or {}
            local lastIndex = 0

            -- Find the last index from hardcoded teleports
            for _, hardcodedTeleport in ipairs(hardcodedList) do
                if hardcodedTeleport.Index and hardcodedTeleport.Index > lastIndex then
                    lastIndex = hardcodedTeleport.Index
                end
            end

            -- Process scanned teleports - match with hardcoded or assign new index
            for _, scannedTeleport in ipairs(scannedList) do
                local matchedIndex = nil

                -- Try to find matching hardcoded teleport by Name (exact match)
                for _, hardcodedTeleport in ipairs(hardcodedList) do
                    if hardcodedTeleport.Name == scannedTeleport.Name then
                        matchedIndex = hardcodedTeleport.Index
                        break
                    end
                end

                -- If no match found, it's a new teleport - assign next index
                if not matchedIndex then
                    lastIndex = lastIndex + 1
                    matchedIndex = lastIndex
                    newTeleportsCount = newTeleportsCount + 1
                end

                -- Add to indexed teleports (only what was scanned)
                table.insert(IndexedTeleports[category], {
                    Index = matchedIndex,
                    Name = scannedTeleport.Name,
                    CFrame = scannedTeleport.CFrame
                })
            end
        end

        -- Generate Areas table code
        local codeLines = {"local Areas = {"}
        for _, stat in ipairs({1, 2, 3, 5, 6}) do
            local areas = IndexedAreas[stat]
            if areas and #areas > 0 then
                table.insert(codeLines, string.format("    [%d] = { -- %s", stat, statNames[stat]))
                for _, area in ipairs(areas) do
                    local cf = area.CFrame
                    table.insert(codeLines, string.format("        {Index = %d, Req = %s, CFrame = CFrame.new(%d, %d, %d) },",
                        area.Index,
                        formatReqForCode(area.Req),
                        math.floor(cf.Position.X), math.floor(cf.Position.Y), math.floor(cf.Position.Z)))
                end
                table.insert(codeLines, "    },")
            end
        end
        table.insert(codeLines, "}")
        table.insert(codeLines, "")

        -- Generate Chikara table code
        table.insert(codeLines, "local Chikara = {")
        for _, chikara in ipairs(IndexedChikara) do
            local cf = chikara.CFrame
            table.insert(codeLines, string.format("    {Index = %d, CFrame = CFrame.new(%d, %d, %d) },",
                chikara.Index,
                math.floor(cf.Position.X), math.floor(cf.Position.Y), math.floor(cf.Position.Z)))
        end
        table.insert(codeLines, "}")
        table.insert(codeLines, "")

        -- Generate Teleports table code
        table.insert(codeLines, "local Teleports = {")
        for _, category in ipairs({"Gachas", "Champions", "Specials", "Quests"}) do
            local teleports = IndexedTeleports[category]
            if teleports and #teleports > 0 then
                table.insert(codeLines, string.format("    %s = {", category))
                for _, teleport in ipairs(teleports) do
                    local cf = teleport.CFrame
                    table.insert(codeLines, string.format("        {Index = %d, Name = \"%s\", CFrame = CFrame.new(%d, %d, %d) },",
                        teleport.Index,
                        teleport.Name,
                        math.floor(cf.Position.X), math.floor(cf.Position.Y), math.floor(cf.Position.Z)))
                end
                table.insert(codeLines, "    },")
            end
        end
        table.insert(codeLines, "}")

        local codeOutput = table.concat(codeLines, "\n")

        -- Copy to clipboard
        local success, err = pcall(function()
            setclipboard(codeOutput)
        end)

        if success then
            local totalAreas = #IndexedAreas[1] + #IndexedAreas[2] + #IndexedAreas[3] + #IndexedAreas[5] + #IndexedAreas[6]
            local totalTeleports = #IndexedTeleports.Gachas + #IndexedTeleports.Champions + #IndexedTeleports.Specials + #IndexedTeleports.Quests
            addDebugLog("Scan complete! Code copied to clipboard.", "SUCCESS")
            addDebugLog(string.format("Scanned %d areas (%d new), %d chikara (%d new), and %d teleports (%d new)",
                totalAreas, newAreasCount, #IndexedChikara, newChikaraCount, totalTeleports, newTeleportsCount), "INFO")
        else
            addDebugLog("Scan complete but failed to copy: " .. tostring(err), "ERROR")
            -- Still output to debug console
            addDebugLog("=== GENERATED CODE ===", "INFO")
            for _, line in ipairs(codeLines) do
                addDebugLog(line, "INFO")
            end
            addDebugLog("=== END CODE ===", "INFO")
        end
    end)
end

addDebugLog("Debug system initialized.", "INFO")

TrainingTab:AddSection("Auto Train")

-- Store toggle references for auto quest override
local TrainingToggles = {}

for stat, name in pairs({
    [1]="Strength",[2]="Durability",[3]="Chakra",
    [4]="Sword",[5]="Agility",[6]="Speed"
}) do
    local toggle = TrainingTab:AddToggle(name, {}, function(v)
        -- Don't allow manual toggles when auto quest is active
        if QuestFlags.AutoQuest then
            addDebugLog("Auto Quest is active - manual training toggles disabled", "WARN")
            return
        end
        Flags[stat] = v
        if v then
            tpToBest(stat)
        end
    end)
    TrainingToggles[stat] = toggle
end

MiscTab:AddSection("Auto Collect")
MiscTab:AddToggle("Auto Collect Chikara", {}, function(v)
    MiscFlags.AutoChikara = v
end)

MiscTab:AddToggle("Auto Pick Up Fruit", {}, function(v)
    MiscFlags.AutoPickupFruit = v
end)

MiscTab:AddSection("Auto Skill")
MiscTab:AddInput("Skill Keys", function(text)
    -- Parse comma-separated keys like "t,r,q" or "t, r, q"
    local keys = {}
    for key in string.gmatch(text, "[^,]+") do
        key = key:match("^%s*(.-)%s*$") -- Trim whitespace
        if key and #key > 0 then
            table.insert(keys, key)
        end
    end
    MiscFlags.AutoSkillKeys = keys
    if #keys > 0 then
        addDebugLog("Auto Skill: Keys set to: " .. table.concat(keys, ", "), "INFO")
    else
        addDebugLog("Auto Skill: Keys cleared", "INFO")
    end
end)

MiscTab:AddToggle("Auto Skill", {}, function(v)
    MiscFlags.AutoSkillEnabled = v
    if v then
        if #MiscFlags.AutoSkillKeys == 0 then
            addDebugLog("Auto Skill enabled but no keys set! Enter keys above (e.g., t,r,q)", "WARN")
        else
            addDebugLog("Auto Skill enabled - spamming keys: " .. table.concat(MiscFlags.AutoSkillKeys, ", "), "INFO")
        end
    else
        addDebugLog("Auto Skill disabled", "INFO")
    end
end)

QuestTab:AddSection("Auto Quest (GainStat / GainIncrement)")
QuestTab:AddDropdown("Quest NPC", QuestDropdownOptions, function(v)
    addDebugLog("Dropdown callback fired with value: " .. tostring(v), "INFO")
    if v ~= QuestFlags.SelectedQuest then
        addDebugLog("Quest selection changed from " .. tostring(QuestFlags.SelectedQuest) .. " to " .. tostring(v), "INFO")
        QuestFlags.SelectedQuest = v
        -- Reset current quest when selection changes
        cleanupQuestConnections()
        CurrentQuest = nil
        CurrentQuestType = nil
        -- Disable all auto-quest enabled stats when switching quests
        for stat, _ in pairs(AutoQuestEnabledStats) do
            if Flags[stat] then
                Flags[stat] = false
            end
            AutoQuestEnabledStats[stat] = nil
        end
        addDebugLog("Quest selection changed to: " .. v .. " (Previous quest cleared)", "INFO")
        -- Force immediate re-check
        ForceQuestRecheck = true
    else
        addDebugLog("Dropdown value same as current: " .. tostring(v), "INFO")
    end
end)

QuestTab:AddToggle("Auto Quest", {}, function(v)
    QuestFlags.AutoQuest = v
    if v then
        -- Store original state and disable all manual training
        for stat = 1, 6 do
            OriginalFlagsState[stat] = Flags[stat]
            Flags[stat] = false
        end
        addDebugLog("Auto Quest enabled for: " .. QuestFlags.SelectedQuest .. " - Manual training disabled", "INFO")
    else
        -- Unequip weapon if one is equipped
        if CurrentEquippedWeapon then
            unequipWeapon()
        end
        
        -- Restore original state and disable all auto-quest enabled stats
        for stat, _ in pairs(AutoQuestEnabledStats) do
            Flags[stat] = false
            AutoQuestEnabledStats[stat] = nil
        end
        -- Restore original Flags state
        for stat = 1, 6 do
            if OriginalFlagsState[stat] ~= nil then
                Flags[stat] = OriginalFlagsState[stat]
            end
        end
        OriginalFlagsState = {}
        addDebugLog("Auto Quest disabled - Manual training restored", "INFO")
    end
end)

-------------------------------------------------
-- KILL QUEST SETTINGS (for KillPlayer quest type)
-------------------------------------------------

QuestTab:AddSection("Kill Quest Settings")

QuestTab:AddSlider("Power Threshold %", {
    Min = 10,
    Max = 100,
    Default = 50
}, function(v)
    QuestFlags.PowerThreshold = v
    local myPower = getLocalPlayerPower()
    local threshold = myPower * (v / 100)
    addDebugLog("Kill Quest: Targeting players below " .. formatNumber(threshold) .. " power (" .. v .. "% of yours)", "INFO")
end)

QuestTab:AddDropdown("Farm Method", {"Fist", "Sword"}, function(v)
    QuestFlags.FarmMethod = v
    -- Reset equipped weapon so it re-equips with new method
    CurrentEquippedWeapon = nil
    addDebugLog("Kill Quest: Farm method set to " .. v, "INFO")
end)

-------------------------------------------------
-- INIT
-------------------------------------------------

-- Count loaded areas
local totalAreas = 0
for _, areas in pairs(Areas) do
    totalAreas = totalAreas + #areas
end
addDebugLog(string.format("Loaded %d hardcoded areas.", totalAreas), "SUCCESS")

-- Count loaded teleports
local totalTeleports = #Teleports.Gachas + #Teleports.Champions + #Teleports.Specials + #Teleports.Quests
addDebugLog(string.format("Loaded %d hardcoded teleports.", totalTeleports), "SUCCESS")

-- Count loaded chikara
addDebugLog(string.format("Loaded %d hardcoded chikara locations.", #Chikara), "SUCCESS")

-- Initialize: TP to all teleports and chikara locations
task.spawn(function()
    local hrp = getHRP()
    local originalPos = hrp.CFrame
    
    -- Show loading screen
    UI.Loading({
        Title = "Initializing",
        Subtitle = "Discovering locations...",
        Duration = 5,
        Fullscreen = true
    })
    
    -- TP to all teleports
    for _, gacha in ipairs(Teleports.Gachas) do
        hrp.CFrame = gacha.CFrame
        task.wait(0.05)
    end
    
    for _, champion in ipairs(Teleports.Champions) do
        hrp.CFrame = champion.CFrame
        task.wait(0.05)
    end
    
    for _, special in ipairs(Teleports.Specials) do
        hrp.CFrame = special.CFrame
        task.wait(0.05)
    end
    
    for _, quest in ipairs(Teleports.Quests) do
        hrp.CFrame = quest.CFrame
        task.wait(0.05)
    end
    
    -- TP to all chikara locations
    for _, chikaraLoc in ipairs(Chikara) do
        hrp.CFrame = chikaraLoc.CFrame
        task.wait(0.05)
    end
    
    -- Return to original position
    hrp.CFrame = originalPos
end)

-- Create UI buttons from hardcoded Teleports data
-- Gachas
TeleportsTab:AddSection("Gachas")
for _, gacha in ipairs(Teleports.Gachas) do
    local displayName = GachaNameMap[gacha.Name] or gacha.Name
    TeleportsTab:AddButton(displayName, function()
        local fired = false
        
        -- First try: Fire without teleporting
        for _, npc in ipairs(GachaFolder:GetChildren()) do
            if npc:IsA("Model") and npc.Name == gacha.Name then
                local clickBox = npc:FindFirstChild("ClickBox")
                if clickBox then
                    local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                    if cd then
                        fireclickdetector(cd)
                        fired = true
                        break
                    end
                end
            end
        end
        
        -- If not fired, teleport and try again
        if not fired then
            local hrp = getHRP()
            hrp.CFrame = gacha.CFrame
            task.wait(0.2)
            -- Keep searching until found and fired
            while not fired do
                for _, npc in ipairs(GachaFolder:GetChildren()) do
                    if npc:IsA("Model") and npc.Name == gacha.Name then
                        local clickBox = npc:FindFirstChild("ClickBox")
                        if clickBox then
                            local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                            if cd then
                                fireclickdetector(cd)
                                fired = true
                                break
                            end
                        end
                    end
                end
                if not fired then
                    task.wait(0.1)
                end
            end
        end
    end)
end

-- Champions
TeleportsTab:AddSection("Champions")
for _, champion in ipairs(Teleports.Champions) do
    TeleportsTab:AddButton(champion.Name, function()
        local fired = false
        
        -- First try: Fire without teleporting
        for _, championFolder in ipairs(ChampionsFolder:GetChildren()) do
            local npc = nil
            if championFolder:IsA("Folder") then
                for _, child in ipairs(championFolder:GetChildren()) do
                    if child:IsA("Model") and child.Name == champion.Name then
                        npc = child
                        break
                    end
                end
            elseif championFolder:IsA("Model") and championFolder.Name == champion.Name then
                npc = championFolder
            end
            if npc then
                local clickBox = npc:FindFirstChild("ClickBox")
                if clickBox then
                    local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                    if cd then
                        fireclickdetector(cd)
                        fired = true
                        break
                    end
                end
            end
        end
        
        -- If not fired, teleport and try again
        if not fired then
            local hrp = getHRP()
            hrp.CFrame = champion.CFrame
            task.wait(0.2)
            -- Keep searching until found and fired
            while not fired do
                for _, championFolder in ipairs(ChampionsFolder:GetChildren()) do
                    local npc = nil
                    if championFolder:IsA("Folder") then
                        for _, child in ipairs(championFolder:GetChildren()) do
                            if child:IsA("Model") and child.Name == champion.Name then
                                npc = child
                                break
                            end
                        end
                    elseif championFolder:IsA("Model") and championFolder.Name == champion.Name then
                        npc = championFolder
                    end
                    if npc then
                        local clickBox = npc:FindFirstChild("ClickBox")
                        if clickBox then
                            local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                            if cd then
                                fireclickdetector(cd)
                                fired = true
                                break
                            end
                        end
                    end
                end
                if not fired then
                    task.wait(0.1)
                end
            end
        end
    end)
end

-- Specials
TeleportsTab:AddSection("Specials")
for _, special in ipairs(Teleports.Specials) do
    TeleportsTab:AddButton(special.Name, function()
        local fired = false
        
        -- First try: Fire without teleporting
        for _, specialFolder in ipairs(SpecialFolder:GetChildren()) do
            if specialFolder:IsA("Folder") and specialFolder.Name == special.Name then
                for _, child in ipairs(specialFolder:GetChildren()) do
                    if child:IsA("Model") then
                        local clickBox = child:FindFirstChild("ClickBox")
                        if clickBox then
                            local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                            if cd then
                                fireclickdetector(cd)
                                fired = true
                                break
                            end
                        end
                    end
                end
                if fired then break end
            end
        end
        
        -- If not fired, teleport and try again
        if not fired then
            local hrp = getHRP()
            hrp.CFrame = special.CFrame
            task.wait(0.2)
            -- Keep searching until found and fired
            while not fired do
                for _, specialFolder in ipairs(SpecialFolder:GetChildren()) do
                    if specialFolder:IsA("Folder") and specialFolder.Name == special.Name then
                        for _, child in ipairs(specialFolder:GetChildren()) do
                            if child:IsA("Model") then
                                local clickBox = child:FindFirstChild("ClickBox")
                                if clickBox then
                                    local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                                    if cd then
                                        fireclickdetector(cd)
                                        fired = true
                                        break
                                    end
                                end
                            end
                        end
                        if fired then break end
                    end
                end
                if not fired then
                    task.wait(0.1)
                end
            end
        end
    end)
end

-- Quests
TeleportsTab:AddSection("Quests")
for _, quest in ipairs(Teleports.Quests) do
    TeleportsTab:AddButton(quest.Name, function()
        local fired = false
        
        -- First try: Fire without teleporting
        for _, npc in ipairs(QuestFolder:GetChildren()) do
            if npc:IsA("Model") and npc.Name == quest.Name then
                local clickBox = npc:FindFirstChild("ClickBox")
                if clickBox then
                    local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                    if cd then
                        fireclickdetector(cd)
                        fired = true
                        break
                    end
                end
            end
        end
        
        -- If not fired, teleport and try again
        if not fired then
            local hrp = getHRP()
            hrp.CFrame = quest.CFrame
            task.wait(0.2)
            -- Keep searching until found and fired
            while not fired do
                for _, npc in ipairs(QuestFolder:GetChildren()) do
                    if npc:IsA("Model") and npc.Name == quest.Name then
                        local clickBox = npc:FindFirstChild("ClickBox")
                        if clickBox then
                            local cd = clickBox:FindFirstChildOfClass("ClickDetector")
                            if cd then
                                fireclickdetector(cd)
                                fired = true
                                break
                            end
                        end
                    end
                end
                if not fired then
                    task.wait(0.1)
                end
            end
        end
    end)
end

-- UI.Corner("AFSE READY", "World scanned. Smart training active.", 5, UI.Icons.Success)

if UI.IsMobile then
    UI.MobileToggle({ Window = Window })
end
