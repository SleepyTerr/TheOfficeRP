--[[
    ╔══════════════════════════════════════════════════════════╗
    ║         OUTFIT SAVE + CATALOG SEARCH — Server Script     ║
    ║  Place inside: ServerScriptService  (as a Script)        ║
    ╚══════════════════════════════════════════════════════════╝
]]

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local HttpService        = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OutfitStore = DataStoreService:GetDataStore("PlayerOutfits_v1")
local MAX_SLOTS   = 6

-- ============================================================
--  REMOTE SETUP
-- ============================================================

local remoteFolder = Instance.new("Folder")
remoteFolder.Name  = "OutfitRemotes"
remoteFolder.Parent = ReplicatedStorage

local function makeEvent(name)
	local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = remoteFolder; return e
end
local function makeFunc(name)
	local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = remoteFolder; return f
end

local SaveOutfitEvent   = makeEvent("SaveOutfit")
local DeleteOutfitEvent = makeEvent("DeleteOutfit")
local SaveResultEvent   = makeEvent("SaveResult")
local LoadOutfitFunc    = makeFunc("LoadOutfit")
local GetOutfitsFunc    = makeFunc("GetOutfits")
local SearchCatalogFunc = makeFunc("SearchCatalog")
local GetBalanceFunc     = makeFunc("GetBalance")
local UpdateBalanceEvent = makeEvent("UpdateBalance")
local GetCharacterModelFunc = makeFunc("GetCharacterModel")

-- ============================================================
--  DATASTORE HELPERS
-- ============================================================

local function getKey(userId) return "outfits_" .. tostring(userId) end

local function loadData(userId)
	local ok, data = pcall(function() return OutfitStore:GetAsync(getKey(userId)) end)
	return (ok and data) or {}
end

local function saveData(userId, data)
	local ok, err = pcall(function() OutfitStore:SetAsync(getKey(userId), data) end)
	if not ok then warn("DataStore save error: " .. tostring(err)) end
	return ok
end

-- ============================================================
--  OUTFIT CAPTURE
-- ============================================================

local function captureOutfit(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local snapshot = { shirt = nil, pants = nil, accessories = {}, description = nil }

	local shirt = character:FindFirstChildOfClass("Shirt")
	if shirt then snapshot.shirt = shirt.ShirtTemplate end

	local pants = character:FindFirstChildOfClass("Pants")
	if pants then snapshot.pants = pants.PantsTemplate end

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

	local ok, desc = pcall(function() return humanoid:GetAppliedDescription() end)
	if ok and desc then
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
-- ============================================================

local function applyOutfit(character, snapshot)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end

	if snapshot.shirt then
		local ex = character:FindFirstChildOfClass("Shirt")
		if ex then ex:Destroy() end
		local s = Instance.new("Shirt"); s.ShirtTemplate = snapshot.shirt; s.Parent = character
	end

	if snapshot.pants then
		local ex = character:FindFirstChildOfClass("Pants")
		if ex then ex:Destroy() end
		local p = Instance.new("Pants"); p.PantsTemplate = snapshot.pants; p.Parent = character
	end

	if snapshot.description then
		local d = snapshot.description
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
-- ============================================================

SaveOutfitEvent.OnServerEvent:Connect(function(player, slotName, customName)
	if typeof(slotName) ~= "string" or #slotName == 0 then return end
	slotName = slotName:sub(1,30)

	local character = player.Character
	if not character then
		SaveResultEvent:FireClient(player, false, "No character found"); return
	end

	local snapshot = captureOutfit(character)
	if not snapshot then
		SaveResultEvent:FireClient(player, false, "Could not read outfit"); return
	end

	local data = loadData(player.UserId)
	local count = 0
	for _ in pairs(data) do count += 1 end

	if not data[slotName] and count >= MAX_SLOTS then
		SaveResultEvent:FireClient(player, false, "Max slots reached ("..MAX_SLOTS..")"); return
	end

	data[slotName] = { snapshot = snapshot, displayName = customName or slotName, savedAt = os.time() }
	local ok = saveData(player.UserId, data)
	SaveResultEvent:FireClient(player, ok, ok and slotName or "DataStore error")
end)

-- ============================================================
--  REMOTE: Load Outfit
-- ============================================================

LoadOutfitFunc.OnServerInvoke = function(player, slotName)
	if typeof(slotName) ~= "string" then return false, "Invalid" end
	local data = loadData(player.UserId)
	local slot = data[slotName]
	if not slot then return false, "Slot not found" end
	local character = player.Character
	if not character then return false, "No character" end
	local ok = applyOutfit(character, slot.snapshot)
	return ok, ok and "Applied!" or "Failed"
end

-- ============================================================
--  REMOTE: Get All Outfits
-- ============================================================

GetOutfitsFunc.OnServerInvoke = function(player)
	local data = loadData(player.UserId)
	local result = {}
	for slotName, slotData in pairs(data) do
		table.insert(result, {
			slotName    = slotName,
			displayName = slotData.displayName or slotName,
			savedAt     = slotData.savedAt or 0,
		})
	end
	table.sort(result, function(a,b) return a.savedAt < b.savedAt end)
	return result
end

-- ============================================================
--  REMOTE: Delete Outfit
-- ============================================================

DeleteOutfitEvent.OnServerEvent:Connect(function(player, slotName)
	if typeof(slotName) ~= "string" then return end
	local data = loadData(player.UserId)
	if data[slotName] then
		data[slotName] = nil
		saveData(player.UserId, data)
	end
end)

-- ============================================================
--  REMOTE: Search Catalog  ← NEW
--
--  Calls the Roblox catalog API via HttpService (server only).
--  query    = search string from player
--  typeFilter = "Shirt" | "Pants" | "Hat" | nil (all)
--
--  Returns: array of { Name, AssetId, Type }
-- ============================================================

-- Map from our internal type names to Roblox API subcategory numbers
local SUBCATEGORY_MAP = {
	Shirt  = 12,   -- Shirts
	Pants  = 13,   -- Pants
	Hat    = 41,   -- Hair & Accessories (broad)
	Face   = 19,   -- Faces
	Outfit = 55,   -- Bundles / Outfits
}

-- ============================================================
--  REMOTE: Search Catalog via AvatarEditorService
--  This is the Roblox-approved way to search the catalog
--  from inside a game — no HttpService needed
-- ============================================================

local AvatarEditorService = game:GetService("AvatarEditorService")

-- Map our type names to Roblox AvatarAssetType enums
local ASSET_TYPE_MAP = {
	Shirt  = Enum.AvatarAssetType.Shirt,
	Pants  = Enum.AvatarAssetType.Pants,
	Hat    = Enum.AvatarAssetType.Hat,
	Face   = Enum.AvatarAssetType.Face,
}

-- Map Roblox AvatarAssetType back to our type names
local ASSET_TYPE_NAMES = {
	[Enum.AvatarAssetType.Shirt] = "Shirt",
	[Enum.AvatarAssetType.Pants] = "Pants",
	[Enum.AvatarAssetType.Hat]   = "Hat",
	[Enum.AvatarAssetType.Face]  = "Face",
	[Enum.AvatarAssetType.TShirt] = "Shirt",
	[Enum.AvatarAssetType.ShoulderAccessory] = "Hat",
	[Enum.AvatarAssetType.WaistAccessory]    = "Hat",
	[Enum.AvatarAssetType.NeckAccessory]     = "Hat",
	[Enum.AvatarAssetType.FaceAccessory]     = "Hat",
	[Enum.AvatarAssetType.FrontAccessory]    = "Hat",
	[Enum.AvatarAssetType.BackAccessory]     = "Hat",
	[Enum.AvatarAssetType.HairAccessory]     = "Hat",
}

SearchCatalogFunc.OnServerInvoke = function(player, query, typeFilter)
	if typeof(query) ~= "string" or #query < 2 then return {} end
	query = query:sub(1, 60)

	local searchParams = CatalogSearchParams.new()
	searchParams.SearchKeyword = query

	-- Apply asset type filter if provided, otherwise just search all clothing
	if typeFilter and ASSET_TYPE_MAP[typeFilter] then
		searchParams.AssetTypes = { ASSET_TYPE_MAP[typeFilter] }
	end
	-- No AssetTypes set = searches everything, which is fine

	local ok, pages = pcall(function()
		return AvatarEditorService:SearchCatalog(searchParams)
	end)

	if not ok then
		warn("AvatarEditorService search error: " .. tostring(pages))
		return {}
	end

	local results = {}

	local pageOk, items = pcall(function()
		return pages:GetCurrentPage()
	end)

	if not pageOk or not items then return {} end

	for _, item in ipairs(items) do
		if item.Id and item.Name then
			local typeName = "Hat"
			if item.AssetType then
				typeName = ASSET_TYPE_NAMES[item.AssetType] or "Hat"
			end
			table.insert(results, {
				Name    = item.Name,
				AssetId = item.Id,
				Type    = typeName,
			})
		end
	end

	print("Search returned", #results, "results for:", query)
	return results
end

-- Client requests character model to be built into their viewport WorldModel
GetCharacterModelFunc.OnServerInvoke = function(player)
	-- Find the player's WorldModel in their PlayerGui
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return false end

	local phoneGui = playerGui:FindFirstChild("PhoneGui")
	if not phoneGui then return false end

	local avatarScreen = phoneGui:FindFirstChild("AvatarScreen")
	if not avatarScreen then return false end

	local charPreview = avatarScreen:FindFirstChild("CharacterPreview")
	if not charPreview then return false end

	local worldModel = charPreview:FindFirstChild("WorldModel")
	if not worldModel then return false end

	-- Clear any existing models
	for _, child in ipairs(worldModel:GetChildren()) do
		if child:IsA("Model") then child:Destroy() end
	end

	-- Build the character model server-side
	local ok, desc = pcall(function()
		return Players:GetCharacterAppearanceAsync(player.UserId)
	end)
	if not ok or not desc then return false end

	local modelOk, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not modelOk or not model then return false end

	-- Anchor all parts and place at origin
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	local root = model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("UpperTorso")
	if root then
		root.CFrame = CFrame.new(0, 0, 0)
	end

	-- Place directly into the WorldModel
	model.Parent = worldModel
	print("✅ Server placed character model for", player.Name)
	return true
end

-- ============================================================
--  BALANCE SYSTEM
-- ============================================================

local BalanceStore  = DataStoreService:GetDataStore("PlayerBalance_v1")
local playerBalances = {} -- in-memory cache

local function getBalanceKey(userId) return "balance_" .. tostring(userId) end

local function loadBalance(userId)
	local ok, data = pcall(function()
		return BalanceStore:GetAsync(getBalanceKey(userId))
	end)
	return (ok and data) or 0
end

local function saveBalance(userId, amount)
	pcall(function()
		BalanceStore:SetAsync(getBalanceKey(userId), amount)
	end)
end

-- Load balance when player joins
Players.PlayerAdded:Connect(function(player)
	local balance = loadBalance(player.UserId)
	playerBalances[player.UserId] = balance
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	if playerBalances[player.UserId] then
		saveBalance(player.UserId, playerBalances[player.UserId])
		playerBalances[player.UserId] = nil
	end
end)

-- Client requests their balance
GetBalanceFunc.OnServerInvoke = function(player)
	return playerBalances[player.UserId] or 0
end

-- Helper function other scripts can use to add money to a player
-- e.g. require this script and call addMoney(player, 100)
local function addMoney(player, amount)
	if not playerBalances[player.UserId] then return end
	playerBalances[player.UserId] = playerBalances[player.UserId] + amount
	saveBalance(player.UserId, playerBalances[player.UserId])
	UpdateBalanceEvent:FireClient(player, playerBalances[player.UserId])
end

print("✅ Outfit Save + Catalog Search + Bank Server loaded!")
