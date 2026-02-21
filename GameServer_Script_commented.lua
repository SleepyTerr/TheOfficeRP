--[[
    ╔══════════════════════════════════════════════════════════╗
    ║         OUTFIT SAVE + CATALOG SEARCH — Server Script     ║
    ║  Place inside: ServerScriptService  (as a Script)        ║
    ╚══════════════════════════════════════════════════════════╝
    
    This script runs on the SERVER only (not the player's computer).
    It handles:
      - Saving and loading player outfits to Roblox's DataStore
      - Searching the Roblox catalog for items
      - Managing each player's bank balance
      - Trying to build a character preview for the wardrobe viewport
]]

-- ============================================================
--  SERVICES
--  These are Roblox's built-in systems we need access to
-- ============================================================

local DataStoreService  = game:GetService("DataStoreService")  -- lets us save data permanently
local Players           = game:GetService("Players")            -- lets us access player info
local HttpService       = game:GetService("HttpService")        -- lets us make web requests (not used much now)
local ReplicatedStorage = game:GetService("ReplicatedStorage")  -- a folder both server and client can see

-- This is where we'll store outfit data permanently
-- "PlayerOutfits_v1" is just the name of the save file — changing it would wipe everyone's outfits
local OutfitStore = DataStoreService:GetDataStore("PlayerOutfits_v1")
local MAX_SLOTS   = 6  -- players can save up to 6 outfits

-- ============================================================
--  REMOTE SETUP
--  Remotes are how the server and client (LocalScript) talk to each other
--  RemoteEvent = one-way message (fire and forget)
--  RemoteFunction = two-way message (ask and wait for answer)
-- ============================================================

-- Create a folder in ReplicatedStorage so the LocalScript can find these remotes
local remoteFolder = Instance.new("Folder")
remoteFolder.Name  = "OutfitRemotes"
remoteFolder.Parent = ReplicatedStorage

-- Helper functions to create remotes quickly
local function makeEvent(name)
    local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = remoteFolder; return e
end
local function makeFunc(name)
    local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = remoteFolder; return f
end

-- Create all the remotes the LocalScript will use
local SaveOutfitEvent       = makeEvent("SaveOutfit")       -- client tells server to save an outfit
local DeleteOutfitEvent     = makeEvent("DeleteOutfit")     -- client tells server to delete an outfit
local SaveResultEvent       = makeEvent("SaveResult")       -- server tells client if save worked
local LoadOutfitFunc        = makeFunc("LoadOutfit")        -- client asks server to apply a saved outfit
local GetOutfitsFunc        = makeFunc("GetOutfits")        -- client asks server for list of saved outfits
local SearchCatalogFunc     = makeFunc("SearchCatalog")     -- client asks server to search the catalog
local GetBalanceFunc        = makeFunc("GetBalance")        -- client asks server for their bank balance
local UpdateBalanceEvent    = makeEvent("UpdateBalance")    -- server tells client their balance changed
local GetCharacterModelFunc = makeFunc("GetCharacterModel") -- client asks server to build avatar preview

-- ============================================================
--  DATASTORE HELPERS
--  Small functions that make saving/loading data easier
-- ============================================================

-- Creates a unique save key for each player using their UserId
-- e.g. player with UserId 12345 gets key "outfits_12345"
local function getKey(userId) return "outfits_" .. tostring(userId) end

-- Loads a player's outfit data from the DataStore
-- pcall means "try this, and if it errors don't crash the whole script"
local function loadData(userId)
    local ok, data = pcall(function() return OutfitStore:GetAsync(getKey(userId)) end)
    return (ok and data) or {}  -- if it fails, return an empty table instead
end

-- Saves a player's outfit data to the DataStore
local function saveData(userId, data)
    local ok, err = pcall(function() OutfitStore:SetAsync(getKey(userId), data) end)
    if not ok then warn("DataStore save error: " .. tostring(err)) end
    return ok
end

-- ============================================================
--  OUTFIT CAPTURE
--  Takes a "snapshot" of what a player is currently wearing
-- ============================================================

local function captureOutfit(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    -- This table will hold everything about the current outfit
    local snapshot = { shirt = nil, pants = nil, accessories = {}, description = nil }

    -- Save the shirt template ID (the texture/design of the shirt)
    local shirt = character:FindFirstChildOfClass("Shirt")
    if shirt then snapshot.shirt = shirt.ShirtTemplate end

    -- Save the pants template ID
    local pants = character:FindFirstChildOfClass("Pants")
    if pants then snapshot.pants = pants.PantsTemplate end

    -- Save all accessories (hats, hair, etc.) — store their mesh and texture IDs
    for _, obj in ipairs(character:GetChildren()) do
        if obj:IsA("Accessory") then
            local handle = obj:FindFirstChild("Handle")
            if handle then
                local mesh = handle:FindFirstChildOfClass("SpecialMesh")
                if mesh and mesh.MeshId ~= "" then
                    table.insert(snapshot.accessories, {
                        name   = obj.Name,
                        meshId = mesh.MeshId,    -- the 3D shape
                        texId  = mesh.TextureId, -- the texture/color
                    })
                end
            end
        end
    end

    -- Save body colors and body shape scales using HumanoidDescription
    local ok, desc = pcall(function() return humanoid:GetAppliedDescription() end)
    if ok and desc then
        -- Convert Color3 to a saveable string like "1,0.5,0.2"
        local function rgb(c) return c.R..","..c.G..","..c.B end
        snapshot.description = {
            HeadColor       = rgb(desc.HeadColor),
            LeftArmColor    = rgb(desc.LeftArmColor),
            RightArmColor   = rgb(desc.RightArmColor),
            LeftLegColor    = rgb(desc.LeftLegColor),
            RightLegColor   = rgb(desc.RightLegColor),
            TorsoColor      = rgb(desc.TorsoColor),
            Face            = desc.Face,
            Head            = desc.Head,
            Torso           = desc.Torso,
            LeftArm         = desc.LeftArm,
            RightArm        = desc.RightArm,
            LeftLeg         = desc.LeftLeg,
            RightLeg        = desc.RightLeg,
            HeightScale     = desc.HeightScale,
            WidthScale      = desc.WidthScale,
            HeadScale       = desc.HeadScale,
            DepthScale      = desc.DepthScale,
            ProportionScale = desc.ProportionScale,
            BodyTypeScale   = desc.BodyTypeScale,
        }
    end

    return snapshot
end

-- ============================================================
--  OUTFIT APPLY
--  Takes a saved snapshot and puts it back on the player
-- ============================================================

local function applyOutfit(character, snapshot)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    -- Apply the shirt — remove old one first, then add the saved one
    if snapshot.shirt then
        local ex = character:FindFirstChildOfClass("Shirt")
        if ex then ex:Destroy() end
        local s = Instance.new("Shirt"); s.ShirtTemplate = snapshot.shirt; s.Parent = character
    end

    -- Apply the pants — same process
    if snapshot.pants then
        local ex = character:FindFirstChildOfClass("Pants")
        if ex then ex:Destroy() end
        local p = Instance.new("Pants"); p.PantsTemplate = snapshot.pants; p.Parent = character
    end

    -- Apply body colors and scales using HumanoidDescription
    if snapshot.description then
        local d = snapshot.description
        -- Convert the saved string "1,0.5,0.2" back to a Color3
        local function parseColor(str)
            if not str then return Color3.new(1,1,1) end
            local r,g,b = str:match("([^,]+),([^,]+),([^,]+)")
            return Color3.new(tonumber(r), tonumber(g), tonumber(b))
        end
        local ok, desc = pcall(function() return humanoid:GetAppliedDescription() end)
        if ok and desc then
            desc.HeadColor       = parseColor(d.HeadColor)
            desc.LeftArmColor    = parseColor(d.LeftArmColor)
            desc.RightArmColor   = parseColor(d.RightArmColor)
            desc.LeftLegColor    = parseColor(d.LeftLegColor)
            desc.RightLegColor   = parseColor(d.RightLegColor)
            desc.TorsoColor      = parseColor(d.TorsoColor)
            if d.Face   and d.Face   > 0 then desc.Face   = d.Face   end
            if d.Head   and d.Head   > 0 then desc.Head   = d.Head   end
            if d.Torso  and d.Torso  > 0 then desc.Torso  = d.Torso  end
            if d.LeftArm  and d.LeftArm  > 0 then desc.LeftArm  = d.LeftArm  end
            if d.RightArm and d.RightArm > 0 then desc.RightArm = d.RightArm end
            if d.LeftLeg  and d.LeftLeg  > 0 then desc.LeftLeg  = d.LeftLeg  end
            if d.RightLeg and d.RightLeg > 0 then desc.RightLeg = d.RightLeg end
            if d.HeightScale     then desc.HeightScale     = d.HeightScale     end
            if d.WidthScale      then desc.WidthScale      = d.WidthScale      end
            if d.HeadScale       then desc.HeadScale       = d.HeadScale       end
            if d.DepthScale      then desc.DepthScale      = d.DepthScale      end
            if d.ProportionScale then desc.ProportionScale = d.ProportionScale end
            if d.BodyTypeScale   then desc.BodyTypeScale   = d.BodyTypeScale   end
            pcall(function() humanoid:ApplyDescription(desc) end)
        end
    end

    return true
end

-- ============================================================
--  REMOTE: Save Outfit
--  Fires when a player clicks "Save" in the wardrobe
-- ============================================================

SaveOutfitEvent.OnServerEvent:Connect(function(player, slotName, customName)
    -- Make sure slotName is valid
    if typeof(slotName) ~= "string" or #slotName == 0 then return end
    slotName = slotName:sub(1,30) -- limit to 30 characters

    local character = player.Character
    if not character then
        SaveResultEvent:FireClient(player, false, "No character found"); return
    end

    -- Take a snapshot of what the player is wearing right now
    local snapshot = captureOutfit(character)
    if not snapshot then
        SaveResultEvent:FireClient(player, false, "Could not read outfit"); return
    end

    -- Load existing saved outfits and check if we're at the limit
    local data = loadData(player.UserId)
    local count = 0
    for _ in pairs(data) do count += 1 end

    if not data[slotName] and count >= MAX_SLOTS then
        SaveResultEvent:FireClient(player, false, "Max slots reached ("..MAX_SLOTS..")"); return
    end

    -- Save the outfit to the slot
    data[slotName] = { snapshot = snapshot, displayName = customName or slotName, savedAt = os.time() }
    local ok = saveData(player.UserId, data)
    -- Tell the client whether it worked
    SaveResultEvent:FireClient(player, ok, ok and slotName or "DataStore error")
end)

-- ============================================================
--  REMOTE: Load Outfit
--  Fires when a player clicks "Wear" in the wardrobe
-- ============================================================

LoadOutfitFunc.OnServerInvoke = function(player, slotName)
    if typeof(slotName) ~= "string" then return false, "Invalid" end
    local data = loadData(player.UserId)
    local slot = data[slotName]
    if not slot then return false, "Slot not found" end
    local character = player.Character
    if not character then return false, "No character" end
    -- Apply the saved outfit snapshot to the player's character
    local ok = applyOutfit(character, slot.snapshot)
    return ok, ok and "Applied!" or "Failed"
end

-- ============================================================
--  REMOTE: Get All Outfits
--  Fires when the wardrobe opens to show saved outfit slots
-- ============================================================

GetOutfitsFunc.OnServerInvoke = function(player)
    local data = loadData(player.UserId)
    local result = {}
    -- Convert the saved data into a simple list the client can use
    for slotName, slotData in pairs(data) do
        table.insert(result, {
            slotName    = slotName,
            displayName = slotData.displayName or slotName,
            savedAt     = slotData.savedAt or 0,
        })
    end
    -- Sort by when they were saved (oldest first)
    table.sort(result, function(a,b) return a.savedAt < b.savedAt end)
    return result
end

-- ============================================================
--  REMOTE: Delete Outfit
--  Fires when a player clicks the trash icon on an outfit slot
-- ============================================================

DeleteOutfitEvent.OnServerEvent:Connect(function(player, slotName)
    if typeof(slotName) ~= "string" then return end
    local data = loadData(player.UserId)
    if data[slotName] then
        data[slotName] = nil  -- remove from the table
        saveData(player.UserId, data)  -- save the updated table
    end
end)

-- ============================================================
--  REMOTE: Search Catalog
--  Uses AvatarEditorService to search for items on the Roblox catalog
--  HttpService can't access Roblox's own APIs, so we use this instead
-- ============================================================

local AvatarEditorService = game:GetService("AvatarEditorService")

-- Maps our simple type names to the official Roblox enum values
local ASSET_TYPE_MAP = {
    Shirt  = Enum.AvatarAssetType.Shirt,
    Pants  = Enum.AvatarAssetType.Pants,
    Hat    = Enum.AvatarAssetType.Hat,
    Face   = Enum.AvatarAssetType.Face,
}

-- Maps Roblox enum values back to our simple type names
local ASSET_TYPE_NAMES = {
    [Enum.AvatarAssetType.Shirt]             = "Shirt",
    [Enum.AvatarAssetType.Pants]             = "Pants",
    [Enum.AvatarAssetType.Hat]               = "Hat",
    [Enum.AvatarAssetType.Face]              = "Face",
    [Enum.AvatarAssetType.TShirt]            = "Shirt",
    [Enum.AvatarAssetType.ShoulderAccessory] = "Hat",
    [Enum.AvatarAssetType.WaistAccessory]    = "Hat",
    [Enum.AvatarAssetType.NeckAccessory]     = "Hat",
    [Enum.AvatarAssetType.FaceAccessory]     = "Hat",
    [Enum.AvatarAssetType.FrontAccessory]    = "Hat",
    [Enum.AvatarAssetType.BackAccessory]     = "Hat",
    [Enum.AvatarAssetType.HairAccessory]     = "Hat",
}

SearchCatalogFunc.OnServerInvoke = function(player, query, typeFilter)
    -- Validate the search query
    if typeof(query) ~= "string" or #query < 2 then return {} end
    query = query:sub(1, 60) -- limit to 60 characters

    -- Set up search parameters
    local searchParams = CatalogSearchParams.new()
    searchParams.SearchKeyword = query

    -- If a category filter is selected (e.g. "Shirts"), add it to the search
    if typeFilter and ASSET_TYPE_MAP[typeFilter] then
        searchParams.AssetTypes = { ASSET_TYPE_MAP[typeFilter] }
    end
    -- If no filter, search everything

    -- Run the search — pcall so we don't crash if it fails
    local ok, pages = pcall(function()
        return AvatarEditorService:SearchCatalog(searchParams)
    end)

    if not ok then
        warn("AvatarEditorService search error: " .. tostring(pages))
        return {}
    end

    local results = {}

    -- Get the first page of results
    local pageOk, items = pcall(function()
        return pages:GetCurrentPage()
    end)

    if not pageOk or not items then return {} end

    -- Convert each item into a simple table the client can use
    for _, item in ipairs(items) do
        if item.Id and item.Name then
            local typeName = "Hat" -- default if we can't figure out the type
            if item.AssetType then
                typeName = ASSET_TYPE_NAMES[item.AssetType] or "Hat"
            end
            table.insert(results, {
                Name    = item.Name,    -- display name
                AssetId = item.Id,      -- the ID needed to equip it
                Type    = typeName,     -- "Shirt", "Pants", "Hat", etc.
            })
        end
    end

    print("Search returned", #results, "results for:", query)
    return results
end

-- ============================================================
--  REMOTE: Get Character Model for Viewport
--  ⚠️ THIS IS THE SECTION THAT'S FAILING
--
--  What we're TRYING to do:
--    1. Find the WorldModel inside the player's CharacterPreview ViewportFrame
--    2. Build a copy of the player's avatar using CreateHumanoidModelFromDescription
--    3. Place it inside the WorldModel so it shows up in the preview
--
--  Why it might be failing:
--    - The server might not be able to access PlayerGui
--    - The path to WorldModel might be wrong
--    - CreateHumanoidModelFromDescription might need special permissions
--
--  Debug tip: Check if each "return false" line is the one triggering
--  by adding print("step 1"), print("step 2") etc. before each check
-- ============================================================

GetCharacterModelFunc.OnServerInvoke = function(player)
    -- Step 1: Find the player's GUI
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then
        warn("Viewport: PlayerGui not found for " .. player.Name)
        return false
    end

    -- Step 2: Find PhoneGui inside PlayerGui
    local phoneGui = playerGui:FindFirstChild("PhoneGui")
    if not phoneGui then
        warn("Viewport: PhoneGui not found")
        return false
    end

    -- Step 3: Find AvatarScreen
    local avatarScreen = phoneGui:FindFirstChild("AvatarScreen")
    if not avatarScreen then
        warn("Viewport: AvatarScreen not found")
        return false
    end

    -- Step 4: Find CharacterPreview (the ViewportFrame)
    local charPreview = avatarScreen:FindFirstChild("CharacterPreview")
    if not charPreview then
        warn("Viewport: CharacterPreview not found")
        return false
    end

    -- Step 5: Find WorldModel inside CharacterPreview
    local worldModel = charPreview:FindFirstChild("WorldModel")
    if not worldModel then
        warn("Viewport: WorldModel not found — did you add it in Studio?")
        return false
    end

    -- Step 6: Clear any existing preview models
    for _, child in ipairs(worldModel:GetChildren()) do
        if child:IsA("Model") then child:Destroy() end
    end

    -- Step 7: Get the player's avatar appearance description
    local ok, desc = pcall(function()
        return Players:GetCharacterAppearanceAsync(player.UserId)
    end)
    if not ok or not desc then
        warn("Viewport: GetCharacterAppearanceAsync failed")
        return false
    end

    -- Step 8: Build a character model from the appearance description
    -- This creates a full R15 character rig with all the player's items
    local modelOk, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    end)
    if not modelOk or not model then
        warn("Viewport: CreateHumanoidModelFromDescription failed — " .. tostring(model))
        return false
    end

    -- Step 9: Anchor all body parts so they don't fall with gravity
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
        end
    end

    -- Step 10: Move the character to position 0,0,0 (the center of the viewport)
    local root = model:FindFirstChild("HumanoidRootPart")
              or model:FindFirstChild("UpperTorso")
    if root then
        root.CFrame = CFrame.new(0, 0, 0)
    end

    -- Step 11: Place the model inside the WorldModel — this makes it visible in the viewport
    model.Parent = worldModel
    print("✅ Server placed character model for", player.Name)
    return true
end

-- ============================================================
--  BALANCE SYSTEM
--  Tracks how much in-game money each player has
-- ============================================================

-- Separate DataStore just for money — keeps it organized
local BalanceStore   = DataStoreService:GetDataStore("PlayerBalance_v1")
local playerBalances = {} -- temporary in-memory table while players are online

-- Creates a unique key for each player's balance save
local function getBalanceKey(userId) return "balance_" .. tostring(userId) end

-- Loads a player's saved balance from DataStore
local function loadBalance(userId)
    local ok, data = pcall(function()
        return BalanceStore:GetAsync(getBalanceKey(userId))
    end)
    return (ok and data) or 0  -- default to 0 if nothing saved yet
end

-- Saves a player's current balance to DataStore
local function saveBalance(userId, amount)
    pcall(function()
        BalanceStore:SetAsync(getBalanceKey(userId), amount)
    end)
end

-- When a player joins, load their balance into memory
Players.PlayerAdded:Connect(function(player)
    local balance = loadBalance(player.UserId)
    playerBalances[player.UserId] = balance
end)

-- When a player leaves, save their balance and clean up memory
Players.PlayerRemoving:Connect(function(player)
    if playerBalances[player.UserId] then
        saveBalance(player.UserId, playerBalances[player.UserId])
        playerBalances[player.UserId] = nil
    end
end)

-- Client asks: "how much money do I have?"
GetBalanceFunc.OnServerInvoke = function(player)
    return playerBalances[player.UserId] or 0
end

-- Helper to add money to a player (use this from salary scripts later)
-- Example: addMoney(player, 500) gives the player $500
local function addMoney(player, amount)
    if not playerBalances[player.UserId] then return end
    playerBalances[player.UserId] = playerBalances[player.UserId] + amount
    saveBalance(player.UserId, playerBalances[player.UserId])
    -- Tell the client immediately so the bank app updates in real time
    UpdateBalanceEvent:FireClient(player, playerBalances[player.UserId])
end

print("✅ Outfit Save + Catalog Search + Bank Server loaded!")
