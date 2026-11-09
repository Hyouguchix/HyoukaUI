-- HyoukaUI: модуль Frames (рамки и колонка способностей), каркас. Plan 3.1, 2.4, 4.
--
-- Один модуль "frames" из нескольких файлов. Файл отдает таблицу H.Frames (F): реестр частей, помощники
-- регистрации кусков Layout, единая рассылка событий и режимы Выкл / Рядом / Вместо.
--
--   F.Part(name, def)     часть модуля. def: Build() один раз (кадры), Enable(mode), Disable(), Refresh(),
--                         Setting(key), Mode(mode). Co-op (Party, Revive, этап 6) добавляется ровно так:
--                         F.Part("party", {...}) в новом файле, без правок остальных.
--   F.On(event, fn)       подписка части: fn(event, a1..a4); работает только пока модуль включен.
--   F.Piece(id, frame, def) / F.Unpiece(id) / F.Repiece(id)   кусок Layout + Vis.Register с учетом режима
--   F.Show(id, want)      показать или спрятать кусок (на карточках выбора и при скрытии пользователем не показывает)
--   F.RefreshAll()        все части пересчитывают себя
--   F.mode                действующий режим: "side" или "replace" (запрошенный "replace" падает в "side", пока
--                         кадры рамок SurvivorUI на экране)
--   F.Selftest()          строки для selftest: режим, число кусков, показы шторки короче порога (должно быть 0)
-- События для других частей: FRAMES_MODE(mode) после смены действующего режима.
-- Режимы (plan 4): Выкл - ничего не создается и не показывается. Рядом - куски на ретейл-местах, корни колонки
-- и рамок сдвинуты вниз на SIDE_SHIFT ретейл-px (для сравнения со стоковыми и SurvivorUI), без Claim и Park.
-- Вместо - Claim "levels", Park стоковых рамок и панели, Cover части "build" (см. StockBar.lua).

local H = HyoukaUI
local L = H.Layout

local getn = table.getn

local F = {}
H.Frames = F

F.DEFAULTS = {
	barStyle = "dark",          -- "dark" (ретейл, dark mode) | "class" (цвет класса и красный враг)
	playerName = false,         -- в ретейле на рамке игрока имени нет
	targetName = true,
	targetOfTarget = true,
	power = false,              -- полоска ресурса 3 AS (в ретейле powerHeight = 0)
	portrait = false,           -- в ретейле портретов нет
	shield = true,
	binds = false,              -- в ретейле на CDM биндов нет, касты автоматические
	rank = true,
	greyCd = false,             -- серые иконки способностей на откате (ретейл 3.3 так; по умолчанию выкл, шторка и цифры остаются)
	cdMin = 1.5,                -- шторка и цифры только для отката от стольких секунд (GameRules.cdShortShutter)
	showMain = true, showClass = true, showBuffs = true, showStatics = true, showUtility = true, showXp = true,
	showPlayer = true, showTarget = true, showTargetAuras = true, showPlayerAuras = true, showLevelUp = true,
	showMicro = true,
	permanentPets = false,      -- постоянные питомцы в ряду призывов
	xpPlace = "top",            -- "top" (решение 5) | "column" (над рядом способностей)
	auraRows = 1,               -- рядов аур цели, 1..3
	parkStock = true,           -- в режиме Вместо прятать стоковые рамки и панель
}

-- Английские строки модуля (русские лежат в вызовах F.T как запасной текст). Язык берется из H.Locale.code.
F.STR = {}
F.STR.enUS = {
	lives_short = "LIVES", rerolls_short = "ROLL",
	frames_survivor = "Frames: SurvivorUI is showing its own frames, staying in Side by side mode. Turn off the frames in SurvivorUI settings and select Replace again.",
	levelup_title = "Level up", levelup_hint = "Click to open the stored level-ups",
	micro_char = "Chr", micro_talents = "Tal",
	revive_by = "is reviving you", revive_you = "You are reviving", down_you = "You are down",
	xp_title = "Run XP", xp_level = "Level", xp_xp = "XP", xp_stored = "Stored levels", xp_pace = "Pace", xp_min = "min",
	xp_next = "Next level in", xp_lv = "Lv.",
	opt_frames_mode = "Mode",
	opt_frames_survivor = "Replace is not active: SurvivorUI frames are on screen. Turn them off in SurvivorUI.",
	opt_frames_look = "Player and target frames", opt_bar_style = "Bar", opt_bar_dark = "Dark (retail)", opt_bar_class = "Class color",
	opt_player_name = "Hero name", opt_target_name = "Target name", opt_tot = "Target of target", opt_shield = "Shield",
	opt_power = "Resource bar", opt_portrait = "Portrait", opt_aura_rows = "Target aura rows",
	opt_frames_abilities = "Abilities", opt_rank = "Rank on icons", opt_binds = "Keys on icons",
	opt_grey_cd = "Grey icons on cooldown", opt_grey_cd_hint = "Like retail. The swipe and numbers stay either way.",
	opt_cd_min = "Cooldown from, s", opt_cd_min_hint = "Swipe and numbers only for cooldowns at least this long.",
	opt_pets = "Permanent pets", opt_frames_xp = "Run XP", opt_xp_place = "Place", opt_xp_top = "Top center",
	opt_xp_column = "Above the column", opt_frames_show = "Show",
	piece_main = "Ability row", piece_class = "Class resource", piece_buffs = "Run buffs", piece_statics = "Lives and rerolls",
	piece_utility = "Timers and summons", piece_xp = "XP bar", piece_player = "Hero frame", piece_target = "Target frame",
	piece_target_auras = "Target debuffs", piece_player_auras = "Hero auras", piece_levelup = "New level",
	piece_micro = "Side buttons", piece_party = "Party frames and revive",
	opt_park_stock = "Hide stock frames", opt_park_stock_hint = "Replace mode only.",
	page_frames_column = "Column", page_frames_show = "Display",
}

-- Строка интерфейса: на английском свой список, затем Locale (H.L), иначе русский текст из вызова.
function F.T(key, ru)
	local loc = H.Locale
	if loc and loc.code == "enUS" then
		local v = F.STR.enUS[key]
		if v then
			return v
		end
	end
	return H.Kit.L(key, ru)
end

local M = H.NewModule("frames", { label = F.T("mod_frames", "Рамки"), schema = 1, migrations = {}, defaults = F.DEFAULTS })
F.M = M

-- Дополнительные стоковые события 1.12, которые шина зарегистрирует на кадре ядра (так делает и Theme).
local STOCK = H.Events and H.Events.STOCK
if STOCK then
	STOCK.UNIT_MAXHEALTH = true
	STOCK.PLAYER_DEAD = true
	STOCK.PLAYER_ALIVE = true
end

-- Подпись модуля в настройках следует за языком.
H.On("LOCALE", "frames_label", function()
	M.label = F.T("mod_frames", "Рамки")
end)

F.mode = "off"
F.live = false
F.built = false
F.frames = {}      -- id -> кадр куска
F.owned = {}       -- id -> true: кусок зарегистрирован этим модулем
F.defs = {}        -- id -> def регистрации
F.parts = {}
F.order = {}
F.stats = { shutterShown = 0, shortShutter = 0, pieces = 0 }

-- Сдвиг корней в режиме Рядом: 50 ретейл-px вниз (около 30 AS), чтобы не лечь поверх ряда SurvivorUI.
local SIDE_SHIFT = -50
local SIDE_ROOTS = { ["col.main"] = true, ["col.xp"] = true, ["uf.player"] = true, ["uf.target"] = true, ["uf.levelup"] = true }

-- Запасной якорь для кусков, которые привязаны к куску другого модуля (plan 2.2): пока там нет миникарты
-- Трекера, ауры игрока встают слева от места миникарты (ретейл-px, от правого верха экрана).
local FALLBACKS = {
	["uf.buffs"] = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -232, y = -1 },
	["uf.debuffs"] = { point = "BOTTOMRIGHT", relPoint = "TOPRIGHT", x = -232, y = -231 },
}

function F.Opt(key)
	return M.db[key]
end

-- Стоковая функция или кадр по имени без прямого чтения глобала (имена игры не из нашего набора).
function F.Env(name)
	return H.Env[name]
end

-- Вызов стоковой функции с юнитом под pcall (party-юниты бросают ошибки): первое значение или nil.
function F.Unit(name, unit, a)
	local fn = H.Env[name]
	if type(fn) ~= "function" then
		return nil
	end
	return H.Hero.SafeUnit(fn, unit, a)
end

-- Токен класса юнита ("WARRIOR") или nil.
function F.UnitClassToken(unit)
	local fn = H.Env.UnitClass
	if type(fn) ~= "function" then
		return nil
	end
	local ok, _, token = pcall(fn, unit)
	if ok then
		return token
	end
	return nil
end

----------------------------------------------------------------------------------------
-- Куски Layout
----------------------------------------------------------------------------------------

local function Merge(id, def)
	local out = {}
	local base = H.LayoutDefaults and H.LayoutDefaults.pieces and H.LayoutDefaults.pieces[id]
	if base then
		for k, v in pairs(base) do
			out[k] = v
		end
	end
	if def then
		for k, v in pairs(def) do
			out[k] = v
		end
	end
	if FALLBACKS[id] and not out.fallback then
		out.fallback = FALLBACKS[id]
	end
	return out
end

-- Опции, меняющие якоря: XP над колонкой (вариант из таблицы умолчаний) и класс-ресурс над ним.
local function Variant(id, out)
	local d = H.LayoutDefaults
	if id == "col.xp" and M.db.xpPlace == "column" then
		local v = d and d.variants and d.variants["col.xp"] and d.variants["col.xp"].column
		if v then
			for k, val in pairs(v) do
				out[k] = val
			end
			out.w, out.collapse = nil, true
		end
	elseif id == "col.class" and M.db.xpPlace == "column" then
		out.rel, out.relPoint = "col.xp", "TOP"
	end
end

local function Overrides(id, def)
	local out = Merge(id, def)
	Variant(id, out)
	if F.mode == "side" and SIDE_ROOTS[id] and out.rel == "UIParent" then
		out.y = (out.y or 0) + SIDE_SHIFT
	end
	return out
end

function F.Piece(id, frame, def)
	F.frames[id] = frame
	F.defs[id] = def or false
	local p = L.Piece(id, frame, Overrides(id, def))
	if not F.owned[id] then
		F.owned[id] = true
		F.stats.pieces = F.stats.pieces + 1
		H.Vis.Register(frame, { overCards = false, id = id })
	end
	return p
end

function F.Repiece(id)
	if F.owned[id] then
		L.Piece(id, F.frames[id], Overrides(id, F.defs[id] or nil))
	end
end

function F.Unpiece(id)
	if not F.owned[id] then
		return
	end
	local frame = F.frames[id]
	F.owned[id] = nil
	F.stats.pieces = F.stats.pieces - 1
	if frame then
		H.Vis.Unregister(frame)
		frame:Hide()
	end
	L.Unpiece(id)
end

function F.Show(id, want)
	local f = F.frames[id]
	if not f or not F.owned[id] then
		return
	end
	if want and F.live and not H.Vis.IsChoosing() and not L.IsHiddenByUser(id) then
		if not f:IsShown() then
			f:Show()
		end
	elseif f:IsShown() then
		f:Hide()
	end
end

-- Кусок виден на экране сейчас (кадр показан).
function F.IsShown(id)
	local f = F.frames[id]
	return f ~= nil and F.owned[id] ~= nil and f:IsShown() and true or false
end

----------------------------------------------------------------------------------------
-- Части, события, режимы
----------------------------------------------------------------------------------------

function F.Part(name, def)
	def.name = name
	F.parts[name] = def
	table.insert(F.order, name)
	return def
end

local function Each(method, a1)
	for i = 1, getn(F.order) do
		local p = F.parts[F.order[i]]
		local fn = p[method]
		if fn then
			H.Safe(M.name, fn, a1)
		end
	end
end

local handlers = {}

local function Dispatch(ev, a1, a2, a3, a4)
	local list = handlers[ev]
	if not list then
		return
	end
	for i = 1, getn(list) do
		H.Safe(M.name, list[i], ev, a1, a2, a3, a4)
	end
end

function F.On(ev, fn)
	local list = handlers[ev]
	if not list then
		list = {}
		handlers[ev] = list
	end
	table.insert(list, fn)
	if F.live then
		M:On(ev, Dispatch)
	end
end

function F.RefreshAll()
	Each("Refresh")
end

-- Кадры рамок SurvivorUI на экране? Тогда режим Вместо (парковка MainMenuBar уносит ActionButton1-6, на которые
-- опирается ряд SurvivorUI, api 3.2) не включается. Ключ модуля рамок в SurvivorUIDB не известен [НЕ ПРОВЕРЕНО]:
-- проверяются кадры.
local SURVIVOR_FRAMES = { "SurvivorUIRow", "SurvivorUIPlayer", "SurvivorUITarget" }

function F.SurvivorActive()
	for i = 1, getn(SURVIVOR_FRAMES) do
		local f = H.Env[SURVIVOR_FRAMES[i]]
		if type(f) == "table" and f.IsShown then
			local ok, shown = pcall(f.IsShown, f)
			if ok and shown then
				return true
			end
		end
	end
	return false
end

function F.EffectiveMode()
	local m = H.GetMode(M.name)
	if m == "replace" and F.SurvivorActive() then
		if not F.warned then
			F.warned = true
			H.Print(F.T("frames_survivor", "Рамки: SurvivorUI показывает свои рамки, остаюсь в режиме Рядом. Выключите рамки в настройках SurvivorUI и снова выберите Вместо."))
		end
		return "side"
	end
	F.warned = nil
	return m
end

function F.ApplyMode()
	local m = F.EffectiveMode()
	if m == "off" or m == F.mode then
		return
	end
	F.mode = m
	for id in pairs(F.owned) do
		F.Repiece(id)
	end
	Each("Mode", m)
	F.RefreshAll()
	H.Fire("FRAMES_MODE", m)
end

local function OnSetting(ev, mod, key)
	if mod ~= M.name then
		return
	end
	if key == "mode" then
		return
	end
	if key == "xpPlace" then
		F.Repiece("col.xp")
		F.Repiece("col.class")
	end
	Each("Setting", key)
	F.RefreshAll()
end

F.On("SETTING", OnSetting)
F.On("LAYOUT", function()
	F.RefreshAll()
end)
F.On("CARDS", function()
	F.RefreshAll()
end)
F.On("PHASE_CHANGED", function()
	F.RefreshAll()
end)

local function HookAll()
	for ev in pairs(handlers) do
		M:On(ev, Dispatch)
	end
end

function M:OnEnable()
	F.mode = F.EffectiveMode()
	if not F.built then
		F.built = true
		Each("Build")
	end
	F.live = true
	HookAll()
	Each("Enable", F.mode)
	F.RefreshAll()
	H.Fire("FRAMES_MODE", F.mode)
end

function M:OnDisable()
	F.live = false
	for i = getn(F.order), 1, -1 do
		local p = F.parts[F.order[i]]
		if p.Disable then
			H.Safe(M.name, p.Disable)
		end
	end
	F.mode = "off"
	H.Fire("FRAMES_MODE", "off")
end

-- Смена режима: запись в DB уже сделана ядром. Из Выкл включает ядро (OnEnable), здесь только Рядом <-> Вместо.
function M:OnMode(mode)
	if mode ~= "off" and M.enabled then
		F.ApplyMode()
	end
end

-- Строки для selftest (интегратор подключает в Debug.Selftest, если найдет H.Frames.Selftest).
function F.Selftest()
	local out = {}
	table.insert(out, "frames: режим "..tostring(F.mode).." (запрошен "..tostring(H.GetMode(M.name))..")"..
		", кусков "..F.stats.pieces..", ошибок "..H.Errors.Count(M.name))
	table.insert(out, "frames: показов шторки у откатов короче "..tostring(M.db.cdMin).." с: "..F.stats.shortShutter..
		" (ждем 0), настоящих запусков шторки всего "..F.stats.shutterShown..
		" (дрожь данных и хвосты условных способностей не считаются; за минуту порядка числа настоящих откатов)")
	if H.Spells and H.Spells.stats then
		table.insert(out, "frames: расхождение источников кулдауна, максимум "..string.format("%.3f", H.Spells.stats.maxDelta).." с")
	end
	return out
end
