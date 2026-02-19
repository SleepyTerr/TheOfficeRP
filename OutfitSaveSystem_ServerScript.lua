--[[
    ╔══════════════════════════════════════════════════════════╗
    ║         OUTFIT SAVE SYSTEM — Server Script               ║
    ║  Place inside: ServerScriptService                       ║
    ║  (as a regular Script, NOT a LocalScript)                ║
    ╚══════════════════════════════════════════════════════════╝

    This script:
    - Saves player outfit slots to DataStore (persists between sessions)
    - Handles RemoteEvents from the client (save, load, list outfits)
    - Each player gets up to MAX_SLOTS outfit slots (Work, Home, etc.)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")

-- The DataStore that holds all outfit data
local OutfitStore = DataStoreService:GetDataStore("PlayerOutfits_v1")

-- Max outfit slots per player
local MAX_SLOTS = 6

-- ============================================================
--  REMOTE EVENTS SETUP
--  These let the client (LocalScript) talk to this server script
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create a folder to hold our RemoteEvents neatly
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "OutfitRemotes"
remoteFolder.Parent = ReplicatedStorage

-- Client → Server: Save current outfit to a slot
local SaveOutfitEvent = Instance.new("RemoteEvent")
SaveOutfitEvent.Name = "SaveOutfit"
SaveOutfitEvent.Parent = remoteFolder

-- Client → Server (with response): Load an outfit slot
local LoadOutfitFunc = Instance.new("RemoteFunction")
LoadOutfitFunc.Name = "LoadOutfit"
LoadOutfitFunc.Parent = remoteFolder

-- Client → Server (with response): Get all saved outfit slots
local GetOutfitsFunc = Instance.new("RemoteFunction")
GetOutfitsFunc.Name = "GetOutfits"
GetOutfitsFunc.Parent = remoteFolder

-- Client → Server: Delete an outfit slot
local DeleteOutfitEvent = Instance.new("RemoteEvent")
DeleteOutfitEvent.Name = "DeleteOutfit"
DeleteOutfitEvent.Parent = remoteFolder

-- Server → Client: Notify client that save succeeded/failed
local SaveResultEvent = Instance.new("RemoteEvent")
SaveResultEvent.Name = "SaveResult"
SaveResultEvent.Parent = remoteFolder

-- ============================================================
--  HELPER: Build a key for the DataStore
-- ============================================================

local function getKey(userId)
    return "outfits_" .. tostring(userId)
end

-- ============================================================
--  HELPER: Load player data from DataStore (with retry)
-- ============================================================

local function loadPlayerData(userId)
    local key = getKey(userId)
    local success, data = pcall(function()
        return OutfitStore:GetAsync(key)
    end)
    if success then
        return data or {}  -- Return empty table if no data yet
    else
        warn("Failed to load outfit data for " .. userId .. ": " .. tostring(data))
        return {}
    end
end

-- ============================================================
--  HELPER: Save player data to DataStore (with retry)
-- ============================================================

local function savePlayerData(userId, data)
    local key = getKey(userId)
    local success, err = pcall(function()
        OutfitStore:SetAsync(key, data)
    end)
    if not success then
        warn("Failed to save outfit data for " .. userId .. ": " .. tostring(err))
    end
    return success
end

-- ============================================================
--  HELPER: Snapshot a player's current appearance
--  Returns a table describing all equipped items
-- ============================================================

local function captureOutfit(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local snapshot = {
        shirt        = nil,
        pants        = nil,
        accessories  = {},
        description  = nil,
    }

    -- Capture shirt
    local shirt = character:FindFirstChildOfClass("Shirt")
    if shirt then
        snapshot.shirt = shirt.ShirtTemplate
    end

    -- Capture pants
    local pants = character:FindFirstChildOfClass("Pants")
    if pants then
        snapshot.pants = pants.PantsTemplate
    end

    -- Capture accessories (hats, hair, etc.)
    for _, obj in ipairs(character:GetChildren()) do
        if obj:IsA("Accessory") then
            local handle = obj:FindFirstChild("Handle")
            if handle then
                local mesh = handle:FindFirstChildOfClass("SpecialMesh")
                if mesh and mesh.MeshId ~= "" then
                    table.insert(snapshot.accessories, {
                        name   = obj.Name,
                        meshId = mesh.MeshId,
                        texId  = mesh.TextureId,
                    })
                end
            end
        end
    end

    -- Capture full HumanoidDescription (body colors, face, body parts)
    local success, desc = pcall(function()
        return humanoid:GetAppliedDescription()
    end)
    if success and desc then
        snapshot.description = {
            -- Body colors
            HeadColor         = desc.HeadColor.R .. "," .. desc.HeadColor.G .. "," .. desc.HeadColor.B,
            LeftArmColor      = desc.LeftArmColor.R .. "," .. desc.LeftArmColor.G .. "," .. desc.LeftArmColor.B,
            RightArmColor     = desc.RightArmColor.R .. "," .. desc.RightArmColor.G .. "," .. desc.RightArmColor.B,
            LeftLegColor      = desc.LeftLegColor.R .. "," .. desc.LeftLegColor.G .. "," .. desc.LeftLegColor.B,
            RightLegColor     = desc.RightLegColor.R .. "," .. desc.RightLegColor.G .. "," .. desc.RightLegColor.B,
            TorsoColor        = desc.TorsoColor.R .. "," .. desc.TorsoColor.G .. "," .. desc.TorsoColor.B,
            -- Face & body assets
            Face              = desc.Face,
            Head              = desc.Head,
            Torso             = desc.Torso,
            LeftArm           = desc.LeftArm,
            RightArm          = desc.RightArm,
            LeftLeg           = desc.LeftLeg,
            RightLeg          = desc.RightLeg,
            -- Scale
            HeightScale       = desc.HeightScale,
            WidthScale        = desc.WidthScale,
            HeadScale         = desc.HeadScale,
            DepthScale        = desc.DepthScale,
            ProportionScale   = desc.ProportionScale,
            BodyTypeScale     = desc.BodyTypeScale,
        }
    end

    return snapshot
end

-- ============================================================
--  HELPER: Apply a saved snapshot to a character
-- ============================================================

local function applyOutfit(character, snapshot)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    -- Apply shirt
    if snapshot.shirt then
        local existing = character:FindFirstChildOfClass("Shirt")
        if existing then existing:Destroy() end
        local shirt = Instance.new("Shirt")
        shirt.ShirtTemplate = snapshot.shirt
        shirt.Parent = character
    end

    -- Apply pants
    if snapshot.pants then
        local existing = character:FindFirstChildOfClass("Pants")
        if existing then existing:Destroy() end
        local pants = Instance.new("Pants")
        pants.PantsTemplate = snapshot.pants
        pants.Parent = character
    end

    -- Apply HumanoidDescription (body, face, scale)
    if snapshot.description then
        local d = snapshot.description

        local function parseColor(str)
            if not str then return Color3.new(1,1,1) end
            local r, g, b = str:match("([^,]+),([^,]+),([^,]+)")
            return Color3.new(tonumber(r), tonumber(g), tonumber(b))
        end

        local success, desc = pcall(function()
            return humanoid:GetAppliedDescription()
        end)

        if success and desc then
            desc.HeadColor       = parseColor(d.HeadColor)
            desc.LeftArmColor    = parseColor(d.LeftArmColor)
            desc.RightArmColor   = parseColor(d.RightArmColor)
            desc.LeftLegColor    = parseColor(d.LeftLegColor)
            desc.RightLegColor   = parseColor(d.RightLegColor)
            desc.TorsoColor      = parseColor(d.TorsoColor)

            if d.Face           and d.Face > 0           then desc.Face = d.Face end
            if d.Head           and d.Head > 0           then desc.Head = d.Head end
            if d.Torso          and d.Torso > 0          then desc.Torso = d.Torso end
            if d.LeftArm        and d.LeftArm > 0        then desc.LeftArm = d.LeftArm end
            if d.RightArm       and d.RightArm > 0       then desc.RightArm = d.RightArm end
            if d.LeftLeg        and d.LeftLeg > 0        then desc.LeftLeg = d.LeftLeg end
            if d.RightLeg       and d.RightLeg > 0       then desc.RightLeg = d.RightLeg end

            if d.HeightScale     then desc.HeightScale = d.HeightScale end
            if d.WidthScale      then desc.WidthScale = d.WidthScale end
            if d.HeadScale       then desc.HeadScale = d.HeadScale end
            if d.DepthScale      then desc.DepthScale = d.DepthScale end
            if d.ProportionScale then desc.ProportionScale = d.ProportionScale end
            if d.BodyTypeScale   then desc.BodyTypeScale = d.BodyTypeScale end

            pcall(function() humanoid:ApplyDescription(desc) end)
        end
    end

    return true
end

-- ============================================================
--  REMOTE: Save Outfit
--  Client sends: slotName (string), optional custom name
-- ============================================================

SaveOutfitEvent.OnServerEvent:Connect(function(player, slotName, customName)
    if typeof(slotName) ~= "string" or #slotName == 0 then return end
    slotName = slotName:sub(1, 30)  -- Limit length

    local character = player.Character
    if not character then
        SaveResultEvent:FireClient(player, false, "No character found")
        return
    end

    local snapshot = captureOutfit(character)
    if not snapshot then
        SaveResultEvent:FireClient(player, false, "Could not read outfit")
        return
    end

    -- Load current data, add/update slot, save back
    local data = loadPlayerData(player.UserId)

    -- Count slots
    local slotCount = 0
    for _ in pairs(data) do slotCount += 1 end

    -- Check if this is a new slot and we're at the limit
    if not data[slotName] and slotCount >= MAX_SLOTS then
        SaveResultEvent:FireClient(player, false, "Max outfit slots reached (" .. MAX_SLOTS .. ")")
        return
    end

    data[slotName] = {
        snapshot    = snapshot,
        displayName = customName or slotName,
        savedAt     = os.time(),
    }

    local ok = savePlayerData(player.UserId, data)
    if ok then
        SaveResultEvent:FireClient(player, true, slotName)
        print("[OutfitSystem] Saved outfit '" .. slotName .. "' for " .. player.Name)
    else
        SaveResultEvent:FireClient(player, false, "DataStore error — try again")
    end
end)

-- ============================================================
--  REMOTE: Load Outfit
--  Client sends: slotName
--  Returns: success (bool), message (string)
-- ============================================================

LoadOutfitFunc.OnServerInvoke = function(player, slotName)
    if typeof(slotName) ~= "string" then return false, "Invalid slot name" end

    local data = loadPlayerData(player.UserId)
    local slot = data[slotName]

    if not slot then
        return false, "Outfit slot '" .. slotName .. "' not found"
    end

    local character = player.Character
    if not character then
        return false, "No character"
    end

    local ok = applyOutfit(character, slot.snapshot)
    if ok then
        print("[OutfitSystem] Loaded outfit '" .. slotName .. "' for " .. player.Name)
        return true, "Outfit applied!"
    else
        return false, "Failed to apply outfit"
    end
end

-- ============================================================
--  REMOTE: Get All Outfits
--  Returns: table of { slotName, displayName, savedAt } for this player
-- ============================================================

GetOutfitsFunc.OnServerInvoke = function(player)
    local data = loadPlayerData(player.UserId)
    local result = {}
    for slotName, slotData in pairs(data) do
        table.insert(result, {
            slotName    = slotName,
            displayName = slotData.displayName or slotName,
            savedAt     = slotData.savedAt or 0,
        })
    end
    -- Sort by saved time
    table.sort(result, function(a, b) return a.savedAt < b.savedAt end)
    return result
end

-- ============================================================
--  REMOTE: Delete Outfit
-- ============================================================

DeleteOutfitEvent.OnServerEvent:Connect(function(player, slotName)
    if typeof(slotName) ~= "string" then return end

    local data = loadPlayerData(player.UserId)
    if data[slotName] then
        data[slotName] = nil
        savePlayerData(player.UserId, data)
        print("[OutfitSystem] Deleted outfit '" .. slotName .. "' for " .. player.Name)
    end
end)

-- ============================================================
--  Auto-save on player leave (extra safety)
-- ============================================================

Players.PlayerRemoving:Connect(function(player)
    -- Data is saved immediately on each save action, this is just a log
    print("[OutfitSystem] " .. player.Name .. " left the game.")
end)

print("✅ Outfit Save System loaded!")
