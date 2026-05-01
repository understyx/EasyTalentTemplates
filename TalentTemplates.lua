local ADDON_NAME, addon = ...

-- ===== CONSTANTS =====
local PANEL_WIDTH    = 460
local BUTTON_WIDTH   = 432
local GLYPH_ROW_H    = 14   -- px per glyph row
local BUTTON_TOP_H   = 74   -- px reserved for icon + name + info + divider
local BUTTON_PAD     = 6    -- bottom padding inside each button
local BUTTON_GAP     = 4    -- vertical gap between buttons

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

-- ===== STATIC POPUP =====
StaticPopupDialogs["TALENT_TEMPLATES_SAVE"] = {
    text         = "Enter a name for this template:",
    button1      = "Save",
    button2      = "Cancel",
    hasEditBox   = true,
    OnAccept = function(self)
        local text = self.editBox:GetText()
        if text and text ~= "" then
            addon.SaveCurrentPreset(text, "")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local text = self:GetText()
        if text and text ~= "" then
            addon.SaveCurrentPreset(text, "")
        end
        self:GetParent():Hide()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ===== UI HELPERS =====
local function ButtonHeight(preset)
    local nMaj = #(preset.majorGlyphs or {})
    local nMin = #(preset.minorGlyphs or {})
    local rows = math.max(nMaj, nMin, 1)
    return BUTTON_TOP_H + rows * GLYPH_ROW_H + BUTTON_PAD
end

local function MakePresetButton(parent, preset, index, y)
    local h   = ButtonHeight(preset)
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

    -- Info line (smaller, grey)
    local infoFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -2)
    infoFs:SetPoint("TOPRIGHT", nameFs, "BOTTOMRIGHT", 0, -2)
    infoFs:SetJustifyH("LEFT")
    infoFs:SetTextColor(0.65, 0.65, 0.65)
    infoFs:SetText(preset.info or "")

    -- Divider
    local div = btn:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT",  btn, "TOPLEFT",  5, -(BUTTON_TOP_H - 8))
    div:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -5, -(BUTTON_TOP_H - 8))
    div:SetTexture(0.3, 0.3, 0.3, 0.8)

    -- Glyph column headers
    local hdrMaj = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrMaj:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -(BUTTON_TOP_H - 4))
    hdrMaj:SetWidth(200)
    hdrMaj:SetJustifyH("LEFT")
    hdrMaj:SetTextColor(1, 0.82, 0)
    hdrMaj:SetText("Major Glyphs")

    local hdrMin = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdrMin:SetPoint("TOPLEFT", btn, "TOPLEFT", 220, -(BUTTON_TOP_H - 4))
    hdrMin:SetWidth(200)
    hdrMin:SetJustifyH("LEFT")
    hdrMin:SetTextColor(0.4, 0.8, 1.0)
    hdrMin:SetText("Minor Glyphs")

    -- Glyph rows: Major Name | Minor Name
    local majGlyphs = preset.majorGlyphs or {}
    local minGlyphs = preset.minorGlyphs or {}
    local rows = math.max(#majGlyphs, #minGlyphs, 1)

    for i = 1, rows do
        local rowY = -(BUTTON_TOP_H + (i - 1) * GLYPH_ROW_H)

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
        StaticPopup_Show("TALENT_TEMPLATES_SAVE")
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
