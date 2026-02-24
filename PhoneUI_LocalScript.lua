--[[
    ╔══════════════════════════════════════════════════════════╗
    ║              PHONE UI — LocalScript                      ║
    ║  Place inside: PhoneGui  (as a LocalScript)              ║
    ╚══════════════════════════════════════════════════════════╝
]]

-- ============================================================
--  DEV ONLY — replace with your UserId
--  Delete this block when releasing to players
-- ============================================================
local DEVELOPER_IDS = {
	1332836159, -- Dev 1
	336655095,  -- Dev 2
}
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local isDevAccount = false
for _, id in ipairs(DEVELOPER_IDS) do
	if localPlayer.UserId == id then isDevAccount = true break end
end
if not isDevAccount then script:Destroy() return end

-- ============================================================
--  SERVICES
-- ============================================================

local TweenService      = game:GetService("TweenService")
local InsertService     = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")

-- ============================================================
--  OUTFIT REMOTES
-- ============================================================

local remoteFolder      = ReplicatedStorage:WaitForChild("OutfitRemotes", 10)
local SaveOutfitEvent   = remoteFolder and remoteFolder:WaitForChild("SaveOutfit")
local LoadOutfitFunc    = remoteFolder and remoteFolder:WaitForChild("LoadOutfit")
local GetOutfitsFunc    = remoteFolder and remoteFolder:WaitForChild("GetOutfits")
local DeleteOutfitEvent = remoteFolder and remoteFolder:WaitForChild("DeleteOutfit")
local SaveResultEvent   = remoteFolder and remoteFolder:WaitForChild("SaveResult")
local SearchCatalogFunc = remoteFolder and remoteFolder:WaitForChild("SearchCatalog")
local GetBalanceFunc        = remoteFolder and remoteFolder:WaitForChild("GetBalance")
local UpdateBalanceEvent    = remoteFolder and remoteFolder:WaitForChild("UpdateBalance")
local GetCharacterModelFunc = remoteFolder and remoteFolder:WaitForChild("GetCharacterModel")

-- ============================================================
--  GUI REFERENCES — Phone
-- ============================================================

local phoneGui    = localPlayer.PlayerGui:WaitForChild("PhoneGui")
local phoneBody   = phoneGui:WaitForChild("PhoneBody")
local phoneScreen = phoneBody:WaitForChild("PhoneScreen")
local homeButton  = phoneBody:WaitForChild("HomeButton")
local toggleBtn   = phoneGui:WaitForChild("ToggleButton")

-- App icon frames
local appIcons = {
	Wardrobe  = phoneScreen:WaitForChild("AppIcon_Wardrobe"),
	Map       = phoneScreen:WaitForChild("AppIcon_Map"),
	Teleport  = phoneScreen:WaitForChild("AppIcon_Teleport"),
	Messages  = phoneScreen:WaitForChild("AppIcon_Messages"),
	Call      = phoneScreen:WaitForChild("AppIcon_Call"),
	Bank      = phoneScreen:WaitForChild("AppIcon_Bank"),
	Vehicles  = phoneScreen:WaitForChild("AppIcon_Vehicles"),
	Settings  = phoneScreen:WaitForChild("AppIcon_Settings"),
}

-- ============================================================
--  GUI REFERENCES — AvatarScreen (fullscreen wardrobe)
-- ============================================================

local avatarScreen   = phoneGui:WaitForChild("AvatarScreen")
local catalogPanel   = avatarScreen:WaitForChild("CatalogPanel")
local closeButton    = avatarScreen:WaitForChild("CloseButton")
local tabCatalog     = catalogPanel:WaitForChild("TabCatalog")
local tabOutfits     = catalogPanel:WaitForChild("TabOutfits")
local searchBar      = catalogPanel:WaitForChild("SearchBar")
local categoryBar    = catalogPanel:WaitForChild("CategoryBar")
local itemGrid       = catalogPanel:WaitForChild("ItemGrid")
local slotContainer  = catalogPanel:WaitForChild("SlotContainer")

-- ============================================================
--  STATE
-- ============================================================

local phoneVisible   = false
local currentApp     = nil
local equippedItems  = {}
local savedOutfits   = {}
local activeCategory = "All"
local searchDebounce = nil
local slotRowMap     = {}

-- ============================================================
--  OUTFIT SLOTS CONFIG
-- ============================================================

local OUTFIT_SLOTS = {
	{ slotName = "Work",   label = "💼 Work",   color = Color3.fromRGB(50, 110, 230)  },
	{ slotName = "Home",   label = "🏠 Home",   color = Color3.fromRGB(60, 170, 90)   },
	{ slotName = "Casual", label = "👕 Casual", color = Color3.fromRGB(200, 130, 40)  },
	{ slotName = "Sport",  label = "⚽ Sport",  color = Color3.fromRGB(210, 70, 60)   },
	{ slotName = "Formal", label = "🎩 Formal", color = Color3.fromRGB(130, 60, 200)  },
	{ slotName = "Custom", label = "✨ Custom", color = Color3.fromRGB(180, 150, 20)  },
}

local CATEGORIES = { "All", "Shirts", "Pants", "Accessories", "Faces", "Outfits" }
local CATEGORY_TYPE_MAP = {
	All = nil, Shirts = "Shirt", Pants = "Pants",
	Accessories = "Hat", Faces = "Face", Outfits = "Outfit",
}

-- ============================================================
--  HELPERS
-- ============================================================

local function tween(obj, props, t, style, dir)
	TweenService:Create(obj,
		TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props):Play()
end

local function makeFrame(parent, size, pos, bg, radius, clip)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = bg or Color3.fromRGB(20, 20, 32)
	f.BorderSizePixel = 0
	f.Parent = parent
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius)
		c.Parent = f
	end
	if clip then f.ClipsDescendants = true end
	return f
end

local function makeLabel(parent, text, size, pos, textSize, color, wrap, xAlign)
	local l = Instance.new("TextLabel")
	l.Text = text
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.TextColor3 = color or Color3.fromRGB(220, 220, 240)
	l.TextSize = textSize or 13
	l.Font = Enum.Font.GothamSemibold
	l.TextWrapped = wrap or false
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function makeButton(parent, text, size, pos, bg, textSize, radius)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = bg or Color3.fromRGB(50, 50, 80)
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextSize = textSize or 12
	b.Font = Enum.Font.GothamBold
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = b
	return b
end

-- ============================================================
--  PHONE TOGGLE
-- ============================================================

phoneBody.Visible = false
avatarScreen.Visible = false

toggleBtn.MouseButton1Click:Connect(function()
	phoneVisible = not phoneVisible
	if phoneVisible then
		phoneBody.Visible = true
		phoneBody.Position = UDim2.new(
			phoneBody.Position.X.Scale,
			phoneBody.Position.X.Offset,
			1, 20)
		tween(phoneBody, {
			Position = UDim2.new(
				phoneBody.Position.X.Scale,
				phoneBody.Position.X.Offset,
				1, -(475 + 20))
		}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		tween(phoneBody, {
			Position = UDim2.new(
				phoneBody.Position.X.Scale,
				phoneBody.Position.X.Offset,
				1, 20)
		}, 0.25)
		task.delay(0.26, function()
			if not phoneVisible then phoneBody.Visible = false end
		end)
	end
end)

-- ============================================================
--  CHARACTER PREVIEW (ViewportFrame with WorldModel)
-- ============================================================

local viewportFrame = avatarScreen:WaitForChild("CharacterPreview")
local worldModel    = viewportFrame:WaitForChild("WorldModel")

local viewportCamera = Instance.new("Camera")
viewportCamera.CameraType = Enum.CameraType.Scriptable
viewportCamera.Parent = viewportFrame
viewportFrame.CurrentCamera = viewportCamera

local previewModel = nil

local function updateViewport()
	if not GetCharacterModelFunc then
		warn("ViewportFrame: remote not found")
		return
	end

	task.spawn(function()
		-- Ask server to build and place the model into WorldModel
		local ok, success = pcall(function()
			return GetCharacterModelFunc:InvokeServer()
		end)

		if not ok or not success then
			warn("ViewportFrame: server failed to place model")
			return
		end

		-- Model is now in WorldModel, just set up the camera
		task.wait(0.1) -- small wait for model to settle
		viewportFrame.CurrentCamera = viewportCamera
		viewportCamera.CFrame = CFrame.new(
			Vector3.new(0, 1.5, 5),
			Vector3.new(0, 0.8, 0)
		)
		print("✅ ViewportFrame camera set!")
	end)
end

-- ============================================================
--  AVATAR SCREEN — Open / Close
-- ============================================================

-- forward declare so openAvatarScreen can call it
local selectCategory

local function openAvatarScreen()
	tween(phoneBody, {
		Position = UDim2.new(
			phoneBody.Position.X.Scale,
			phoneBody.Position.X.Offset,
			1, 20)
	}, 0.2)
	task.delay(0.21, function() phoneBody.Visible = false end)
	phoneVisible = false

	avatarScreen.Visible = true
	avatarScreen.Position = UDim2.new(-1, 0, 0, 0)
	tween(avatarScreen, { Position = UDim2.new(0, 0, 0, 0) }, 0.3,
	Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	task.delay(0.35, updateViewport)

	-- Auto-select Featured category on open
	task.delay(0.4, function()
		local featuredBtn = categoryBar:FindFirstChild("Cat_Featured")
		if featuredBtn then
			selectCategory("Cat_Featured", featuredBtn)
		end
	end)
end

local function closeAvatarScreen()
	-- Slide AvatarScreen out to the left
	tween(avatarScreen, { Position = UDim2.new(-1, 0, 0, 0) }, 0.25)
	task.delay(0.26, function()
		avatarScreen.Visible = false
	end)

	-- Bring phone back up
	task.delay(0.15, function()
		phoneBody.Visible = true
		phoneVisible = true
		phoneBody.Position = UDim2.new(
			phoneBody.Position.X.Scale,
			phoneBody.Position.X.Offset,
			1, 20)
		tween(phoneBody, {
			Position = UDim2.new(
				phoneBody.Position.X.Scale,
				phoneBody.Position.X.Offset,
				1, -(475 + 20))
		}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

closeButton.MouseButton1Click:Connect(closeAvatarScreen)

-- ============================================================
--  APP SCREEN (for phone-screen apps like Map, Messages etc.)
-- ============================================================

local appScreen = makeFrame(phoneScreen,
	UDim2.new(1, 0, 1, 0),
	UDim2.new(1, 0, 0, 0),
	Color3.fromRGB(12, 12, 20), 0, true)
appScreen.ZIndex = 2
appScreen.Visible = false

local appBar = makeFrame(appScreen,
	UDim2.new(1, 0, 0, 36),
	UDim2.new(0, 0, 0, 0),
	Color3.fromRGB(20, 20, 34))

local appTitleLabel = makeLabel(appBar, "",
	UDim2.new(1, 0, 1, 0),
	UDim2.new(0, 0, 0, 0),
	14, Color3.fromRGB(240, 240, 255), false,
	Enum.TextXAlignment.Center)

local appContent = makeFrame(appScreen,
	UDim2.new(1, 0, 1, -36),
	UDim2.new(0, 0, 0, 36),
	Color3.fromRGB(0, 0, 0), 0, true)
appContent.BackgroundTransparency = 1

local function openAppScreen(title)
	currentApp = title
	appTitleLabel.Text = title
	for _, child in ipairs(appContent:GetChildren()) do
		child:Destroy()
	end
	appScreen.Visible = true
	appScreen.Position = UDim2.new(1, 0, 0, 0)
	tween(appScreen, { Position = UDim2.new(0, 0, 0, 0) }, 0.25,
	Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

local function closeAppScreen()
	tween(appScreen, { Position = UDim2.new(1, 0, 0, 0) }, 0.22)
	task.delay(0.23, function()
		currentApp = nil
		appScreen.Visible = false
	end)
end

homeButton.ZIndex = 10
homeButton.MouseButton1Click:Connect(function()
	closeAppScreen()
end)

-- ============================================================
--  APP ICON PRESS ANIMATION
-- ============================================================

local function addIconAnimation(iconFrame)
	local iconBg = iconFrame:FindFirstChild("IconBg")
	if not iconBg then return end

	-- Remove any existing click buttons from previous runs
	for _, child in ipairs(iconFrame:GetChildren()) do
		if child:IsA("TextButton") and child.Text == "" then
			child:Destroy()
		end
	end

	local clickBtn = Instance.new("TextButton")
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.Position = UDim2.new(0, 0, 0, 0)
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.ZIndex = iconBg.ZIndex + 1
	clickBtn.Parent = iconFrame

	clickBtn.MouseButton1Down:Connect(function()
		tween(iconBg, {
			Size = UDim2.new(0, 50, 0, 50),
			Position = UDim2.new(0.5, -25, 0, 6)
		}, 0.1)
	end)
	clickBtn.MouseButton1Up:Connect(function()
		tween(iconBg, {
			Size = UDim2.new(0, 58, 0, 58),
			Position = UDim2.new(0.5, -29, 0, 2)
		}, 0.15, Enum.EasingStyle.Back)
	end)

	return clickBtn
end

-- ============================================================
--  PLACEHOLDER APP (for phone-screen apps)
-- ============================================================

local PLACEHOLDERS = {
	Map      = { icon = "🗺",  msg = "Map coming soon!\nYour office buildings\nwill appear here." },
	Teleport = { icon = "🚀", msg = "Teleport coming soon!\nJump to People, Houses\nand Apartments." },
	Messages = { icon = "💬", msg = "Messages coming soon!\nChat with other players." },
	Call     = { icon = "📞", msg = "Calls coming soon!\nVoice chat with colleagues." },
	Bank     = { icon = "🏦", msg = "Bank coming soon!\nManage your in-game money." },
	Vehicles = { icon = "🚗", msg = "Vehicles coming soon!\nBrowse and equip your cars." },
	Settings = { icon = "⚙",  msg = "Settings coming soon!\nCustomise your experience." },
}

local function buildPlaceholder(appId)
	local info = PLACEHOLDERS[appId]
	if not info then return end

	makeLabel(appContent, info.icon,
		UDim2.new(1, 0, 0, 60),
		UDim2.new(0, 0, 0, 30),
		44, Color3.fromRGB(240, 240, 255), false,
		Enum.TextXAlignment.Center)

	makeLabel(appContent, info.msg,
		UDim2.new(1, -20, 0, 70),
		UDim2.new(0, 10, 0, 100),
		12, Color3.fromRGB(150, 150, 190), true,
		Enum.TextXAlignment.Center)

	local badge = makeFrame(appContent,
		UDim2.new(0, 140, 0, 30),
		UDim2.new(0.5, -70, 0, 178),
		Color3.fromRGB(60, 40, 120), 15)

	makeLabel(badge, "🔨 In Development",
		UDim2.new(1, 0, 1, 0),
		UDim2.new(0, 0, 0, 0),
		11, Color3.fromRGB(200, 180, 255), false,
		Enum.TextXAlignment.Center)
end

-- ============================================================
--  EQUIP / UNEQUIP
-- ============================================================

local function equipItem(item)
	character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	humanoid  = character:WaitForChild("Humanoid")
	local ok, err = pcall(function()
		if item.Type == "Shirt" then
			for _, o in ipairs(character:GetChildren()) do
				if o:IsA("Shirt") then o:Destroy() end
			end
			local s = Instance.new("Shirt")
			s.ShirtTemplate = "rbxassetid://" .. item.AssetId
			s.Parent = character
			equippedItems[item.AssetId] = s
		elseif item.Type == "Pants" then
			for _, o in ipairs(character:GetChildren()) do
				if o:IsA("Pants") then o:Destroy() end
			end
			local p = Instance.new("Pants")
			p.PantsTemplate = "rbxassetid://" .. item.AssetId
			p.Parent = character
			equippedItems[item.AssetId] = p
		elseif item.Type == "Hat" or item.Type == "Face" then
			local loaded = InsertService:LoadAsset(item.AssetId)
			local acc = loaded:FindFirstChildOfClass("Accessory")
				or loaded:FindFirstChildOfClass("Hat")
			if acc then
				acc.Parent = character
				loaded:Destroy()
				equippedItems[item.AssetId] = acc
			else
				loaded:Destroy()
			end
		elseif item.Type == "Outfit" then
			local desc = Players:GetHumanoidDescriptionFromOutfitId(item.AssetId)
			humanoid:ApplyDescription(desc)
			equippedItems[item.AssetId] = true
		end
	end)
	if not ok then warn("Equip error: " .. tostring(err)) end
end

local function unequipItem(item)
	local ex = equippedItems[item.AssetId]
	if not ex then return end
	if item.Type == "Shirt" then
		for _, o in ipairs(character:GetChildren()) do
			if o:IsA("Shirt") then o:Destroy() end
		end
	elseif item.Type == "Pants" then
		for _, o in ipairs(character:GetChildren()) do
			if o:IsA("Pants") then o:Destroy() end
		end
	elseif typeof(ex) == "Instance" and ex.Parent then
		ex:Destroy()
	end
	equippedItems[item.AssetId] = nil
end

-- ============================================================
--  ITEM CARD
-- ============================================================

local function makeItemCard(itemData)
	local card = makeFrame(itemGrid,
		UDim2.new(0, 82, 0, 102),
		UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(24, 24, 38), 8)
	card:SetAttribute("ItemType", itemData.Type)

	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(80, 60, 160)
	s.Thickness = 1
	s.Parent = card

	local thumb = Instance.new("ImageLabel")
	thumb.Size = UDim2.new(1, -8, 0, 60)
	thumb.Position = UDim2.new(0, 4, 0, 4)
	thumb.BackgroundColor3 = Color3.fromRGB(32, 32, 50)
	thumb.BorderSizePixel = 0
	thumb.Image = "rbxthumb://type=Asset&id=" .. itemData.AssetId .. "&w=420&h=420"
	thumb.Parent = card
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 6); tc.Parent = thumb

	makeLabel(card, itemData.Name,
		UDim2.new(1, -6, 0, 22),
		UDim2.new(0, 3, 0, 66),
		9, Color3.fromRGB(200, 200, 220), true,
		Enum.TextXAlignment.Center)

	local equipBtn = makeButton(card, "Equip",
		UDim2.new(1, -8, 0, 18),
		UDim2.new(0, 4, 1, -22),
		Color3.fromRGB(70, 40, 160), 10, 6)

	local DEFAULT_C  = Color3.fromRGB(70, 40, 160)
	local EQUIPPED_C = Color3.fromRGB(180, 40, 40)

	equipBtn.MouseButton1Click:Connect(function()
		if equippedItems[itemData.AssetId] then
			unequipItem(itemData)
			equipBtn.Text = "Equip"
			equipBtn.BackgroundColor3 = DEFAULT_C
		else
			equipBtn.Text = "..."
			equipBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
			equipItem(itemData)
			if equippedItems[itemData.AssetId] then
				equipBtn.Text = "Remove"
				equipBtn.BackgroundColor3 = EQUIPPED_C
			else
				equipBtn.Text = "Error"
				task.delay(2, function()
					equipBtn.Text = "Equip"
					equipBtn.BackgroundColor3 = DEFAULT_C
				end)
			end
		end
	end)

	return card
end

-- ============================================================
--  OUTFIT STATUS LABEL
--  (we create this in code and parent it to catalogPanel)
-- ============================================================

local outfitStatusLabel = makeLabel(catalogPanel, "",
	UDim2.new(1, -20, 0, 20),
	UDim2.new(0, 10, 1, -26),
	11, Color3.fromRGB(120, 200, 120), false,
	Enum.TextXAlignment.Center)
outfitStatusLabel.Name = "OutfitStatusLabel"

local function setOutfitStatus(msg, color)
	outfitStatusLabel.Text = msg
	outfitStatusLabel.TextColor3 = color or Color3.fromRGB(120, 200, 120)
	task.delay(3, function()
		if outfitStatusLabel.Text == msg then
			outfitStatusLabel.Text = ""
		end
	end)
end

-- ============================================================
--  OUTFIT SLOT ROWS (built into SlotContainer)
-- ============================================================

local function refreshSlot(slotName)
	local r = slotRowMap[slotName]
	if not r then return end
	local saved = savedOutfits[slotName]
	if saved then
		r.statusLbl.Text = "● Saved"
		r.statusLbl.TextColor3 = Color3.fromRGB(80, 200, 100)
		r.loadBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 60)
		r.saveBtn.Text = "Update"
		r.deleteBtn.Visible = true
	else
		r.statusLbl.Text = "Empty"
		r.statusLbl.TextColor3 = Color3.fromRGB(100, 100, 130)
		r.loadBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
		r.saveBtn.Text = "Save"
		r.deleteBtn.Visible = false
	end
end

for i, slot in ipairs(OUTFIT_SLOTS) do
	local row = makeFrame(slotContainer,
		UDim2.new(1, 0, 0, 56),
		UDim2.new(0, 0, 0, 0),
		Color3.fromRGB(22, 22, 36), 10)
	row.LayoutOrder = i

	makeFrame(row, UDim2.new(0, 4, 1, -12), UDim2.new(0, 0, 0, 6), slot.color, 3)

	makeLabel(row, slot.label,
		UDim2.new(0, 160, 0, 22), UDim2.new(0, 14, 0, 6),
		14, Color3.fromRGB(230, 230, 250))

	local statusLbl = makeLabel(row, "Empty",
		UDim2.new(0, 120, 0, 18), UDim2.new(0, 14, 0, 30),
		11, Color3.fromRGB(100, 100, 130))

	local loadBtn = makeButton(row, "Wear",
		UDim2.new(0, 70, 0, 34), UDim2.new(1, -222, 0, 11),
		Color3.fromRGB(40, 40, 60), 12, 8)

	local saveBtn = makeButton(row, "Save",
		UDim2.new(0, 80, 0, 34), UDim2.new(1, -134, 0, 11),
		Color3.fromRGB(50, 100, 220), 12, 8)

	local deleteBtn = makeButton(row, "🗑",
		UDim2.new(0, 40, 0, 34), UDim2.new(1, -46, 0, 11),
		Color3.fromRGB(160, 40, 40), 13, 8)
	deleteBtn.Visible = false

	slotRowMap[slot.slotName] = {
		statusLbl = statusLbl,
		loadBtn   = loadBtn,
		saveBtn   = saveBtn,
		deleteBtn = deleteBtn,
	}

	refreshSlot(slot.slotName)

	saveBtn.MouseButton1Click:Connect(function()
		saveBtn.Text = "..."
		saveBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		if SaveOutfitEvent then
			SaveOutfitEvent:FireServer(slot.slotName, slot.slotName)
		else
			setOutfitStatus("⚠ Server not connected", Color3.fromRGB(220, 150, 50))
			saveBtn.Text = "Save"
			saveBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 220)
		end
	end)

	loadBtn.MouseButton1Click:Connect(function()
		if not savedOutfits[slot.slotName] then
			setOutfitStatus("Nothing saved in " .. slot.label .. " yet!", Color3.fromRGB(220, 180, 50))
			return
		end
		loadBtn.Text = "..."
		if LoadOutfitFunc then
			local ok, msg = LoadOutfitFunc:InvokeServer(slot.slotName)
			setOutfitStatus(
				ok and "✅ " .. slot.label .. " applied!" or "❌ " .. (msg or "Failed"),
				ok and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(220, 80, 80)
			)
		end
		loadBtn.Text = "Wear"
	end)

	deleteBtn.MouseButton1Click:Connect(function()
		if DeleteOutfitEvent then
			DeleteOutfitEvent:FireServer(slot.slotName)
			savedOutfits[slot.slotName] = nil
			refreshSlot(slot.slotName)
			setOutfitStatus("🗑 " .. slot.label .. " deleted.", Color3.fromRGB(200, 100, 100))
		end
	end)
end

-- ============================================================
--  CATEGORY BUTTONS (reads from Studio-built CategoryBar)
-- ============================================================

-- Map category button names to AvatarEditorService search keywords/types
local CATEGORY_CONFIG = {
	Cat_Featured   = { keyword = "featured",   assetType = nil },
	Cat_Hair       = { keyword = "hair",        assetType = "Hat" },
	Cat_Faces      = { keyword = "face",        assetType = "Face" },
	Cat_Clothing   = { keyword = "shirt",       assetType = "Shirt" },
	Cat_Animations = { keyword = nil,           assetType = nil, subFrame = true },
	Cat_Body       = { keyword = nil,           assetType = nil, subFrame = true },
	Cat_Heads      = { keyword = "head",        assetType = nil },
	Cat_Characters = { keyword = "character",   assetType = nil },
}

local activeCatBtn = nil

-- ============================================================
--  LIVE SEARCH
-- ============================================================

local loadingLabel = makeLabel(itemGrid, "Select a category to browse items",
	UDim2.new(1, -10, 0, 40),
	UDim2.new(0, 5, 0, 20),
	13, Color3.fromRGB(120, 120, 160), true,
	Enum.TextXAlignment.Center)

local function clearItems()
	for _, child in ipairs(itemGrid:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function displayResults(items)
	clearItems()
	if #items == 0 then
		loadingLabel.Text = "No results found."
		loadingLabel.Visible = true
		return
	end
	loadingLabel.Visible = false
	for _, item in ipairs(items) do
		makeItemCard(item)
	end
end

local function doSearch(query, assetType)
	if not SearchCatalogFunc then
		loadingLabel.Text = "⚠ Search not connected."
		loadingLabel.Visible = true
		return
	end
	clearItems()
	loadingLabel.Text = "Loading..."
	loadingLabel.Visible = true
	local ok, results = pcall(function()
		return SearchCatalogFunc:InvokeServer(query, assetType)
	end)
	if ok and results then
		displayResults(results)
	else
		loadingLabel.Text = "Search failed. Try again."
		loadingLabel.Visible = true
	end
end

-- Sub-frame placeholder for Body and Animations
local function showSubFrame(catName)
	clearItems()
	loadingLabel.Visible = false

	local msgs = {
		Cat_Animations = { icon = "🎭", msg = "Animation browser\ncoming soon!" },
		Cat_Body       = { icon = "🧍", msg = "Body customizer\ncoming soon!" },
	}
	local info = msgs[catName]
	if not info then return end

	makeLabel(itemGrid, info.icon,
		UDim2.new(1, 0, 0, 50),
		UDim2.new(0, 0, 0, 20),
		40, Color3.fromRGB(220, 220, 240), false,
		Enum.TextXAlignment.Center)

	makeLabel(itemGrid, info.msg,
		UDim2.new(1, -20, 0, 50),
		UDim2.new(0, 10, 0, 76),
		13, Color3.fromRGB(150, 150, 190), true,
		Enum.TextXAlignment.Center)
end

selectCategory = function(catBtnName, catBtn)
	-- Update active button styling
	if activeCatBtn then
		activeCatBtn.BackgroundTransparency = 0.5
		activeCatBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
	end
	activeCatBtn = catBtn
	catBtn.BackgroundTransparency = 0
	catBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

	local config = CATEGORY_CONFIG[catBtnName]
	if not config then return end

	-- Sub-frame categories
	if config.subFrame then
		showSubFrame(catBtnName)
		return
	end

	-- Combine category keyword with any search text
	local searchText = searchBar.Text
	local query = ""

	if #searchText >= 2 then
		query = searchText
	elseif config.keyword then
		query = config.keyword
	else
		query = "a" -- fallback to get any results
	end

	doSearch(query, config.assetType)
end

-- Wire up all Studio-built category buttons
for _, child in ipairs(categoryBar:GetChildren()) do
	if child:IsA("TextButton") then
		local btnName = child.Name
		child.BackgroundTransparency = 0.5
		child.TextColor3 = Color3.fromRGB(180, 180, 200)

		child.MouseButton1Click:Connect(function()
			selectCategory(btnName, child)
		end)
	end
end

-- Search bar — re-runs search for current category when text changes
searchBar:GetPropertyChangedSignal("Text"):Connect(function()
	local query = searchBar.Text
	if searchDebounce then task.cancel(searchDebounce) end

	if not activeCatBtn then return end
	local config = CATEGORY_CONFIG[activeCatBtn.Name]
	if not config or config.subFrame then return end

	if #query < 2 then
		-- Revert to category default
		searchDebounce = task.delay(0.4, function()
			doSearch(config.keyword or "a", config.assetType)
		end)
	else
		searchDebounce = task.delay(0.6, function()
			doSearch(query, config.assetType)
		end)
	end
end)

-- Store the original colors you set in Studio so we can restore them
local tabCatalogColor  = tabCatalog.BackgroundColor3
local tabOutfitsColor  = tabOutfits.BackgroundColor3
local tabInactiveColor = Color3.fromRGB(
	tabCatalog.BackgroundColor3.R * 0.5,
	tabCatalog.BackgroundColor3.G * 0.5,
	tabCatalog.BackgroundColor3.B * 0.5)

local function setWardrobeTab(tab)
	if tab == "catalog" then
		itemGrid.Visible = true
		categoryBar.Visible = true
		searchBar.Visible = true
		slotContainer.Visible = false
		-- Active tab keeps its Studio color, inactive tab goes dimmer
		tabCatalog.BackgroundColor3 = tabCatalogColor
		tabCatalog.BackgroundTransparency = 0
		tabOutfits.BackgroundTransparency = 0.4
	else
		itemGrid.Visible = false
		categoryBar.Visible = false
		searchBar.Visible = false
		slotContainer.Visible = true
		tabCatalog.BackgroundTransparency = 0.4
		tabOutfits.BackgroundColor3 = tabOutfitsColor
		tabOutfits.BackgroundTransparency = 0
	end
end

tabCatalog.MouseButton1Click:Connect(function() setWardrobeTab("catalog") end)
tabOutfits.MouseButton1Click:Connect(function() setWardrobeTab("outfits") end)
setWardrobeTab("catalog")

-- ============================================================
--  SAVE RESULT HANDLER
-- ============================================================

if SaveResultEvent then
	SaveResultEvent.OnClientEvent:Connect(function(success, slotNameOrMsg)
		if success then
			savedOutfits[slotNameOrMsg] = { displayName = slotNameOrMsg }
			setOutfitStatus("✅ Saved to " .. slotNameOrMsg .. "!", Color3.fromRGB(80, 220, 100))
		else
			setOutfitStatus("❌ " .. (slotNameOrMsg or "Save failed"), Color3.fromRGB(220, 80, 80))
		end
		for _, slot in ipairs(OUTFIT_SLOTS) do
			local r = slotRowMap[slot.slotName]
			if r and r.saveBtn.Text == "..." then
				r.saveBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 220)
			end
			refreshSlot(slot.slotName)
		end
	end)
end

-- Load saved outfits on join
task.spawn(function()
	if GetOutfitsFunc then
		local result = GetOutfitsFunc:InvokeServer()
		if result then
			for _, s in ipairs(result) do
				savedOutfits[s.slotName] = { displayName = s.displayName }
			end
			for _, slot in ipairs(OUTFIT_SLOTS) do refreshSlot(slot.slotName) end
		end
	end
end)

-- ============================================================
--  PHONE APP SCREENS — Open / Close
--  Uses Studio-built screens inside PhoneBody
-- ============================================================

local phoneAppScreens = {
	Messages = phoneBody:WaitForChild("MessageAppScreen"),
	Call     = phoneBody:WaitForChild("CallAppScreen"),
	Vehicles = phoneBody:WaitForChild("VehiclesAppScreen"),
	Settings = phoneBody:WaitForChild("SettingsAppScreen"),
	Bank     = phoneBody:WaitForChild("BankAppScreen"),
}

-- Hide all app screens at start, preserving their Y position
for _, screen in pairs(phoneAppScreens) do
	screen.Visible = false
	screen.Position = UDim2.new(1, 0, screen.Position.Y.Scale, screen.Position.Y.Offset)
end

local currentPhoneApp = nil

local function openPhoneApp(appId)
	if currentPhoneApp then
		local prev = phoneAppScreens[currentPhoneApp]
		if prev then
			local y = prev.Position.Y
			tween(prev, { Position = UDim2.new(1, 0, y.Scale, y.Offset) }, 0.2)
			task.delay(0.21, function() prev.Visible = false end)
		end
	end

	local screen = phoneAppScreens[appId]
	if not screen then return end

	-- Hide home screen icons so they can't be clicked through
	phoneScreen.Visible = false

	local y = screen.Position.Y
	currentPhoneApp = appId
	screen.Visible = true
	screen.Position = UDim2.new(1, 0, y.Scale, y.Offset)
	tween(screen, { Position = UDim2.new(0, 8, y.Scale, y.Offset) }, 0.25,
	Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

local function closePhoneApp()
	if not currentPhoneApp then return end
	local screen = phoneAppScreens[currentPhoneApp]
	if screen then
		local y = screen.Position.Y
		tween(screen, { Position = UDim2.new(1, 0, y.Scale, y.Offset) }, 0.22)
		task.delay(0.23, function()
			screen.Visible = false
			-- Restore home screen icons
			phoneScreen.Visible = true
		end)
	end
	currentPhoneApp = nil
end

-- Home button closes whatever phone app is open
homeButton.MouseButton1Click:Connect(function()
	closePhoneApp()
end)

-- ============================================================
--  WIRE UP APP ICON CLICKS
-- ============================================================

local function wireIcon(iconFrame, openFn)
	local clickBtn = addIconAnimation(iconFrame)
	if not clickBtn then return end
	clickBtn.MouseButton1Click:Connect(openFn)
end

-- Wardrobe opens fullscreen AvatarScreen
wireIcon(appIcons.Wardrobe, openAvatarScreen)

-- Phone-screen apps use Studio-built screens
wireIcon(appIcons.Messages, function() openPhoneApp("Messages") end)
wireIcon(appIcons.Call,     function() openPhoneApp("Call")     end)
wireIcon(appIcons.Vehicles, function() openPhoneApp("Vehicles") end)
wireIcon(appIcons.Settings, function() openPhoneApp("Settings") end)
wireIcon(appIcons.Bank,     function() openPhoneApp("Bank")     end)

-- Map and Teleport still placeholder for now
wireIcon(appIcons.Map,      function() openAppScreen("Map");      buildPlaceholder("Map")      end)
wireIcon(appIcons.Teleport, function() openAppScreen("Teleport"); buildPlaceholder("Teleport") end)

-- ============================================================
--  SETTINGS APP
-- ============================================================

local settingsScreen = phoneAppScreens.Settings

local TOGGLE_ON_COLOR  = Color3.fromRGB(50, 200, 80)
local TOGGLE_OFF_COLOR = Color3.fromRGB(180, 50, 50)

-- State table — both start Off
local settingsState = {
	Music = false,
	SFX   = false,
}

local function animateToggle(toggleFrame, knob, stateLabel, isOn)
	if isOn then
		tween(knob, { Position = UDim2.new(0, 10, 0, 0) }, 0.2, Enum.EasingStyle.Quad)
		tween(toggleFrame, { BackgroundColor3 = TOGGLE_ON_COLOR }, 0.2)
		if stateLabel then
			stateLabel.Text = "On"
			stateLabel.TextColor3 = TOGGLE_ON_COLOR
		end
	else
		tween(knob, { Position = UDim2.new(0, 0, 0, 0) }, 0.2, Enum.EasingStyle.Quad)
		tween(toggleFrame, { BackgroundColor3 = TOGGLE_OFF_COLOR }, 0.2)
		if stateLabel then
			stateLabel.Text = "Off"
			stateLabel.TextColor3 = TOGGLE_OFF_COLOR
		end
	end
end

local function setupToggle(rowName, toggleName, settingKey, onToggle)
	local row = settingsScreen:FindFirstChild(rowName)
	if not row then warn("Settings: cant find " .. rowName) return end

	local toggleFrame = row:FindFirstChild(toggleName)
	if not toggleFrame then warn("Settings: cant find " .. toggleName) return end

	local knob       = toggleFrame:FindFirstChild("Knob")
	local stateLabel = row:FindFirstChild("StateLabel")
		or toggleFrame:FindFirstChild("StateLabel")

	if not knob then warn("Settings: cant find Knob in " .. toggleName) return end

	-- Set initial visual state
	animateToggle(toggleFrame, knob, stateLabel, settingsState[settingKey])

	-- Make the whole row and toggle clickable
	local function doToggle()
		settingsState[settingKey] = not settingsState[settingKey]
		animateToggle(toggleFrame, knob, stateLabel, settingsState[settingKey])
		if onToggle then onToggle(settingsState[settingKey]) end
	end

	toggleFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			doToggle()
		end
	end)

	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			doToggle()
		end
	end)
end

-- Wire up toggles
-- Music: no sound object yet, just tracks state for when music is added
setupToggle("Row_Music", "Toggle_Music", "Music", function(isOn)
	-- TODO: when music Sound object is added, set Sound.Playing = isOn here
	print("Music:", isOn and "ON" or "OFF")
end)

-- SFX: same, tracks state for future use
setupToggle("Row_SFX", "Toggle_SFX", "SFX", function(isOn)
	-- TODO: when SFX are added, toggle them here
	print("SFX:", isOn and "ON" or "OFF")
end)

-- ============================================================
--  BANK APP
-- ============================================================

local bankScreen   = phoneAppScreens.Bank
local balanceLabel = bankScreen:FindFirstChild("BalanceLabel")
local depositLabel = bankScreen:FindFirstChild("DepositLabel")

local function formatMoney(amount)
	return "$" .. string.format("%,.2f", amount)
end

local function updateBalanceDisplay(amount)
	if balanceLabel then
		balanceLabel.Text = formatMoney(amount)
	end
end

-- Fetch balance when bank app opens
local originalOpenPhoneApp = openPhoneApp
openPhoneApp = function(appId)
	originalOpenPhoneApp(appId)
	if appId == "Bank" and GetBalanceFunc then
		task.spawn(function()
			local ok, balance = pcall(function()
				return GetBalanceFunc:InvokeServer()
			end)
			if ok then updateBalanceDisplay(balance) end
		end)
	end
end

-- Listen for balance updates pushed from server (e.g. when paid)
if UpdateBalanceEvent then
	UpdateBalanceEvent.OnClientEvent:Connect(function(newBalance)
		updateBalanceDisplay(newBalance)
	end)
end

-- ============================================================
--  RESPAWN
-- ============================================================

localPlayer.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid  = newChar:WaitForChild("Humanoid")
	equippedItems = {}
end)

print("✅ Phone UI loaded!")
