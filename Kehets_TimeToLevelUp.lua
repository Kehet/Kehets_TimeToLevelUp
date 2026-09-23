local TimeToLevelUp = LibStub("AceAddon-3.0"):NewAddon("Kehet's TimeToLevelUp", "AceEvent-3.0", "AceConsole-3.0")

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
    profile = {
        locked = false,
        point = { "CENTER", "CENTER", 0, 200 },
    },
}

function TimeToLevelUp:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("TimeToLevelUpDB", defaults, true)

    -- Register slash command
    self:RegisterChatCommand("xp", "ShowXPInfo")
    self:RegisterChatCommand("ttl", "HandleCommand")
end

function TimeToLevelUp:OnEnable()
    -- Initialize tracking on login, when XP values are available
    xpData.startSessionTime = time()
    xpData.levelStartTime = time()
    xpData.levelStartXP = UnitXP("player") or 0

    -- Register events for XP tracking
    self:RegisterEvent("PLAYER_XP_UPDATE", "OnXPUpdate")
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnLevelUp")
    self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", "OnXPGain")

    self:CreateDisplay()
    -- XP events refresh the box right away; the slow ticker only lets the estimate drift while idle
    C_Timer.NewTicker(60, function() self:UpdateDisplay() end)

    self:Print("Enabled - Use /xp or /ttl to show XP information, /ttl lock or /ttl unlock to lock the box")
end

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
    local frame = CreateFrame("Frame", "KehetsTimeToLevelUpFrame", UIParent, "BackdropTemplate")
    frame:SetSize(120, 24)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relativePoint, x, y = f:GetPoint()
        self.db.profile.point = { point, relativePoint, x, y }
    end)

    local p = self.db.profile.point
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("CENTER")

    self.frame = frame
    self:SetLocked(self.db.profile.locked)
    self:UpdateDisplay()
end

function TimeToLevelUp:SetLocked(locked)
    self.db.profile.locked = locked
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
    self.frame:SetWidth(self.frame.text:GetStringWidth() + 20)
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
