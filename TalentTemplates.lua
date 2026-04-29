local ADDON_NAME, addon = ...
local frame = CreateFrame("Frame")

-- Default database structure
local defaultDB = {
    presets = {}
}

-- Initialize database when addon loads
-- Helper to save current state
function addon.SaveCurrentPreset(name, info)
    local preset = {
        name = name,
        info = info,
        icon = "Interface\\Icons\\INV_Misc_QuestionMark", -- Default icon
        talents = {},
        majorGlyphs = {},
        minorGlyphs = {}
    }

    -- Try to get a better icon from the active talent tab
    local highestPoints = 0
    for tab = 1, GetNumTalentTabs() do
        local _, icon, points = GetTalentTabInfo(tab)
        if points > highestPoints then
            highestPoints = points
            preset.icon = icon
        end

        preset.talents[tab] = {}
        for i = 1, GetNumTalents(tab) do
            local _, _, _, _, rank = GetTalentInfo(tab, i)
            preset.talents[tab][i] = rank
        end
    end

    -- Fetch current glyphs
    for i = 1, 6 do
        local enabled, glyphType, glyphTooltipIndex, glyphSpellID, icon = GetGlyphSocketInfo(i)
        if enabled and glyphSpellID then
            local name = GetSpellInfo(glyphSpellID)
            if glyphType == 1 then -- Major
                table.insert(preset.majorGlyphs, name)
            elseif glyphType == 2 then -- Minor
                table.insert(preset.minorGlyphs, name)
            end
        end
    end

    table.insert(TalentTemplatesDB.presets, preset)
    if addon.UpdatePresetList then
        addon.UpdatePresetList()
    end
end

-- Popup dialog for saving
StaticPopupDialogs["TALENT_TEMPLATES_SAVE"] = {
    text = "Enter a name for the new template:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local text = self.editBox:GetText()
        if text and text ~= "" then
            addon.SaveCurrentPreset(text, "Saved configuration")
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local text = self:GetText()
        if text and text ~= "" then
            addon.SaveCurrentPreset(text, "Saved configuration")
        end
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Helper to apply a saved preset
function addon.ApplyPreset(preset)
    if not preset or not preset.talents then return end

    -- In 3.3.5 we reset talents first using the frame's reset functionality if possible
    -- Or just add points if they are already partly applied.
    -- The most robust way is to prompt user or attempt AddPreviewTalentPoints
    if ResetGroupPreviewTalentPoints and GetActiveTalentGroup then
        ResetGroupPreviewTalentPoints(GetActiveTalentGroup())
    end

    for tab, talentList in pairs(preset.talents) do
        for index, rank in ipairs(talentList) do
            local name, iconTexture, tier, column, currentRank, maxRank, isExceptional, meetsPrereq = GetTalentInfo(tab, index)
            local diff = rank - currentRank
            if diff > 0 then
                for p = 1, diff do
                    AddPreviewTalentPoints(tab, index)
                end
            end
        end
    end

    -- Tell the UI to update the preview
    if PlayerTalentFrame_Update then
        PlayerTalentFrame_Update()
    end

    print("TalentTemplates: Applied template " .. (preset.name or "Unknown") .. " to preview.")
    print("TalentTemplates: Glyphs must be applied manually.")
end

local uiCreated = false
local mainFrame = nil

local function CreateUI()
    if uiCreated then return end
    uiCreated = true

    -- Create the main addon frame and attach it to PlayerTalentFrame
    mainFrame = CreateFrame("Frame", "TalentTemplatesFrame", PlayerTalentFrame)
    mainFrame:SetWidth(250)
    mainFrame:SetHeight(400)
    mainFrame:SetPoint("TOPLEFT", PlayerTalentFrame, "TOPRIGHT", -10, -12)

    -- Background
    local tex = mainFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture(0, 0, 0, 0.8)

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Talent Templates")

    -- Scroll Frame for Presets
    local scrollFrame = CreateFrame("ScrollFrame", "TalentTemplatesScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(210, 10) -- Height will update dynamically
    scrollFrame:SetScrollChild(scrollChild)
    mainFrame.scrollChild = scrollChild

    -- Save Button
    local saveBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 25)
    saveBtn:SetPoint("BOTTOM", 0, 10)
    saveBtn:SetText("Save Current")

    saveBtn:SetScript("OnClick", function()
        StaticPopup_Show("TALENT_TEMPLATES_SAVE")
    end)

    addon.mainFrame = mainFrame

    -- Function to render the presets
    function addon.UpdatePresetList()
        -- Clear existing buttons
        if addon.presetButtons then
            for _, btn in ipairs(addon.presetButtons) do
                btn:Hide()
            end
        end
        addon.presetButtons = {}

        local yOffset = -5
        local db = TalentTemplatesDB.presets or {}

        for index, preset in ipairs(db) do
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(210, 80)
            btn:SetPoint("TOPLEFT", 0, yOffset)

            -- Button Background
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(1, 1, 1, 0.1)

            -- Icon
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(32, 32)
            icon:SetPoint("TOPLEFT", 5, -5)
            icon:SetTexture(preset.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Name
            local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
            nameText:SetText(preset.name or "Unknown")

            -- Info
            local infoText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
            infoText:SetText(preset.info or "")

            -- Glyphs rendering
            local glyphY = -40
            local majorGlyphs = preset.majorGlyphs or {}
            local minorGlyphs = preset.minorGlyphs or {}

            for i = 1, 3 do
                -- Major Glyph
                local majGlyph = majorGlyphs[i]
                local majText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                majText:SetPoint("TOPLEFT", 5, glyphY)
                majText:SetWidth(100)
                majText:SetJustifyH("LEFT")
                majText:SetText(majGlyph or "")

                -- Minor Glyph
                local minGlyph = minorGlyphs[i]
                local minText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                minText:SetPoint("TOPLEFT", 105, glyphY)
                minText:SetWidth(100)
                minText:SetJustifyH("LEFT")
                minText:SetText(minGlyph or "")

                glyphY = glyphY - 12
            end

            btn:SetScript("OnClick", function()
                if addon.ApplyPreset then
                    addon.ApplyPreset(preset)
                end
            end)

            table.insert(addon.presetButtons, btn)
            yOffset = yOffset - 85
        end

        scrollChild:SetHeight(math.abs(yOffset))
    end

    if addon.UpdatePresetList then
        addon.UpdatePresetList()
    end
end

local function CheckInit()
    if not TalentTemplatesDB then
        TalentTemplatesDB = defaultDB
    end
    -- Ensure 'presets' table exists
    if not TalentTemplatesDB.presets then
        TalentTemplatesDB.presets = {}
    end
    addon.db = TalentTemplatesDB
end

local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        CheckInit()
        -- If Blizzard_TalentUI is already loaded when we load, create UI now
        if IsAddOnLoaded("Blizzard_TalentUI") then
            CreateUI()
        end
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_TalentUI" then
        CheckInit()
        CreateUI()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnEvent)
