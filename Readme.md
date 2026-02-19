# 🏢 The Office RP — Phone UI System

A fully custom phone UI system for a Roblox office roleplay game. Built entirely by hand in Roblox Studio with a LocalScript + Server Script powering all the functionality.

---

## 📁 File Structure

```
TheOfficeRP/
  src/
    Client/
      PhoneUI_LocalScript.lua      ← Place inside PhoneGui (LocalScript)
    Server/
      GameServer_Script.lua        ← Place inside ServerScriptService (Script)
  README.md
```

---

## 📱 What's Included

### Phone UI (`PhoneUI_LocalScript.lua`)
A fully interactive phone that lives in the corner of the screen. Players tap the 📱 toggle button to slide it up and access all apps.

**Apps:**
| App | Type | Status |
|-----|------|--------|
| 👗 Avatar/Wardrobe | Fullscreen takeover | ✅ Functional |
| 💬 Messages | Phone screen | ✅ Functional |
| 📞 Call | Phone screen | ✅ Functional |
| 🚗 Vehicles | Phone screen | ✅ Functional |
| 🏦 Bank | Phone screen | ✅ Functional |
| ⚙️ Settings | Phone screen | ✅ Functional |
| 🗺 Map | Phone screen | 🔨 Placeholder |
| 🚀 Teleport | Phone screen | 🔨 Placeholder |

**Wardrobe/Avatar App features:**
- Live catalog search powered by `AvatarEditorService`
- Category sidebar (Featured, Hair, Faces, Clothing, Animations, Body, Heads, Characters)
- Equip/remove items directly onto your character
- 6 outfit slots (Work, Home, Casual, Sport, Formal, Custom)
- Outfit saving and loading across sessions via DataStore

**Settings App features:**
- Music on/off toggle + volume slider
- Sound effects toggle
- Chat bubble toggle
- Graphics quality control

**Call App features:**
- Live list of players currently in the server

**Messages App features:**
- Player list + in-game messaging

**Bank App features:**
- Displays current in-game balance

---

## 🗄️ Server Script (`GameServer_Script.lua`)
Handles all server-side logic including:
- **Outfit saving/loading** via `DataStoreService`
- **Catalog search** via `AvatarEditorService`
- **Player balance** storage and retrieval
- All `RemoteEvent` and `RemoteFunction` setup

---

## 🛠️ Setup Instructions

### Step 1 — Studio Settings
1. Open **Game Settings** → **Security**
2. Enable **Allow HTTP Requests**
3. Enable **Enable Studio Access to API Services**

### Step 2 — Place the Scripts
| Script | Location | Type |
|--------|----------|------|
| `PhoneUI_LocalScript.lua` | `StarterGui > PhoneGui` | LocalScript |
| `GameServer_Script.lua` | `ServerScriptService` | Script |

### Step 3 — Set Your UserId
At the top of `PhoneUI_LocalScript.lua`, find this section and replace `123456789` with your actual Roblox UserId:
```lua
local DEVELOPER_IDS = {
    123456789, -- ← your Roblox UserId here
}
```
> ⚠️ Remove this entire block before publishing to players!

### Step 4 — GUI Structure
The phone UI relies on a manually built GUI tree in Studio. The structure must match exactly:

```
StarterGui/
  PhoneGui (ScreenGui, ResetOnSpawn = false)
    LocalScript
    AvatarScreen (Frame, Visible = false)
      CharacterPreview (ViewportFrame)
      CatalogPanel (Frame)
        CategoryBar (ScrollingFrame)
          Cat_Featured (TextButton)
          Cat_Hair (TextButton)
          Cat_Faces (TextButton)
          Cat_Clothing (TextButton)
          Cat_Animations (TextButton)
          Cat_Body (TextButton)
          Cat_Heads (TextButton)
          Cat_Characters (TextButton)
        ItemGrid (ScrollingFrame + UIGridLayout)
        SlotContainer (ScrollingFrame + UIListLayout)
        SearchBar (TextBox)
        TabCatalog (TextButton)
        TabOutfits (TextButton)
      CloseButton (TextButton)
    PhoneBody (Frame, Visible = false)
      UICorner
      Notch (Frame)
      PhoneScreen (Frame, ClipsDescendants = true)
        UICorner
        UIGridLayout
        UIPadding
        AppIcon_Wardrobe (Frame)
        AppIcon_Map (Frame)
        AppIcon_Teleport (Frame)
        AppIcon_Messages (Frame)
        AppIcon_Call (Frame)
        AppIcon_Bank (Frame)
        AppIcon_Vehicles (Frame)
        AppIcon_Settings (Frame)
      CallAppScreen (Frame, Visible = false)
      MessageAppScreen (Frame, Visible = false)
      VehiclesAppScreen (Frame, Visible = false)
      SettingsAppScreen (Frame, Visible = false)
      BankAppScreen (Frame, Visible = false)
      HomeButton (TextButton)
    ToggleButton (TextButton)
```

Each `AppIcon_X` frame must contain:
- `IconBg` (Frame with UICorner)
  - TextLabel (emoji)
- TextLabel (app name)

---

## 🎮 How It Works

### Phone Toggle
The small 📱 button in the top-right corner slides the phone up and down with a spring animation.

### App Navigation
- **Home screen** — shows the app icon grid
- **Phone-screen apps** — slide in over the home screen; Home button closes them
- **Avatar app** — hides the phone entirely and opens a fullscreen catalog

### Outfit System
Outfits are saved server-side using DataStore with this key format:
```
outfits_[UserId]
```
Each player gets up to 6 named outfit slots.

### Catalog Search
Search is powered by `AvatarEditorService:SearchCatalog()` on the server, invoked via `RemoteFunction`. Results are sent back to the client and rendered as item cards.

---

## 🔌 RemoteEvents & RemoteFunctions

All remotes are created automatically by the server script inside `ReplicatedStorage/OutfitRemotes`:

| Name | Type | Purpose |
|------|------|---------|
| `SaveOutfit` | RemoteEvent | Save current outfit to a slot |
| `LoadOutfit` | RemoteFunction | Apply a saved outfit |
| `GetOutfits` | RemoteFunction | Fetch all saved outfit slots |
| `DeleteOutfit` | RemoteEvent | Delete an outfit slot |
| `SaveResult` | RemoteEvent | Server → client save confirmation |
| `SearchCatalog` | RemoteFunction | Search the Roblox catalog |

---

## 📝 Notes

- The developer UserId whitelist at the top of the LocalScript prevents the UI from showing for regular players during testing. **Remove it before publishing.**
- The Bank balance system requires a separate money/economy script to feed values into the `BalanceLabel`.
- Music settings require a `Sound` object placed in the game — the Settings app is designed to reference it by name.
- The Map and Teleport apps are currently placeholders — future updates will add full functionality.

---

## 🗓️ Development Log

| Date | Update |
|------|--------|
| Feb 2026 | Initial phone UI built |
| Feb 2026 | Avatar catalog + live search added |
| Feb 2026 | Outfit slot saving system added |
| Feb 2026 | Category sidebar added |
| Feb 2026 | Phone-screen apps added (Call, Messages, Vehicles, Settings, Bank) |

---

*Built for The Office RP — a realistic Roblox roleplay experience.*
