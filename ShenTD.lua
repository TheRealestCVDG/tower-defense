--[[
    Shenanigans TD! (RAIDS) — Hub
    Author: olliE
    Modular state-driven Lobby Auto Summon, Match Automation,
    Simple Macro Recorder & Playback (Time / Money / Hybrid),
    and JSON Config Manager with WindUI dashboard.
]]

--// =========================================================================
--// 1. LIFECYCLE & CLEAN RELOAD GUARD
--// =========================================================================

local GLOBAL_KEY = "ShenanigansTDHub"

local function getGlobalEnv()
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        return env
    end
    return _G
end

local GlobalEnv = getGlobalEnv()
if type(GlobalEnv[GLOBAL_KEY]) == "table" and type(GlobalEnv[GLOBAL_KEY].destroy) == "function" then
    pcall(GlobalEnv[GLOBAL_KEY].destroy)
end

--// =========================================================================
--// 2. SERVICES & SAFE UTILS
--// =========================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SafeUtils = {}

function SafeUtils.safeCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "not a function"
    end
    local ok, a, b, c = pcall(fn, ...)
    return ok, a, b, c
end

function SafeUtils.isFiniteNumber(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function SafeUtils.parsePositiveInt(value)
    local raw = tostring(value or "")
    local digits = raw:match("%d+")
    if not digits then
        return nil
    end
    local num = tonumber(digits)
    if not SafeUtils.isFiniteNumber(num) then
        return nil
    end
    local intVal = math.floor(num)
    if intVal < 1 then
        return nil
    end
    return intVal
end

function SafeUtils.parseNonNegativeInt(value)
    local raw = tostring(value or "")
    local digits = raw:match("%d+")
    if not digits then
        return nil
    end
    local num = tonumber(digits)
    if not SafeUtils.isFiniteNumber(num) then
        return nil
    end
    local intVal = math.floor(num)
    if intVal < 0 then
        return 0
    end
    return intVal
end

function SafeUtils.parseFormattedNumber(text, fallback)
    if type(text) ~= "string" then
        return fallback
    end
    local cleaned = text:gsub(",", "")
    local matchStr = cleaned:match("%-?%d+%.?%d*")
    local num = matchStr and tonumber(matchStr) or nil
    if SafeUtils.isFiniteNumber(num) then
        return num
    end
    return fallback
end

function SafeUtils.formatNumber(value)
    local num = tonumber(value)
    if not SafeUtils.isFiniteNumber(num) then
        return tostring(value or 0)
    end
    local intPart = math.floor(num + 0.5)
    local sign = intPart < 0 and "-" or ""
    local str = tostring(math.abs(intPart))
    local formatted = str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. formatted
end

function SafeUtils.cleanName(value)
    local s = tostring(value or ""):gsub("[^%w%-%_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return s:sub(1, 64)
end

function SafeUtils.getLocalPlayer()
    local ok, lp = pcall(function()
        return Players.LocalPlayer
    end)
    if ok and typeof(lp) == "Instance" and lp:IsA("Player") then
        return lp
    end
    return nil
end

function SafeUtils.findChild(parent, name)
    if typeof(parent) ~= "Instance" or type(name) ~= "string" then
        return nil
    end
    local ok, child = pcall(parent.FindFirstChild, parent, name)
    if ok and typeof(child) == "Instance" then
        return child
    end
    return nil
end

function SafeUtils.findChildOfClass(parent, className)
    if typeof(parent) ~= "Instance" or type(className) ~= "string" then
        return nil
    end
    local ok, child = pcall(parent.FindFirstChildOfClass, parent, className)
    if ok and typeof(child) == "Instance" then
        return child
    end
    return nil
end

function SafeUtils.findPath(root, ...)
    local current = root
    for i = 1, select("#", ...) do
        current = SafeUtils.findChild(current, select(i, ...))
        if not current then
            return nil
        end
    end
    return current
end

function SafeUtils.getValue(inst)
    if typeof(inst) ~= "Instance" then
        return nil
    end
    local ok, value = pcall(function()
        return inst.Value
    end)
    if ok then
        return value
    end
    return nil
end

function SafeUtils.getProp(inst, propName)
    if typeof(inst) ~= "Instance" or type(propName) ~= "string" then
        return nil
    end
    local ok, value = pcall(function()
        return inst[propName]
    end)
    if ok then
        return value
    end
    return nil
end

function SafeUtils.getAttribute(inst, attrName)
    if typeof(inst) ~= "Instance" or type(attrName) ~= "string" then
        return nil
    end
    local ok, value = pcall(inst.GetAttribute, inst, attrName)
    if ok then
        return value
    end
    return nil
end

function SafeUtils.jsonEncode(tbl)
    local ok, res = pcall(HttpService.JSONEncode, HttpService, tbl)
    if ok and type(res) == "string" then
        return true, res
    end
    return false, res
end

function SafeUtils.jsonDecode(str)
    if type(str) ~= "string" or str == "" then
        return false, "empty json"
    end
    local ok, res = pcall(HttpService.JSONDecode, HttpService, str)
    if ok and type(res) == "table" then
        return true, res
    end
    return false, res
end

function SafeUtils.hasFS()
    return type(isfolder) == "function"
        and type(makefolder) == "function"
        and type(isfile) == "function"
        and type(readfile) == "function"
        and type(writefile) == "function"
        and type(listfiles) == "function"
end

function SafeUtils.ensureFolder(path)
    if not SafeUtils.hasFS() then
        return false
    end
    local okExists, exists = pcall(isfolder, path)
    if okExists and exists then
        return true
    end
    local okMake = pcall(makefolder, path)
    return okMake
end

function SafeUtils.readTextFile(path)
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        return false, nil
    end
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        return false, nil
    end
    local okRead, content = pcall(readfile, path)
    if okRead and type(content) == "string" then
        return true, content
    end
    return false, nil
end

function SafeUtils.writeTextFile(path, content)
    if type(writefile) ~= "function" then
        return false
    end
    local ok = pcall(writefile, path, tostring(content or ""))
    return ok
end

function SafeUtils.listFiles(folder)
    if type(listfiles) ~= "function" then
        return {}
    end
    local ok, files = pcall(listfiles, folder)
    if ok and type(files) == "table" then
        return files
    end
    return {}
end

function SafeUtils.deleteFile(path)
    if type(delfile) ~= "function" or type(isfile) ~= "function" then
        return false
    end
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        return false
    end
    return pcall(delfile, path)
end

--// =========================================================================
--// 3. CONFIGURATION & STATE
--// =========================================================================

local VERSION = "1.3.0"
local PLAYBACK_MODES = { "Hybrid", "Money", "Time" }
local MUTATOR_MODES = { "Off", "Refuse (None)", "Highest Bonus" }
local MAP_FALLBACK = { "Duels", "Towers", "ShinjukuStation", "Endless", "Nightmare" }

local DEFAULT_CFG = {
    -- Lobby
    AutoSummon = false,
    SummonAmount = 1,
    AlwaysSummonMax = false,
    SummonDelay = 1.1,
    NotifyRarePulls = true,

    -- Match
    VoteMapName = "",
    AutoVoteMap = false,
    VoteMapDelay = 2.0,
    AutoSkipGame = false,
    AutoSkipScript = false,
    StopSkipWave = 0,
    AutoDoubleSpeed = false,
    AutoMutatorMode = "Off",
    AutoReplay = false,
    ReplayDelay = 1.5,

    -- Macro
    MacroName = "",
    SelectedMacro = "",
    PlaybackMode = "Hybrid",
    AutoPlayback = false,
    IgnoreMapCheck = false,
    AutoExecOnTeleport = false,
    AutoExecUrl = "",
}

local function cloneDefaults()
    local t = {}
    for k, v in pairs(DEFAULT_CFG) do
        t[k] = v
    end
    return t
end

local CFG = cloneDefaults()

local State = {
    Running = true,
    UIReady = false,
    ApplyingConfig = false,
    UpdatingAmountInput = false,
    UpdatingMacroNameInput = false,
    UpdatingStopSkipInput = false,
    UpdatingAutoExecUrlInput = false,
    Window = nil,
    WindUI = nil,
    Connections = {},
    CachedServerCash = nil,
    LastServerCashFetchAt = 0,
    CachedCapacity = nil,
    LastCapacityFetchAt = 0,
    CachedPrices = nil,
    CachedTowersModule = nil,
    IsSummoning = false,
    NextSummonAt = 0,
    TotalSummoned = 0,
    TotalBatches = 0,
    LastSummonStatus = "Idle",
    LastPullSummary = "None",
    StatusLogs = {},
    Widgets = {},

    -- Match runtime
    MatchSerial = 1,
    LastMatchRunning = false,
    LastMatchEnded = false,
    LastWave = 0,
    WaveStartedAt = os.clock(),
    SkipVoteSent = false,
    ReplaySent = false,
    ReplayReadyAt = 0,
    VoteSent = false,
    NextVoteAt = 0,
    SpeedSentForSerial = 0,
    LastMutatorOptions = "",
    TowerPriceCache = {},

    -- Macro runtime
    Recording = false,
    Playing = false,
    PlaySerial = 0,
    SuppressMacroRecord = false,
    MacroActions = {},
    ActiveMacro = nil,
    MacroMap = "",
    MacroStartedAt = 0,
    PlaybackStartedAt = 0,
    PlaybackStep = 0,
    PlaybackTotal = 0,
    PlaybackWaitReason = "",
    MacroStatus = "Idle",
    MacroHookStatus = "Not installed",
    RecordHandles = setmetatable({}, { __mode = "k" }),
    PlaybackHandles = {},
    NextMacroHandle = 0,
    AutoPlayedForSerial = 0,
    AutoPlayFailedForSerial = 0,
    AutoPlayEligibleAt = 0,
    TeleportQueueStatus = "Off",
    LastQueuedPayload = nil,
}

function SafeUtils.trackConnection(conn)
    if typeof(conn) == "RBXScriptConnection" then
        table.insert(State.Connections, conn)
    end
    return conn
end

function SafeUtils.disconnectAll()
    for i = #State.Connections, 1, -1 do
        local conn = State.Connections[i]
        State.Connections[i] = nil
        if typeof(conn) == "RBXScriptConnection" then
            pcall(function()
                conn:Disconnect()
            end)
        end
    end
end

function SafeUtils.logStatus(key, message, isWarning)
    local now = os.clock()
    local entry = State.StatusLogs[key]
    if entry and entry.message == message and (now - entry.at) < 10 then
        return
    end
    State.StatusLogs[key] = { message = message, at = now }
    if isWarning then
        warn("[ShenanigansTD] " .. tostring(message))
    else
        print("[ShenanigansTD] " .. tostring(message))
    end
end

local function notify(title, content, duration)
    if State.WindUI and type(State.WindUI.Notify) == "function" then
        pcall(State.WindUI.Notify, State.WindUI, {
            Title = tostring(title),
            Content = tostring(content),
            Duration = duration or 3,
        })
    end
end

--// =========================================================================
--// 4. LOBBY SUMMON MODULE
--// =========================================================================

local LobbySummon = {}

local RARE_PULL_RARITIES = {
    Legendary = true,
    Mythic = true,
    SpecialGrade = true,
    Exclusive = true,
}

function LobbySummon.getLobbyFunction(name)
    return SafeUtils.findPath(ReplicatedStorage, "Game", "Functions", name)
end

function LobbySummon.getLobbyEvent(name)
    return SafeUtils.findPath(ReplicatedStorage, "Game", "Events", name)
end

function LobbySummon.isLobbyAvailable()
    local summonFn = LobbySummon.getLobbyFunction("SummonTower")
    return typeof(summonFn) == "Instance" and summonFn:IsA("RemoteFunction")
end

function LobbySummon.getPriceTiers()
    if type(State.CachedPrices) ~= "table" then
        local mod = SafeUtils.findChild(ReplicatedStorage, "Summon_Prices")
        if mod and mod:IsA("ModuleScript") then
            local ok, tbl = pcall(require, mod)
            if ok and type(tbl) == "table" then
                State.CachedPrices = {
                    First = tonumber(tbl.First) or 100,
                    Second = tonumber(tbl.Second) or tonumber(tbl.First) or 100,
                    Third = tonumber(tbl.Third) or tonumber(tbl.Second) or tonumber(tbl.First) or 100,
                }
            end
        end
    end

    local prices = State.CachedPrices or { First = 100, Second = 100, Third = 100 }
    local discountInst = SafeUtils.findChild(ReplicatedStorage, "Summon Discount")
    local discountEnabled = SafeUtils.getValue(discountInst) == true

    return prices, discountEnabled
end

function LobbySummon.getSummonCost(count)
    local amount = math.floor(tonumber(count) or 0)
    if amount < 1 then
        return 0
    end
    local prices, discountEnabled = LobbySummon.getPriceTiers()
    if not discountEnabled then
        return prices.First * amount
    end
    if amount >= 20 then
        return prices.Third * amount
    elseif amount >= 10 then
        return prices.Second * amount
    end
    return prices.First * amount
end

function LobbySummon.getMaxAffordable(cash)
    local balance = tonumber(cash) or 0
    if not SafeUtils.isFiniteNumber(balance) or balance <= 0 then
        return 0
    end
    balance = math.floor(balance)

    local prices, discountEnabled = LobbySummon.getPriceTiers()
    if not discountEnabled then
        if prices.First <= 0 then
            return 0
        end
        return math.floor(balance / prices.First)
    end

    local best = 0

    -- Bracket 1: 1..9 at First price
    if prices.First > 0 then
        local b1 = math.min(9, math.floor(balance / prices.First))
        if b1 > best then
            best = b1
        end
    end

    -- Bracket 2: 10..19 at Second price
    if prices.Second > 0 then
        local b2 = math.floor(balance / prices.Second)
        if b2 >= 10 then
            b2 = math.min(19, b2)
            if b2 > best then
                best = b2
            end
        end
    end

    -- Bracket 3: >= 20 at Third price
    if prices.Third > 0 then
        local b3 = math.floor(balance / prices.Third)
        if b3 >= 20 and b3 > best then
            best = b3
        end
    end

    return best
end

function LobbySummon.refreshServerCash(force)
    local now = os.clock()
    if not force and State.CachedServerCash ~= nil and (now - State.LastServerCashFetchAt) < 1.0 then
        return State.CachedServerCash
    end
    local getCurrency = LobbySummon.getLobbyFunction("GetCurrency")
    if not getCurrency or not getCurrency:IsA("RemoteFunction") then
        return State.CachedServerCash
    end
    local ok, val = pcall(getCurrency.InvokeServer, getCurrency, "Cash")
    local num = ok and tonumber(val) or nil
    if SafeUtils.isFiniteNumber(num) then
        State.CachedServerCash = num
        State.LastServerCashFetchAt = os.clock()
        return num
    end
    return State.CachedServerCash
end

function LobbySummon.getCash(preferServerRefresh)
    if preferServerRefresh then
        local serverCash = LobbySummon.refreshServerCash(true)
        if SafeUtils.isFiniteNumber(serverCash) then
            return serverCash
        end
    end

    local lp = SafeUtils.getLocalPlayer()
    local cashInst = lp and SafeUtils.findPath(lp, "leaderstats", "Cash")
    local lsCash = tonumber(SafeUtils.getValue(cashInst))
    if SafeUtils.isFiniteNumber(lsCash) then
        return lsCash
    end

    if SafeUtils.isFiniteNumber(State.CachedServerCash) then
        return State.CachedServerCash
    end

    local label = lp and SafeUtils.findPath(
        lp,
        "PlayerGui",
        "Main",
        "Main",
        "Currencies",
        "CoinAmount",
        "CurrencyLayout",
        "AmountLabel"
    )
    if label then
        local okText, text = pcall(function()
            return label.Text
        end)
        if okText and type(text) == "string" then
            local cleaned = text:gsub(",", "")
            local num = tonumber(cleaned:match("%-?%d+%.?%d*"))
            if SafeUtils.isFiniteNumber(num) then
                return num
            end
        end
    end

    return 0
end

function LobbySummon.getBannerAndPityInfo()
    local lp = SafeUtils.getLocalPlayer()
    local bannerFolder = SafeUtils.findPath(ReplicatedStorage, "Game", "TowersInSummon")
    local mythic = bannerFolder and SafeUtils.getValue(SafeUtils.findChild(bannerFolder, "Mythic")) or "?"
    local special = bannerFolder and SafeUtils.getValue(SafeUtils.findChild(bannerFolder, "SpecialGrade")) or "?"

    local timerText = "?"
    local timerLabel = lp and SafeUtils.findPath(lp, "PlayerGui", "Main", "Main", "Summon", "Timer")
    if timerLabel then
        local okTimer, txt = pcall(function()
            return timerLabel.Text
        end)
        if okTimer and type(txt) == "string" and txt ~= "" then
            timerText = txt
        end
    end

    local pityMythic = lp and SafeUtils.getAttribute(lp, "PityMythic")
    local pitySpecial = lp and SafeUtils.getAttribute(lp, "PitySpecialGrade")
    local hardMythic, hardSpecial = 1000, 10000
    local pityMod = SafeUtils.findChild(ReplicatedStorage, "SummonPity")
    if pityMod and pityMod:IsA("ModuleScript") then
        local okPity, tbl = pcall(require, pityMod)
        if okPity and type(tbl) == "table" and type(tbl.HardPity) == "table" then
            hardMythic = tonumber(tbl.HardPity.Mythic) or hardMythic
            hardSpecial = tonumber(tbl.HardPity.SpecialGrade) or hardSpecial
        end
    end

    return {
        Mythic = tostring(mythic or "?"),
        SpecialGrade = tostring(special or "?"),
        Timer = timerText,
        PityMythic = tonumber(pityMythic) or 0,
        HardMythic = hardMythic,
        PitySpecialGrade = tonumber(pitySpecial) or 0,
        HardSpecialGrade = hardSpecial,
    }
end

function LobbySummon.refreshCapacity(force)
    local usingCap = SafeUtils.getValue(SafeUtils.findChild(ReplicatedStorage, "UsingCapacity"))
    if usingCap ~= true then
        return nil
    end
    local now = os.clock()
    if not force and State.CachedCapacity ~= nil and (now - State.LastCapacityFetchAt) < 5.0 then
        return State.CachedCapacity
    end
    local getInv = LobbySummon.getLobbyFunction("GetInventoryData")
    if not getInv or not getInv:IsA("RemoteFunction") then
        return State.CachedCapacity
    end
    local ok, inv = pcall(getInv.InvokeServer, getInv)
    if ok and type(inv) == "table" then
        local towers = type(inv.Towers) == "table" and #inv.Towers or 0
        local crates = type(inv.Crates) == "table" and #inv.Crates or 0
        local maxCap = tonumber(inv.MaxCapacity) or 0
        State.CachedCapacity = {
            Used = towers + crates,
            Max = maxCap,
        }
        State.LastCapacityFetchAt = os.clock()
    end
    return State.CachedCapacity
end

function LobbySummon.getTowerMeta(towerName)
    if type(towerName) ~= "string" then
        return nil
    end
    if State.CachedTowersModule == nil then
        local mod = SafeUtils.findChild(ReplicatedStorage, "Module_Towers")
        if mod and mod:IsA("ModuleScript") then
            local ok, tbl = pcall(require, mod)
            if ok and type(tbl) == "table" then
                State.CachedTowersModule = tbl
            else
                State.CachedTowersModule = false
            end
        else
            State.CachedTowersModule = false
        end
    end
    if type(State.CachedTowersModule) == "table" then
        return State.CachedTowersModule[towerName]
    end
    return nil
end

function LobbySummon.summarizeSummonResult(result)
    if type(result) ~= "table" then
        return "None", {}
    end
    local count = 0
    local rarityCounts = {}
    local rareHits = {}
    local autoSoldCount = 0

    for _, item in pairs(result) do
        if item ~= "Counted" then
            count += 1
            local unitName = nil
            local rarity = nil
            local isShiny = false
            local isAutosold = false

            if type(item) == "table" then
                unitName = item.name or item.OldName
                rarity = item.rarity
                isShiny = item.Shiny == true
                isAutosold = item.autosold == true
                if not rarity and type(item.OldName) == "string" then
                    local meta = LobbySummon.getTowerMeta(item.OldName)
                    rarity = meta and meta.rarity
                end
                if not rarity and type(item.name) == "string" then
                    local meta = LobbySummon.getTowerMeta(item.name)
                    rarity = meta and meta.rarity
                end
            elseif type(item) == "string" then
                unitName = item
                local meta = LobbySummon.getTowerMeta(item)
                rarity = meta and meta.rarity
            end

            rarity = tostring(rarity or "Unknown")
            rarityCounts[rarity] = (rarityCounts[rarity] or 0) + 1
            if isAutosold then
                autoSoldCount += 1
            end
            if RARE_PULL_RARITIES[rarity] or isShiny then
                local tag = (isShiny and "[Shiny] " or "") .. tostring(unitName or "Unit") .. " (" .. rarity .. ")"
                table.insert(rareHits, tag)
            end
        end
    end

    local parts = {}
    for _, rar in ipairs({ "SpecialGrade", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Basic", "Unknown" }) do
        if rarityCounts[rar] then
            table.insert(parts, rarityCounts[rar] .. "x " .. rar)
        end
    end
    local summary = tostring(count) .. " summoned"
    if #parts > 0 then
        summary = summary .. " [" .. table.concat(parts, ", ") .. "]"
    end
    if autoSoldCount > 0 then
        summary = summary .. " (" .. autoSoldCount .. " autosold)"
    end
    return summary, rareHits
end

function LobbySummon.executeSummon(explicitAmount)
    if State.IsSummoning then
        return false, "Summon already in progress", 0.1
    end
    if not LobbySummon.isLobbyAvailable() then
        State.LastSummonStatus = "Lobby Summon remote unavailable"
        return false, State.LastSummonStatus, 1.5
    end

    State.IsSummoning = true

    local okExec, success, message, retryDelay = pcall(function()
        local cash = LobbySummon.getCash(true)
        local targetAmount
        if explicitAmount ~= nil then
            targetAmount = math.floor(tonumber(explicitAmount) or 0)
        elseif CFG.AlwaysSummonMax then
            targetAmount = LobbySummon.getMaxAffordable(cash)
        else
            targetAmount = math.floor(tonumber(CFG.SummonAmount) or 1)
        end

        if targetAmount < 1 then
            local oneCost = LobbySummon.getSummonCost(1)
            local msg = string.format(
                "Need %s Cash for 1 summon (have %s)",
                SafeUtils.formatNumber(oneCost),
                SafeUtils.formatNumber(cash)
            )
            State.LastSummonStatus = msg
            return false, msg, 1.0
        end

        local neededCost = LobbySummon.getSummonCost(targetAmount)
        if cash < neededCost then
            local msg = string.format(
                "Waiting for Cash (%s / %s for x%s)",
                SafeUtils.formatNumber(cash),
                SafeUtils.formatNumber(neededCost),
                SafeUtils.formatNumber(targetAmount)
            )
            State.LastSummonStatus = msg
            return false, msg, 1.0
        end

        local summonRemote = LobbySummon.getLobbyFunction("SummonTower")
        local okInvoke, res = pcall(summonRemote.InvokeServer, summonRemote, targetAmount)
        if not okInvoke then
            local errMsg = "Invoke error: " .. tostring(res)
            State.LastSummonStatus = errMsg
            return false, errMsg, 1.5
        end

        if type(res) == "table" and #res > 0 then
            local updateMoney = LobbySummon.getLobbyEvent("UpdateMoneyClient")
            if updateMoney and updateMoney:IsA("BindableEvent") then
                pcall(updateMoney.Fire, updateMoney, "Cash")
            end

            local summary, rareHits = LobbySummon.summarizeSummonResult(res)
            State.TotalSummoned += #res
            State.TotalBatches += 1
            State.LastPullSummary = summary
            State.LastSummonStatus = "Summoned x" .. tostring(#res)

            task.spawn(function()
                LobbySummon.refreshServerCash(true)
                LobbySummon.refreshCapacity(true)
            end)

            if CFG.NotifyRarePulls and #rareHits > 0 then
                notify("Rare Pull!", table.concat(rareHits, "\n"), 4)
            end

            return true, summary, math.max(0.05, tonumber(CFG.SummonDelay) or 1.1)
        elseif type(res) == "string" then
            if res == "Cooldown" then
                State.LastSummonStatus = "Server cooldown — retrying"
                return false, "Cooldown", 0.2
            elseif res == "Not Enough money" then
                LobbySummon.refreshServerCash(true)
                State.LastSummonStatus = "Not Enough money"
                return false, "Not Enough money", 1.0
            else
                State.LastSummonStatus = "Server: " .. res
                return false, res, 1.5
            end
        else
            State.LastSummonStatus = "Unexpected response: " .. tostring(res)
            return false, State.LastSummonStatus, 1.5
        end
    end)

    State.IsSummoning = false

    if not okExec then
        State.LastSummonStatus = "Internal error: " .. tostring(success)
        return false, State.LastSummonStatus, 1.5
    end
    return success, message, retryDelay
end

--// =========================================================================
--// 5. MATCH STATE & AUTOMATION MODULE
--// =========================================================================

local MatchState = {}

function MatchState.getPlayerGui()
    local lp = SafeUtils.getLocalPlayer()
    if not lp then
        return nil
    end
    return SafeUtils.findChildOfClass(lp, "PlayerGui")
end

function MatchState.getGameGui()
    return SafeUtils.findChild(MatchState.getPlayerGui(), "GameGui")
end

function MatchState.getInfoFolder()
    return SafeUtils.findChild(Workspace, "Info")
end

function MatchState.matchEvent(name)
    local direct = SafeUtils.findChild(ReplicatedStorage, name)
    if direct then
        return direct
    end
    return SafeUtils.findPath(ReplicatedStorage, "Events", name)
end

function MatchState.macroRemote(name)
    local fn = SafeUtils.findPath(ReplicatedStorage, "Functions", name)
    if fn then
        return fn
    end
    local ev = SafeUtils.findPath(ReplicatedStorage, "Events", name)
    if ev then
        return ev
    end
    return SafeUtils.findChild(ReplicatedStorage, name)
end

function MatchState.isMatchServer()
    return MatchState.getInfoFolder() ~= nil or SafeUtils.findChild(ReplicatedStorage, "Functions") ~= nil
end

function MatchState.isMatchRunning()
    local info = MatchState.getInfoFolder()
    local runningVal = SafeUtils.getValue(SafeUtils.findChild(info, "GameRunning"))
    if type(runningVal) == "boolean" then
        return runningVal
    end
    local statsFrame = SafeUtils.findPath(MatchState.getGameGui(), "Info", "Stats")
    local statsVisible = SafeUtils.getProp(statsFrame, "Visible")
    if type(statsVisible) == "boolean" then
        return statsVisible
    end
    return false
end

function MatchState.getMatchEndState()
    local endScreen = SafeUtils.findChild(MatchState.getGameGui(), "EndScreen")
    local endScreenVisible = SafeUtils.getProp(endScreen, "Visible") == true

    local info = MatchState.getInfoFolder()
    local msg = SafeUtils.getValue(SafeUtils.findChild(info, "Message"))
    local gameOverAttr = SafeUtils.getAttribute(info, "GameOver") == true
    local outcome = nil
    if msg == "VICTORY" or msg == "GAME OVER" then
        outcome = msg
    elseif gameOverAttr then
        outcome = "GAME OVER"
    end

    return {
        ended = endScreenVisible or gameOverAttr or (outcome ~= nil),
        endScreenVisible = endScreenVisible,
        gameOver = gameOverAttr,
        outcome = outcome,
    }
end

function MatchState.getTimerSeconds()
    local info = MatchState.getInfoFolder()
    local secs = tonumber(SafeUtils.getAttribute(info, "TimerSeconds"))
    if SafeUtils.isFiniteNumber(secs) and secs > 0 then
        return math.floor(secs)
    end
    return 0
end

function MatchState.pickMutatorOption(optionsStr, mode)
    if mode == "Refuse (None)" then
        return "None"
    end
    if type(optionsStr) ~= "string" or optionsStr == "" then
        return nil
    end

    local offered = {}
    for id in string.gmatch(optionsStr, "[^,]+") do
        local clean = id:match("^%s*(.-)%s*$")
        if clean ~= "" then
            table.insert(offered, clean)
        end
    end
    if #offered == 0 then
        return nil
    end

    if mode == "Highest Bonus" then
        local bonusById = {}
        local mod = SafeUtils.findChild(ReplicatedStorage, "EndlessRewards")
        if mod and mod:IsA("ModuleScript") then
            local ok, tbl = pcall(require, mod)
            if ok and type(tbl) == "table" and type(tbl.Mutators) == "table" then
                for _, entry in ipairs(tbl.Mutators) do
                    if type(entry) == "table" and type(entry.id) == "string" then
                        bonusById[entry.id] = tonumber(entry.bonus) or 0
                    end
                end
            end
        end

        local bestId = offered[1]
        local bestBonus = -math.huge
        for _, id in ipairs(offered) do
            local bonus = bonusById[id] or 0
            if bonus > bestBonus then
                bestBonus = bonus
                bestId = id
            end
        end
        return bestId
    end

    return offered[1]
end

function MatchState.voteMutator(choice)
    if type(choice) ~= "string" or choice == "" then
        return false, "No mutator choice"
    end
    local remote = MatchState.matchEvent("MutatorVote")
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "MutatorVote remote unavailable"
    end
    local ok, err = pcall(function()
        remote:FireServer(choice)
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

function MatchState.isMatchEnded()
    return MatchState.getMatchEndState().ended
end

function MatchState.isMatchActive()
    if not MatchState.isMatchRunning() then
        return false
    end
    return not MatchState.isMatchEnded()
end

function MatchState.getWave()
    local info = MatchState.getInfoFolder()
    local waveNum = tonumber(SafeUtils.getValue(SafeUtils.findChild(info, "Wave")))
    if SafeUtils.isFiniteNumber(waveNum) and waveNum >= 0 then
        return math.floor(waveNum)
    end

    if MatchState.isMatchRunning() then
        local waveLabel = SafeUtils.findPath(MatchState.getGameGui(), "Info", "Stats", "Wave")
        local text = SafeUtils.getProp(waveLabel, "Text")
        if type(text) == "string" then
            local primaryPart = text:match("^(.-)/") or text
            local parsed = SafeUtils.parseFormattedNumber(primaryPart, nil)
            if parsed and parsed >= 0 then
                return math.floor(parsed)
            end
        end
    end
    return 0
end

function MatchState.getCash()
    local lp = SafeUtils.getLocalPlayer()
    if lp then
        local goldVal = tonumber(SafeUtils.getValue(SafeUtils.findChild(lp, "Gold")))
        if SafeUtils.isFiniteNumber(goldVal) then
            return goldVal
        end
    end

    if MatchState.isMatchRunning() then
        local goldLabel = SafeUtils.findPath(MatchState.getGameGui(), "Info", "Stats", "Gold")
        local text = SafeUtils.getProp(goldLabel, "Text")
        local parsed = SafeUtils.parseFormattedNumber(text, nil)
        if parsed ~= nil then
            return parsed
        end
    end
    return 0
end

function MatchState.getKills()
    local lp = SafeUtils.getLocalPlayer()
    local val = lp and tonumber(SafeUtils.getValue(SafeUtils.findChild(lp, "Kills")))
    return SafeUtils.isFiniteNumber(val) and math.floor(val) or 0
end

function MatchState.getPlacedTowers()
    local lp = SafeUtils.getLocalPlayer()
    local val = lp and tonumber(SafeUtils.getValue(SafeUtils.findChild(lp, "PlacedTowers")))
    return SafeUtils.isFiniteNumber(val) and math.floor(val) or 0
end

function MatchState.getCurrentMap()
    local info = MatchState.getInfoFolder()
    local mapValue = SafeUtils.getValue(SafeUtils.findChild(info, "CurrentMap"))
    if type(mapValue) == "string" and mapValue ~= "" then
        return mapValue
    end
    return ""
end

function MatchState.isVoting()
    local info = MatchState.getInfoFolder()
    local votingInst = SafeUtils.findChild(info, "Voting")
    if votingInst and votingInst:IsA("BoolValue") then
        return SafeUtils.getValue(votingInst) == true
    end
    local votingFrame = SafeUtils.findChild(MatchState.getGameGui(), "Voting")
    return SafeUtils.getProp(votingFrame, "Visible") == true
end

function MatchState.isSkipAvailable()
    local info = MatchState.getInfoFolder()
    return SafeUtils.getAttribute(info, "SkipAvailable") == true
end

function MatchState.getInGameAutoSkip()
    local button = SafeUtils.findPath(MatchState.getGameGui(), "SettingsPanel", "AutoSkipButton")
    local text = SafeUtils.getProp(button, "Text")
    if type(text) ~= "string" then
        return false
    end
    return text:upper():find("%f[%a]ON%f[%A]") ~= nil
end

function MatchState.setInGameAutoSkip(enabled)
    local button = SafeUtils.findPath(MatchState.getGameGui(), "SettingsPanel", "AutoSkipButton")
    if not button or not button:IsA("GuiButton") then
        return false, "In-game AutoSkip button unavailable"
    end
    if MatchState.getInGameAutoSkip() == enabled then
        return true
    end
    local ok = pcall(function()
        button:Activate()
    end)
    if (not ok or MatchState.getInGameAutoSkip() ~= enabled) and type(firesignal) == "function" then
        pcall(firesignal, button.Activated)
    end
    if MatchState.getInGameAutoSkip() ~= enabled then
        return false, "Could not toggle in-game AutoSkip"
    end
    return true
end

function MatchState.getDoubleSpeed()
    local active = SafeUtils.findPath(ReplicatedStorage, "Events", "DoubleSpeedActive")
    if active and active:IsA("BoolValue") then
        return SafeUtils.getValue(active) == true
    end
    return false
end

function MatchState.setDoubleSpeed(enabled)
    if not MatchState.isMatchActive() then
        return false, "Start a match before changing speed"
    end
    if MatchState.getDoubleSpeed() == enabled then
        return true
    end
    local lp = SafeUtils.getLocalPlayer()
    local wins = lp and tonumber(SafeUtils.getAttribute(lp, "Wins")) or 0
    if enabled and (not wins or wins < 10) then
        return false, "2x speed requires 10 wins"
    end
    local remote = MatchState.matchEvent(enabled and "DoubleSpeed" or "OneSpeed")
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "Speed remote unavailable"
    end
    local ok, err = pcall(function()
        remote:FireServer()
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

function MatchState.replayNow()
    if not MatchState.isMatchEnded() then
        return false, "Play Again is available after the match ends"
    end
    local remote = MatchState.matchEvent("ReplayButtonPressed")
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "ReplayButtonPressed remote unavailable"
    end
    local ok, err = pcall(function()
        remote:FireServer()
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

function MatchState.exitToLobby()
    local remote = MatchState.matchEvent("ExitGame")
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "ExitGame remote unavailable"
    end
    local ok, err = pcall(function()
        remote:FireServer()
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

function MatchState.getMapList()
    local names, seen = {}, {}
    local mapsFrame = SafeUtils.findPath(MatchState.getGameGui(), "Voting", "Maps")
    if mapsFrame then
        local ok, children = pcall(mapsFrame.GetChildren, mapsFrame)
        if ok and type(children) == "table" then
            for _, button in ipairs(children) do
                if typeof(button) == "Instance" and button:IsA("GuiButton") and button.Name ~= "Example" then
                    local name = SafeUtils.getAttribute(button, "MapName") or button.Name
                    if type(name) == "string" and name ~= "" and not seen[name] then
                        seen[name] = true
                        table.insert(names, name)
                    end
                end
            end
        end
    end
    if #names == 0 then
        for _, name in ipairs(MAP_FALLBACK) do
            table.insert(names, name)
        end
    end
    return names
end

function MatchState.voteForMap(name)
    local mapName = tostring(name or CFG.VoteMapName or "")
    if mapName == "" then
        return false, "No map selected"
    end
    if not table.find(MatchState.getMapList(), mapName) then
        return false, "Selected map not in current map list"
    end
    local remote = MatchState.matchEvent("VoteForMap")
    if not remote or not remote:IsA("RemoteEvent") then
        return false, "VoteForMap remote unavailable"
    end
    local ok, err = pcall(function()
        remote:FireServer(mapName)
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

function MatchState.updateSerial()
    local running = MatchState.isMatchRunning()
    local ended = MatchState.isMatchEnded()
    local wave = MatchState.getWave()

    local started = running and not State.LastMatchRunning
    local endedTransition = ended and not State.LastMatchEnded
    local stoppedTransition = (not running) and State.LastMatchRunning
    local reopened = State.LastMatchEnded and (not ended) and running
    local waveReset = running and not ended and wave < State.LastWave and State.LastWave >= 1
    local waveChanged = wave ~= State.LastWave

    if started or endedTransition or stoppedTransition or reopened or waveReset then
        State.MatchSerial += 1
        State.WaveStartedAt = os.clock()
    elseif waveChanged then
        State.WaveStartedAt = os.clock()
    end

    State.LastMatchRunning = running
    State.LastMatchEnded = ended
    State.LastWave = wave

    return State.MatchSerial, {
        started = started,
        ended = endedTransition,
        stopped = stoppedTransition,
        reopened = reopened,
        waveReset = waveReset,
        waveChanged = waveChanged,
        running = running,
        active = running and not ended,
        wave = wave,
    }
end

function MatchState.getMatchSerial()
    return State.MatchSerial
end

function MatchState.getSnapshot()
    local endState = MatchState.getMatchEndState()
    local running = MatchState.isMatchRunning()
    local lp = SafeUtils.getLocalPlayer()
    return {
        InMatchServer = MatchState.isMatchServer(),
        Running = running,
        Ended = endState.ended,
        EndScreenVisible = endState.endScreenVisible,
        GameOver = endState.gameOver,
        Outcome = endState.outcome,
        Active = running and not endState.ended,
        Voting = MatchState.isVoting(),
        Wave = MatchState.getWave(),
        TimerSeconds = MatchState.getTimerSeconds(),
        Cash = MatchState.getCash(),
        Kills = MatchState.getKills(),
        PlacedTowers = MatchState.getPlacedTowers(),
        Map = MatchState.getCurrentMap(),
        DoubleSpeed = MatchState.getDoubleSpeed(),
        AutoSkip = MatchState.getInGameAutoSkip(),
        EndlessCash = lp and tonumber(SafeUtils.getAttribute(lp, "EndlessCash")) or 0,
        EndlessGems = lp and tonumber(SafeUtils.getAttribute(lp, "EndlessGems")) or 0,
        EndlessCrates = lp and tonumber(SafeUtils.getAttribute(lp, "EndlessCrates")) or 0,
        MatchSerial = State.MatchSerial,
    }
end

--// =========================================================================
--// 6. MACRO SERIALIZER & PROFILE MANAGER
--// =========================================================================

local MacroSerializer = {}

local VALID_ACTION_KINDS = {
    Place = true,
    Upgrade = true,
    Sell = true,
    Mode = true,
    Skip = true,
}

local function sanitizePrimitiveArgs(rawArgs, argCount)
    local count = math.clamp(math.floor(tonumber(argCount) or 0), 0, 16)
    local packed = table.create(count)
    for i = 1, count do
        local entry = type(rawArgs) == "table" and rawArgs[i] or nil
        if type(entry) ~= "table" or entry.Type == "nil" then
            packed[i] = { Type = "nil" }
        elseif entry.Type == "string" and type(entry.Value) == "string" then
            packed[i] = { Type = "string", Value = entry.Value }
        elseif entry.Type == "number" and SafeUtils.isFiniteNumber(entry.Value) then
            packed[i] = { Type = "number", Value = entry.Value }
        elseif entry.Type == "boolean" and type(entry.Value) == "boolean" then
            packed[i] = { Type = "boolean", Value = entry.Value }
        else
            return nil, "Unsupported arg entry at index " .. tostring(i)
        end
    end
    return packed, count
end

function MacroSerializer.validateAction(action, activeHandles)
    if type(action) ~= "table" then
        return false, "Action entry is not a table"
    end
    if type(action.Kind) ~= "string" or not VALID_ACTION_KINDS[action.Kind] then
        return false, "Unsupported action Kind: " .. tostring(action.Kind)
    end
    if not SafeUtils.isFiniteNumber(action.Time) or action.Time < 0 then
        return false, "Invalid action Time"
    end
    if action.Gold ~= nil and (not SafeUtils.isFiniteNumber(action.Gold) or action.Gold < 0) then
        return false, "Invalid action Gold"
    end
    if action.Cost ~= nil and (not SafeUtils.isFiniteNumber(action.Cost) or action.Cost < 0) then
        return false, "Invalid action Cost"
    end
    if action.Wave ~= nil and (not SafeUtils.isFiniteNumber(action.Wave) or action.Wave < 0) then
        return false, "Invalid action Wave"
    end
    if action.WaveTime ~= nil and (not SafeUtils.isFiniteNumber(action.WaveTime) or action.WaveTime < 0) then
        return false, "Invalid action WaveTime"
    end

    if action.Position ~= nil then
        if type(action.Position) ~= "table" or #action.Position ~= 3 then
            return false, "Position must have 3 coordinates"
        end
        for i = 1, 3 do
            if not SafeUtils.isFiniteNumber(action.Position[i]) then
                return false, "Non-finite Position coordinate"
            end
        end
    end

    if action.Kind == "Place" or action.Kind == "Upgrade" then
        if type(action.Unit) ~= "string" or action.Unit == "" then
            return false, "Missing Unit name"
        end
        if type(action.Handle) ~= "string" or action.Handle == "" then
            return false, "Missing tower Handle"
        end
        if type(action.Frame) ~= "table" or #action.Frame ~= 12 then
            return false, "Frame must contain 12 CFrame components"
        end
        for i = 1, 12 do
            if not SafeUtils.isFiniteNumber(action.Frame[i]) then
                return false, "Non-finite CFrame component"
            end
        end
        if activeHandles then
            if action.Kind == "Upgrade" and not activeHandles[action.Handle] then
                return false, "Upgrade references inactive handle: " .. action.Handle
            end
            activeHandles[action.Handle] = true
        end
    elseif action.Kind == "Mode" or action.Kind == "Sell" then
        if type(action.Handle) ~= "string" or action.Handle == "" then
            return false, "Missing tower Handle for " .. action.Kind
        end
        if activeHandles then
            if not activeHandles[action.Handle] then
                return false, action.Kind .. " references inactive handle: " .. action.Handle
            end
            if action.Kind == "Sell" then
                activeHandles[action.Handle] = nil
            end
        end
    elseif action.Kind == "Skip" then
        local count = action.ArgCount or 0
        if not SafeUtils.isFiniteNumber(count) or count < 0 or count > 16 then
            return false, "Invalid Skip ArgCount"
        end
        local packed, err = sanitizePrimitiveArgs(action.Args, count)
        if not packed then
            return false, err
        end
    end

    return true
end

function MacroSerializer.sanitizeActionsForSave(actions)
    if type(actions) ~= "table" then
        return nil, "Actions table is missing"
    end
    if #actions > 50000 then
        return nil, "Macro exceeds 50,000 action limit"
    end

    local sanitized = {}
    local activeHandles = {}
    local skippedCount = 0

    for idx, raw in ipairs(actions) do
        if type(raw) == "table" then
            local candidate = {
                Kind = raw.Kind,
                Time = SafeUtils.isFiniteNumber(raw.Time) and math.max(0, raw.Time) or 0,
                Wave = SafeUtils.isFiniteNumber(raw.Wave) and math.max(0, math.floor(raw.Wave)) or 0,
                WaveTime = SafeUtils.isFiniteNumber(raw.WaveTime) and math.max(0, raw.WaveTime) or 0,
                Gold = SafeUtils.isFiniteNumber(raw.Gold) and math.max(0, raw.Gold) or 0,
                Cost = SafeUtils.isFiniteNumber(raw.Cost) and math.max(0, raw.Cost) or 0,
                Unit = raw.Unit,
                Handle = raw.Handle,
                Frame = raw.Frame,
                Position = raw.Position,
                Args = raw.Args,
                ArgCount = raw.ArgCount,
            }

            if type(raw.Frame) == "table" and #raw.Frame == 12 then
                local cleanFrame = table.create(12)
                for i = 1, 12 do
                    cleanFrame[i] = raw.Frame[i]
                end
                candidate.Frame = cleanFrame
                if candidate.Position == nil
                    and SafeUtils.isFiniteNumber(cleanFrame[1])
                    and SafeUtils.isFiniteNumber(cleanFrame[2])
                    and SafeUtils.isFiniteNumber(cleanFrame[3])
                then
                    candidate.Position = { cleanFrame[1], cleanFrame[2], cleanFrame[3] }
                end
            end

            if type(candidate.Position) == "table" and #candidate.Position == 3 then
                candidate.Position = { candidate.Position[1], candidate.Position[2], candidate.Position[3] }
            end

            if candidate.Kind == "Skip" then
                local packed, count = sanitizePrimitiveArgs(
                    raw.Args,
                    raw.ArgCount or (type(raw.Args) == "table" and #raw.Args or 0)
                )
                if packed then
                    candidate.Args = packed
                    candidate.ArgCount = count
                end
            end

            local ok, err = MacroSerializer.validateAction(candidate, activeHandles)
            if ok then
                table.insert(sanitized, candidate)
            else
                skippedCount += 1
                SafeUtils.logStatus(
                    "macro_drop_" .. tostring(idx),
                    "Dropped invalid action #" .. tostring(idx) .. ": " .. tostring(err),
                    true
                )
            end
        else
            skippedCount += 1
        end
    end

    return sanitized, skippedCount
end

function MacroSerializer.validateMacroData(data, checkLifecycle)
    if type(data) ~= "table" or type(data.Actions) ~= "table" then
        return false, "Invalid macro header"
    end
    if #data.Actions > 50000 then
        return false, "Macro exceeds 50,000 action limit"
    end
    local activeHandles = checkLifecycle and {} or nil
    for idx, action in ipairs(data.Actions) do
        local ok, err = MacroSerializer.validateAction(action, activeHandles)
        if not ok then
            return false, "Action #" .. tostring(idx) .. ": " .. tostring(err)
        end
    end
    return true
end

function MacroSerializer.encode(macroTable)
    local okValid, errValid = MacroSerializer.validateMacroData(macroTable, true)
    if not okValid then
        return nil, errValid
    end
    local okEnc, json = SafeUtils.jsonEncode(macroTable)
    if not okEnc then
        return nil, tostring(json)
    end
    return json
end

function MacroSerializer.decode(rawJson)
    local okDec, data = SafeUtils.jsonDecode(rawJson)
    if not okDec then
        return nil, "JSON decode failed"
    end
    local valid, err = MacroSerializer.validateMacroData(data, false)
    if not valid then
        return nil, err
    end
    return data
end

local MacroManager = {
    Folder = "ShenanigansTDMacros",
}

function MacroManager:GetMacroPath(name)
    local clean = SafeUtils.cleanName(name)
    if clean == "" then
        return nil, nil
    end
    return self.Folder .. "/" .. clean .. ".json", clean
end

function MacroManager:List()
    if not SafeUtils.ensureFolder(self.Folder) then
        return {}
    end
    local out = {}
    for _, fullPath in ipairs(SafeUtils.listFiles(self.Folder)) do
        local normalized = tostring(fullPath):gsub("\\", "/")
        local fileName = normalized:match("([^/]+)$") or normalized
        local base = fileName:match("^(.+)%.json$")
        if base and base ~= "" then
            table.insert(out, base)
        end
    end
    table.sort(out)
    return out
end

function MacroManager:Save(name, actions, mapName)
    if not SafeUtils.ensureFolder(self.Folder) then
        return false, "Filesystem unavailable"
    end
    local path, clean = self:GetMacroPath(name)
    if not path then
        return false, "Enter a macro name"
    end
    local sanitized, droppedOrErr = MacroSerializer.sanitizeActionsForSave(actions or State.MacroActions)
    if not sanitized then
        return false, tostring(droppedOrErr)
    end

    local payload = {
        Schema = 1,
        Game = "Shenanigans TD",
        Name = clean,
        Map = tostring(mapName ~= nil and mapName or State.MacroMap or ""),
        Actions = sanitized,
    }

    local encoded, encErr = MacroSerializer.encode(payload)
    if not encoded then
        return false, tostring(encErr)
    end

    local tmpPath = path .. ".tmp"
    if SafeUtils.writeTextFile(tmpPath, encoded) then
        local okVerify, verified = SafeUtils.readTextFile(tmpPath)
        if not okVerify or verified ~= encoded then
            SafeUtils.deleteFile(tmpPath)
            return false, "Temp write verification failed"
        end
    end

    if not SafeUtils.writeTextFile(path, encoded) then
        SafeUtils.deleteFile(tmpPath)
        return false, "Write failed"
    end
    SafeUtils.deleteFile(tmpPath)

    State.MacroActions = sanitized
    State.ActiveMacro = payload
    return true, clean, #sanitized
end

function MacroManager:Load(name)
    local path, clean = self:GetMacroPath(name)
    if not path then
        return false, "Select or enter a macro name"
    end
    local okRead, raw = SafeUtils.readTextFile(path)
    if not okRead or not raw then
        return false, "Macro not found: " .. clean
    end
    local data, decErr = MacroSerializer.decode(raw)
    if not data then
        return false, tostring(decErr)
    end
    State.ActiveMacro = data
    State.MacroActions = data.Actions
    State.MacroMap = type(data.Map) == "string" and data.Map or ""
    return true, clean, #data.Actions
end

function MacroManager:Delete(name)
    local path, clean = self:GetMacroPath(name)
    if not path then
        return false, "No macro selected"
    end
    local ok = SafeUtils.deleteFile(path)
    return ok, clean
end

--// =========================================================================
--// 7. ACTION RECORDER
--// =========================================================================

local ActionRecorder = {}

local function getTowerPosition(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end
    local ok, pos = pcall(function()
        if instance:IsA("Model") then
            if instance.PrimaryPart then
                return instance.PrimaryPart.Position
            end
            return instance:GetPivot().Position
        elseif instance:IsA("BasePart") then
            return instance.Position
        end
        return nil
    end)
    if ok and typeof(pos) == "Vector3"
        and SafeUtils.isFiniteNumber(pos.X)
        and SafeUtils.isFiniteNumber(pos.Y)
        and SafeUtils.isFiniteNumber(pos.Z)
    then
        return { pos.X, pos.Y, pos.Z }
    end
    return nil
end

local function isTowerInstanceAlive(instance)
    if typeof(instance) ~= "Instance" then
        return false
    end
    local ok, alive = pcall(function()
        return instance.Parent ~= nil and instance:IsDescendantOf(Workspace)
    end)
    return ok and alive == true
end

local function getTowerHandle(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end
    return State.RecordHandles[instance]
end

local function getOrCreateTowerHandle(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end
    local handle = getTowerHandle(instance)
    if handle then
        return handle
    end
    State.NextMacroHandle += 1
    handle = "t_" .. tostring(State.NextMacroHandle)
    State.RecordHandles[instance] = handle
    return handle
end

local function recordAction(kind, fields)
    if not State.Recording or State.SuppressMacroRecord then
        return false
    end
    local now = os.clock()
    fields = fields or {}
    fields.Kind = kind
    fields.Time = math.max(0, now - State.MacroStartedAt)
    fields.Wave = MatchState.getWave()
    fields.WaveTime = math.max(0, now - State.WaveStartedAt)
    if fields.Gold == nil then
        fields.Gold = MatchState.getCash()
    end
    if fields.Cost == nil then
        fields.Cost = 0
    end

    local ok, err = MacroSerializer.validateAction(fields, nil)
    if not ok then
        SafeUtils.logStatus("rec_invalid_" .. tostring(kind), "Skipped malformed action: " .. tostring(err), true)
        return false
    end

    table.insert(State.MacroActions, fields)
    State.MacroStatus = string.format(
        "Recording (%d actions | Wave %d)",
        #State.MacroActions,
        fields.Wave
    )
    return true
end

function ActionRecorder.getTowerPrice(unitName)
    if type(unitName) ~= "string" or unitName == "" then
        return nil
    end
    local cached = State.TowerPriceCache[unitName]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local towersFolder = SafeUtils.findChild(ReplicatedStorage, "Towers")
    if not towersFolder then
        return nil
    end
    local okFind, model = pcall(towersFolder.FindFirstChild, towersFolder, unitName, true)
    if okFind and typeof(model) == "Instance" then
        local priceInst = SafeUtils.findPath(model, "Config", "Price")
        local priceVal = tonumber(SafeUtils.getValue(priceInst))
        if SafeUtils.isFiniteNumber(priceVal) and priceVal >= 0 then
            State.TowerPriceCache[unitName] = priceVal
            return priceVal
        end
    end
    State.TowerPriceCache[unitName] = false
    return nil
end

function ActionRecorder.recordRemote(remote, method, args, results, goldBefore)
    if not State.Recording or State.SuppressMacroRecord then
        return
    end
    local okName, name = pcall(function()
        return remote.Name
    end)
    if not okName or type(name) ~= "string" then
        return
    end

    if name == "SpawnTower" and method == "InvokeServer" and typeof(results[1]) == "Instance" then
        local unitName = type(args[1]) == "string" and args[1] or tostring(args[1] or "")
        if unitName == "" or typeof(args[2]) ~= "CFrame" then
            return
        end

        local frame = { args[2]:GetComponents() }
        if #frame ~= 12 then
            return
        end
        for i = 1, 12 do
            if not SafeUtils.isFiniteNumber(frame[i]) then
                return
            end
        end
        local pos = { frame[1], frame[2], frame[3] }
        local goldAfter = MatchState.getCash()
        local beforeVal = SafeUtils.isFiniteNumber(goldBefore) and goldBefore or goldAfter
        local cost = ActionRecorder.getTowerPrice(unitName)
        if cost == nil then
            cost = math.max(0, beforeVal - goldAfter)
        end

        if typeof(args[3]) == "Instance" then
            local targetHandle = getTowerHandle(args[3])
            if not targetHandle then
                SafeUtils.logStatus("rec_untracked_upg", "Ignored Upgrade on pre-existing tower without Place handle", true)
                return
            end
            if recordAction("Upgrade", {
                Unit = unitName,
                Frame = frame,
                Position = pos,
                Handle = targetHandle,
                Gold = beforeVal,
                Cost = cost,
            }) then
                State.RecordHandles[args[3]] = nil
                State.RecordHandles[results[1]] = targetHandle
            end
        else
            local handle = getOrCreateTowerHandle(results[1])
            if handle then
                recordAction("Place", {
                    Unit = unitName,
                    Frame = frame,
                    Position = pos,
                    Handle = handle,
                    Gold = beforeVal,
                    Cost = cost,
                })
            end
        end

    elseif name == "SellTower" and method == "InvokeServer" and results[1] == true then
        local handle = getTowerHandle(args[1])
        if handle then
            local pos = getTowerPosition(args[1])
            if recordAction("Sell", { Handle = handle, Position = pos, Gold = goldBefore or MatchState.getCash(), Cost = 0 }) then
                State.RecordHandles[args[1]] = nil
            end
        end

    elseif name == "ChangeTowerMode" and method == "InvokeServer" and results[1] == true then
        local handle = getTowerHandle(args[1])
        if handle and isTowerInstanceAlive(args[1]) then
            recordAction("Mode", {
                Handle = handle,
                Position = getTowerPosition(args[1]),
                Gold = goldBefore or MatchState.getCash(),
                Cost = 0,
            })
        end

    elseif name == "SkipVoteEvent" and method == "FireServer" then
        local packed = {}
        for i = 1, args.n do
            local value = args[i]
            local kind = typeof(value)
            if kind == "string" or (kind == "number" and SafeUtils.isFiniteNumber(value)) or kind == "boolean" then
                packed[i] = { Type = kind, Value = value }
            elseif value == nil then
                packed[i] = { Type = "nil" }
            else
                return
            end
        end
        recordAction("Skip", { Args = packed, ArgCount = args.n, Gold = MatchState.getCash(), Cost = 0 })
    end
end

function ActionRecorder.installHook()
    local HOOK_VERSION = 2
    local WATCHED_REMOTES = {
        SpawnTower = true,
        SellTower = true,
        ChangeTowerMode = true,
        SkipVoteEvent = true,
    }

    local function buildHookStatus(router)
        local parts = {}
        if router.NamecallHooked then
            table.insert(parts, "Namecall")
        end
        if router.InvokeHooked then
            table.insert(parts, "InvokeServer")
        end
        if router.FireHooked then
            table.insert(parts, "FireServer")
        end
        return #parts > 0 and ("Installed (" .. table.concat(parts, " + ") .. ")") or "Hook API unavailable", #parts > 0
    end

    local existing = GlobalEnv.__ShenanigansTDMacroRouter
    if existing and existing.HookVersion == HOOK_VERSION then
        existing.State = State
        existing.Record = ActionRecorder.recordRemote
        existing.GetCash = MatchState.getCash
        existing.ActiveThreads = setmetatable({}, { __mode = "k" })
        local status, ok = buildHookStatus(existing)
        State.MacroHookStatus = status
        return ok
    elseif existing then
        existing.State = nil
        existing.Record = nil
        existing.GetCash = nil
        existing.InHook = true
        if type(restorefunction) == "function" then
            local okMt, mt = pcall(getrawmetatable, game)
            if okMt and type(mt) == "table" and type(mt.__namecall) == "function" then
                pcall(restorefunction, mt.__namecall)
            end
            pcall(function()
                local tempRF = Instance.new("RemoteFunction")
                local fn = tempRF.InvokeServer
                tempRF:Destroy()
                restorefunction(fn)
            end)
            pcall(function()
                local tempRE = Instance.new("RemoteEvent")
                local fn = tempRE.FireServer
                tempRE:Destroy()
                restorefunction(fn)
            end)
        end
        GlobalEnv.__ShenanigansTDMacroRouter = nil
    end

    local router = {
        HookVersion = HOOK_VERSION,
        State = State,
        Record = ActionRecorder.recordRemote,
        GetCash = MatchState.getCash,
        ActiveThreads = setmetatable({}, { __mode = "k" }),
        NamecallHooked = false,
        InvokeHooked = false,
        FireHooked = false,
        RawInvoke = nil,
        RawFire = nil,
    }

    local function safeGetCash()
        if type(router.GetCash) ~= "function" then
            return nil
        end
        local ok, val = pcall(router.GetCash)
        if ok and SafeUtils.isFiniteNumber(val) then
            return val
        end
        return nil
    end

    local function shouldIntercept(self)
        local state = router.State
        if not state or not state.Running or not state.Recording or state.SuppressMacroRecord then
            return false, nil, nil
        end
        local thread = coroutine.running()
        if router.ActiveThreads[thread] then
            return false, nil, nil
        end
        if typeof(self) ~= "Instance" then
            return false, nil, nil
        end
        local ok, name, cls = pcall(function()
            return self.Name, self.ClassName
        end)
        if not ok or not WATCHED_REMOTES[name] then
            return false, nil, nil
        end
        return true, name, cls
    end

    local wrapper = type(newcclosure) == "function" and newcclosure or function(fn)
        return fn
    end

    if type(hookfunction) == "function" then
        local origInvoke
        local okInv, oldInv = pcall(function()
            local tempRF = Instance.new("RemoteFunction")
            local targetFn = tempRF.InvokeServer
            tempRF:Destroy()
            return hookfunction(targetFn, wrapper(function(self, ...)
                local intercept, _, cls = shouldIntercept(self)
                if intercept and cls == "RemoteFunction" then
                    local thread = coroutine.running()
                    router.ActiveThreads[thread] = true
                    local args = table.pack(...)
                    local goldBefore = safeGetCash()
                    local results = table.pack(pcall(origInvoke, self, ...))
                    if results[1] and router.Record then
                        local cleanResults = table.pack(table.unpack(results, 2, results.n))
                        pcall(router.Record, self, "InvokeServer", args, cleanResults, goldBefore)
                    end
                    router.ActiveThreads[thread] = nil
                    if results[1] then
                        return table.unpack(results, 2, results.n)
                    end
                    error(results[2], 0)
                end
                return origInvoke(self, ...)
            end))
        end)
        if okInv and type(oldInv) == "function" then
            origInvoke = oldInv
            router.RawInvoke = oldInv
            router.InvokeHooked = true
        end

        local origFire
        local okFire, oldFire = pcall(function()
            local tempRE = Instance.new("RemoteEvent")
            local targetFn = tempRE.FireServer
            tempRE:Destroy()
            return hookfunction(targetFn, wrapper(function(self, ...)
                local intercept, _, cls = shouldIntercept(self)
                if intercept and cls == "RemoteEvent" then
                    local thread = coroutine.running()
                    router.ActiveThreads[thread] = true
                    local args = table.pack(...)
                    local goldBefore = safeGetCash()
                    local okCall, errCall = pcall(origFire, self, ...)
                    if okCall and router.Record then
                        pcall(router.Record, self, "FireServer", args, { n = 0 }, goldBefore)
                    end
                    router.ActiveThreads[thread] = nil
                    if not okCall then
                        error(errCall, 0)
                    end
                    return
                end
                return origFire(self, ...)
            end))
        end)
        if okFire and type(oldFire) == "function" then
            origFire = oldFire
            router.RawFire = oldFire
            router.FireHooked = true
        end
    end

    if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
        local setNC = type(setnamecallmethod) == "function" and setnamecallmethod or nil
        local origNamecall
        local okNC, oldNC = pcall(function()
            return hookmetamethod(game, "__namecall", wrapper(function(self, ...)
                local method = getnamecallmethod()
                if method ~= "InvokeServer" and method ~= "FireServer" then
                    return origNamecall(self, ...)
                end

                local state = router.State
                local thread = coroutine.running()
                if state and state.Running and state.Recording and not state.SuppressMacroRecord
                    and not router.ActiveThreads[thread] and typeof(self) == "Instance"
                then
                    local okMeta, name, cls = pcall(function()
                        return self.Name, self.ClassName
                    end)
                    if okMeta and WATCHED_REMOTES[name] then
                        if method == "InvokeServer" and cls == "RemoteFunction" then
                            router.ActiveThreads[thread] = true
                            local args = table.pack(...)
                            local goldBefore = safeGetCash()
                            local results
                            if router.RawInvoke then
                                results = table.pack(pcall(router.RawInvoke, self, ...))
                            else
                                results = table.pack(pcall(function(...)
                                    if setNC then
                                        setNC("InvokeServer")
                                    end
                                    return origNamecall(self, ...)
                                end, ...))
                            end
                            if results[1] and router.Record then
                                local cleanResults = table.pack(table.unpack(results, 2, results.n))
                                pcall(router.Record, self, "InvokeServer", args, cleanResults, goldBefore)
                            end
                            router.ActiveThreads[thread] = nil
                            if results[1] then
                                return table.unpack(results, 2, results.n)
                            end
                            error(results[2], 0)
                        elseif method == "FireServer" and cls == "RemoteEvent" then
                            router.ActiveThreads[thread] = true
                            local args = table.pack(...)
                            local goldBefore = safeGetCash()
                            local okCall, errCall
                            if router.RawFire then
                                okCall, errCall = pcall(router.RawFire, self, ...)
                            else
                                okCall, errCall = pcall(function(...)
                                    if setNC then
                                        setNC("FireServer")
                                    end
                                    return origNamecall(self, ...)
                                end, ...)
                            end
                            if okCall and router.Record then
                                pcall(router.Record, self, "FireServer", args, { n = 0 }, goldBefore)
                            end
                            router.ActiveThreads[thread] = nil
                            if not okCall then
                                error(errCall, 0)
                            end
                            return
                        end
                    end
                    if setNC then
                        setNC(method)
                    end
                end
                return origNamecall(self, ...)
            end))
        end)
        if okNC and type(oldNC) == "function" then
            origNamecall = oldNC
            router.OriginalNamecall = oldNC
            router.NamecallHooked = true
        end
    end

    GlobalEnv.__ShenanigansTDMacroRouter = router
    local status, ok = buildHookStatus(router)
    State.MacroHookStatus = status
    return ok
end

function ActionRecorder.start()
    if not MatchState.isMatchActive() then
        return false, "Start an active match before recording"
    end
    if State.Playing then
        return false, "Stop playback before recording"
    end
    if not ActionRecorder.installHook() then
        return false, State.MacroHookStatus
    end

    table.clear(State.MacroActions)
    State.RecordHandles = setmetatable({}, { __mode = "k" })
    State.NextMacroHandle = 0
    State.MacroStartedAt = os.clock()
    State.WaveStartedAt = os.clock()
    State.MacroMap = MatchState.getCurrentMap()
    State.Recording = true
    State.MacroStatus = "Recording on " .. (State.MacroMap ~= "" and State.MacroMap or "current map")
    return true
end

function ActionRecorder.stop()
    if not State.Recording then
        return false, "Not recording"
    end
    State.Recording = false
    local sanitized, dropped = MacroSerializer.sanitizeActionsForSave(State.MacroActions)
    if sanitized then
        State.MacroActions = sanitized
    end
    local name = SafeUtils.cleanName(CFG.MacroName ~= "" and CFG.MacroName or CFG.SelectedMacro)
    State.ActiveMacro = {
        Schema = 1,
        Game = "Shenanigans TD",
        Name = name,
        Map = State.MacroMap or "",
        Actions = State.MacroActions,
    }
    local suffix = (dropped and dropped > 0) and (" (" .. tostring(dropped) .. " invalid dropped)") or ""
    State.MacroStatus = "Stopped recording — " .. tostring(#State.MacroActions) .. " actions" .. suffix
    return true, #State.MacroActions
end

--// =========================================================================
--// 8. PLAYBACK ENGINE (TIME / MONEY / HYBRID)
--// =========================================================================

local PlaybackEngine = {
    MAX_RETRIES = 5,
    BASE_BACKOFF = 0.15,
    MAX_BACKOFF = 2.4,
    POLL_INTERVAL = 0.05,
}

local function decodePackedArgs(rawArgs, argCount)
    local count = math.clamp(math.floor(tonumber(argCount) or 0), 0, 16)
    local args = table.create(count)
    for i = 1, count do
        local entry = rawArgs and rawArgs[i]
        if not entry or entry.Type == "nil" then
            args[i] = nil
        elseif entry.Type == "string" or entry.Type == "number" or entry.Type == "boolean" then
            args[i] = entry.Value
        else
            return nil
        end
    end
    return args, count
end

function PlaybackEngine.isCancelled(playSerial, startMatchSerial)
    if not State.Running then
        return true, "Hub stopped"
    end
    if not State.Playing then
        return true, "Playback stopped"
    end
    if State.PlaySerial ~= playSerial then
        return true, "Superseded by newer playback"
    end
    if MatchState.getMatchSerial() ~= startMatchSerial then
        return true, "Match round changed"
    end
    if not MatchState.isMatchActive() then
        return true, "Match ended"
    end
    return false
end

function PlaybackEngine.waitCancelable(seconds, playSerial, startMatchSerial)
    local deadline = os.clock() + math.max(0, seconds)
    while os.clock() < deadline do
        local cancelled, reason = PlaybackEngine.isCancelled(playSerial, startMatchSerial)
        if cancelled then
            return false, reason
        end
        task.wait(math.min(PlaybackEngine.POLL_INTERVAL, math.max(0.01, deadline - os.clock())))
    end
    local cancelled, reason = PlaybackEngine.isCancelled(playSerial, startMatchSerial)
    return not cancelled, reason
end

function PlaybackEngine.resolveHandle(action)
    local handle = action.Handle
    if type(handle) ~= "string" or handle == "" then
        return nil
    end

    local target = State.PlaybackHandles[handle]
    if isTowerInstanceAlive(target) then
        return target
    end

    local posArr = action.Position
        or (type(action.Frame) == "table" and { action.Frame[1], action.Frame[2], action.Frame[3] })
        or nil
    if type(posArr) == "table"
        and SafeUtils.isFiniteNumber(posArr[1])
        and SafeUtils.isFiniteNumber(posArr[2])
        and SafeUtils.isFiniteNumber(posArr[3])
    then
        local refPos = Vector3.new(posArr[1], posArr[2], posArr[3])
        local towersFolder = SafeUtils.findChild(Workspace, "Towers")
        local lp = SafeUtils.getLocalPlayer()
        local lpName = lp and lp.Name or ""
        if towersFolder then
            local okList, children = pcall(towersFolder.GetChildren, towersFolder)
            if okList and type(children) == "table" then
                local bestTower, bestDist = nil, 2.5
                for _, tower in ipairs(children) do
                    if typeof(tower) == "Instance" and tower:IsA("Model") then
                        local ownerVal = SafeUtils.getValue(SafeUtils.findPath(tower, "Config", "Owner"))
                        if lpName == "" or ownerVal == lpName then
                            local okPos, towerPos = pcall(function()
                                return tower.PrimaryPart and tower.PrimaryPart.Position or tower:GetPivot().Position
                            end)
                            if okPos and typeof(towerPos) == "Vector3" then
                                local dist = (towerPos - refPos).Magnitude
                                if dist < bestDist then
                                    bestDist = dist
                                    bestTower = tower
                                end
                            end
                        end
                    end
                end
                if bestTower then
                    State.PlaybackHandles[handle] = bestTower
                    return bestTower
                end
            end
        end
    end

    State.PlaybackHandles[handle] = nil
    return nil
end

function PlaybackEngine.areThresholdsMet(action, mode, startedAt, waveStartedAt, currentWave, currentCash, now)
    now = now or os.clock()
    local isSpending = action.Kind == "Place" or action.Kind == "Upgrade"
    local reqCost = (SafeUtils.isFiniteNumber(action.Cost) and action.Cost > 0)
        and action.Cost
        or (tonumber(action.Gold) or 0)
    local reqWave = math.floor(tonumber(action.Wave) or 0)
    local reqTime = tonumber(action.Time) or 0
    local reqWaveTime = SafeUtils.isFiniteNumber(action.WaveTime) and action.WaveTime or nil

    if mode == "Time" then
        local remaining = (startedAt + reqTime) - now
        if remaining > 0 then
            return false, string.format("Time %.1fs", remaining)
        end
        return true, "Ready"
    elseif mode == "Money" then
        if isSpending then
            if currentCash < reqCost then
                return false, string.format("Cash %s/%s", SafeUtils.formatNumber(currentCash), SafeUtils.formatNumber(reqCost))
            end
            return true, "Ready"
        else
            if reqWave > 0 and currentWave < reqWave then
                return false, string.format("Wave %d/%d", currentWave, reqWave)
            end
            if reqWave > 0 and currentWave == reqWave and reqWaveTime ~= nil then
                local waveElapsed = now - waveStartedAt
                if waveElapsed < reqWaveTime then
                    return false, string.format("WaveTime %.1fs", reqWaveTime - waveElapsed)
                end
            end
            return true, "Ready"
        end
    else
        -- Hybrid (KeroHub-style): Wave + Wave-Time + Money with lag catch-up
        if reqWave > 0 and currentWave < reqWave then
            return false, string.format("Wave %d/%d", currentWave, reqWave)
        end

        if reqWave <= 0 or currentWave == reqWave then
            if reqWaveTime ~= nil then
                local waveElapsed = now - waveStartedAt
                if waveElapsed < reqWaveTime then
                    return false, string.format("WaveTime %.1fs", reqWaveTime - waveElapsed)
                end
            else
                local remaining = (startedAt + reqTime) - now
                if remaining > 0 then
                    return false, string.format("Time %.1fs", remaining)
                end
            end
        end
        -- When currentWave > reqWave, skip time wait to catch up immediately

        if isSpending and currentCash < reqCost then
            return false, string.format("Cash %s/%s", SafeUtils.formatNumber(currentCash), SafeUtils.formatNumber(reqCost))
        end

        return true, "Ready"
    end
end

function PlaybackEngine.findPlacementSurface(posVec)
    if typeof(posVec) ~= "Vector3" then
        return nil
    end

    local towerAreas = {}
    local mapFolder = SafeUtils.findChild(Workspace, "Map")
    local searchRoot = mapFolder or Workspace
    for _, desc in ipairs(searchRoot:GetDescendants()) do
        if desc.Name == "TowerArea" then
            table.insert(towerAreas, desc)
        end
    end

    if #towerAreas > 0 then
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Include
        rayParams.FilterDescendantsInstances = towerAreas
        local hit = Workspace:Raycast(posVec + Vector3.new(0, 5, 0), Vector3.new(0, -25, 0), rayParams)
        if hit and hit.Instance and hit.Normal.Y > 0.1 then
            return hit.Instance
        end

        -- Fallback: nearest BasePart inside any TowerArea
        local bestPart, bestDist = nil, math.huge
        for _, area in ipairs(towerAreas) do
            for _, part in ipairs(area:GetDescendants()) do
                if part:IsA("BasePart") then
                    local dist = (part.Position - posVec).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPart = part
                    end
                end
            end
        end
        if bestPart then
            return bestPart
        end
    end

    -- Generic downward raycast excluding units/towers/characters
    local exclude = {}
    for _, folderName in ipairs({ "Towers", "Mobs", "Units" }) do
        local f = SafeUtils.findChild(Workspace, folderName)
        if f then
            table.insert(exclude, f)
        end
    end
    local lp = SafeUtils.getLocalPlayer()
    if lp and lp.Character then
        table.insert(exclude, lp.Character)
    end
    local cam = Workspace.CurrentCamera
    if cam then
        table.insert(exclude, cam)
    end
    local fallbackParams = RaycastParams.new()
    fallbackParams.FilterType = Enum.RaycastFilterType.Exclude
    fallbackParams.FilterDescendantsInstances = exclude
    local hit = Workspace:Raycast(posVec + Vector3.new(0, 5, 0), Vector3.new(0, -25, 0), fallbackParams)
    if hit and hit.Instance and hit.Normal.Y > 0.1 then
        return hit.Instance
    end
    return nil
end

function PlaybackEngine.executeAction(action)
    State.SuppressMacroRecord = true
    local ok, result, fatalErr = pcall(function()
        if action.Kind == "Place" or action.Kind == "Upgrade" then
            local remote = MatchState.macroRemote("SpawnTower")
            if not remote then
                return nil, "SpawnTower remote unavailable"
            end
            if type(action.Frame) ~= "table" or #action.Frame ~= 12 then
                return nil, "Invalid CFrame components"
            end
            for i = 1, 12 do
                if not SafeUtils.isFiniteNumber(action.Frame[i]) then
                    return nil, "Non-finite CFrame component"
                end
            end
            local frame = CFrame.new(table.unpack(action.Frame, 1, 12))
            local spawned = nil
            if action.Kind == "Upgrade" then
                local target = PlaybackEngine.resolveHandle(action)
                if not target then
                    return nil, "Target handle missing for Upgrade"
                end
                local upgFrame = (target.PrimaryPart and target.PrimaryPart.CFrame) or frame
                spawned = remote:InvokeServer(action.Unit, upgFrame, target)
            else
                local surfacePart = PlaybackEngine.findPlacementSurface(frame.Position)
                spawned = remote:InvokeServer(action.Unit, frame, nil, surfacePart)
            end
            if typeof(spawned) == "Instance" and action.Handle then
                State.PlaybackHandles[action.Handle] = spawned
            end
            return spawned

        elseif action.Kind == "Sell" then
            local remote = MatchState.macroRemote("SellTower")
            if not remote then
                return nil, "SellTower remote unavailable"
            end
            local target = PlaybackEngine.resolveHandle(action)
            if not target then
                return nil, "Target handle missing for Sell"
            end
            local sold = remote:InvokeServer(target)
            if sold then
                State.PlaybackHandles[action.Handle] = nil
            end
            return sold

        elseif action.Kind == "Mode" then
            local remote = MatchState.macroRemote("ChangeTowerMode")
            if not remote then
                return nil, "ChangeTowerMode remote unavailable"
            end
            local target = PlaybackEngine.resolveHandle(action)
            if not target then
                return nil, "Target handle missing for Mode"
            end
            return remote:InvokeServer(target)

        elseif action.Kind == "Skip" then
            local remote = MatchState.macroRemote("SkipVoteEvent")
            if not remote then
                return nil, "SkipVoteEvent remote unavailable"
            end
            local args, count = decodePackedArgs(action.Args, action.ArgCount or 0)
            if not args then
                return nil, "Malformed Skip args"
            end
            remote:FireServer(table.unpack(args, 1, count))
            return true
        end

        return nil, "Unknown action Kind"
    end)
    State.SuppressMacroRecord = false

    if not ok then
        return false, nil, tostring(result)
    end
    return true, result, fatalErr
end

function PlaybackEngine.executeWithBackoff(action, playSerial, startMatchSerial)
    for attempt = 1, PlaybackEngine.MAX_RETRIES do
        local cancelled, cancelReason = PlaybackEngine.isCancelled(playSerial, startMatchSerial)
        if cancelled then
            return false, cancelReason
        end

        local ok, result, errMsg = PlaybackEngine.executeAction(action)
        local succeeded = ok and (action.Kind == "Skip" or (result ~= nil and result ~= false))
        if succeeded then
            return true
        end

        if attempt < PlaybackEngine.MAX_RETRIES then
            local backoff = math.min(PlaybackEngine.MAX_BACKOFF, PlaybackEngine.BASE_BACKOFF * (2 ^ (attempt - 1)))
            State.PlaybackWaitReason = string.format("Retry %d/%d (%s)", attempt + 1, PlaybackEngine.MAX_RETRIES, tostring(action.Kind))
            local stillActive, waitReason = PlaybackEngine.waitCancelable(backoff, playSerial, startMatchSerial)
            if not stillActive then
                return false, waitReason
            end
        else
            return false, tostring(errMsg or (ok and "Remote returned false/nil" or "Invocation failed"))
        end
    end
    return false, "Retries exhausted"
end

function PlaybackEngine.start()
    if not MatchState.isMatchActive() then
        return false, "Start an active match before playback"
    end
    if State.Recording then
        return false, "Stop recording before playback"
    end
    if not State.ActiveMacro or (CFG.SelectedMacro ~= "" and State.ActiveMacro.Name ~= CFG.SelectedMacro) then
        if CFG.SelectedMacro ~= "" then
            local loaded, _, errOrCount = MacroManager:Load(CFG.SelectedMacro)
            if not loaded then
                return false, tostring(errOrCount)
            end
        end
    end
    if not State.ActiveMacro then
        return false, "Load or record a macro first"
    end

    local valid, validErr = MacroSerializer.validateMacroData(State.ActiveMacro, false)
    if not valid then
        return false, "Invalid macro: " .. tostring(validErr)
    end

    local currentMap = MatchState.getCurrentMap()
    if not CFG.IgnoreMapCheck and State.ActiveMacro.Map ~= "" and currentMap ~= "" and State.ActiveMacro.Map ~= currentMap then
        return false, "Macro recorded on '" .. State.ActiveMacro.Map .. "' (current: '" .. currentMap .. "')"
    end

    MatchState.updateSerial()
    State.Playing = true
    State.PlaybackStartedAt = os.clock()
    State.PlaybackHandles = {}
    State.PlaySerial += 1

    local playSerial = State.PlaySerial
    local startMatchSerial = MatchState.getMatchSerial()
    local actions = State.ActiveMacro.Actions
    local macroName = tostring(State.ActiveMacro.Name or CFG.SelectedMacro or "Unsaved")

    State.PlaybackStep = 0
    State.PlaybackTotal = #actions
    State.PlaybackWaitReason = ""
    State.MacroStatus = string.format("Playing %s (0/%d)", macroName, #actions)

    task.spawn(function()
        local abortReason = nil

        for idx, action in ipairs(actions) do
            State.PlaybackStep = idx

            while true do
                local cancelled, reason = PlaybackEngine.isCancelled(playSerial, startMatchSerial)
                if cancelled then
                    abortReason = reason
                    break
                end

                local ready, waitReason = PlaybackEngine.areThresholdsMet(
                    action,
                    CFG.PlaybackMode,
                    State.PlaybackStartedAt,
                    State.WaveStartedAt,
                    MatchState.getWave(),
                    MatchState.getCash(),
                    os.clock()
                )
                if ready then
                    State.PlaybackWaitReason = ""
                    break
                end
                State.PlaybackWaitReason = waitReason
                State.MacroStatus = string.format(
                    "Playing %s (%d/%d) — %s",
                    macroName,
                    idx,
                    #actions,
                    waitReason
                )
                task.wait(PlaybackEngine.POLL_INTERVAL)
            end

            if abortReason then
                break
            end

            State.MacroStatus = string.format(
                "Playing %s (%d/%d) — %s",
                macroName,
                idx,
                #actions,
                tostring(action.Kind)
            )

            local execOk, execErr = PlaybackEngine.executeWithBackoff(action, playSerial, startMatchSerial)
            if not execOk then
                abortReason = string.format("%s (#%d): %s", tostring(action.Kind), idx, tostring(execErr))
                break
            end

            local stepOk, stepErr = PlaybackEngine.waitCancelable(PlaybackEngine.POLL_INTERVAL, playSerial, startMatchSerial)
            if not stepOk then
                abortReason = stepErr
                break
            end
        end

        State.SuppressMacroRecord = false
        if State.PlaySerial == playSerial then
            State.Playing = false
            State.PlaybackHandles = {}
            State.PlaybackWaitReason = ""
            if State.Running then
                if abortReason then
                    State.MacroStatus = "Stopped (" .. tostring(abortReason) .. ")"
                else
                    State.MacroStatus = "Finished (" .. tostring(#actions) .. "/" .. tostring(#actions) .. ")"
                end
            end
        end
    end)

    return true
end

function PlaybackEngine.stop()
    if not State.Playing then
        return false, "Not playing"
    end
    State.PlaySerial += 1
    State.Playing = false
    State.SuppressMacroRecord = false
    State.PlaybackHandles = {}
    State.PlaybackWaitReason = ""
    State.MacroStatus = "Playback stopped"
    State.AutoPlayedForSerial = MatchState.getMatchSerial()
    return true
end

--// =========================================================================
--// 9. CONFIG MANAGER
--// =========================================================================

local ConfigManager = {
    Folder = "ShenanigansTDConfigs",
    AutoloadFile = "_autoload.txt",
    TeleportStateFile = "_teleport_state.json",
    WidgetRefreshers = {},
}

local function sanitizeConfigName(name)
    local s = tostring(name or ""):gsub("[^%w%-%_%. ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return "default"
    end
    return s
end

function ConfigManager:GetConfigPath(name)
    return self.Folder .. "/" .. sanitizeConfigName(name) .. ".json"
end

function ConfigManager:GetAutoloadPath()
    return self.Folder .. "/" .. self.AutoloadFile
end

function ConfigManager:GetTeleportStatePath()
    return self.Folder .. "/" .. self.TeleportStateFile
end

function ConfigManager:ApplyData(data)
    if type(data) ~= "table" then
        return
    end
    for k, defaultVal in pairs(DEFAULT_CFG) do
        local loadedVal = data[k]
        if type(loadedVal) == type(defaultVal) then
            if k == "SummonAmount" then
                CFG[k] = math.max(1, math.floor(loadedVal))
            elseif k == "SummonDelay" then
                CFG[k] = math.clamp(loadedVal, 0, 10)
            elseif k == "VoteMapDelay" or k == "ReplayDelay" then
                CFG[k] = math.clamp(loadedVal, 0, 15)
            elseif k == "StopSkipWave" then
                CFG[k] = math.max(0, math.floor(loadedVal))
            elseif k == "PlaybackMode" then
                if table.find(PLAYBACK_MODES, loadedVal) then
                    CFG[k] = loadedVal
                end
            elseif k == "AutoMutatorMode" then
                if table.find(MUTATOR_MODES, loadedVal) then
                    CFG[k] = loadedVal
                end
            elseif k == "AutoExecUrl" then
                CFG[k] = tostring(loadedVal):gsub("^%s+", ""):gsub("%s+$", "")
            else
                CFG[k] = loadedVal
            end
        end
    end
end

function ConfigManager:RunWithApplyGuard(fn)
    State.ApplyingConfig = true
    local ok, err = pcall(fn)
    State.ApplyingConfig = false
    if not ok then
        warn("[ShenanigansTD] Config apply guard error: " .. tostring(err))
    end
end

function ConfigManager:RefreshWidgets()
    self:RunWithApplyGuard(function()
        for _, refresher in ipairs(self.WidgetRefreshers) do
            pcall(refresher)
        end
    end)
end

function ConfigManager:ListConfigs()
    if not SafeUtils.ensureFolder(self.Folder) then
        return {}
    end
    local out = {}
    for _, fullPath in ipairs(SafeUtils.listFiles(self.Folder)) do
        local normalized = tostring(fullPath):gsub("\\", "/")
        local fileName = normalized:match("([^/]+)$") or normalized
        local base = fileName:match("^(.+)%.json$")
        if base and base ~= "" and fileName ~= self.TeleportStateFile then
            table.insert(out, base)
        end
    end
    table.sort(out)
    return out
end

function ConfigManager:GetAutoload()
    local ok, content = SafeUtils.readTextFile(self:GetAutoloadPath())
    if not ok or not content then
        return nil
    end
    local clean = sanitizeConfigName(content)
    if clean == "" then
        return nil
    end
    return clean
end

function ConfigManager:SetAutoload(name)
    if not SafeUtils.ensureFolder(self.Folder) then
        return false, "Filesystem unavailable"
    end
    local clean = sanitizeConfigName(name)
    local ok = SafeUtils.writeTextFile(self:GetAutoloadPath(), clean)
    return ok, clean
end

function ConfigManager:ClearAutoload()
    SafeUtils.deleteFile(self:GetAutoloadPath())
    return true
end

function ConfigManager:Save(name)
    if not SafeUtils.ensureFolder(self.Folder) then
        return false, "Filesystem unavailable"
    end
    local clean = sanitizeConfigName(name)
    local okEnc, encoded = SafeUtils.jsonEncode(CFG)
    if not okEnc then
        return false, "JSON encode failed"
    end
    local okWrite = SafeUtils.writeTextFile(self:GetConfigPath(clean), encoded)
    if not okWrite then
        return false, "Write failed"
    end
    return true, clean
end

function ConfigManager:Load(name)
    local clean = sanitizeConfigName(name)
    local okRead, content = SafeUtils.readTextFile(self:GetConfigPath(clean))
    if not okRead or not content then
        return false, "Config not found: " .. clean
    end
    local okDec, data = SafeUtils.jsonDecode(content)
    if not okDec or type(data) ~= "table" then
        return false, "Invalid JSON in config"
    end

    self:ApplyData(data)
    self:RefreshWidgets()
    return true, clean
end

function ConfigManager:Delete(name)
    local clean = sanitizeConfigName(name)
    local ok = SafeUtils.deleteFile(self:GetConfigPath(clean))
    if self:GetAutoload() == clean then
        self:ClearAutoload()
    end
    return ok, clean
end

function ConfigManager:SaveTeleportState()
    if not SafeUtils.ensureFolder(self.Folder) then
        return false
    end
    local payload = {
        SavedAt = os.time(),
        CFG = CFG,
    }
    local okEnc, encoded = SafeUtils.jsonEncode(payload)
    if not okEnc then
        return false
    end
    return SafeUtils.writeTextFile(self:GetTeleportStatePath(), encoded)
end

function ConfigManager:LoadTeleportState()
    local okRead, content = SafeUtils.readTextFile(self:GetTeleportStatePath())
    if not okRead or not content then
        return false
    end
    local okDec, data = SafeUtils.jsonDecode(content)
    if not okDec or type(data) ~= "table" or type(data.CFG) ~= "table" then
        return false
    end
    if data.CFG.AutoExecOnTeleport ~= true then
        return false
    end
    local age = os.time() - (tonumber(data.SavedAt) or 0)
    if age > 1800 then
        return false
    end
    self:ApplyData(data.CFG)
    self:RefreshWidgets()
    return true
end

function ConfigManager:ClearTeleportState()
    return SafeUtils.deleteFile(self:GetTeleportStatePath())
end

--// =========================================================================
--// 9B. TELEPORT AUTO-EXEC MODULE
--// =========================================================================

local TeleportAutoExec = {}

function TeleportAutoExec.getQueueFn()
    local candidates = {
        type(queue_on_teleport) == "function" and queue_on_teleport or nil,
        type(queueonteleport) == "function" and queueonteleport or nil,
        type(queueteleport) == "function" and queueteleport or nil,
        type(GlobalEnv.queue_on_teleport) == "function" and GlobalEnv.queue_on_teleport or nil,
        type(GlobalEnv.queueonteleport) == "function" and GlobalEnv.queueonteleport or nil,
        type(syn) == "table" and type(syn.queue_on_teleport) == "function" and syn.queue_on_teleport or nil,
        type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" and fluxus.queue_on_teleport or nil,
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then
            return fn
        end
    end
    return nil
end

function TeleportAutoExec.getClearFn()
    local candidates = {
        type(clearqueueonteleport) == "function" and clearqueueonteleport or nil,
        type(clearteleportqueue) == "function" and clearteleportqueue or nil,
        type(clear_teleport_queue) == "function" and clear_teleport_queue or nil,
        type(GlobalEnv.clearqueueonteleport) == "function" and GlobalEnv.clearqueueonteleport or nil,
    }
    for _, fn in ipairs(candidates) do
        if type(fn) == "function" then
            return fn
        end
    end
    return nil
end

function TeleportAutoExec.isSupported()
    return type(TeleportAutoExec.getQueueFn()) == "function"
end

function TeleportAutoExec.findLocalScriptPath()
    if type(isfile) ~= "function" then
        return nil
    end
    for _, candidate in ipairs({ "ShenanigansTDConfigs/_autoexec_script.lua", "shenanigans_td.lua", "ShenTD.lua" }) do
        local ok, exists = pcall(isfile, candidate)
        if ok and exists == true then
            return candidate
        end
    end
    return nil
end

function TeleportAutoExec.getEffectiveUrl()
    local cfgUrl = tostring(CFG.AutoExecUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cfgUrl:match("^https?://") then
        return cfgUrl
    end
    local envUrl = type(GlobalEnv.ShenanigansTDLoaderUrl) == "string"
        and GlobalEnv.ShenanigansTDLoaderUrl:gsub("^%s+", ""):gsub("%s+$", "")
        or ""
    if envUrl:match("^https?://") then
        return envUrl
    end
    return ""
end

function TeleportAutoExec.buildLoaderSource()
    local url = TeleportAutoExec.getEffectiveUrl()
    local quotedUrl = string.format("%q", url)
    local lines = {
        "local url = " .. quotedUrl,
        "if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end",
        "local Players = game:GetService('Players')",
        "local t0 = os.clock()",
        "while not Players.LocalPlayer and (os.clock() - t0) < 20 do task.wait(0.1) end",
        "task.wait(0.75)",
        "local src = nil",
        "if url ~= '' then",
        "    local ok, res = pcall(function() return game:HttpGet(url) end)",
        "    if ok and type(res) == 'string' and #res > 100 then",
        "        src = res",
        "        if type(isfolder) == 'function' and type(makefolder) == 'function' and type(writefile) == 'function' then",
        "            pcall(function()",
        "                if not isfolder('ShenanigansTDConfigs') then makefolder('ShenanigansTDConfigs') end",
        "                writefile('ShenanigansTDConfigs/_autoexec_script.lua', res)",
        "            end)",
        "        end",
        "    end",
        "end",
        "if (not src or src == '') and type(isfile) == 'function' and type(readfile) == 'function' then",
        "    for _, p in ipairs({ 'ShenanigansTDConfigs/_autoexec_script.lua', 'shenanigans_td.lua', 'ShenTD.lua' }) do",
        "        local okE, exists = pcall(isfile, p)",
        "        if okE and exists then",
        "            local okR, data = pcall(readfile, p)",
        "            if okR and type(data) == 'string' and #data > 100 then",
        "                src = data",
        "                break",
        "            end",
        "        end",
        "    end",
        "end",
        "if type(src) == 'string' and #src > 100 then",
        "    if url ~= '' and type(getgenv) == 'function' then pcall(function() getgenv().ShenanigansTDLoaderUrl = url end) end",
        "    local fn, err = loadstring(src)",
        "    if type(fn) == 'function' then task.spawn(fn) else warn('[ShenanigansTD AutoExec] Compile error: ' .. tostring(err)) end",
        "else",
        "    warn('[ShenanigansTD AutoExec] No script source found (set Auto-Run Script URL or keep shenanigans_td.lua in workspace).')",
        "end",
    }
    return table.concat(lines, "\n")
end

function TeleportAutoExec.clear()
    local clearFn = TeleportAutoExec.getClearFn()
    if type(clearFn) == "function" then
        pcall(clearFn)
    end
    State.LastQueuedPayload = nil
    State.TeleportQueueStatus = "Off"
end

function TeleportAutoExec.sync(forceRequeue)
    if not CFG.AutoExecOnTeleport then
        TeleportAutoExec.clear()
        ConfigManager:ClearTeleportState()
        return true, "Off"
    end

    local queueFn = TeleportAutoExec.getQueueFn()
    if type(queueFn) ~= "function" then
        State.TeleportQueueStatus = "Unsupported by executor"
        return false, "Executor does not support queue_on_teleport"
    end

    ConfigManager:SaveTeleportState()

    local url = TeleportAutoExec.getEffectiveUrl()
    local localPath = TeleportAutoExec.findLocalScriptPath()
    if url == "" and not localPath then
        State.TeleportQueueStatus = "Needs URL or local file"
        return false, "No local script file found — enter your raw script URL in Auto-Run Script URL"
    end

    local payload = TeleportAutoExec.buildLoaderSource()
    if forceRequeue or State.LastQueuedPayload ~= payload then
        local clearFn = TeleportAutoExec.getClearFn()
        if type(clearFn) == "function" then
            pcall(clearFn)
        end
        local ok, err = pcall(queueFn, payload)
        if not ok then
            State.TeleportQueueStatus = "Queue failed"
            return false, tostring(err)
        end
        State.LastQueuedPayload = payload
    end

    State.TeleportQueueStatus = url ~= "" and "Armed (URL)" or ("Armed (" .. tostring(localPath) .. ")")
    return true, State.TeleportQueueStatus
end

--// =========================================================================
--// 10. WINDUI DASHBOARD & DISPLAY HELPERS
--// =========================================================================

local StatusParagraph = nil
local AmountInputWidget = nil
local MatchStatusParagraph = nil
local MacroStatusParagraph = nil

local function buildStatusText()
    local cash = LobbySummon.getCash(false)
    local prices, discountEnabled = LobbySummon.getPriceTiers()
    local targetAmount = CFG.AlwaysSummonMax and LobbySummon.getMaxAffordable(cash) or CFG.SummonAmount
    local targetCost = targetAmount >= 1 and LobbySummon.getSummonCost(targetAmount) or LobbySummon.getSummonCost(1)
    local maxAffordable = LobbySummon.getMaxAffordable(cash)
    local banner = LobbySummon.getBannerAndPityInfo()
    local cap = State.CachedCapacity

    local lines = {
        "Cash: " .. SafeUtils.formatNumber(cash) .. "$",
        string.format(
            "Selected Amount: x%s (%s$)%s",
            SafeUtils.formatNumber(math.max(0, targetAmount)),
            SafeUtils.formatNumber(targetCost),
            CFG.AlwaysSummonMax and " [Auto Max]" or ""
        ),
        string.format(
            "Max Affordable: x%s (%s$ each%s)",
            SafeUtils.formatNumber(maxAffordable),
            SafeUtils.formatNumber(prices.First),
            discountEnabled and ", Discount Active" or ""
        ),
        string.format(
            "Banner (%s): Mythic = %s | SpecialGrade = %s",
            banner.Timer,
            banner.Mythic,
            banner.SpecialGrade
        ),
        string.format(
            "Pity: Mythic %d/%d | SpecialGrade %d/%d",
            banner.PityMythic,
            banner.HardMythic,
            banner.PitySpecialGrade,
            banner.HardSpecialGrade
        ),
    }

    if type(cap) == "table" and cap.Max > 0 then
        table.insert(lines, string.format("Inventory Capacity: %d / %d", cap.Used, cap.Max))
    end

    table.insert(
        lines,
        string.format("Session: %s summoned (%d batches)", SafeUtils.formatNumber(State.TotalSummoned), State.TotalBatches)
    )
    table.insert(lines, "Status: " .. tostring(State.LastSummonStatus))
    table.insert(lines, "Last Pull: " .. tostring(State.LastPullSummary))

    return table.concat(lines, "\n")
end

local function buildMatchStatusText()
    if not MatchState.isMatchServer() then
        return "Not in a Match server (join a map to use Match & Macro features)."
    end

    local snap = MatchState.getSnapshot()
    local phase = snap.Ended and (snap.Outcome or "Ended")
        or (snap.Voting and "Voting" or (snap.Active and "In Progress" or "Waiting"))

    local lines = {
        string.format("Map: %s | Phase: %s", snap.Map ~= "" and snap.Map or "Not selected", phase),
        string.format("Wave: %d | Gold: %s$", snap.Wave, SafeUtils.formatNumber(snap.Cash)),
        string.format("Placed Towers: %d | Kills: %d", snap.PlacedTowers, snap.Kills),
        string.format(
            "Speed: %s | In-Game AutoSkip: %s",
            snap.DoubleSpeed and "2x" or "1x",
            snap.AutoSkip and "ON" or "OFF"
        ),
    }

    if snap.TimerSeconds > 0 then
        table.insert(lines, string.format("Wave Timer: %d:%02d", math.floor(snap.TimerSeconds / 60), snap.TimerSeconds % 60))
    end

    if snap.EndlessCash > 0 or snap.EndlessGems > 0 or snap.EndlessCrates > 0 then
        table.insert(
            lines,
            string.format(
                "Endless Rewards: %s$ | %s Gems | %s Crates",
                SafeUtils.formatNumber(snap.EndlessCash),
                SafeUtils.formatNumber(snap.EndlessGems),
                SafeUtils.formatNumber(snap.EndlessCrates)
            )
        )
    end

    return table.concat(lines, "\n")
end

local function buildMacroStatusText()
    local loadedName = "None"
    local loadedMap = "-"
    local actionCount = #State.MacroActions
    if type(State.ActiveMacro) == "table" then
        loadedName = State.ActiveMacro.Name ~= "" and State.ActiveMacro.Name or "Unsaved"
        loadedMap = State.ActiveMacro.Map ~= "" and State.ActiveMacro.Map or "Any"
        actionCount = type(State.ActiveMacro.Actions) == "table" and #State.ActiveMacro.Actions or actionCount
    elseif State.Recording then
        loadedName = "Recording..."
        loadedMap = State.MacroMap ~= "" and State.MacroMap or "-"
    end

    local lines = {
        "Status: " .. tostring(State.MacroStatus),
        string.format("Loaded Macro: %s (Map: %s | Actions: %d)", loadedName, loadedMap, actionCount),
        string.format("Playback Mode: %s | Hook: %s", tostring(CFG.PlaybackMode), tostring(State.MacroHookStatus)),
        string.format("Auto-Run New Match: %s", tostring(State.TeleportQueueStatus)),
    }
    return table.concat(lines, "\n")
end

local function updateStatusDisplay()
    if StatusParagraph and type(StatusParagraph.SetDesc) == "function" then
        pcall(StatusParagraph.SetDesc, StatusParagraph, buildStatusText())
    end
end

local function updateMatchDisplay()
    if MatchStatusParagraph and type(MatchStatusParagraph.SetDesc) == "function" then
        pcall(MatchStatusParagraph.SetDesc, MatchStatusParagraph, buildMatchStatusText())
    end
end

local function updateMacroDisplay()
    if MacroStatusParagraph and type(MacroStatusParagraph.SetDesc) == "function" then
        pcall(MacroStatusParagraph.SetDesc, MacroStatusParagraph, buildMacroStatusText())
    end
end

local function setAmountToMax(showNotify)
    local cash = LobbySummon.getCash(true)
    local maxCount = LobbySummon.getMaxAffordable(cash)
    local oneCost = LobbySummon.getSummonCost(1)

    if maxCount < 1 then
        updateStatusDisplay()
        if showNotify then
            notify(
                "Max Summon",
                string.format(
                    "Not enough Cash for 1 summon (Have %s$, need %s$)",
                    SafeUtils.formatNumber(cash),
                    SafeUtils.formatNumber(oneCost)
                ),
                3.5
            )
        end
        return false, 0, cash
    end

    CFG.SummonAmount = maxCount
    if AmountInputWidget and type(AmountInputWidget.Set) == "function" then
        State.UpdatingAmountInput = true
        pcall(AmountInputWidget.Set, AmountInputWidget, tostring(maxCount))
        State.UpdatingAmountInput = false
    end
    updateStatusDisplay()

    if showNotify then
        local totalCost = LobbySummon.getSummonCost(maxCount)
        notify(
            "Max Summon Set",
            string.format(
                "Set amount to %s (Cost: %s$ | Cash: %s$)",
                SafeUtils.formatNumber(maxCount),
                SafeUtils.formatNumber(totalCost),
                SafeUtils.formatNumber(cash)
            ),
            3
        )
    end
    return true, maxCount, cash
end

local function onSettingChanged()
    if CFG.AutoExecOnTeleport then
        ConfigManager:SaveTeleportState()
    end
end

local function destroy(isManualUnload)
    if not State.Running then
        return
    end
    State.Running = false
    CFG.AutoSummon = false
    if isManualUnload == true then
        CFG.AutoExecOnTeleport = false
        pcall(TeleportAutoExec.clear)
        pcall(ConfigManager.ClearTeleportState, ConfigManager)
    end
    pcall(PlaybackEngine.stop)
    if State.Recording then
        pcall(ActionRecorder.stop)
    end
    local router = GlobalEnv.__ShenanigansTDMacroRouter
    if router and router.State == State then
        router.State = nil
        router.ActiveThreads = setmetatable({}, { __mode = "k" })
    end
    SafeUtils.disconnectAll()
    if State.Window and type(State.Window.Destroy) == "function" then
        pcall(State.Window.Destroy, State.Window)
    end
    State.Window = nil
    if GlobalEnv[GLOBAL_KEY] and GlobalEnv[GLOBAL_KEY].State == State then
        GlobalEnv[GLOBAL_KEY] = nil
    end
end

local function buildUI()
    local okLoad, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
    end)
    if not okLoad or type(WindUI) ~= "table" then
        warn("[ShenanigansTD] Failed to load WindUI: " .. tostring(WindUI))
        return nil
    end
    State.WindUI = WindUI

    local Window = WindUI:CreateWindow({
        Title = "Shenanigans TD",
        Icon = "shield",
        Author = "by olliE",
        Folder = "ShenanigansTDUI",
        Size = UDim2.fromOffset(610, 500),
        Transparent = true,
        Theme = "Dark",
        ToggleKey = Enum.KeyCode.RightShift,
        OpenButton = {
            Title = "Shenanigans TD",
            Icon = "shield",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
        },
    })
    State.Window = Window

    if type(Window.EditOpenButton) == "function" then
        pcall(Window.EditOpenButton, Window, {
            Title = "Shenanigans TD",
            Icon = "shield",
            Enabled = true,
            Draggable = true,
            OnlyMobile = false,
        })
    end
    if type(Window.SetToggleKey) == "function" then
        pcall(Window.SetToggleKey, Window, Enum.KeyCode.RightShift)
    end

    local function registerToggle(tab, opts, getter, setter)
        local t = tab:Toggle({
            Title = opts.Title,
            Desc = opts.Desc,
            Value = getter(),
            Callback = function(v)
                if State.ApplyingConfig or not State.UIReady then
                    return
                end
                setter(v == true)
                onSettingChanged()
                updateStatusDisplay()
                updateMatchDisplay()
                updateMacroDisplay()
            end,
        })
        table.insert(ConfigManager.WidgetRefreshers, function()
            if t and type(t.Set) == "function" then
                t:Set(getter())
            end
        end)
        return t
    end

    local function registerSlider(tab, opts, getter, setter)
        local s = tab:Slider({
            Title = opts.Title,
            Desc = opts.Desc,
            Step = opts.Step,
            Value = { Min = opts.Min, Max = opts.Max, Default = getter() },
            Callback = function(v)
                if State.ApplyingConfig or not State.UIReady then
                    return
                end
                local num = tonumber(v)
                if num then
                    setter(num)
                    onSettingChanged()
                end
            end,
        })
        table.insert(ConfigManager.WidgetRefreshers, function()
            if s and type(s.Set) == "function" then
                s:Set(getter())
            end
        end)
        return s
    end

    --// ---------------------------------------------------------------------
    --// TAB 1: LOBBY
    --// ---------------------------------------------------------------------
    local TabLobby = Window:Tab({ Title = "Lobby", Icon = "house" })

    TabLobby:Section({ Title = "Summon Overview" })
    StatusParagraph = TabLobby:Paragraph({
        Title = "Live Summon Status",
        Desc = buildStatusText(),
    })

    TabLobby:Section({ Title = "Auto Summon" })

    registerToggle(TabLobby, {
        Title = "Auto Summon",
        Desc = "Automatically summons towers in the lobby using your target amount or Max.",
    }, function()
        return CFG.AutoSummon
    end, function(v)
        CFG.AutoSummon = v
        if v then
            State.NextSummonAt = 0
            State.LastSummonStatus = "Auto Summon active"
        else
            State.LastSummonStatus = "Idle"
        end
    end)

    AmountInputWidget = TabLobby:Input({
        Title = "Summon Amount",
        Desc = "Number of towers to summon per batch.",
        Placeholder = "Amount to summon (e.g. 10)",
        Value = tostring(CFG.SummonAmount),
        Callback = function(v)
            if State.ApplyingConfig or State.UpdatingAmountInput or not State.UIReady then
                return
            end
            local parsed = SafeUtils.parsePositiveInt(v)
            if parsed then
                CFG.SummonAmount = parsed
                if tostring(v) ~= tostring(parsed) and AmountInputWidget and type(AmountInputWidget.Set) == "function" then
                    State.UpdatingAmountInput = true
                    pcall(AmountInputWidget.Set, AmountInputWidget, tostring(parsed))
                    State.UpdatingAmountInput = false
                end
            end
            updateStatusDisplay()
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if AmountInputWidget and type(AmountInputWidget.Set) == "function" then
            State.UpdatingAmountInput = true
            pcall(AmountInputWidget.Set, AmountInputWidget, tostring(CFG.SummonAmount))
            State.UpdatingAmountInput = false
        end
    end)

    TabLobby:Button({
        Title = "Max (Based on Cash)",
        Desc = "Sets Summon Amount to the maximum towers your current Cash can afford.",
        Callback = function()
            setAmountToMax(true)
        end,
    })

    registerToggle(TabLobby, {
        Title = "Always Summon Max",
        Desc = "Dynamically recalculates Max from Cash before every summon.",
    }, function()
        return CFG.AlwaysSummonMax
    end, function(v)
        CFG.AlwaysSummonMax = v
    end)

    TabLobby:Button({
        Title = "Summon Now",
        Desc = "Triggers a single summon batch immediately.",
        Callback = function()
            task.spawn(function()
                local ok, msg = LobbySummon.executeSummon()
                updateStatusDisplay()
                if ok then
                    notify("Summon", msg, 3)
                else
                    notify("Summon", tostring(msg), 3.5)
                end
            end)
        end,
    })

    registerSlider(TabLobby, {
        Title = "Summon Delay (s)",
        Desc = "Wait time between summon batches (0 uses fastest safe server retry).",
        Min = 0,
        Max = 10,
        Step = 0.1,
    }, function()
        return CFG.SummonDelay
    end, function(v)
        CFG.SummonDelay = math.clamp(v, 0, 10)
    end)

    registerToggle(TabLobby, {
        Title = "Notify Rare Pulls",
        Desc = "Shows a notification on Legendary, Mythic, SpecialGrade, or Shiny pulls.",
    }, function()
        return CFG.NotifyRarePulls
    end, function(v)
        CFG.NotifyRarePulls = v
    end)

    --// ---------------------------------------------------------------------
    --// TAB 2: MATCH
    --// ---------------------------------------------------------------------
    local TabMatch = Window:Tab({ Title = "Match", Icon = "swords" })

    TabMatch:Section({ Title = "Match Overview" })
    MatchStatusParagraph = TabMatch:Paragraph({
        Title = "Live Match Status",
        Desc = buildMatchStatusText(),
    })

    TabMatch:Section({ Title = "Map Vote" })
    local initialMaps = MatchState.getMapList()
    if CFG.VoteMapName == "" or not table.find(initialMaps, CFG.VoteMapName) then
        CFG.VoteMapName = initialMaps[1] or ""
    end

    local mapDropdown = TabMatch:Dropdown({
        Title = "Map",
        Values = initialMaps,
        Value = CFG.VoteMapName ~= "" and CFG.VoteMapName or nil,
        AllowNone = true,
        Callback = function(v)
            if State.ApplyingConfig or not State.UIReady then
                return
            end
            if type(v) == "table" then
                v = v[1]
            end
            if type(v) == "string" and v ~= "" then
                CFG.VoteMapName = v
                State.VoteSent = false
                onSettingChanged()
            end
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if mapDropdown and type(mapDropdown.Refresh) == "function" then
            pcall(mapDropdown.Refresh, mapDropdown, MatchState.getMapList())
        end
    end)

    registerToggle(TabMatch, {
        Title = "Auto Vote Map",
        Desc = "Automatically votes for the selected map during voting phase.",
    }, function()
        return CFG.AutoVoteMap
    end, function(v)
        CFG.AutoVoteMap = v
        State.VoteSent = false
    end)

    registerSlider(TabMatch, {
        Title = "Vote Delay (s)",
        Desc = "Delay before sending map vote.",
        Min = 0,
        Max = 15,
        Step = 0.5,
    }, function()
        return CFG.VoteMapDelay
    end, function(v)
        CFG.VoteMapDelay = math.clamp(v, 0, 15)
    end)

    TabMatch:Button({
        Title = "Refresh Map List",
        Callback = function()
            local maps = MatchState.getMapList()
            if mapDropdown and type(mapDropdown.Refresh) == "function" then
                ConfigManager:RunWithApplyGuard(function()
                    mapDropdown:Refresh(maps)
                end)
            end
            notify("Map Vote", #maps > 0 and ("Found " .. #maps .. " maps") or "No maps found", 2.5)
        end,
    })

    TabMatch:Button({
        Title = "Vote Now",
        Callback = function()
            local ok, err = MatchState.voteForMap(CFG.VoteMapName)
            notify("Map Vote", ok and ("Voted: " .. CFG.VoteMapName) or tostring(err), 3)
        end,
    })

    TabMatch:Section({ Title = "Wave & Speed" })

    registerToggle(TabMatch, {
        Title = "Use In-Game AutoSkip",
        Desc = "Toggles the game's built-in AutoSkip setting button.",
    }, function()
        return CFG.AutoSkipGame
    end, function(v)
        CFG.AutoSkipGame = v
        local ok, err = MatchState.setInGameAutoSkip(v)
        if not ok then
            notify("Auto Skip", tostring(err), 3)
        end
    end)

    registerToggle(TabMatch, {
        Title = "Auto Skip Wave",
        Desc = "Automatically fires SkipVoteEvent when wave skip is available.",
    }, function()
        return CFG.AutoSkipScript
    end, function(v)
        CFG.AutoSkipScript = v
        State.SkipVoteSent = false
    end)

    local stopSkipInput = TabMatch:Input({
        Title = "Stop Auto Skip At Wave",
        Desc = "0 = never stop skipping.",
        Placeholder = "0 (no limit)",
        Value = tostring(CFG.StopSkipWave),
        Callback = function(v)
            if State.ApplyingConfig or State.UpdatingStopSkipInput or not State.UIReady then
                return
            end
            local parsed = SafeUtils.parseNonNegativeInt(v)
            if parsed ~= nil then
                CFG.StopSkipWave = parsed
                onSettingChanged()
            end
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if stopSkipInput and type(stopSkipInput.Set) == "function" then
            State.UpdatingStopSkipInput = true
            pcall(stopSkipInput.Set, stopSkipInput, tostring(CFG.StopSkipWave))
            State.UpdatingStopSkipInput = false
        end
    end)

    registerToggle(TabMatch, {
        Title = "Auto 2x Speed",
        Desc = "Automatically enables 2x speed when a match starts (requires 10 wins).",
    }, function()
        return CFG.AutoDoubleSpeed
    end, function(v)
        CFG.AutoDoubleSpeed = v
        State.SpeedSentForSerial = 0
        if v and MatchState.isMatchActive() then
            local ok, err = MatchState.setDoubleSpeed(true)
            if not ok then
                notify("Game Speed", tostring(err), 3)
            end
        end
    end)

    TabMatch:Button({
        Title = "Set 1x Speed",
        Callback = function()
            local ok, err = MatchState.setDoubleSpeed(false)
            notify("Game Speed", ok and "Set to 1x" or tostring(err), 2.5)
        end,
    })

    TabMatch:Button({
        Title = "Set 2x Speed",
        Callback = function()
            local ok, err = MatchState.setDoubleSpeed(true)
            notify("Game Speed", ok and "Set to 2x" or tostring(err), 2.5)
        end,
    })

    local mutatorDropdown = TabMatch:Dropdown({
        Title = "Auto Mutator Vote",
        Desc = "Automatically votes on Endless Curse/Mutator prompts.",
        Values = MUTATOR_MODES,
        Value = CFG.AutoMutatorMode,
        Callback = function(v)
            if State.ApplyingConfig or not State.UIReady then
                return
            end
            if type(v) == "table" then
                v = v[1]
            end
            if table.find(MUTATOR_MODES, v) then
                CFG.AutoMutatorMode = v
                State.LastMutatorOptions = ""
                onSettingChanged()
            end
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if mutatorDropdown and type(mutatorDropdown.Select) == "function" then
            pcall(mutatorDropdown.Select, mutatorDropdown, CFG.AutoMutatorMode)
        end
    end)

    TabMatch:Section({ Title = "End of Match" })

    registerToggle(TabMatch, {
        Title = "Auto Play Again",
        Desc = "Automatically votes Play Again when the match ends.",
    }, function()
        return CFG.AutoReplay
    end, function(v)
        CFG.AutoReplay = v
        State.ReplaySent = false
    end)

    registerSlider(TabMatch, {
        Title = "Play Again Delay (s)",
        Desc = "Delay before triggering Play Again.",
        Min = 0,
        Max = 15,
        Step = 0.5,
    }, function()
        return CFG.ReplayDelay
    end, function(v)
        CFG.ReplayDelay = math.clamp(v, 0, 15)
    end)

    TabMatch:Button({
        Title = "Play Again Now",
        Callback = function()
            local ok, err = MatchState.replayNow()
            if ok then
                State.ReplaySent = true
            end
            notify("Play Again", ok and "Replay request sent" or tostring(err), 3)
        end,
    })

    TabMatch:Button({
        Title = "Exit to Lobby",
        Callback = function()
            local ok, err = MatchState.exitToLobby()
            notify("Match", ok and "Returning to lobby..." or tostring(err), 3)
        end,
    })

    --// ---------------------------------------------------------------------
    --// TAB 3: MACRO
    --// ---------------------------------------------------------------------
    local TabMacro = Window:Tab({ Title = "Macro", Icon = "play" })

    TabMacro:Section({ Title = "Macro Status" })
    MacroStatusParagraph = TabMacro:Paragraph({
        Title = "Live Macro Status",
        Desc = buildMacroStatusText(),
    })

    TabMacro:Section({ Title = "Macros" })

    local macroNameInputWidget = TabMacro:Input({
        Title = "Macro Name",
        Placeholder = "Enter macro name",
        Value = CFG.MacroName,
        Callback = function(v)
            if State.ApplyingConfig or State.UpdatingMacroNameInput or not State.UIReady then
                return
            end
            CFG.MacroName = SafeUtils.cleanName(v)
            onSettingChanged()
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if macroNameInputWidget and type(macroNameInputWidget.Set) == "function" then
            State.UpdatingMacroNameInput = true
            pcall(macroNameInputWidget.Set, macroNameInputWidget, tostring(CFG.MacroName))
            State.UpdatingMacroNameInput = false
        end
    end)

    local initialMacros = MacroManager:List()
    local macroDropdown = TabMacro:Dropdown({
        Title = "Saved Macros",
        Values = #initialMacros > 0 and initialMacros or { "No saved macros" },
        Value = CFG.SelectedMacro ~= "" and CFG.SelectedMacro or nil,
        AllowNone = true,
        Callback = function(v)
            if State.ApplyingConfig or not State.UIReady then
                return
            end
            if type(v) == "table" then
                v = v[1]
            end
            if type(v) == "string" and v ~= "No saved macros" and v ~= "" then
                CFG.SelectedMacro = v
                CFG.MacroName = v
                if macroNameInputWidget and type(macroNameInputWidget.Set) == "function" then
                    State.UpdatingMacroNameInput = true
                    pcall(macroNameInputWidget.Set, macroNameInputWidget, v)
                    State.UpdatingMacroNameInput = false
                end
            else
                CFG.SelectedMacro = ""
            end
            State.AutoPlayFailedForSerial = 0
            onSettingChanged()
            updateMacroDisplay()
        end,
    })

    local function refreshMacroUI()
        local list = MacroManager:List()
        if macroDropdown and type(macroDropdown.Refresh) == "function" then
            ConfigManager:RunWithApplyGuard(function()
                macroDropdown:Refresh(#list > 0 and list or { "No saved macros" })
            end)
        end
        updateMacroDisplay()
    end
    table.insert(ConfigManager.WidgetRefreshers, refreshMacroUI)

    TabMacro:Button({
        Title = "Save Macro",
        Callback = function()
            if State.Recording or State.Playing then
                notify("Macro", "Stop recording or playback before saving", 3)
                return
            end
            local name = CFG.MacroName ~= "" and CFG.MacroName or CFG.SelectedMacro
            local ok, msg, count = MacroManager:Save(name, State.MacroActions, State.MacroMap)
            if ok then
                CFG.SelectedMacro = msg
                CFG.MacroName = msg
                State.MacroStatus = string.format("Saved %s (%d actions)", msg, count or 0)
                onSettingChanged()
            end
            refreshMacroUI()
            notify("Macro", ok and ("Saved " .. tostring(msg) .. " (" .. tostring(count) .. " actions)") or tostring(msg), 3)
        end,
    })

    TabMacro:Button({
        Title = "Load Selected Macro",
        Callback = function()
            if State.Recording or State.Playing then
                notify("Macro", "Stop recording or playback before loading", 3)
                return
            end
            local target = CFG.SelectedMacro ~= "" and CFG.SelectedMacro or CFG.MacroName
            local ok, msg, count = MacroManager:Load(target)
            if ok then
                CFG.SelectedMacro = msg
                CFG.MacroName = msg
                if macroNameInputWidget and type(macroNameInputWidget.Set) == "function" then
                    State.UpdatingMacroNameInput = true
                    pcall(macroNameInputWidget.Set, macroNameInputWidget, msg)
                    State.UpdatingMacroNameInput = false
                end
                State.MacroStatus = string.format("Loaded %s (%d actions)", msg, count or 0)
                State.AutoPlayFailedForSerial = 0
                onSettingChanged()
            end
            updateMacroDisplay()
            notify("Macro", ok and ("Loaded " .. tostring(msg) .. " (" .. tostring(count) .. " actions)") or tostring(msg), 3)
        end,
    })

    TabMacro:Button({
        Title = "Delete Selected Macro",
        Callback = function()
            local target = CFG.SelectedMacro ~= "" and CFG.SelectedMacro or CFG.MacroName
            local ok, msg = MacroManager:Delete(target)
            if ok and CFG.SelectedMacro == msg then
                CFG.SelectedMacro = ""
            end
            refreshMacroUI()
            notify("Macro", ok and ("Deleted " .. tostring(msg)) or "Delete failed", 2.5)
        end,
    })

    TabMacro:Button({
        Title = "Refresh Macro List",
        Callback = function()
            refreshMacroUI()
            notify("Macro", "Macro list refreshed", 2)
        end,
    })

    TabMacro:Section({ Title = "Recorder & Playback" })

    local modeDropdown = TabMacro:Dropdown({
        Title = "Playback Mode",
        Desc = "Hybrid syncs Wave + Time + Money with lag catch-up.",
        Values = PLAYBACK_MODES,
        Value = CFG.PlaybackMode,
        Callback = function(v)
            if State.ApplyingConfig or not State.UIReady then
                return
            end
            if type(v) == "table" then
                v = v[1]
            end
            if table.find(PLAYBACK_MODES, v) then
                CFG.PlaybackMode = v
                onSettingChanged()
                updateMacroDisplay()
            end
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if modeDropdown and type(modeDropdown.Select) == "function" then
            pcall(modeDropdown.Select, modeDropdown, CFG.PlaybackMode)
        end
    end)

    TabMacro:Button({
        Title = "Start Recording",
        Callback = function()
            local ok, err = ActionRecorder.start()
            updateMacroDisplay()
            notify("Macro", ok and "Recording started" or tostring(err), 3)
        end,
    })

    TabMacro:Button({
        Title = "Stop Recording",
        Callback = function()
            local ok, res = ActionRecorder.stop()
            updateMacroDisplay()
            notify("Macro", ok and ("Recorded " .. tostring(res) .. " actions") or tostring(res), 3)
        end,
    })

    TabMacro:Button({
        Title = "Play Macro",
        Callback = function()
            local ok, err = PlaybackEngine.start()
            updateMacroDisplay()
            if not ok then
                notify("Macro", tostring(err), 3.5)
            end
        end,
    })

    TabMacro:Button({
        Title = "Stop Playback",
        Callback = function()
            local ok, err = PlaybackEngine.stop()
            updateMacroDisplay()
            notify("Macro", ok and "Playback stopped" or tostring(err), 2.5)
        end,
    })

    registerToggle(TabMacro, {
        Title = "Auto Playback on Match Start",
        Desc = "Automatically plays the selected/loaded macro when a round begins.",
    }, function()
        return CFG.AutoPlayback
    end, function(v)
        CFG.AutoPlayback = v
        State.AutoPlayFailedForSerial = 0
    end)

    registerToggle(TabMacro, {
        Title = "Ignore Map Check",
        Desc = "Allows playing a macro even if the current map differs from the recorded map.",
    }, function()
        return CFG.IgnoreMapCheck
    end, function(v)
        CFG.IgnoreMapCheck = v
        State.AutoPlayFailedForSerial = 0
    end)

    registerToggle(TabMacro, {
        Title = "Auto-Run in New Match",
        Desc = "Automatically reloads the hub & macro session when teleporting to a match.",
    }, function()
        return CFG.AutoExecOnTeleport
    end, function(v)
        CFG.AutoExecOnTeleport = v
        local okSync, msgSync = TeleportAutoExec.sync(true)
        updateMacroDisplay()
        notify("Auto-Run", okSync and ("Auto-Run: " .. tostring(msgSync)) or tostring(msgSync), 3.5)
    end)

    local autoExecUrlInput = TabMacro:Input({
        Title = "Auto-Run Script URL (Optional)",
        Desc = "Raw script URL for executors without a local workspace file.",
        Placeholder = "https://raw.githubusercontent.com/...",
        Value = CFG.AutoExecUrl,
        Callback = function(v)
            if State.ApplyingConfig or State.UpdatingAutoExecUrlInput or not State.UIReady then
                return
            end
            CFG.AutoExecUrl = tostring(v or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if CFG.AutoExecOnTeleport then
                TeleportAutoExec.sync(true)
            else
                onSettingChanged()
            end
            updateMacroDisplay()
        end,
    })
    table.insert(ConfigManager.WidgetRefreshers, function()
        if autoExecUrlInput and type(autoExecUrlInput.Set) == "function" then
            State.UpdatingAutoExecUrlInput = true
            pcall(autoExecUrlInput.Set, autoExecUrlInput, tostring(CFG.AutoExecUrl))
            State.UpdatingAutoExecUrlInput = false
        end
    end)

    --// ---------------------------------------------------------------------
    --// TAB 4: CONFIGS
    --// ---------------------------------------------------------------------
    local TabCfg = Window:Tab({ Title = "Configs", Icon = "save" })
    local configNameInput = "default"
    local selectedConfig = ConfigManager:GetAutoload() or "default"

    local autoloadPara = TabCfg:Paragraph({
        Title = "Autoload Status",
        Desc = "Autoload: " .. (ConfigManager:GetAutoload() or "None"),
    })

    TabCfg:Input({
        Title = "Config Name",
        Placeholder = "default",
        Value = "default",
        Callback = function(v)
            if type(v) == "string" and v ~= "" then
                configNameInput = v
            end
        end,
    })

    local cfgDropdown = TabCfg:Dropdown({
        Title = "Saved Configs",
        Values = ConfigManager:ListConfigs(),
        Value = selectedConfig,
        AllowNone = true,
        Callback = function(v)
            if type(v) == "string" and v ~= "" then
                selectedConfig = v
            end
        end,
    })

    local function refreshConfigUI()
        local list = ConfigManager:ListConfigs()
        if cfgDropdown and type(cfgDropdown.Refresh) == "function" then
            ConfigManager:RunWithApplyGuard(function()
                cfgDropdown:Refresh(list)
            end)
        end
        if autoloadPara and type(autoloadPara.SetDesc) == "function" then
            autoloadPara:SetDesc("Autoload: " .. (ConfigManager:GetAutoload() or "None"))
        end
    end

    TabCfg:Button({
        Title = "Save Config",
        Callback = function()
            local ok, msg = ConfigManager:Save(configNameInput)
            refreshConfigUI()
            notify("Configs", ok and ("Saved " .. msg) or tostring(msg), 2.5)
        end,
    })

    TabCfg:Button({
        Title = "Load Selected Config",
        Callback = function()
            local ok, msg = ConfigManager:Load(selectedConfig)
            if ok then
                TeleportAutoExec.sync(false)
                onSettingChanged()
            end
            refreshConfigUI()
            updateStatusDisplay()
            updateMatchDisplay()
            updateMacroDisplay()
            notify("Configs", ok and ("Loaded " .. msg) or tostring(msg), 2.5)
        end,
    })

    TabCfg:Button({
        Title = "Delete Selected Config",
        Callback = function()
            local ok = ConfigManager:Delete(selectedConfig)
            refreshConfigUI()
            notify("Configs", ok and ("Deleted " .. selectedConfig) or "Delete failed", 2.5)
        end,
    })

    TabCfg:Button({
        Title = "Set Selected as Autoload",
        Callback = function()
            local ok, msg = ConfigManager:SetAutoload(selectedConfig)
            refreshConfigUI()
            notify("Autoload", ok and ("Autoload set to " .. tostring(msg)) or "Failed", 2.5)
        end,
    })

    TabCfg:Button({
        Title = "Clear Autoload",
        Callback = function()
            ConfigManager:ClearAutoload()
            refreshConfigUI()
            notify("Autoload", "Autoload cleared", 2.5)
        end,
    })

    TabCfg:Section({ Title = "Session" })
    TabCfg:Button({
        Title = "Unload Script",
        Desc = "Stops all loops, disconnects signals, and closes the UI.",
        Callback = function()
            destroy(true)
        end,
    })

    return Window
end

--// =========================================================================
--// 11. REACTIVE LISTENERS, LOOPS & STARTUP
--// =========================================================================

local function hookCashSignals()
    local lp = SafeUtils.getLocalPlayer()
    if not lp then
        return
    end

    local function attachToLeaderstats(ls)
        if typeof(ls) ~= "Instance" then
            return
        end
        local cashInst = SafeUtils.findChild(ls, "Cash")
        if cashInst and cashInst:IsA("ValueBase") then
            SafeUtils.trackConnection(cashInst.Changed:Connect(function()
                if State.Running then
                    updateStatusDisplay()
                end
            end))
        end
        SafeUtils.trackConnection(ls.ChildAdded:Connect(function(child)
            if child.Name == "Cash" and child:IsA("ValueBase") then
                SafeUtils.trackConnection(child.Changed:Connect(function()
                    if State.Running then
                        updateStatusDisplay()
                    end
                end))
                updateStatusDisplay()
            end
        end))
    end

    local existingLS = SafeUtils.findChild(lp, "leaderstats")
    if existingLS then
        attachToLeaderstats(existingLS)
    end
    SafeUtils.trackConnection(lp.ChildAdded:Connect(function(child)
        if child.Name == "leaderstats" then
            attachToLeaderstats(child)
        end
    end))
end

local function startLoops()
    -- Auto Summon loop (Lobby)
    task.spawn(function()
        local lastSyncWhenWaiting = 0
        while State.Running do
            if CFG.AutoSummon then
                local now = os.clock()
                if now >= State.NextSummonAt and not State.IsSummoning then
                    if not LobbySummon.isLobbyAvailable() then
                        State.LastSummonStatus = "Waiting for Lobby Summon remote"
                        State.NextSummonAt = now + 1.5
                    else
                        local fastCash = LobbySummon.getCash(false)
                        local target = CFG.AlwaysSummonMax and LobbySummon.getMaxAffordable(fastCash) or CFG.SummonAmount
                        local cost = target >= 1 and LobbySummon.getSummonCost(target) or LobbySummon.getSummonCost(1)

                        if target < 1 or fastCash < cost then
                            if (now - lastSyncWhenWaiting) >= 3.0 then
                                lastSyncWhenWaiting = now
                                LobbySummon.refreshServerCash(true)
                                fastCash = LobbySummon.getCash(false)
                                target = CFG.AlwaysSummonMax and LobbySummon.getMaxAffordable(fastCash) or CFG.SummonAmount
                                cost = target >= 1 and LobbySummon.getSummonCost(target) or LobbySummon.getSummonCost(1)
                            end
                        end

                        if target >= 1 and fastCash >= cost then
                            local ok, _, retryDelay = LobbySummon.executeSummon()
                            local delaySec = tonumber(retryDelay)
                            if not SafeUtils.isFiniteNumber(delaySec) then
                                delaySec = ok and math.max(0.05, CFG.SummonDelay) or 1.0
                            end
                            State.NextSummonAt = os.clock() + math.max(0.05, delaySec)
                            updateStatusDisplay()
                        else
                            State.LastSummonStatus = string.format(
                                "Waiting for Cash (%s$ / %s$)",
                                SafeUtils.formatNumber(fastCash),
                                SafeUtils.formatNumber(cost)
                            )
                            State.NextSummonAt = os.clock() + 0.5
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)

    -- Match automation loop
    task.spawn(function()
        while State.Running do
            if MatchState.isMatchServer() then
                local okLoop, loopErr = pcall(function()
                    local serial, transition = MatchState.updateSerial()

                    if not transition.active then
                        if State.Playing then
                            PlaybackEngine.stop()
                            State.MacroStatus = "Playback stopped (match ended)"
                        end
                        if State.Recording then
                            ActionRecorder.stop()
                        end
                    end

                    -- Auto Skip Wave
                    if not MatchState.isSkipAvailable() then
                        State.SkipVoteSent = false
                    elseif CFG.AutoSkipScript and not MatchState.getInGameAutoSkip() and not State.SkipVoteSent then
                        local stopAt = math.floor(tonumber(CFG.StopSkipWave) or 0)
                        if stopAt == 0 or transition.wave < stopAt then
                            local skipRemote = MatchState.matchEvent("SkipVoteEvent")
                            if skipRemote and skipRemote:IsA("RemoteEvent") then
                                State.SuppressMacroRecord = true
                                local okSkip = pcall(skipRemote.FireServer, skipRemote)
                                State.SuppressMacroRecord = false
                                if okSkip then
                                    State.SkipVoteSent = true
                                end
                            end
                        end
                    end

                    -- Auto 2x Speed
                    if CFG.AutoDoubleSpeed and transition.active and State.SpeedSentForSerial ~= serial then
                        if not MatchState.getDoubleSpeed() then
                            local okSpeed = MatchState.setDoubleSpeed(true)
                            if okSpeed then
                                State.SpeedSentForSerial = serial
                            end
                        else
                            State.SpeedSentForSerial = serial
                        end
                    end

                    -- Auto Mutator Vote
                    local infoFolder = MatchState.getInfoFolder()
                    local mutatorOpts = infoFolder and SafeUtils.getAttribute(infoFolder, "MutatorOptions") or nil
                    if type(mutatorOpts) == "string" and mutatorOpts ~= "" then
                        if CFG.AutoMutatorMode ~= "Off" and mutatorOpts ~= State.LastMutatorOptions then
                            local choice = MatchState.pickMutatorOption(mutatorOpts, CFG.AutoMutatorMode)
                            if choice and MatchState.voteMutator(choice) then
                                State.LastMutatorOptions = mutatorOpts
                            end
                        end
                    else
                        State.LastMutatorOptions = ""
                    end

                    -- Auto Play Again
                    if MatchState.isMatchEnded() then
                        if State.ReplayReadyAt == 0 then
                            State.ReplayReadyAt = os.clock() + math.max(0, tonumber(CFG.ReplayDelay) or 0)
                        end
                        if CFG.AutoReplay and not State.ReplaySent and os.clock() >= State.ReplayReadyAt then
                            local okReplay = MatchState.replayNow()
                            if okReplay then
                                State.ReplaySent = true
                            end
                        end
                    else
                        State.ReplaySent = false
                        State.ReplayReadyAt = 0
                    end

                    -- Auto Vote Map
                    if not MatchState.isVoting() then
                        State.VoteSent = false
                    elseif CFG.AutoVoteMap and CFG.VoteMapName ~= "" and not State.VoteSent then
                        local now = os.clock()
                        if State.NextVoteAt == 0 then
                            State.NextVoteAt = now + math.max(0, tonumber(CFG.VoteMapDelay) or 0)
                        elseif now >= State.NextVoteAt then
                            local okVote = MatchState.voteForMap(CFG.VoteMapName)
                            if okVote then
                                State.VoteSent = true
                                State.NextVoteAt = 0
                            else
                                State.NextVoteAt = now + 1.0
                            end
                        end
                    end

                    -- Auto Playback on Match Start
                    if not transition.active then
                        State.AutoPlayEligibleAt = 0
                    elseif CFG.AutoPlayback and not State.Playing and not State.Recording then
                        if (type(State.ActiveMacro) == "table" or CFG.SelectedMacro ~= "")
                            and State.AutoPlayedForSerial ~= serial
                            and State.AutoPlayFailedForSerial ~= serial
                        then
                            if CFG.IgnoreMapCheck or MatchState.getCurrentMap() ~= "" then
                                if State.AutoPlayEligibleAt == 0 then
                                    State.AutoPlayEligibleAt = os.clock() + 0.75
                                elseif os.clock() >= State.AutoPlayEligibleAt then
                                    local okPlay, errPlay = PlaybackEngine.start()
                                    if okPlay then
                                        State.AutoPlayedForSerial = serial
                                        State.AutoPlayEligibleAt = 0
                                    else
                                        State.AutoPlayFailedForSerial = serial
                                        State.MacroStatus = "Auto playback: " .. tostring(errPlay)
                                    end
                                    updateMacroDisplay()
                                end
                            end
                        end
                    end
                end)
                if not okLoop then
                    SafeUtils.logStatus("match_loop_err", "Match loop error: " .. tostring(loopErr), true)
                end
            end
            task.wait(0.2)
        end
    end)

    -- Status refresh loop
    task.spawn(function()
        while State.Running do
            if LobbySummon.isLobbyAvailable() then
                LobbySummon.refreshCapacity(false)
            end
            updateStatusDisplay()
            updateMatchDisplay()
            updateMacroDisplay()
            task.wait(0.5)
        end
    end)
end

-- Initial server sync & UI launch
task.spawn(function()
    if LobbySummon.isLobbyAvailable() then
        LobbySummon.refreshServerCash(true)
        LobbySummon.refreshCapacity(true)
    end
end)

State.LastMatchRunning = MatchState.isMatchRunning()
State.LastMatchEnded = MatchState.isMatchEnded()
State.LastWave = MatchState.getWave()

if type(GlobalEnv.ShenanigansTDLoaderUrl) == "string"
    and GlobalEnv.ShenanigansTDLoaderUrl:match("^https?://")
    and CFG.AutoExecUrl == ""
then
    CFG.AutoExecUrl = GlobalEnv.ShenanigansTDLoaderUrl
end

local Window = buildUI()
if Window then
    State.UIReady = true
    local autoloadName = ConfigManager:GetAutoload()
    if autoloadName then
        local okLoad, msg = ConfigManager:Load(autoloadName)
        if okLoad then
            notify("Autoload", "Loaded config: " .. tostring(msg), 2.5)
        end
    end
    local restoredSession = ConfigManager:LoadTeleportState()
    if restoredSession then
        notify("Auto-Run", "Restored Match & Macro session", 2.5)
    end
    if CFG.SelectedMacro ~= "" and not State.ActiveMacro then
        pcall(MacroManager.Load, MacroManager, CFG.SelectedMacro)
    end
    if CFG.AutoExecOnTeleport then
        TeleportAutoExec.sync(true)
    end
    updateStatusDisplay()
    updateMatchDisplay()
    updateMacroDisplay()
end

do
    local lp = SafeUtils.getLocalPlayer()
    if lp then
        SafeUtils.trackConnection(lp.OnTeleport:Connect(function(teleportState)
            if teleportState == Enum.TeleportState.Started or teleportState == Enum.TeleportState.InProgress then
                if CFG.AutoExecOnTeleport then
                    ConfigManager:SaveTeleportState()
                    TeleportAutoExec.sync(false)
                end
            end
        end))
    end
end

hookCashSignals()
startLoops()

GlobalEnv[GLOBAL_KEY] = {
    Version = VERSION,
    CFG = CFG,
    State = State,
    LobbySummon = LobbySummon,
    MatchState = MatchState,
    MacroSerializer = MacroSerializer,
    MacroManager = MacroManager,
    ActionRecorder = ActionRecorder,
    PlaybackEngine = PlaybackEngine,
    ConfigManager = ConfigManager,
    TeleportAutoExec = TeleportAutoExec,
    setAmountToMax = setAmountToMax,
    updateStatusDisplay = updateStatusDisplay,
    updateMatchDisplay = updateMatchDisplay,
    updateMacroDisplay = updateMacroDisplay,
    destroy = destroy,
}
