local ADDON_NAME = ...

-- Chat lines start with a short tag, not the full name that the settings page shows
local TimeToLevelUp = { name = "Kehet's TimeToLevelUp", chatPrefix = "|cFF009900TTL|r: " }
LibStub("LibKehetsVerbosity-2.0"):Embed(TimeToLevelUp)

-- Messages the player can turn off or move in the settings
TimeToLevelUp:RegisterMessageTypes({
    banner = {
        name = "Login message",
        desc = "The line that says the addon is enabled.",
    },
})

-- XP tracking variables
local xpData = {
    lastMobXP = 0,
    lastXPGain = 0,
    sessionXP = 0,
    startSessionTime = 0,
    levelStartTime = 0,
    levelStartXP = 0,
}

local defaults = {
    locked = false,
    point = { "CENTER", "CENTER", 0, 200 },
}

-- Versions up to 1.3.0 saved an AceDB-3.0 database, with the settings in the shared "Default" profile
local function MigrateAceDB(db)
    if type(db.profiles) ~= "table" then
        return db
    end
    local profile = type(db.profiles.Default) == "table" and db.profiles.Default or {}
    return { locked = profile.locked, point = profile.point, verbosity = profile.verbosity }
end

local function LoadDB()
    local db = MigrateAceDB(type(TimeToLevelUpDB) == "table" and TimeToLevelUpDB or {})
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = value
        end
    end
    TimeToLevelUpDB = db
    return db
end

function TimeToLevelUp:OnInitialize()
    self.db = LoadDB()
    self:RegisterMessagePage()

    SLASH_KEHETSTTLXP1 = "/xp"
    SlashCmdList.KEHETSTTLXP = function() self:ShowXPInfo() end
    SLASH_KEHETSTTL1 = "/ttl"
    SlashCmdList.KEHETSTTL = function(input) self:HandleCommand(input) end
end

function TimeToLevelUp:OnEnable()
    -- Initialize tracking on login, when XP values are available
    xpData.startSessionTime = time()
    xpData.levelStartTime = time()
    xpData.levelStartXP = UnitXP("player") or 0

    -- Register events for XP tracking
    self.events.PLAYER_XP_UPDATE = self.OnXPUpdate
    self.events.PLAYER_LEVEL_UP = self.OnLevelUp
    self.events.CHAT_MSG_COMBAT_XP_GAIN = self.OnXPGain
    for event in pairs(self.events) do
        self.eventFrame:RegisterEvent(event)
    end

    self:CreateDisplay()
    -- XP events refresh the box right away; the slow ticker only lets the estimate drift while idle
    C_Timer.NewTicker(60, function() self:UpdateDisplay() end)

    self:Notify("banner", "Enabled - Use /xp or /ttl to show XP information, /ttl lock or /ttl unlock to lock the box")
end

-- Handlers are called as handler(self, event, ...), like AceEvent-3.0 did
TimeToLevelUp.events = {
    ADDON_LOADED = function(self, event, name)
        if name == ADDON_NAME then
            self.eventFrame:UnregisterEvent("ADDON_LOADED")
            self.events.ADDON_LOADED = nil
            self:OnInitialize()
        end
    end,
    PLAYER_LOGIN = function(self)
        self.eventFrame:UnregisterEvent("PLAYER_LOGIN")
        self.events.PLAYER_LOGIN = nil
        self:OnEnable()
    end,
}

TimeToLevelUp.eventFrame = CreateFrame("Frame")
TimeToLevelUp.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = TimeToLevelUp.events[event]
    if handler then
        handler(TimeToLevelUp, event, ...)
    end
end)
TimeToLevelUp.eventFrame:RegisterEvent("ADDON_LOADED")
TimeToLevelUp.eventFrame:RegisterEvent("PLAYER_LOGIN")

function TimeToLevelUp:HandleCommand(input)
    input = strtrim(input or ""):lower()
    if input == "lock" then
        self:SetLocked(true)
        self:Print("Box locked")
    elseif input == "unlock" then
        self:SetLocked(false)
        self:Print("Box unlocked, drag it to move")
    else
        self:ShowXPInfo()
    end
end

function TimeToLevelUp:CreateDisplay()
    -- The game's tooltip frame where the client has it, so the box looks like a tooltip of that client
    local hasTooltipTemplate = C_XMLUtil ~= nil and C_XMLUtil.GetTemplateInfo ~= nil
        and C_XMLUtil.GetTemplateInfo("TooltipBackdropTemplate") ~= nil
    local frame = CreateFrame("Frame", "KehetsTimeToLevelUpFrame", UIParent,
        hasTooltipTemplate and "TooltipBackdropTemplate" or "BackdropTemplate")
    if not hasTooltipTemplate then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.7)
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relativePoint, x, y = f:GetPoint()
        self.db.point = { point, relativePoint, x, y }
    end)

    local p = self.db.point
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])

    frame.text = frame:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Med1")
    frame.text:SetPoint("CENTER")

    self.frame = frame
    self:SetLocked(self.db.locked)
    self:UpdateDisplay()
end

function TimeToLevelUp:SetLocked(locked)
    self.db.locked = locked
    -- A locked box ignores the mouse, so it can't be dragged and doesn't block clicks
    self.frame:EnableMouse(not locked)
end

function TimeToLevelUp:UpdateDisplay()
    local text
    if UnitLevel("player") >= GetMaxPlayerLevel() then
        text = "TTL: Max level"
    else
        local rate = self:GetLevelRate()
        local needed = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
        text = "TTL: " .. self:FormatShortTime(rate > 0 and needed / rate * 3600 or 0)
    end
    self.frame.text:SetText(text)
    self.frame:SetSize(self.frame.text:GetStringWidth() + 20, self.frame.text:GetStringHeight() + 12)
end

-- XP per hour since login or the last level up, whichever is later
function TimeToLevelUp:GetLevelRate()
    local levelTime = time() - xpData.levelStartTime
    local gained = (UnitXP("player") or 0) - xpData.levelStartXP
    if levelTime > 0 and gained > 0 then
        return (gained / levelTime) * 3600
    end
    return 0
end

function TimeToLevelUp:OnLevelUp()
    xpData.levelStartTime = time()
    xpData.levelStartXP = 0
    self:UpdateDisplay()
end

function TimeToLevelUp:OnXPUpdate()
    -- Track session XP when XP changes
    local currentXP = UnitXP("player") or 0
    if xpData.levelStartXP > 0 then
        xpData.sessionXP = currentXP - xpData.levelStartXP + (xpData.sessionXP or 0)
    end

    self:UpdateDisplay()
end

function TimeToLevelUp:OnXPGain(event, message)
    -- Parse XP gain from combat messages to track mob XP and other gains
    local xpGain = string.match(message, "(%d+) experience") or string.match(message, "(%d+) XP")
    if xpGain then
        xpGain = tonumber(xpGain)
        if string.find(message, "dies") or string.find(message, "killed") then
            xpData.lastMobXP = xpGain
        else
            xpData.lastXPGain = xpGain
        end
    end
end

function TimeToLevelUp:ShowXPInfo()
    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    local restedXP = GetXPExhaustion() or 0

    -- Calculate values
    local xpGainedThisLevel = currentXP
    local xpNeededToLevel = maxXP - currentXP
    local sessionTime = time() - xpData.startSessionTime

    -- XP per hour calculations
    local xpPerHourLevel = self:GetLevelRate()
    local xpPerHourSession = 0
    if sessionTime > 0 and xpData.sessionXP > 0 then
        xpPerHourSession = (xpData.sessionXP / sessionTime) * 3600
    end

    -- Time to level calculations
    local timeToLevelByLevel = xpPerHourLevel > 0 and (xpNeededToLevel / xpPerHourLevel) * 3600 or 0
    local timeToLevelBySession = xpPerHourSession > 0 and (xpNeededToLevel / xpPerHourSession) * 3600 or 0

    -- Kills/gains to level
    local killsToLevel = xpData.lastMobXP > 0 and math.ceil(xpNeededToLevel / xpData.lastMobXP) or 0
    local gainsToLevel = xpData.lastXPGain > 0 and math.ceil(xpNeededToLevel / xpData.lastXPGain) or 0

    -- Format output
    self:Print("|cFFFFFF00XP Information:|r")
    self:Print(string.format("Total XP Required This Level: |cFF00FF00%s|r", self:FormatNumber(maxXP)))
    self:Print(string.format("Rested XP: |cFF00FFFF%s|r", self:FormatNumber(restedXP)))
    self:Print(string.format("XP Gained This Level: |cFF00FF00%s|r", self:FormatNumber(xpGainedThisLevel)))
    self:Print(string.format("XP Needed to Level: |cFFFF8000%s|r", self:FormatNumber(xpNeededToLevel)))
    self:Print(string.format("XP Gained This Session: |cFF00FF00%s|r", self:FormatNumber(xpData.sessionXP)))

    if xpData.lastMobXP > 0 then
        self:Print(string.format("Kills to Level: |cFFFFFF00%d|r (last kill: |cFF00FF00%s XP|r)", killsToLevel, self:FormatNumber(xpData.lastMobXP)))
    else
        self:Print("Kills to Level: |cFFFF0000No kill data|r")
    end

    if xpData.lastXPGain > 0 then
        self:Print(string.format("XP Increases to Level: |cFFFFFF00%d|r (last gain: |cFF00FF00%s XP|r)", gainsToLevel, self:FormatNumber(xpData.lastXPGain)))
    else
        self:Print("XP Increases to Level: |cFFFF0000No gain data|r")
    end

    self:Print(string.format("XP/Hour This Level: |cFF00FFFF%s|r", self:FormatNumber(math.floor(xpPerHourLevel))))
    self:Print(string.format("XP/Hour This Session: |cFF00FFFF%s|r", self:FormatNumber(math.floor(xpPerHourSession))))
    self:Print(string.format("Time to Level (level rate): |cFFFFFF00%s|r", self:FormatTime(timeToLevelByLevel)))
    self:Print(string.format("Time to Level (session rate): |cFFFFFF00%s|r", self:FormatTime(timeToLevelBySession)))
end

function TimeToLevelUp:FormatNumber(num)
    if not num or num == 0 then return "0" end
    local formatted = tostring(math.floor(num))
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

function TimeToLevelUp:FormatTime(seconds)
    if not seconds or seconds <= 0 then return "Unknown" end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

-- Minute resolution for the box, so the text doesn't tick every second
function TimeToLevelUp:FormatShortTime(seconds)
    if not seconds or seconds <= 0 then return "Unknown" end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm", minutes)
    else
        return "<1m"
    end
end
