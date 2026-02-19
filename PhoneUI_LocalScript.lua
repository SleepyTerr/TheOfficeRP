--[[
    ╔══════════════════════════════════════════════════════════╗
    ║              PHONE UI — LocalScript                      ║
    ║  Place inside: StarterGui  (as a LocalScript)            ║
    ║                                                          ║
    ║  Apps:                                                   ║
    ║    ✅ Wardrobe  — live search, equip items, outfit slots  ║
    ║    🔲 Map       — placeholder                            ║
    ║    🔲 Teleport  — placeholder                            ║
    ║    🔲 Messages  — placeholder                            ║
    ║    🔲 Call      — placeholder                            ║
    ║    🔲 Settings  — placeholder                            ║
    ╚══════════════════════════════════════════════════════════╝
]]

-- ============================================================
--  DEV ONLY — replace with your UserId
--  Delete this block when releasing to players
-- ============================================================
local DEVELOPER_IDS = {
    123456789, -- ← your Roblox UserId here
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
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local character  = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid   = character:WaitForChild("Humanoid")

-- ============================================================
--  OUTFIT REMOTES
-- ============================================================

local remoteFolder     = ReplicatedStorage:WaitForChild("OutfitRemotes", 10)
local SaveOutfitEvent  = remoteFolder and remoteFolder:WaitForChild("SaveOutfit")
local LoadOutfitFunc   = remoteFolder and remoteFolder:WaitForChild("LoadOutfit")
local GetOutfitsFunc   = remoteFolder and remoteFolder:WaitForChild("GetOutfits")
local DeleteOutfitEvent = remoteFolder and remoteFolder:WaitForChild("DeleteOutfit")
local SaveResultEvent  = remoteFolder and remoteFolder:WaitForChild("SaveResult")

-- ============================================================
--  STATE
-- ============================================================

local equippedItems  = {}
local savedOutfits   = {}
local activeCategory = "All"
local searchDebounce = nil
local currentAppPage = nil  -- which app is open inside the phone screen

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

-- ============================================================
--  CATEGORY FILTERS
-- ============================================================

local CATEGORIES = { "All", "Shirts", "Pants", "Accessories", "Faces", "Outfits" }

local CATEGORY_TYPE_MAP = {
    All         = nil,
    Shirts      = "Shirt",
    Pants       = "Pants",
    Accessories = "Hat",
    Faces       = "Face",
    Outfits     = "Outfit",
}

-- ============================================================
--  HELPERS
-- ============================================================

local function tween(obj, props, t, style, dir)
    TweenService:Create(obj,
        TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props):Play()
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(255,255,255)
    s.Transparency = 0.85
    s.Thickness = thickness or 1
    s.Parent = parent
    return s
end

local function label(parent, text, size, pos, props)
    local l = Instance.new("TextLabel")
    l.Text = text
    l.Size = size
    l.Position = pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency = 1
    l.TextColor3 = (props and props.color) or Color3.fromRGB(240,240,255)
    l.TextSize = (props and props.textSize) or 14
    l.Font = (props and props.font) or Enum.Font.GothamSemibold
    l.TextWrapped = (props and props.wrap) or false
    l.TextXAlignment = (props and props.xAlign) or Enum.TextXAlignment.Left
    l.TextYAlignment = (props and props.yAlign) or Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function btn(parent, text, size, pos, bg, props)
    local b = Instance.new("TextButton")
    b.Text = text
    b.Size = size
    b.Position = pos or UDim2.new(0,0,0,0)
    b.BackgroundColor3 = bg or Color3.fromRGB(50,120,240)
    b.TextColor3 = (props and props.textColor) or Color3.fromRGB(255,255,255)
    b.TextSize = (props and props.textSize) or 13
    b.Font = (props and props.font) or Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = parent
    corner(b, (props and props.radius) or 8)
    return b
end

local function frame(parent, size, pos, bg, props)
    local f = Instance.new("Frame")
    f.Size = size
    f.Position = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = bg or Color3.fromRGB(20,20,32)
    f.BorderSizePixel = 0
    f.Parent = parent
    if props and props.radius then corner(f, props.radius) end
    if props and props.clip then f.ClipsDescendants = true end
    return f
end

-- ============================================================
--  BUILD THE SCREEN GUI
-- ============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PhoneGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = localPlayer.PlayerGui

-- ============================================================
--  PHONE BODY (bottom-right corner)
-- ============================================================

local PHONE_W, PHONE_H = 220, 420

local phoneBody = frame(screenGui,
    UDim2.new(0, PHONE_W, 0, PHONE_H),
    UDim2.new(1, -(PHONE_W + 20), 1, -(PHONE_H + 20)),
    Color3.fromRGB(14, 14, 22))
phoneBody.Name = "PhoneBody"
corner(phoneBody, 32)
stroke(phoneBody, Color3.fromRGB(180,180,255), 1.5)

-- Subtle inner gradient feel via a semi-transparent overlay
local gloss = frame(phoneBody,
    UDim2.new(1,0,0.5,0), UDim2.new(0,0,0,0),
    Color3.fromRGB(255,255,255))
gloss.BackgroundTransparency = 0.96
corner(gloss, 32)

-- Notch / camera pill
local notch = frame(phoneBody, UDim2.new(0,60,0,16), UDim2.new(0.5,-30,0,10),
    Color3.fromRGB(8,8,14))
corner(notch, 10)

-- ── Status bar ───────────────────────────────────────────────
local statusBar = frame(phoneBody, UDim2.new(1,-20,0,20), UDim2.new(0,10,0,30),
    Color3.fromRGB(0,0,0))
statusBar.BackgroundTransparency = 1

-- Clock (updates every minute)
local clockLabel = label(statusBar, "12:00",
    UDim2.new(0,50,1,0), UDim2.new(0,0,0,0),
    { textSize = 11, font = Enum.Font.GothamBold, color = Color3.fromRGB(220,220,240) })

local function updateClock()
    -- Roblox doesn't expose real time easily in LocalScript without os.date
    -- We'll show a static placeholder — replace with your preferred time source
    clockLabel.Text = "●●:●●"
end
updateClock()

label(statusBar, "● ●  ▐▐", UDim2.new(0,70,1,0), UDim2.new(1,-72,0,0),
    { textSize = 10, color = Color3.fromRGB(180,220,180),
      xAlign = Enum.TextXAlignment.Right })

-- ============================================================
--  PHONE SCREEN (clipped content area)
-- ============================================================

local phoneScreen = frame(phoneBody,
    UDim2.new(1,-16,1,-110),
    UDim2.new(0,8,0,56),
    Color3.fromRGB(10,10,18), { radius = 24, clip = true })

-- ── Home screen (app grid) ───────────────────────────────────
local homeScreen = frame(phoneScreen, UDim2.new(1,0,1,0), UDim2.new(0,0,0,0),
    Color3.fromRGB(0,0,0))
homeScreen.BackgroundTransparency = 1
homeScreen.Name = "HomeScreen"

-- App grid layout
local appGrid = Instance.new("UIGridLayout")
appGrid.CellSize = UDim2.new(0, 62, 0, 74)
appGrid.CellPadding = UDim2.new(0, 10, 0, 10)
appGrid.SortOrder = Enum.SortOrder.LayoutOrder
appGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
appGrid.Parent = homeScreen

local appGridPad = Instance.new("UIPadding")
appGridPad.PaddingTop = UDim.new(0, 14)
appGridPad.Parent = homeScreen

-- ── App screen (shown when an app is open) ───────────────────
local appScreen = frame(phoneScreen, UDim2.new(1,0,1,0), UDim2.new(1,0,0,0),
    Color3.fromRGB(12,12,20), { clip = true })
appScreen.Name = "AppScreen"

-- App top bar
local appBar = frame(appScreen, UDim2.new(1,0,0,40), UDim2.new(0,0,0,0),
    Color3.fromRGB(18,18,30))

local appTitle = label(appBar, "App",
    UDim2.new(1,-80,1,0), UDim2.new(0,40,0,0),
    { textSize = 14, font = Enum.Font.GothamBold,
      xAlign = Enum.TextXAlignment.Center })

local backBtn = btn(appBar, "‹ Back",
    UDim2.new(0,64,0,28), UDim2.new(0,6,0,6),
    Color3.fromRGB(30,30,50), { textSize = 12, radius = 8 })

-- App content area (scrollable)
local appContent = frame(appScreen, UDim2.new(1,0,1,-40), UDim2.new(0,0,0,40),
    Color3.fromRGB(0,0,0))
appContent.BackgroundTransparency = 1
appContent.ClipsDescendants = true
appContent.Name = "AppContent"

-- ============================================================
--  PHONE BOTTOM BAR (home indicator)
-- ============================================================

local homeBar = frame(phoneBody, UDim2.new(0,60,0,4), UDim2.new(0.5,-30,1,-14),
    Color3.fromRGB(200,200,220))
corner(homeBar, 4)

-- ============================================================
--  APP DEFINITIONS
-- ============================================================

local APPS = {
    {
        id      = "wardrobe",
        label   = "Wardrobe",
        icon    = "👗",
        color   = Color3.fromRGB(90, 60, 180),
        order   = 1,
    },
    {
        id      = "map",
        label   = "Map",
        icon    = "🗺️",
        color   = Color3.fromRGB(40, 130, 80),
        order   = 2,
    },
    {
        id      = "teleport",
        label   = "Teleport",
        icon    = "🚀",
        color   = Color3.fromRGB(40, 100, 200),
        order   = 3,
    },
    {
        id      = "messages",
        label   = "Messages",
        icon    = "💬",
        color   = Color3.fromRGB(40, 180, 100),
        order   = 4,
    },
    {
        id      = "call",
        label   = "Call",
        icon    = "📞",
        color   = Color3.fromRGB(50, 190, 80),
        order   = 5,
    },
    {
        id      = "settings",
        label   = "Settings",
        icon    = "⚙️",
        color   = Color3.fromRGB(100, 100, 120),
        order   = 6,
    },
}

-- ============================================================
--  BUILD APP ICONS ON HOME SCREEN
-- ============================================================

local function makeAppIcon(app)
    local iconFrame = frame(homeScreen, UDim2.new(0,62,0,74), UDim2.new(0,0,0,0),
        Color3.fromRGB(0,0,0))
    iconFrame.BackgroundTransparency = 1
    iconFrame.LayoutOrder = app.order

    local iconBg = frame(iconFrame, UDim2.new(0,54,0,54), UDim2.new(0.5,-27,0,2),
        app.color, { radius = 14 })
    stroke(iconBg, Color3.fromRGB(255,255,255), 1)

    -- Gloss on icon
    local iconGloss = frame(iconBg, UDim2.new(1,0,0.45,0), UDim2.new(0,0,0,0),
        Color3.fromRGB(255,255,255))
    iconGloss.BackgroundTransparency = 0.88
    corner(iconGloss, 14)

    label(iconBg, app.icon, UDim2.new(1,0,1,0), UDim2.new(0,0,0,0),
        { textSize = 26, xAlign = Enum.TextXAlignment.Center,
          yAlign = Enum.TextYAlignment.Center })

    label(iconFrame, app.label, UDim2.new(1,0,0,16), UDim2.new(0,0,0,58),
        { textSize = 10, xAlign = Enum.TextXAlignment.Center,
          color = Color3.fromRGB(200,200,220) })

    -- Click to open app
    local clickBtn = Instance.new("TextButton")
    clickBtn.Size = UDim2.new(1,0,1,0)
    clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""
    clickBtn.Parent = iconFrame

    -- Press scale animation
    clickBtn.MouseButton1Down:Connect(function()
        tween(iconBg, { Size = UDim2.new(0,48,0,48),
            Position = UDim2.new(0.5,-24,0,5) }, 0.1)
    end)
    clickBtn.MouseButton1Up:Connect(function()
        tween(iconBg, { Size = UDim2.new(0,54,0,54),
            Position = UDim2.new(0.5,-27,0,2) }, 0.15, Enum.EasingStyle.Back)
    end)

    return clickBtn
end

-- ============================================================
--  OPEN / CLOSE APP SCREEN
-- ============================================================

local function openApp(appId, appLabel)
    currentAppPage = appId
    appTitle.Text = appLabel

    -- Slide app screen in from right
    appScreen.Position = UDim2.new(1, 0, 0, 0)
    tween(appScreen, { Position = UDim2.new(0,0,0,0) }, 0.25,
        Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    -- Clear previous content
    for _, child in ipairs(appContent:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function closeApp()
    tween(appScreen, { Position = UDim2.new(1,0,0,0) }, 0.22)
    task.delay(0.23, function() currentAppPage = nil end)
end

backBtn.MouseButton1Click:Connect(closeApp)

-- ============================================================
--  ══ WARDROBE APP ══════════════════════════════════════════
-- ============================================================

--  Tab bar
local wardrobeTabBar = frame(nil, UDim2.new(1,0,0,34), UDim2.new(0,0,0,0),
    Color3.fromRGB(18,18,30))
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = wardrobeTabBar

local wardrobeCatalogTab = btn(wardrobeTabBar, "🛍 Catalog",
    UDim2.new(0.5,0,1,0), UDim2.new(0,0,0,0),
    Color3.fromRGB(70,40,160), { textSize = 12, radius = 0 })
local wardrobeOutfitsTab = btn(wardrobeTabBar, "👔 Outfits",
    UDim2.new(0.5,0,1,0), UDim2.new(0.5,0,0,0),
    Color3.fromRGB(25,25,38), { textSize = 12, radius = 0 })

-- Catalog page
local catalogPage = frame(nil, UDim2.new(1,0,1,-34), UDim2.new(0,0,0,34),
    Color3.fromRGB(0,0,0))
catalogPage.BackgroundTransparency = 1
catalogPage.ClipsDescendants = true

-- Search bar
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1,-12,0,28)
searchBox.Position = UDim2.new(0,6,0,4)
searchBox.BackgroundColor3 = Color3.fromRGB(30,30,48)
searchBox.TextColor3 = Color3.fromRGB(220,220,240)
searchBox.PlaceholderText = "🔍  Search catalog..."
searchBox.PlaceholderColor3 = Color3.fromRGB(100,100,130)
searchBox.Text = ""
searchBox.TextSize = 12
searchBox.Font = Enum.Font.Gotham
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.Parent = catalogPage
corner(searchBox, 8)
local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0,8)
searchPad.Parent = searchBox

-- Category scroll
local catScroll = Instance.new("ScrollingFrame")
catScroll.Size = UDim2.new(1,0,0,28)
catScroll.Position = UDim2.new(0,0,0,36)
catScroll.BackgroundTransparency = 1
catScroll.BorderSizePixel = 0
catScroll.ScrollBarThickness = 0
catScroll.CanvasSize = UDim2.new(0,0,0,0)
catScroll.ScrollingDirection = Enum.ScrollingDirection.X
catScroll.Parent = catalogPage

local catListLayout = Instance.new("UIListLayout")
catListLayout.FillDirection = Enum.FillDirection.Horizontal
catListLayout.SortOrder = Enum.SortOrder.LayoutOrder
catListLayout.Padding = UDim.new(0,4)
catListLayout.Parent = catScroll

local catPad = Instance.new("UIPadding")
catPad.PaddingLeft = UDim.new(0,6)
catPad.Parent = catScroll

catListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    catScroll.CanvasSize = UDim2.new(0, catListLayout.AbsoluteContentSize.X + 12, 0, 0)
end)

-- Item scroll grid
local itemScroll = Instance.new("ScrollingFrame")
itemScroll.Size = UDim2.new(1,0,1,-68)
itemScroll.Position = UDim2.new(0,0,0,68)
itemScroll.BackgroundTransparency = 1
itemScroll.BorderSizePixel = 0
itemScroll.ScrollBarThickness = 3
itemScroll.ScrollBarImageColor3 = Color3.fromRGB(100,80,200)
itemScroll.CanvasSize = UDim2.new(0,0,0,0)
itemScroll.Parent = catalogPage

local itemGrid = Instance.new("UIGridLayout")
itemGrid.CellSize = UDim2.new(0, 82, 0, 102)
itemGrid.CellPadding = UDim2.new(0, 6, 0, 6)
itemGrid.SortOrder = Enum.SortOrder.LayoutOrder
itemGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
itemGrid.Parent = itemScroll

local itemPad = Instance.new("UIPadding")
itemPad.PaddingTop = UDim.new(0,4)
itemPad.Parent = itemScroll

itemGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    itemScroll.CanvasSize = UDim2.new(0,0,0,itemGrid.AbsoluteContentSize.Y + 12)
end)

-- Outfits page
local outfitsPage = frame(nil, UDim2.new(1,0,1,-34), UDim2.new(0,0,0,34),
    Color3.fromRGB(0,0,0))
outfitsPage.BackgroundTransparency = 1
outfitsPage.Visible = false
outfitsPage.ClipsDescendants = true

local outfitStatusLabel = label(outfitsPage, "",
    UDim2.new(1,-12,0,22), UDim2.new(0,6,0,4),
    { textSize = 11, color = Color3.fromRGB(120,200,120),
      xAlign = Enum.TextXAlignment.Center })

local slotScroll = Instance.new("ScrollingFrame")
slotScroll.Size = UDim2.new(1,0,1,-30)
slotScroll.Position = UDim2.new(0,0,0,28)
slotScroll.BackgroundTransparency = 1
slotScroll.BorderSizePixel = 0
slotScroll.ScrollBarThickness = 3
slotScroll.ScrollBarImageColor3 = Color3.fromRGB(100,80,200)
slotScroll.CanvasSize = UDim2.new(0,0,0,0)
slotScroll.Parent = outfitsPage

local slotListLayout = Instance.new("UIListLayout")
slotListLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotListLayout.Padding = UDim.new(0, 5)
slotListLayout.Parent = slotScroll

local slotPad = Instance.new("UIPadding")
slotPad.PaddingLeft = UDim.new(0,6)
slotPad.PaddingRight = UDim.new(0,6)
slotPad.PaddingTop = UDim.new(0,4)
slotPad.Parent = slotScroll

slotListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    slotScroll.CanvasSize = UDim2.new(0,0,0,slotListLayout.AbsoluteContentSize.Y+12)
end)

-- ============================================================
--  OUTFIT STATUS HELPER
-- ============================================================

local function setOutfitStatus(msg, color)
    outfitStatusLabel.Text = msg
    outfitStatusLabel.TextColor3 = color or Color3.fromRGB(120,200,120)
    task.delay(3, function()
        if outfitStatusLabel.Text == msg then
            outfitStatusLabel.Text = ""
        end
    end)
end

-- ============================================================
--  SLOT ROWS
-- ============================================================

local slotRowMap = {}

local function refreshSlot(slotName)
    local r = slotRowMap[slotName]
    if not r then return end
    local saved = savedOutfits[slotName]
    if saved then
        r.statusLbl.Text = "● Saved"
        r.statusLbl.TextColor3 = Color3.fromRGB(80,200,100)
        r.loadBtn.BackgroundColor3 = Color3.fromRGB(40,130,60)
        r.saveBtn.Text = "Update"
        r.deleteBtn.Visible = true
    else
        r.statusLbl.Text = "Empty"
        r.statusLbl.TextColor3 = Color3.fromRGB(100,100,130)
        r.loadBtn.BackgroundColor3 = Color3.fromRGB(40,40,60)
        r.saveBtn.Text = "Save"
        r.deleteBtn.Visible = false
    end
end

for i, slot in ipairs(OUTFIT_SLOTS) do
    local row = frame(slotScroll, UDim2.new(1,0,0,52), UDim2.new(0,0,0,0),
        Color3.fromRGB(22,22,36), { radius = 10 })
    row.LayoutOrder = i

    -- Accent
    local acc = frame(row, UDim2.new(0,4,1,-10), UDim2.new(0,0,0,5), slot.color, { radius = 3 })

    label(row, slot.label, UDim2.new(0,90,0,20), UDim2.new(0,12,0,6),
        { textSize = 13, font = Enum.Font.GothamBold })

    local statusLbl = label(row, "Empty", UDim2.new(0,80,0,16), UDim2.new(0,12,0,28),
        { textSize = 10, color = Color3.fromRGB(100,100,130) })

    local loadBtn = btn(row, "Wear",
        UDim2.new(0,50,0,30), UDim2.new(1,-164,0,11),
        Color3.fromRGB(40,40,60), { textSize = 11, radius = 7 })

    local saveBtn = btn(row, "Save",
        UDim2.new(0,58,0,30), UDim2.new(1,-106,0,11),
        Color3.fromRGB(50,100,220), { textSize = 11, radius = 7 })

    local deleteBtn = btn(row, "🗑",
        UDim2.new(0,30,0,30), UDim2.new(1,-38,0,11),
        Color3.fromRGB(160,40,40), { textSize = 12, radius = 7 })
    deleteBtn.Visible = false

    slotRowMap[slot.slotName] = {
        statusLbl  = statusLbl,
        loadBtn    = loadBtn,
        saveBtn    = saveBtn,
        deleteBtn  = deleteBtn,
    }

    saveBtn.MouseButton1Click:Connect(function()
        saveBtn.Text = "..."
        saveBtn.BackgroundColor3 = Color3.fromRGB(70,70,70)
        if SaveOutfitEvent then
            SaveOutfitEvent:FireServer(slot.slotName, slot.slotName)
        else
            setOutfitStatus("⚠ Server not connected", Color3.fromRGB(220,150,50))
            saveBtn.Text = "Save"
            saveBtn.BackgroundColor3 = Color3.fromRGB(50,100,220)
        end
    end)

    loadBtn.MouseButton1Click:Connect(function()
        if not savedOutfits[slot.slotName] then
            setOutfitStatus("Nothing saved in " .. slot.label .. " yet!", Color3.fromRGB(220,180,50))
            return
        end
        loadBtn.Text = "..."
        if LoadOutfitFunc then
            local ok, msg = LoadOutfitFunc:InvokeServer(slot.slotName)
            if ok then
                setOutfitStatus("✅ " .. slot.label .. " applied!", Color3.fromRGB(80,220,100))
            else
                setOutfitStatus("❌ " .. (msg or "Failed"), Color3.fromRGB(220,80,80))
            end
        end
        loadBtn.Text = "Wear"
    end)

    deleteBtn.MouseButton1Click:Connect(function()
        if DeleteOutfitEvent then
            DeleteOutfitEvent:FireServer(slot.slotName)
            savedOutfits[slot.slotName] = nil
            refreshSlot(slot.slotName)
            setOutfitStatus("🗑 " .. slot.label .. " deleted.", Color3.fromRGB(200,100,100))
        end
    end)
end

-- Save result handler
if SaveResultEvent then
    SaveResultEvent.OnClientEvent:Connect(function(success, slotNameOrMsg)
        if success then
            savedOutfits[slotNameOrMsg] = { displayName = slotNameOrMsg }
            setOutfitStatus("✅ Saved to " .. slotNameOrMsg .. "!", Color3.fromRGB(80,220,100))
        else
            setOutfitStatus("❌ " .. (slotNameOrMsg or "Save failed"), Color3.fromRGB(220,80,80))
        end
        for _, slot in ipairs(OUTFIT_SLOTS) do
            local r = slotRowMap[slot.slotName]
            if r and r.saveBtn.Text == "..." then
                r.saveBtn.BackgroundColor3 = Color3.fromRGB(50,100,220)
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
--  WARDROBE TABS LOGIC
-- ============================================================

local function setWardrobeTab(tab)
    if tab == "catalog" then
        catalogPage.Visible = true
        outfitsPage.Visible = false
        wardrobeCatalogTab.BackgroundColor3 = Color3.fromRGB(70,40,160)
        wardrobeOutfitsTab.BackgroundColor3 = Color3.fromRGB(25,25,38)
    else
        catalogPage.Visible = false
        outfitsPage.Visible = true
        wardrobeCatalogTab.BackgroundColor3 = Color3.fromRGB(25,25,38)
        wardrobeOutfitsTab.BackgroundColor3 = Color3.fromRGB(70,40,160)
    end
end

wardrobeCatalogTab.MouseButton1Click:Connect(function() setWardrobeTab("catalog") end)
wardrobeOutfitsTab.MouseButton1Click:Connect(function() setWardrobeTab("outfits") end)

-- ============================================================
--  CATEGORY FILTER BUTTONS
-- ============================================================

local catBtnMap = {}

local function setCategory(cat)
    activeCategory = cat
    for catName, catBtn in pairs(catBtnMap) do
        local active = catName == cat
        catBtn.BackgroundColor3 = active
            and Color3.fromRGB(90,50,200)
            or  Color3.fromRGB(28,28,45)
        catBtn.TextColor3 = active
            and Color3.fromRGB(255,255,255)
            or  Color3.fromRGB(160,160,200)
    end
end

for i, catName in ipairs(CATEGORIES) do
    local catBtn = btn(catScroll, catName,
        UDim2.new(0,0,1,-4), UDim2.new(0,0,0,2),
        Color3.fromRGB(28,28,45),
        { textSize = 11, radius = 6 })
    catBtn.AutomaticSize = Enum.AutomaticSize.X
    catBtn.LayoutOrder = i

    local cp = Instance.new("UIPadding")
    cp.PaddingLeft = UDim.new(0,8)
    cp.PaddingRight = UDim.new(0,8)
    cp.Parent = catBtn

    catBtnMap[catName] = catBtn
    catBtn.MouseButton1Click:Connect(function()
        setCategory(catName)
        searchBox.Text = ""
        -- Re-show/hide cards
        for _, card in ipairs(itemScroll:GetChildren()) do
            if card:IsA("Frame") then
                local typeTag = card:GetAttribute("ItemType")
                if typeTag then
                    local filter = CATEGORY_TYPE_MAP[catName]
                    card.Visible = (filter == nil) or (typeTag == filter)
                end
            end
        end
    end)
end

setCategory("All")

-- ============================================================
--  EQUIP / UNEQUIP
-- ============================================================

local function equipItem(item)
    character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    humanoid  = character:WaitForChild("Humanoid")
    local ok, err = pcall(function()
        if item.Type == "Shirt" then
            for _, o in ipairs(character:GetChildren()) do if o:IsA("Shirt") then o:Destroy() end end
            local s = Instance.new("Shirt")
            s.ShirtTemplate = "rbxassetid://"..item.AssetId
            s.Parent = character
            equippedItems[item.AssetId] = s
        elseif item.Type == "Pants" then
            for _, o in ipairs(character:GetChildren()) do if o:IsA("Pants") then o:Destroy() end end
            local p = Instance.new("Pants")
            p.PantsTemplate = "rbxassetid://"..item.AssetId
            p.Parent = character
            equippedItems[item.AssetId] = p
        elseif item.Type == "Hat" or item.Type == "Face" or item.Type == "Gear" then
            local loaded = InsertService:LoadAsset(item.AssetId)
            local acc = loaded:FindFirstChildOfClass("Accessory") or loaded:FindFirstChildOfClass("Hat")
            if acc then acc.Parent = character; loaded:Destroy(); equippedItems[item.AssetId] = acc
            else loaded:Destroy() end
        elseif item.Type == "Outfit" then
            local desc = Players:GetHumanoidDescriptionFromOutfitId(item.AssetId)
            humanoid:ApplyDescription(desc)
            equippedItems[item.AssetId] = true
        end
    end)
    if not ok then warn("Equip error: "..tostring(err)) end
end

local function unequipItem(item)
    local ex = equippedItems[item.AssetId]
    if not ex then return end
    if item.Type == "Shirt" then
        for _, o in ipairs(character:GetChildren()) do if o:IsA("Shirt") then o:Destroy() end end
    elseif item.Type == "Pants" then
        for _, o in ipairs(character:GetChildren()) do if o:IsA("Pants") then o:Destroy() end end
    elseif typeof(ex) == "Instance" and ex.Parent then
        ex:Destroy()
    end
    equippedItems[item.AssetId] = nil
end

-- ============================================================
--  CREATE ITEM CARD
-- ============================================================

local function makeItemCard(itemData)
    local card = frame(itemScroll, UDim2.new(0,82,0,102), UDim2.new(0,0,0,0),
        Color3.fromRGB(24,24,38), { radius = 8 })
    card:SetAttribute("ItemType", itemData.Type)
    stroke(card, Color3.fromRGB(150,130,255), 1)

    local thumb = Instance.new("ImageLabel")
    thumb.Size = UDim2.new(1,-8,0,60)
    thumb.Position = UDim2.new(0,4,0,4)
    thumb.BackgroundColor3 = Color3.fromRGB(32,32,50)
    thumb.BorderSizePixel = 0
    thumb.Image = "rbxthumb://type=Asset&id="..itemData.AssetId.."&w=420&h=420"
    thumb.Parent = card
    corner(thumb, 6)

    label(card, itemData.Name,
        UDim2.new(1,-6,0,22), UDim2.new(0,3,0,65),
        { textSize = 9, wrap = true, color = Color3.fromRGB(200,200,220),
          xAlign = Enum.TextXAlignment.Center })

    local equipBtn = btn(card, "Equip",
        UDim2.new(1,-8,0,18), UDim2.new(0,4,1,-22),
        Color3.fromRGB(70,40,160), { textSize = 10, radius = 6 })

    local DEFAULT_C  = Color3.fromRGB(70,40,160)
    local EQUIPPED_C = Color3.fromRGB(180,40,40)

    equipBtn.MouseButton1Click:Connect(function()
        if equippedItems[itemData.AssetId] then
            unequipItem(itemData)
            equipBtn.Text = "Equip"
            equipBtn.BackgroundColor3 = DEFAULT_C
        else
            equipBtn.Text = "..."
            equipBtn.BackgroundColor3 = Color3.fromRGB(70,70,70)
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
--  LIVE SEARCH via Roblox Catalog API
-- ============================================================

-- The catalog search goes through a server proxy Script because
-- HttpService can only be called from the server, not LocalScripts.
-- Results come back via a RemoteFunction.

local SearchFunc = remoteFolder and remoteFolder:FindFirstChild("SearchCatalog")

local loadingLabel = label(itemScroll, "Type to search the catalog...",
    UDim2.new(1,0,0,30), UDim2.new(0,0,0,10),
    { textSize = 11, color = Color3.fromRGB(120,120,160),
      xAlign = Enum.TextXAlignment.Center })

local function clearItems()
    for _, child in ipairs(itemScroll:GetChildren()) do
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

local function doSearch(query)
    if not SearchFunc then
        loadingLabel.Text = "⚠ Search server not connected."
        loadingLabel.Visible = true
        return
    end

    clearItems()
    loadingLabel.Text = "Searching..."
    loadingLabel.Visible = true

    -- Fire to server, get results back
    local ok, results = pcall(function()
        return SearchFunc:InvokeServer(query, CATEGORY_TYPE_MAP[activeCategory])
    end)

    if ok and results then
        displayResults(results)
    else
        loadingLabel.Text = "Search failed. Try again."
        loadingLabel.Visible = true
    end
end

-- Debounced search on text change
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local query = searchBox.Text
    if searchDebounce then task.cancel(searchDebounce) end
    if #query < 2 then
        clearItems()
        loadingLabel.Text = "Type to search the catalog..."
        loadingLabel.Visible = true
        return
    end
    searchDebounce = task.delay(0.6, function()
        doSearch(query)
    end)
end)

-- ============================================================
--  WIRE WARDROBE APP INTO APP SCREEN
-- ============================================================

local function buildWardrobeApp()
    wardrobeTabBar.Parent = appContent
    catalogPage.Parent = appContent
    outfitsPage.Parent = appContent
    setWardrobeTab("catalog")
end

-- ============================================================
--  PLACEHOLDER APP BUILDER
-- ============================================================

local PLACEHOLDER_MESSAGES = {
    map      = { icon = "🗺️", msg = "Map coming soon!\nYour office buildings\nwill appear here." },
    teleport = { icon = "🚀", msg = "Teleport coming soon!\nJump to People, Houses,\nand Apartments." },
    messages = { icon = "💬", msg = "Messages coming soon!\nChat with other players\nin the game." },
    call     = { icon = "📞", msg = "Calls coming soon!\nVoice chat with your\ncolleagues." },
    settings = { icon = "⚙️", msg = "Settings coming soon!\nCustomise your game\nexperience." },
}

local function buildPlaceholder(appId)
    local info = PLACEHOLDER_MESSAGES[appId]
    if not info then return end

    local iconLbl = label(appContent, info.icon,
        UDim2.new(1,0,0,60), UDim2.new(0,0,0,30),
        { textSize = 44, xAlign = Enum.TextXAlignment.Center })

    label(appContent, info.msg,
        UDim2.new(1,-20,0,60), UDim2.new(0,10,0,96),
        { textSize = 13, color = Color3.fromRGB(140,140,180),
          xAlign = Enum.TextXAlignment.Center, wrap = true })

    local comingSoonBadge = frame(appContent,
        UDim2.new(0,130,0,30), UDim2.new(0.5,-65,0,164),
        Color3.fromRGB(70,40,140), { radius = 15 })
    label(comingSoonBadge, "🔨 In Development",
        UDim2.new(1,0,1,0), UDim2.new(0,0,0,0),
        { textSize = 11, xAlign = Enum.TextXAlignment.Center })
end

-- ============================================================
--  BUILD APP ICONS & WIRE OPEN HANDLERS
-- ============================================================

for _, app in ipairs(APPS) do
    local clickBtn = makeAppIcon(app)

    clickBtn.MouseButton1Click:Connect(function()
        openApp(app.id, app.label)

        if app.id == "wardrobe" then
            buildWardrobeApp()
        else
            buildPlaceholder(app.id)
        end
    end)
end

-- ============================================================
--  PHONE TOGGLE BUTTON (small pill above phone)
-- ============================================================

local toggleBtn = btn(screenGui, "📱",
    UDim2.new(0,38,0,38),
    UDim2.new(1, -(PHONE_W + 20) + (PHONE_W/2) - 19, 1, -(PHONE_H + 20) - 46),
    Color3.fromRGB(30,30,50), { textSize = 20, radius = 12 })
stroke(toggleBtn, Color3.fromRGB(180,180,255), 1)

local phoneVisible = true

toggleBtn.MouseButton1Click:Connect(function()
    phoneVisible = not phoneVisible
    if phoneVisible then
        phoneBody.Visible = true
        tween(phoneBody, { Position = UDim2.new(1,-(PHONE_W+20),1,-(PHONE_H+20)) }, 0.25,
            Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    else
        tween(phoneBody, { Position = UDim2.new(1,-(PHONE_W+20),1,20) }, 0.2)
        task.delay(0.21, function() phoneBody.Visible = false end)
    end
end)

-- ============================================================
--  RESPAWN HANDLING
-- ============================================================

localPlayer.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid  = newChar:WaitForChild("Humanoid")
    equippedItems = {}
end)

print("✅ Phone UI loaded!")
