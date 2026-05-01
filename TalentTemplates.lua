local ADDON_NAME, addon = ...

-- ===== CONSTANTS =====
local PANEL_WIDTH     = 460
local BUTTON_WIDTH    = 432
local GLYPH_ROW_H     = 14   -- px per glyph row
local BUTTON_TOP_H    = 74   -- px reserved for icon + name + 1 info line + divider
local INFO_LINE_H     = 14   -- px per info line (GameFontHighlightSmall)
local INFO_TEXT_WIDTH = BUTTON_WIDTH - 68  -- info column width (minus icon + margins)
local BUTTON_PAD      = 6    -- bottom padding inside each button
local BUTTON_GAP      = 4    -- vertical gap between buttons

-- ===== MEASURE HELPER =====
-- Returns the extra height (beyond 1 line) needed for multi-line info text.
local measureFs
local function ExtraInfoHeight(info)
    if not info or info == "" then return 0 end
    if not measureFs then
        measureFs = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        measureFs:SetWidth(INFO_TEXT_WIDTH)
    end
    measureFs:SetText(info)
    local h = measureFs:GetStringHeight()
    return math.max(0, h - INFO_LINE_H)
end

-- ===== DATABASE =====
local function CheckInit()
    if not TalentTemplatesDB then
        TalentTemplatesDB = { presets = {} }
    end
    if not TalentTemplatesDB.presets then
        TalentTemplatesDB.presets = {}
    end
    addon.db = TalentTemplatesDB
end

-- ===== GLYPH HELPER =====
local function FetchCurrentGlyphs()
    local major, minor = {}, {}
    for i = 1, 6 do
        local enabled, glyphType, _, glyphSpellID = GetGlyphSocketInfo(i)
        if enabled and glyphSpellID then
            local spellName = GetSpellInfo(glyphSpellID)
            if glyphType == 1 then
                table.insert(major, spellName or "?")
            elseif glyphType == 2 then
                table.insert(minor, spellName or "?")
            end
        end
    end
    return major, minor
end

-- ===== PRESET MANAGEMENT =====
function addon.SaveCurrentPreset(name, info)
    if not name or name == "" then return end
    local preset = {
        name        = name,
        info        = info or "",
        icon        = "Interface\\Icons\\INV_Misc_QuestionMark",
        talents     = {},
        majorGlyphs = {},
        minorGlyphs = {},
    }

    -- Pick icon from the talent tree with the most points invested
    local highestPoints = 0
    for tab = 1, GetNumTalentTabs() do
        local _, tabIcon, points = GetTalentTabInfo(tab)
        if points > highestPoints then
            highestPoints = points
            preset.icon = tabIcon
        end
        preset.talents[tab] = {}
        for i = 1, GetNumTalents(tab) do
            local _, _, _, _, rank = GetTalentInfo(tab, i)
            preset.talents[tab][i] = rank
        end
    end

    preset.majorGlyphs, preset.minorGlyphs = FetchCurrentGlyphs()

    table.insert(TalentTemplatesDB.presets, preset)
    if addon.UpdatePresetList then addon.UpdatePresetList() end
    print("|cff00ff00TalentTemplates:|r Saved \"|cffffff00" .. name .. "|r\".")
end

function addon.DeletePreset(index)
    local preset = TalentTemplatesDB.presets[index]
    if not preset then return end
    local name = preset.name or "?"
    table.remove(TalentTemplatesDB.presets, index)
    if addon.UpdatePresetList then addon.UpdatePresetList() end
    print("|cff00ff00TalentTemplates:|r Deleted \"|cffffff00" .. name .. "|r\".")
end

function addon.ApplyPreset(preset)
    if not preset or not preset.talents then return end
    if not AddPreviewTalentPoints then return end

    if GetActiveTalentGroup and ResetGroupPreviewTalentPoints then
        ResetGroupPreviewTalentPoints(GetActiveTalentGroup())
    end

    for tab, talentList in pairs(preset.talents) do
        for index, savedRank in ipairs(talentList) do
            local _, _, _, _, currentRank = GetTalentInfo(tab, index)
            local diff = savedRank - currentRank
            if diff > 0 then
                for _ = 1, diff do
                    AddPreviewTalentPoints(tab, index)
                end
            end
        end
    end

    if PlayerTalentFrame_Update then PlayerTalentFrame_Update() end
    print("|cff00ff00TalentTemplates:|r Applied \"|cffffff00" .. (preset.name or "?") .. "|r\" to talent preview.")
    if #(preset.majorGlyphs or {}) > 0 or #(preset.minorGlyphs or {}) > 0 then
        print("|cffffff00TalentTemplates:|r Don't forget to apply glyphs manually!")
    end
end

-- ===== SAVE DIALOG =====
local saveDialog

local function CreateSaveDialog()
    if saveDialog then return saveDialog end

    saveDialog = CreateFrame("Frame", "TalentTemplatesSaveDialog", UIParent)
    saveDialog:SetFrameStrata("DIALOG")
    saveDialog:SetSize(360, 180)
    saveDialog:SetPoint("CENTER")
    saveDialog:SetMovable(true)
    saveDialog:EnableMouse(true)
    saveDialog:EnableKeyboard(true)
    saveDialog:RegisterForDrag("LeftButton")
    saveDialog:SetScript("OnDragStart", saveDialog.StartMoving)
    saveDialog:SetScript("OnDragStop",  saveDialog.StopMovingOrSizing)
    saveDialog:Hide()

    -- Background
    local bg = saveDialog:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.05, 0.05, 0.05, 0.95)

    -- Title bar
    local titleBar = saveDialog:CreateTexture(nil, "BORDER")
    titleBar:SetHeight(26)
    titleBar:SetPoint("TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetTexture(0.12, 0.12, 0.12, 1)

    local titleFs = saveDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOP", 0, -7)
    titleFs:SetText("|cffffd700Save Template|r")

    -- Name field
    local nameLabel = saveDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", 14, -38)
    nameLabel:SetText("Name:")

    local nameBox = CreateFrame("EditBox", nil, saveDialog, "InputBoxTemplate")
    nameBox:SetSize(328, 20)
    nameBox:SetPoint("TOPLEFT", 14, -54)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(64)
    saveDialog.nameBox = nameBox

    -- Description field
    local descLabel = saveDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descLabel:SetPoint("TOPLEFT", 14, -82)
    descLabel:SetText("Description (optional):")

    local descBox = CreateFrame("EditBox", nil, saveDialog, "InputBoxTemplate")
    descBox:SetSize(328, 20)
    descBox:SetPoint("TOPLEFT", 14, -98)
    descBox:SetAutoFocus(false)
    descBox:SetMaxLetters(256)
    saveDialog.descBox = descBox

    -- Tab / Enter navigation
    nameBox:SetScript("OnTabPressed",   function() descBox:SetFocus() end)
    nameBox:SetScript("OnEnterPressed", function() descBox:SetFocus() end)
    descBox:SetScript("OnTabPressed",   function() nameBox:SetFocus() end)

    -- Shared save action
    local function CloseDialog()
        saveDialog:Hide()
        nameBox:SetText("")
        descBox:SetText("")
    end

    local function DoSave()
        local name = nameBox:GetText()
        local desc = descBox:GetText()
        if name and name ~= "" then
            addon.SaveCurrentPreset(name, desc)
            CloseDialog()
        end
    end
    descBox:SetScript("OnEnterPressed", DoSave)

    -- Buttons
    local saveBtn = CreateFrame("Button", nil, saveDialog, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 50, 12)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", DoSave)

    local cancelBtn = CreateFrame("Button", nil, saveDialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", -50, 12)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", CloseDialog)

    -- Close on Escape
    saveDialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then CloseDialog() end
    end)

    return saveDialog
end

-- ===== UI HELPERS =====
local function ButtonHeight(preset)
    local nMaj = #(preset.majorGlyphs or {})
    local nMin = #(preset.minorGlyphs or {})
    local rows = math.max(nMaj, nMin, 1)
    return BUTTON_TOP_H + ExtraInfoHeight(preset.info) + rows * GLYPH_ROW_H + BUTTON_PAD
end

local function MakePresetButton(parent, preset, index, y)
    local extraH = ExtraInfoHeight(preset.info)
    local topH   = BUTTON_TOP_H + extraH
    local h      = ButtonHeight(preset)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(BUTTON_WIDTH, h)
    btn:SetPoint("TOPLEFT", 0, y)

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.08, 0.08, 0.08, 0.9)

    -- Hover highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(1, 1, 1, 0.08)

    -- Icon
    local iconTex = btn:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(50, 50)
    iconTex:SetPoint("TOPLEFT", 8, -12)
    iconTex:SetTexture(preset.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Icon border
    local iconBd = btn:CreateTexture(nil, "OVERLAY")
    iconBd:SetSize(56, 56)
    iconBd:SetPoint("CENTER", iconTex, "CENTER")
    iconBd:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    -- Template name
    local nameFs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFs:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, -2)
    nameFs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -24, -2)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetText(preset.name or "Unnamed")

    -- Info line (smaller, light)
    local infoFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -2)
    infoFs:SetPoint("TOPRIGHT", nameFs, "BOTTOMRIGHT", 0, -2)
    infoFs:SetWidth(INFO_TEXT_WIDTH)
    infoFs:SetJustifyH("LEFT")
    infoFs:SetTextColor(0.9, 0.9, 0.9)
    infoFs:SetText(preset.info or "")

    -- Divider (positioned below the info text, which may be multi-line)
    local div = btn:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  btn, "TOPLEFT",  5, -(topH - 8))
    div:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -(topH - 8))
    div:SetTexture(0.3, 0.3, 0.3, 0.8)

    -- Glyph column headers
    local hdrMaj = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrMaj:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -(topH - 4))
    hdrMaj:SetWidth(200)
    hdrMaj:SetJustifyH("LEFT")
    hdrMaj:SetTextColor(1, 0.82, 0)
    hdrMaj:SetText("Major Glyphs")

    local hdrMin = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrMin:SetPoint("TOPLEFT", btn, "TOPLEFT", 220, -(topH - 4))
    hdrMin:SetWidth(200)
    hdrMin:SetJustifyH("LEFT")
    hdrMin:SetTextColor(0.4, 0.8, 1.0)
    hdrMin:SetText("Minor Glyphs")

    -- Glyph rows: Major Name | Minor Name
    local majGlyphs = preset.majorGlyphs or {}
    local minGlyphs = preset.minorGlyphs or {}
    local rows = math.max(#majGlyphs, #minGlyphs, 1)

    for i = 1, rows do
        local rowY = -(topH + (i - 1) * GLYPH_ROW_H)

        local majFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        majFs:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, rowY)
        majFs:SetWidth(200)
        majFs:SetJustifyH("LEFT")
        if majGlyphs[i] then
            majFs:SetTextColor(1, 0.82, 0)
            majFs:SetText(majGlyphs[i])
        else
            majFs:SetTextColor(0.35, 0.35, 0.35)
            majFs:SetText("-")
        end

        local sepFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sepFs:SetPoint("TOPLEFT", btn, "TOPLEFT", 210, rowY)
        sepFs:SetTextColor(0.35, 0.35, 0.35)
        sepFs:SetText("|")

        local minFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        minFs:SetPoint("TOPLEFT", btn, "TOPLEFT", 216, rowY)
        minFs:SetWidth(200)
        minFs:SetJustifyH("LEFT")
        if minGlyphs[i] then
            minFs:SetTextColor(0.4, 0.8, 1.0)
            minFs:SetText(minGlyphs[i])
        else
            minFs:SetTextColor(0.35, 0.35, 0.35)
            minFs:SetText("-")
        end
    end

    -- Delete button (top-right X)
    local delBtn = CreateFrame("Button", nil, btn)
    delBtn:SetSize(18, 18)
    delBtn:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
    delBtn:EnableMouse(true)
    local delFs = delBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    delFs:SetAllPoints()
    delFs:SetText("|cffff4444X|r")
    delBtn:SetScript("OnClick", function()
        addon.DeletePreset(index)
    end)
    delBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Delete this template", 1, 0.2, 0.2)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Apply preset on left-click
    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            addon.ApplyPreset(preset)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cffffd700" .. (preset.name or "Unnamed"), 1, 1, 1)
        if preset.info and preset.info ~= "" then
            GameTooltip:AddLine(preset.info, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to apply talent preview", 0, 1, 0)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn, h
end

-- ===== UI CREATION =====
local uiCreated  = false
local mainFrame  = nil
local trashFrame = nil  -- hidden parent for recycled buttons

local function CreateUI()
    if uiCreated then return end
    uiCreated = true

    -- Hidden frame used to detach recycled preset buttons
    trashFrame = CreateFrame("Frame", nil, UIParent)
    trashFrame:Hide()

    mainFrame = CreateFrame("Frame", "TalentTemplatesFrame", PlayerTalentFrame)
    mainFrame:SetWidth(PANEL_WIDTH)
    mainFrame:SetHeight(500)
    mainFrame:SetPoint("TOPLEFT", PlayerTalentFrame, "TOPRIGHT", 5, 0)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)

    -- Restrict dragging to the title bar area
    local dragHandle = CreateFrame("Frame", nil, mainFrame)
    dragHandle:SetHeight(26)
    dragHandle:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT")
    dragHandle:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT")
    dragHandle:EnableMouse(true)
    dragHandle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            mainFrame:StartMoving()
        end
    end)
    dragHandle:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
    end)

    -- Panel background
    local bgTex = mainFrame:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetTexture(0.05, 0.05, 0.05, 0.92)

    -- Title bar
    local titleBarTex = mainFrame:CreateTexture(nil, "BORDER")
    titleBarTex:SetHeight(26)
    titleBarTex:SetPoint("TOPLEFT", 0, 0)
    titleBarTex:SetPoint("TOPRIGHT", 0, 0)
    titleBarTex:SetTexture(0.12, 0.12, 0.12, 1)

    -- Title text
    local titleFs = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOP", 0, -7)
    titleFs:SetText("|cffffd700Talent Templates|r")

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "TalentTemplatesScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     5,  -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 40)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(BUTTON_WIDTH + 4)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    mainFrame.scrollChild = scrollChild

    -- Save button
    local saveBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(140, 24)
    saveBtn:SetPoint("BOTTOM", 0, 10)
    saveBtn:SetText("Save Current")
    saveBtn:SetScript("OnClick", function()
        local dlg = CreateSaveDialog()
        dlg:Show()
        dlg.nameBox:SetFocus()
    end)

    addon.mainFrame = mainFrame

    -- Persistent empty-state hint (created once, shown/hidden as needed)
    local hintFrame = CreateFrame("Frame", nil, scrollChild)
    hintFrame:SetSize(BUTTON_WIDTH, 60)
    hintFrame:SetPoint("TOPLEFT", 0, -4)
    local hintFs = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintFs:SetAllPoints()
    hintFs:SetTextColor(0.5, 0.5, 0.5)
    hintFs:SetText("No templates saved.\nClick \"Save Current\" to create one.")
    hintFs:SetJustifyH("CENTER")
    hintFs:SetJustifyV("MIDDLE")
    hintFrame:Hide()

    -- Track active preset buttons for recycling on next refresh
    local activeButtons = {}

    function addon.UpdatePresetList()
        -- Detach old buttons to the trash frame (hides them without destroying)
        for _, btn in ipairs(activeButtons) do
            btn:SetParent(trashFrame)
            btn:Hide()
        end
        activeButtons = {}

        local presets = TalentTemplatesDB and TalentTemplatesDB.presets or {}
        local y = -4

        if #presets == 0 then
            hintFrame:SetParent(scrollChild)
            hintFrame:Show()
            y = y - 65
        else
            hintFrame:Hide()
            for i, preset in ipairs(presets) do
                local btn, h = MakePresetButton(scrollChild, preset, i, y)
                table.insert(activeButtons, btn)
                y = y - h - BUTTON_GAP
            end
        end

        scrollChild:SetHeight(math.max(1, math.abs(y)))
    end

    addon.UpdatePresetList()
end

-- ===== EVENT HANDLER =====
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, arg1)
    if event ~= "ADDON_LOADED" then return end
    if arg1 == ADDON_NAME then
        CheckInit()
        if IsAddOnLoaded("Blizzard_TalentUI") then
            CreateUI()
        end
    elseif arg1 == "Blizzard_TalentUI" then
        CheckInit()
        CreateUI()
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", OnEvent)
