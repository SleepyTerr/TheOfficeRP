--[[
    ╔══════════════════════════════════════════════════════════╗
    ║              PHONE UI — LocalScript                      ║
    ║  Place inside: PhoneGui  (as a LocalScript)              ║
    ╚══════════════════════════════════════════════════════════╝
    
    This script runs on the CLIENT — meaning it runs separately
    on each player's computer. It handles everything visual:
    the phone toggle, app navigation, catalog search display,
    outfit slots UI, settings toggles, and bank display.
    
    It talks to the server (GameServer_Script) using Remotes
    whenever it needs to save data or do something that requires
    server authority (like equipping items or saving outfits).
]]

-- ============================================================
--  DEV ONLY LOCK
--  This block makes the phone only show for the two devs
--  while the game is still being built.
--  ⚠️ DELETE this entire block before publishing to players!
-- ============================================================

local DEVELOPER_IDS = {
    1332836159, -- Dev 1
    336655095,  -- Dev 2
}
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer  -- the player running this script on their computer

-- Check if this player is one of the devs
local isDevAccount = false
for _, id in ipairs(DEVELOPER_IDS) do
    if localPlayer.UserId == id then isDevAccount = true break end
end
-- If not a dev, destroy the script and stop running
if not isDevAccount then script:Destroy() return end

-- ============================================================
--  SERVICES
--  Built-in Roblox systems this script needs
-- ============================================================

local TweenService      = game:GetService("TweenService")      -- for smooth animations
local InsertService     = game:GetService("InsertService")      -- for loading catalog items onto the character
local ReplicatedStorage = game:GetService("ReplicatedStorage")  -- shared storage between server and client

-- Get the player's character and humanoid (the thing that controls the character)
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")

-- ============================================================
--  OUTFIT REMOTES
--  These are the communication channels between this script
--  and the server script. WaitForChild waits until the server
--  creates them (since server runs slightly before client)
-- ============================================================

local remoteFolder          = ReplicatedStorage:WaitForChild("OutfitRemotes", 10)
local SaveOutfitEvent       = remoteFolder and remoteFolder:WaitForChild("SaveOutfit")       -- tell server to save outfit
local LoadOutfitFunc        = remoteFolder and remoteFolder:WaitForChild("LoadOutfit")       -- ask server to apply outfit
local GetOutfitsFunc        = remoteFolder and remoteFolder:WaitForChild("GetOutfits")       -- ask server for saved outfit list
local DeleteOutfitEvent     = remoteFolder and remoteFolder:WaitForChild("DeleteOutfit")     -- tell server to delete outfit
local SaveResultEvent       = remoteFolder and remoteFolder:WaitForChild("SaveResult")       -- server tells us if save worked
local SearchCatalogFunc     = remoteFolder and remoteFolder:WaitForChild("SearchCatalog")    -- ask server to search catalog
local GetBalanceFunc        = remoteFolder and remoteFolder:WaitForChild("GetBalance")       -- ask server for bank balance
local UpdateBalanceEvent    = remoteFolder and remoteFolder:WaitForChild("UpdateBalance")    -- server tells us balance changed
local GetCharacterModelFunc = remoteFolder and remoteFolder:WaitForChild("GetCharacterModel") -- ask server to build avatar preview

-- ============================================================
--  GUI REFERENCES — Phone
--  These grab the actual GUI objects from the Studio hierarchy
--  so we can show/hide/move them in code
-- ============================================================

local phoneGui    = localPlayer.PlayerGui:WaitForChild("PhoneGui")   -- the main GUI container
local phoneBody   = phoneGui:WaitForChild("PhoneBody")               -- the phone frame itself
local phoneScreen = phoneBody:WaitForChild("PhoneScreen")            -- the app icon grid area
local homeButton  = phoneBody:WaitForChild("HomeButton")             -- the circle button at the bottom
local toggleBtn   = phoneGui:WaitForChild("ToggleButton")            -- the 📱 button to show/hide phone

-- Each app icon frame on the home screen
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

local avatarScreen   = phoneGui:WaitForChild("AvatarScreen")          -- the fullscreen wardrobe
local catalogPanel   = avatarScreen:WaitForChild("CatalogPanel")      -- left side with items + search
local closeButton    = avatarScreen:WaitForChild("CloseButton")        -- red X button
local tabCatalog     = catalogPanel:WaitForChild("TabCatalog")         -- "Catalog" tab button
local tabOutfits     = catalogPanel:WaitForChild("TabOutfits")         -- "Outfits" tab button
local searchBar      = catalogPanel:WaitForChild("SearchBar")          -- text input for searching
local categoryBar    = catalogPanel:WaitForChild("CategoryBar")        -- left sidebar with category buttons
local itemGrid       = catalogPanel:WaitForChild("ItemGrid")           -- grid where item cards appear
local slotContainer  = catalogPanel:WaitForChild("SlotContainer")      -- list of saved outfit slots

-- ============================================================
--  STATE
--  These variables track what's currently happening in the UI
-- ============================================================

local phoneVisible   = false   -- is the phone currently showing?
local currentApp     = nil     -- which app screen is open (if any)
local equippedItems  = {}      -- table of items the player has equipped: { assetId = instance }
local savedOutfits   = {}      -- table of saved outfit slots fetched from server
local activeCategory = "All"   -- currently selected category in the wardrobe
local searchDebounce = nil     -- timer that delays search until player stops typing
local slotRowMap     = {}      -- maps slot names to their UI row elements

-- ============================================================
--  OUTFIT SLOTS CONFIG
--  Defines the 6 outfit slots — their name, label, and color
-- ============================================================

local OUTFIT_SLOTS = {
    { slotName = "Work",   label = "💼 Work",   color = Color3.fromRGB(50, 110, 230)  },
    { slotName = "Home",   label = "🏠 Home",   color = Color3.fromRGB(60, 170, 90)   },
    { slotName = "Casual", label = "👕 Casual", color = Color3.fromRGB(200, 130, 40)  },
    { slotName = "Sport",  label = "⚽ Sport",  color = Color3.fromRGB(210, 70, 60)   },
    { slotName = "Formal", label = "🎩 Formal", color = Color3.fromRGB(130, 60, 200)  },
    { slotName = "Custom", label = "✨ Custom", color = Color3.fromRGB(180, 150, 20)  },
}

-- Old category system (kept for reference, replaced by CATEGORY_CONFIG below)
local CATEGORIES = { "All", "Shirts", "Pants", "Accessories", "Faces", "Outfits" }
local CATEGORY_TYPE_MAP = {
    All = nil, Shirts = "Shirt", Pants = "Pants",
    Accessories = "Hat", Faces = "Face", Outfits = "Outfit",
}

-- ============================================================
--  HELPERS
--  Small reusable functions used throughout the script
-- ============================================================

-- Smoothly animates any property of a GUI object
-- obj = the thing to animate, props = what to change, t = time in seconds
local function tween(obj, props, t, style, dir)
    TweenService:Create(obj,
        TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props):Play()
end

-- Creates a Frame with optional rounded corners
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
    if clip then f.ClipsDescendants = true end  -- hides anything outside the frame's bounds
    return f
end

-- Creates a TextLabel
local function makeLabel(parent, text, size, pos, textSize, color, wrap, xAlign)
    local l = Instance.new("TextLabel")
    l.Text = text
    l.Size = size
    l.Position = pos
    l.BackgroundTransparency = 1  -- no background, just text
    l.TextColor3 = color or Color3.fromRGB(220, 220, 240)
    l.TextSize = textSize or 13
    l.Font = Enum.Font.GothamSemibold
    l.TextWrapped = wrap or false  -- if true, text wraps to next line instead of cutting off
    l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

-- Creates a TextButton (clickable)
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
    b.AutoButtonColor = false  -- we handle hover effects manually
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = b
    return b
end

-- ============================================================
--  PHONE TOGGLE
--  Handles the 📱 button that shows/hides the phone
-- ============================================================

phoneBody.Visible = false    -- phone starts hidden
avatarScreen.Visible = false -- wardrobe starts hidden

toggleBtn.MouseButton1Click:Connect(function()
    phoneVisible = not phoneVisible  -- flip between true and false
    if phoneVisible then
        -- Show the phone by sliding it up from the bottom
        phoneBody.Visible = true
        phoneBody.Position = UDim2.new(
            phoneBody.Position.X.Scale,
            phoneBody.Position.X.Offset,
            1, 20)  -- start just off the bottom of the screen
        tween(phoneBody, {
            Position = UDim2.new(
                phoneBody.Position.X.Scale,
                phoneBody.Position.X.Offset,
                1, -(475 + 20))  -- slide up by the height of the phone (475px)
        }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)  -- bouncy spring effect
    else
        -- Hide the phone by sliding it back down
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
--  ⚠️ THIS SECTION IS CURRENTLY NOT WORKING
--
--  What it's supposed to do:
--    Show a 3D preview of your avatar inside the wardrobe
--
--  How it works (in theory):
--    1. Client calls GetCharacterModelFunc:InvokeServer()
--    2. Server builds avatar model and places it in WorldModel
--    3. Client sets up camera to look at it
--
--  Current issue:
--    The server is failing to build/place the model
--    Check the server script's GetCharacterModelFunc section
--    for detailed debug steps
-- ============================================================

local viewportFrame = avatarScreen:WaitForChild("CharacterPreview")  -- the ViewportFrame
local worldModel    = viewportFrame:WaitForChild("WorldModel")        -- container for 3D objects inside viewport

-- Create a camera to look into the ViewportFrame
-- CameraType.Scriptable means we control it manually with code
local viewportCamera = Instance.new("Camera")
viewportCamera.CameraType = Enum.CameraType.Scriptable
viewportCamera.Parent = viewportFrame
viewportFrame.CurrentCamera = viewportCamera  -- tell the viewport to use this camera

local previewModel = nil  -- will hold the character model once built

local function updateViewport()
    if not GetCharacterModelFunc then
        warn("ViewportFrame: remote not found")
        return
    end

    task.spawn(function()  -- task.spawn runs this in the background so UI doesn't freeze
        -- Ask the server to build the avatar model and place it in WorldModel
        local ok, success = pcall(function()
            return GetCharacterModelFunc:InvokeServer()
        end)

        if not ok or not success then
            warn("ViewportFrame: server failed to place model")
            return
        end

        -- Wait a tiny bit for the model to finish loading
        task.wait(0.1)

        -- Point the camera at where the character should be standing
        -- Camera position: 5 studs in front, 1.5 studs up
        -- Looking at: slightly below center (0.8 studs up) for a nice framing
        viewportFrame.CurrentCamera = viewportCamera
        viewportCamera.CFrame = CFrame.new(
            Vector3.new(0, 1.5, 5),   -- camera position
            Vector3.new(0, 0.8, 0)    -- what the camera looks at
        )
        print("✅ ViewportFrame camera set!")
    end)
end

-- ============================================================
--  AVATAR SCREEN — Open / Close
--  The fullscreen wardrobe that hides the phone
-- ============================================================

-- Forward declaration: selectCategory is defined later but openAvatarScreen needs to call it
-- In Lua, you can't call a function before it's defined unless you declare it first like this
local selectCategory

local function openAvatarScreen()
    -- Slide phone down and hide it
    tween(phoneBody, {
        Position = UDim2.new(
            phoneBody.Position.X.Scale,
            phoneBody.Position.X.Offset,
            1, 20)
    }, 0.2)
    task.delay(0.21, function() phoneBody.Visible = false end)
    phoneVisible = false

    -- Slide wardrobe in from the left
    avatarScreen.Visible = true
    avatarScreen.Position = UDim2.new(-1, 0, 0, 0)  -- start off screen to the left
    tween(avatarScreen, { Position = UDim2.new(0, 0, 0, 0) }, 0.3,
        Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    -- Try to update the character preview after screen is visible
    task.delay(0.35, updateViewport)

    -- Auto-select Featured category so items load immediately on open
    task.delay(0.4, function()
        local featuredBtn = categoryBar:FindFirstChild("Cat_Featured")
        if featuredBtn then
            selectCategory("Cat_Featured", featuredBtn)
        end
    end)
end

local function closeAvatarScreen()
    -- Slide wardrobe back out to the left
    tween(avatarScreen, { Position = UDim2.new(-1, 0, 0, 0) }, 0.25)
    task.delay(0.26, function()
        avatarScreen.Visible = false
    end)

    -- Bring phone back up with a slight delay for overlap effect
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
--  APP SCREEN (for Map and Teleport placeholder screens)
--  These are code-generated screens — the other apps use
--  Studio-built screens in phoneBody instead
-- ============================================================

-- Create a dark overlay screen that slides in from the right
local appScreen = makeFrame(phoneScreen,
    UDim2.new(1, 0, 1, 0),
    UDim2.new(1, 0, 0, 0),
    Color3.fromRGB(12, 12, 20), 0, true)
appScreen.ZIndex = 2    -- sits on top of the icons
appScreen.Visible = false

-- Title bar at the top
local appBar = makeFrame(appScreen,
    UDim2.new(1, 0, 0, 36),
    UDim2.new(0, 0, 0, 0),
    Color3.fromRGB(20, 20, 34))

local appTitleLabel = makeLabel(appBar, "",
    UDim2.new(1, 0, 1, 0),
    UDim2.new(0, 0, 0, 0),
    14, Color3.fromRGB(240, 240, 255), false,
    Enum.TextXAlignment.Center)

-- Content area below the title bar
local appContent = makeFrame(appScreen,
    UDim2.new(1, 0, 1, -36),
    UDim2.new(0, 0, 0, 36),
    Color3.fromRGB(0, 0, 0), 0, true)
appContent.BackgroundTransparency = 1

-- Slides the app screen in from the right
local function openAppScreen(title)
    currentApp = title
    appTitleLabel.Text = title
    -- Clear any previous content
    for _, child in ipairs(appContent:GetChildren()) do
        child:Destroy()
    end
    appScreen.Visible = true
    appScreen.Position = UDim2.new(1, 0, 0, 0)  -- start off screen to the right
    tween(appScreen, { Position = UDim2.new(0, 0, 0, 0) }, 0.25,
        Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Slides the app screen back out to the right
local function closeAppScreen()
    tween(appScreen, { Position = UDim2.new(1, 0, 0, 0) }, 0.22)
    task.delay(0.23, function()
        currentApp = nil
        appScreen.Visible = false
    end)
end

homeButton.ZIndex = 10  -- make sure home button is always clickable on top
homeButton.MouseButton1Click:Connect(function()
    closeAppScreen()
end)

-- ============================================================
--  APP ICON PRESS ANIMATION
--  Adds a satisfying press-down effect to app icons
-- ============================================================

local function addIconAnimation(iconFrame)
    local iconBg = iconFrame:FindFirstChild("IconBg")
    if not iconBg then return end

    -- Remove any duplicate click buttons from previous Play runs in Studio
    for _, child in ipairs(iconFrame:GetChildren()) do
        if child:IsA("TextButton") and child.Text == "" then
            child:Destroy()
        end
    end

    -- Invisible button that covers the whole icon and detects clicks
    local clickBtn = Instance.new("TextButton")
    clickBtn.Size = UDim2.new(1, 0, 1, 0)
    clickBtn.Position = UDim2.new(0, 0, 0, 0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.ZIndex = iconBg.ZIndex + 1
    clickBtn.Parent = iconFrame

    -- Shrink icon when pressed down
    clickBtn.MouseButton1Down:Connect(function()
        tween(iconBg, {
            Size = UDim2.new(0, 50, 0, 50),
            Position = UDim2.new(0.5, -25, 0, 6)
        }, 0.1)
    end)
    -- Spring back when released
    clickBtn.MouseButton1Up:Connect(function()
        tween(iconBg, {
            Size = UDim2.new(0, 58, 0, 58),
            Position = UDim2.new(0.5, -29, 0, 2)
        }, 0.15, Enum.EasingStyle.Back)
    end)

    return clickBtn
end

-- ============================================================
--  PLACEHOLDER APP
--  Shows a "coming soon" screen for Map and Teleport
-- ============================================================

local PLACEHOLDERS = {
    Map      = { icon = "🗺",  msg = "Map coming soon!\nYour office buildings\nwill appear here." },
    Teleport = { icon = "🚀", msg = "Teleport coming soon!\nJump to People, Houses\nand Apartments." },
}

local function buildPlaceholder(appId)
    local info = PLACEHOLDERS[appId]
    if not info then return end

    -- Big emoji icon
    makeLabel(appContent, info.icon,
        UDim2.new(1, 0, 0, 60),
        UDim2.new(0, 0, 0, 30),
        44, Color3.fromRGB(240, 240, 255), false,
        Enum.TextXAlignment.Center)

    -- Description text
    makeLabel(appContent, info.msg,
        UDim2.new(1, -20, 0, 70),
        UDim2.new(0, 10, 0, 100),
        12, Color3.fromRGB(150, 150, 190), true,
        Enum.TextXAlignment.Center)

    -- "In Development" badge
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
--  Puts catalog items on or takes them off the player's character
-- ============================================================

local function equipItem(item)
    -- Refresh character reference in case player respawned
    character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    humanoid  = character:WaitForChild("Humanoid")
    local ok, err = pcall(function()
        if item.Type == "Shirt" then
            -- Remove existing shirt first, then add new one
            for _, o in ipairs(character:GetChildren()) do
                if o:IsA("Shirt") then o:Destroy() end
            end
            local s = Instance.new("Shirt")
            s.ShirtTemplate = "rbxassetid://" .. item.AssetId  -- asset ID as texture
            s.Parent = character
            equippedItems[item.AssetId] = s  -- remember we equipped this

        elseif item.Type == "Pants" then
            for _, o in ipairs(character:GetChildren()) do
                if o:IsA("Pants") then o:Destroy() end
            end
            local p = Instance.new("Pants")
            p.PantsTemplate = "rbxassetid://" .. item.AssetId
            p.Parent = character
            equippedItems[item.AssetId] = p

        elseif item.Type == "Hat" or item.Type == "Face" then
            -- Accessories need to be loaded from Roblox's servers first
            local loaded = InsertService:LoadAsset(item.AssetId)
            local acc = loaded:FindFirstChildOfClass("Accessory")
                     or loaded:FindFirstChildOfClass("Hat")
            if acc then
                acc.Parent = character  -- move accessory onto character
                loaded:Destroy()        -- clean up the container
                equippedItems[item.AssetId] = acc
            else
                loaded:Destroy()
            end

        elseif item.Type == "Outfit" then
            -- Full outfit bundles use HumanoidDescription to apply everything at once
            local desc = Players:GetHumanoidDescriptionFromOutfitId(item.AssetId)
            humanoid:ApplyDescription(desc)
            equippedItems[item.AssetId] = true
        end
    end)
    if not ok then warn("Equip error: " .. tostring(err)) end
end

local function unequipItem(item)
    local ex = equippedItems[item.AssetId]
    if not ex then return end  -- wasn't equipped, nothing to do

    if item.Type == "Shirt" then
        for _, o in ipairs(character:GetChildren()) do
            if o:IsA("Shirt") then o:Destroy() end
        end
    elseif item.Type == "Pants" then
        for _, o in ipairs(character:GetChildren()) do
            if o:IsA("Pants") then o:Destroy() end
        end
    elseif typeof(ex) == "Instance" and ex.Parent then
        ex:Destroy()  -- remove accessories directly
    end
    equippedItems[item.AssetId] = nil  -- forget we had it equipped
end

-- ============================================================
--  ITEM CARD
--  Creates one catalog item card in the item grid
-- ============================================================

local function makeItemCard(itemData)
    -- Card background frame
    local card = makeFrame(itemGrid,
        UDim2.new(0, 82, 0, 102),
        UDim2.new(0, 0, 0, 0),
        Color3.fromRGB(24, 24, 38), 8)
    card:SetAttribute("ItemType", itemData.Type)  -- tag so we can filter by category

    -- Purple border outline
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(80, 60, 160)
    s.Thickness = 1
    s.Parent = card

    -- Item thumbnail image (Roblox provides these automatically from asset IDs)
    local thumb = Instance.new("ImageLabel")
    thumb.Size = UDim2.new(1, -8, 0, 60)
    thumb.Position = UDim2.new(0, 4, 0, 4)
    thumb.BackgroundColor3 = Color3.fromRGB(32, 32, 50)
    thumb.BorderSizePixel = 0
    thumb.Image = "rbxthumb://type=Asset&id=" .. itemData.AssetId .. "&w=420&h=420"
    thumb.Parent = card
    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 6); tc.Parent = thumb

    -- Item name label (truncated to fit)
    makeLabel(card, itemData.Name,
        UDim2.new(1, -6, 0, 22),
        UDim2.new(0, 3, 0, 66),
        9, Color3.fromRGB(200, 200, 220), true,
        Enum.TextXAlignment.Center)

    -- Equip / Remove button
    local equipBtn = makeButton(card, "Equip",
        UDim2.new(1, -8, 0, 18),
        UDim2.new(0, 4, 1, -22),
        Color3.fromRGB(70, 40, 160), 10, 6)

    local DEFAULT_C  = Color3.fromRGB(70, 40, 160)   -- purple = not equipped
    local EQUIPPED_C = Color3.fromRGB(180, 40, 40)   -- red = equipped (click to remove)

    equipBtn.MouseButton1Click:Connect(function()
        if equippedItems[itemData.AssetId] then
            -- Already equipped — remove it
            unequipItem(itemData)
            equipBtn.Text = "Equip"
            equipBtn.BackgroundColor3 = DEFAULT_C
        else
            -- Not equipped — equip it
            equipBtn.Text = "..."    -- loading state
            equipBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
            equipItem(itemData)
            if equippedItems[itemData.AssetId] then
                equipBtn.Text = "Remove"
                equipBtn.BackgroundColor3 = EQUIPPED_C
            else
                -- Equip failed
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
--  Shows messages like "✅ Saved to Work!" at the bottom of the wardrobe
-- ============================================================

local outfitStatusLabel = makeLabel(catalogPanel, "",
    UDim2.new(1, -20, 0, 20),
    UDim2.new(0, 10, 1, -26),
    11, Color3.fromRGB(120, 200, 120), false,
    Enum.TextXAlignment.Center)
outfitStatusLabel.Name = "OutfitStatusLabel"

-- Shows a message then clears it after 3 seconds
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
--  OUTFIT SLOT ROWS
--  Builds the 6 outfit slots inside SlotContainer
-- ============================================================

-- Updates a slot row's visual state based on whether it has a saved outfit
local function refreshSlot(slotName)
    local r = slotRowMap[slotName]
    if not r then return end
    local saved = savedOutfits[slotName]
    if saved then
        -- Slot has a saved outfit
        r.statusLbl.Text = "● Saved"
        r.statusLbl.TextColor3 = Color3.fromRGB(80, 200, 100)
        r.loadBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 60)
        r.saveBtn.Text = "Update"
        r.deleteBtn.Visible = true
    else
        -- Slot is empty
        r.statusLbl.Text = "Empty"
        r.statusLbl.TextColor3 = Color3.fromRGB(100, 100, 130)
        r.loadBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        r.saveBtn.Text = "Save"
        r.deleteBtn.Visible = false
    end
end

-- Build a row for each of the 6 outfit slots
for i, slot in ipairs(OUTFIT_SLOTS) do
    -- Row background
    local row = makeFrame(slotContainer,
        UDim2.new(1, 0, 0, 56),
        UDim2.new(0, 0, 0, 0),
        Color3.fromRGB(22, 22, 36), 10)
    row.LayoutOrder = i

    -- Colored left accent bar
    makeFrame(row, UDim2.new(0, 4, 1, -12), UDim2.new(0, 0, 0, 6), slot.color, 3)

    -- Slot label (e.g. "💼 Work")
    makeLabel(row, slot.label,
        UDim2.new(0, 160, 0, 22), UDim2.new(0, 14, 0, 6),
        14, Color3.fromRGB(230, 230, 250))

    -- Status text (shows "Empty" or "● Saved")
    local statusLbl = makeLabel(row, "Empty",
        UDim2.new(0, 120, 0, 18), UDim2.new(0, 14, 0, 30),
        11, Color3.fromRGB(100, 100, 130))

    -- Wear button — applies the saved outfit
    local loadBtn = makeButton(row, "Wear",
        UDim2.new(0, 70, 0, 34), UDim2.new(1, -222, 0, 11),
        Color3.fromRGB(40, 40, 60), 12, 8)

    -- Save button — saves current outfit to this slot
    local saveBtn = makeButton(row, "Save",
        UDim2.new(0, 80, 0, 34), UDim2.new(1, -134, 0, 11),
        Color3.fromRGB(50, 100, 220), 12, 8)

    -- Delete button — removes the saved outfit from this slot
    local deleteBtn = makeButton(row, "🗑",
        UDim2.new(0, 40, 0, 34), UDim2.new(1, -46, 0, 11),
        Color3.fromRGB(160, 40, 40), 13, 8)
    deleteBtn.Visible = false  -- hidden until slot has data

    -- Store references so refreshSlot can update them later
    slotRowMap[slot.slotName] = {
        statusLbl = statusLbl,
        loadBtn   = loadBtn,
        saveBtn   = saveBtn,
        deleteBtn = deleteBtn,
    }

    refreshSlot(slot.slotName)

    -- SAVE BUTTON: take a snapshot of current outfit and send to server
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

    -- WEAR BUTTON: ask server to apply the saved outfit to the character
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

    -- DELETE BUTTON: remove saved outfit from this slot
    deleteBtn.MouseButton1Click:Connect(function()
        if DeleteOutfitEvent then
            DeleteOutfitEvent:FireServer(slot.slotName)
            savedOutfits[slot.slotName] = nil  -- clear from local table too
            refreshSlot(slot.slotName)
            setOutfitStatus("🗑 " .. slot.label .. " deleted.", Color3.fromRGB(200, 100, 100))
        end
    end)
end

-- ============================================================
--  CATEGORY BUTTONS
--  Reads from Studio-built buttons in CategoryBar
--  Each button triggers a catalog search for that category
-- ============================================================

-- Config for each category button:
-- keyword = what to search when button is tapped
-- assetType = filter to only show this type of item (nil = show all)
-- subFrame = true means show a custom sub-screen instead of searching
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

local activeCatBtn = nil  -- the currently highlighted category button

-- ============================================================
--  LIVE SEARCH
--  Handles searching the catalog and displaying results
-- ============================================================

-- "Select a category" message shown before anything is loaded
local loadingLabel = makeLabel(itemGrid, "Select a category to browse items",
    UDim2.new(1, -10, 0, 40),
    UDim2.new(0, 5, 0, 20),
    13, Color3.fromRGB(120, 120, 160), true,
    Enum.TextXAlignment.Center)

-- Removes all item cards from the grid
local function clearItems()
    for _, child in ipairs(itemGrid:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end

-- Shows search results by creating item cards for each result
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

-- Sends a search request to the server and displays results
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

-- Shows a "coming soon" placeholder for Body and Animations categories
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

-- Called when a category button is tapped
-- Highlights the button and triggers the appropriate search
selectCategory = function(catBtnName, catBtn)
    -- Dim the previously active button
    if activeCatBtn then
        activeCatBtn.BackgroundTransparency = 0.5
        activeCatBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
    end
    -- Highlight the new active button
    activeCatBtn = catBtn
    catBtn.BackgroundTransparency = 0
    catBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

    local config = CATEGORY_CONFIG[catBtnName]
    if not config then return end

    -- Body and Animations show sub-frames instead of search results
    if config.subFrame then
        showSubFrame(catBtnName)
        return
    end

    -- Determine search query:
    -- If player has typed something in the search bar, use that
    -- Otherwise use the category's default keyword
    local searchText = searchBar.Text
    local query = ""

    if #searchText >= 2 then
        query = searchText
    elseif config.keyword then
        query = config.keyword
    else
        query = "a"  -- fallback: "a" returns general results
    end

    doSearch(query, config.assetType)
end

-- Connect all Studio-built category buttons to selectCategory
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

-- When search bar text changes, re-run search with current category filter
searchBar:GetPropertyChangedSignal("Text"):Connect(function()
    local query = searchBar.Text
    if searchDebounce then task.cancel(searchDebounce) end  -- cancel previous timer

    if not activeCatBtn then return end
    local config = CATEGORY_CONFIG[activeCatBtn.Name]
    if not config or config.subFrame then return end

    if #query < 2 then
        -- If search is cleared, go back to category default results
        searchDebounce = task.delay(0.4, function()
            doSearch(config.keyword or "a", config.assetType)
        end)
    else
        -- Wait 0.6s after last keypress before searching (debounce)
        searchDebounce = task.delay(0.6, function()
            doSearch(query, config.assetType)
        end)
    end
end)

-- ============================================================
--  WARDROBE TABS (Catalog / Outfits)
-- ============================================================

-- Remember original Studio colors so we can restore them
local tabCatalogColor  = tabCatalog.BackgroundColor3
local tabOutfitsColor  = tabOutfits.BackgroundColor3

-- Switches between the Catalog tab (item grid) and Outfits tab (saved slots)
local function setWardrobeTab(tab)
    if tab == "catalog" then
        itemGrid.Visible = true
        categoryBar.Visible = true
        searchBar.Visible = true
        slotContainer.Visible = false
        tabCatalog.BackgroundColor3 = tabCatalogColor
        tabCatalog.BackgroundTransparency = 0       -- active = full opacity
        tabOutfits.BackgroundTransparency = 0.4     -- inactive = dimmed
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
setWardrobeTab("catalog")  -- start on catalog tab

-- ============================================================
--  SAVE RESULT HANDLER
--  Listens for the server's response after saving an outfit
-- ============================================================

if SaveResultEvent then
    SaveResultEvent.OnClientEvent:Connect(function(success, slotNameOrMsg)
        if success then
            -- Update local data so the slot shows as saved
            savedOutfits[slotNameOrMsg] = { displayName = slotNameOrMsg }
            setOutfitStatus("✅ Saved to " .. slotNameOrMsg .. "!", Color3.fromRGB(80, 220, 100))
        else
            setOutfitStatus("❌ " .. (slotNameOrMsg or "Save failed"), Color3.fromRGB(220, 80, 80))
        end
        -- Reset all save buttons and refresh slot displays
        for _, slot in ipairs(OUTFIT_SLOTS) do
            local r = slotRowMap[slot.slotName]
            if r and r.saveBtn.Text == "..." then
                r.saveBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 220)
            end
            refreshSlot(slot.slotName)
        end
    end)
end

-- Fetch saved outfits from server when the game loads
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
--  These use Studio-built screens inside PhoneBody
--  Each one slides in from the right when opened
-- ============================================================

-- References to each Studio-built app screen
local phoneAppScreens = {
    Messages = phoneBody:WaitForChild("MessageAppScreen"),
    Call     = phoneBody:WaitForChild("CallAppScreen"),
    Vehicles = phoneBody:WaitForChild("VehiclesAppScreen"),
    Settings = phoneBody:WaitForChild("SettingsAppScreen"),
    Bank     = phoneBody:WaitForChild("BankAppScreen"),
}

-- Hide all app screens at start, keeping their Y position from Studio
for _, screen in pairs(phoneAppScreens) do
    screen.Visible = false
    screen.Position = UDim2.new(1, 0, screen.Position.Y.Scale, screen.Position.Y.Offset)
end

local currentPhoneApp = nil  -- which phone app is currently open

-- Opens a phone app screen by sliding it in from the right
local function openPhoneApp(appId)
    -- If another app is already open, slide it out first
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

    -- Hide the icon grid so icons can't be clicked through the app screen
    phoneScreen.Visible = false

    local y = screen.Position.Y
    currentPhoneApp = appId
    screen.Visible = true
    screen.Position = UDim2.new(1, 0, y.Scale, y.Offset)  -- start off right
    tween(screen, { Position = UDim2.new(0, 8, y.Scale, y.Offset) }, 0.25,
        Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Closes the current phone app and shows the home screen again
local function closePhoneApp()
    if not currentPhoneApp then return end
    local screen = phoneAppScreens[currentPhoneApp]
    if screen then
        local y = screen.Position.Y
        tween(screen, { Position = UDim2.new(1, 0, y.Scale, y.Offset) }, 0.22)
        task.delay(0.23, function()
            screen.Visible = false
            phoneScreen.Visible = true  -- bring back the icon grid
        end)
    end
    currentPhoneApp = nil
end

-- Home button closes the current app and goes back to icon grid
homeButton.MouseButton1Click:Connect(function()
    closePhoneApp()
end)

-- ============================================================
--  WIRE UP APP ICON CLICKS
--  Connects each icon to the correct open function
-- ============================================================

local function wireIcon(iconFrame, openFn)
    local clickBtn = addIconAnimation(iconFrame)  -- add press animation
    if not clickBtn then return end
    clickBtn.MouseButton1Click:Connect(openFn)    -- connect click to open function
end

-- Avatar/Wardrobe opens the fullscreen wardrobe (hides the phone)
wireIcon(appIcons.Wardrobe, openAvatarScreen)

-- These apps use Studio-built screens that slide over the phone
wireIcon(appIcons.Messages, function() openPhoneApp("Messages") end)
wireIcon(appIcons.Call,     function() openPhoneApp("Call")     end)
wireIcon(appIcons.Vehicles, function() openPhoneApp("Vehicles") end)
wireIcon(appIcons.Settings, function() openPhoneApp("Settings") end)
wireIcon(appIcons.Bank,     function() openPhoneApp("Bank")     end)

-- Map and Teleport still use code-generated placeholder screens
wireIcon(appIcons.Map,      function() openAppScreen("Map");      buildPlaceholder("Map")      end)
wireIcon(appIcons.Teleport, function() openAppScreen("Teleport"); buildPlaceholder("Teleport") end)

-- ============================================================
--  SETTINGS APP
--  Handles the toggle switches in SettingsAppScreen
-- ============================================================

local settingsScreen = phoneAppScreens.Settings

local TOGGLE_ON_COLOR  = Color3.fromRGB(50, 200, 80)   -- green when On
local TOGGLE_OFF_COLOR = Color3.fromRGB(180, 50, 50)   -- red when Off

-- Tracks the current state of each setting
local settingsState = {
    Music = false,  -- starts Off (no music in game yet)
    SFX   = false,  -- starts Off (no SFX in game yet)
}

-- Animates the toggle knob sliding left/right and changes track color
local function animateToggle(toggleFrame, knob, stateLabel, isOn)
    if isOn then
        tween(knob, { Position = UDim2.new(0, 10, 0, 0) }, 0.2, Enum.EasingStyle.Quad)  -- slide right
        tween(toggleFrame, { BackgroundColor3 = TOGGLE_ON_COLOR }, 0.2)
        if stateLabel then
            stateLabel.Text = "On"
            stateLabel.TextColor3 = TOGGLE_ON_COLOR
        end
    else
        tween(knob, { Position = UDim2.new(0, 0, 0, 0) }, 0.2, Enum.EasingStyle.Quad)  -- slide left
        tween(toggleFrame, { BackgroundColor3 = TOGGLE_OFF_COLOR }, 0.2)
        if stateLabel then
            stateLabel.Text = "Off"
            stateLabel.TextColor3 = TOGGLE_OFF_COLOR
        end
    end
end

-- Sets up a toggle row: finds the elements, sets initial state, connects click
local function setupToggle(rowName, toggleName, settingKey, onToggle)
    -- Find the row and toggle frame in the settings screen
    local row = settingsScreen:FindFirstChild(rowName)
    if not row then warn("Settings: cant find " .. rowName) return end

    local toggleFrame = row:FindFirstChild(toggleName)
    if not toggleFrame then warn("Settings: cant find " .. toggleName) return end

    local knob       = toggleFrame:FindFirstChild("Knob")         -- the sliding circle
    local stateLabel = row:FindFirstChild("StateLabel")            -- "On"/"Off" text
        or toggleFrame:FindFirstChild("StateLabel")

    if not knob then warn("Settings: cant find Knob in " .. toggleName) return end

    -- Set the visual state based on current settingsState value
    animateToggle(toggleFrame, knob, stateLabel, settingsState[settingKey])

    -- Flip the setting when clicked
    local function doToggle()
        settingsState[settingKey] = not settingsState[settingKey]  -- flip true/false
        animateToggle(toggleFrame, knob, stateLabel, settingsState[settingKey])
        if onToggle then onToggle(settingsState[settingKey]) end  -- call the callback
    end

    -- Both the toggle track AND the row background can be clicked
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

-- Wire up Music toggle
-- TODO: when a Music Sound object is added to the game,
-- replace the print with: game.Workspace.Music.Playing = isOn
setupToggle("Row_Music", "Toggle_Music", "Music", function(isOn)
    print("Music:", isOn and "ON" or "OFF")
end)

-- Wire up SFX toggle
-- TODO: when SFX Sound objects are added,
-- toggle them here with something like: SoundService:SetListener(...)
setupToggle("Row_SFX", "Toggle_SFX", "SFX", function(isOn)
    print("SFX:", isOn and "ON" or "OFF")
end)

-- ============================================================
--  BANK APP
--  Shows the player's current in-game balance
-- ============================================================

local bankScreen   = phoneAppScreens.Bank
local balanceLabel = bankScreen:FindFirstChild("BalanceLabel")  -- the "$0.00" text
local depositLabel = bankScreen:FindFirstChild("DepositLabel")  -- upcoming deposits (future use)

-- Formats a number as a dollar amount e.g. 1500 → "$1,500.00"
local function formatMoney(amount)
    return "$" .. string.format("%,.2f", amount)
end

-- Updates the balance label with a formatted amount
local function updateBalanceDisplay(amount)
    if balanceLabel then
        balanceLabel.Text = formatMoney(amount)
    end
end

-- When the Bank app opens, fetch the latest balance from the server
-- We wrap openPhoneApp to add this extra behavior just for Bank
local originalOpenPhoneApp = openPhoneApp
openPhoneApp = function(appId)
    originalOpenPhoneApp(appId)
    if appId == "Bank" and GetBalanceFunc then
        task.spawn(function()  -- run in background so UI doesn't freeze
            local ok, balance = pcall(function()
                return GetBalanceFunc:InvokeServer()
            end)
            if ok then updateBalanceDisplay(balance) end
        end)
    end
end

-- Listen for real-time balance updates from the server
-- (e.g. when the salary system pays out, the bank app updates immediately)
if UpdateBalanceEvent then
    UpdateBalanceEvent.OnClientEvent:Connect(function(newBalance)
        updateBalanceDisplay(newBalance)
    end)
end

-- ============================================================
--  RESPAWN
--  When the player respawns, update our character references
--  so equipping items still works on the new character
-- ============================================================

localPlayer.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid  = newChar:WaitForChild("Humanoid")
    equippedItems = {}  -- clear equipped items since it's a new character
end)

print("✅ Phone UI loaded!")
