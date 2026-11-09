-- HyoukaUI: Core\Hud, захват частей нативного HUD игры (plan 2.2 и раздел 4).
--
-- Игра держит 11 частей HUD (banners bosses build clock flag levels localClock loot meter revive
-- tally; состав берется обходом AZS_HUD_CVARS) и переключает их AZS_SetHudShown(part, shown).
--
-- Claim(part, owner) / Release(part, owner): часть скрыта, пока на нее есть хотя бы один claim.
-- Cover(part, pieceId) / Uncover(part, pieceId): часть с несколькими покрытиями (build: три куска из
-- двух модулей) скрыта, только когда покрыты ВСЕ куски из Rules.cover[part]; без записи в Rules
-- хватает одного покрытия. Дубль на экране лучше пустоты.
-- ЧТО ЭТО СКРЫЛИ МЫ. HyoukaUIDB.global.hud.owned[part] = true пишется ДО вызова AZS_SetHudShown, и
-- только если мы сами сменили состояние: часть была показана. Часть, скрытая до нас (остатки
-- другого аддона в config.toml), не считается нашей: Release и RestoreAll ее не показывают.
-- Если позже ее покажут (например SurvivorUI), Reassert скроет ее заново и она станет нашей.
-- Release / последнее Uncover возвращают часть, только если ее скрыли мы.
-- Возврат: Release, RestoreAll() (все и сразу, сбрасывает claims, команда /hui hud reset),
-- PLAYER_LOGOUT (RestoreAll), после нечистого выхода на ADDON_LOADED (Recover) вернутся части из owned.
-- Ограничение: SavedVariables пишутся при выходе и /reload. Падение клиента без записи файла
-- Recover восстановить не сможет (файл остается тем, что был), у двух частей игры нет переключателя
-- в настройках: поэтому owned пишется сразу в таблицу, а RestoreAll идет на LOGOUT.
-- Reassert идет на WORLD и PHASE_CHANGED, а пока загружен SurvivorUI - еще и раз в 2 секунды.
-- Событие HUD_CHANGED(part, hidden).
-- Чтение AZS_IsHudShown и вызов AZS_SetHudShown только здесь (и в Debug для дампа).

local H = HyoukaUI

local U = {}
H.Hud = U

U.REASSERT_STEP = 2

local claims, nClaims = {}, {}   -- part -> { owner = true }, part -> число
local covers, nCovers = {}, {}   -- part -> { pieceId = true }, part -> число
local parts                       -- кэш отсортированных имен частей

H.counters.covers = H.counters.covers or 0

local function HudState()
	local g = H.DB and H.DB.ready and H.DB.Global()
	if not g then
		return nil
	end
	g.hud = g.hud or { owned = {}, cleanExit = true }
	g.hud.owned = g.hud.owned or {}
	return g.hud
end

-- Имена частей из AZS_HUD_CVARS (проба 0.4), по алфавиту. Кэшируется; пусто, если таблицы нет.
function U.Parts()
	if not parts then
		parts = {}
		if type(AZS_HUD_CVARS) == "table" then
			for k in pairs(AZS_HUD_CVARS) do
				table.insert(parts, k)
			end
			table.sort(parts)
		end
	end
	return parts
end

local function Known(part)
	return type(part) == "string" and part ~= "all" and type(AZS_HUD_CVARS) == "table" and AZS_HUD_CVARS[part] ~= nil
end

-- Показана ли часть сейчас: true, false или nil, если прочитать нельзя.
function U.IsShown(part)
	if not AZS_IsHudShown then
		return nil
	end
	local ok, v = pcall(AZS_IsHudShown, part)
	if not ok then
		return nil
	end
	return v and true or false
end

local function SetShown(part, shown)
	if AZS_SetHudShown and Known(part) then
		local ok, err = pcall(AZS_SetHudShown, part, shown)
		if not ok then
			H.Errors.Add("hud", tostring(err))
		end
	end
end

local function ShouldHide(part)
	if (nClaims[part] or 0) > 0 then
		return true
	end
	if (nCovers[part] or 0) == 0 then
		return false
	end
	local req = H.Rules.Required(part)
	if not req then
		return true
	end
	local c = covers[part]
	for i = 1, table.getn(req) do
		if not c[req[i]] then
			return false
		end
	end
	return true
end

local function Clean(hud)
	if next(hud.owned) == nil then
		hud.cleanExit = true
	end
end

local function Apply(part)
	local hud = HudState()
	if not hud then
		return
	end
	local owned = hud.owned[part]
	if ShouldHide(part) then
		if not owned then
			if U.IsShown(part) == true then
				hud.owned[part] = true
				hud.cleanExit = false
				SetShown(part, false)
				H.Fire("HUD_CHANGED", part, true)
			end
		elseif U.IsShown(part) == true then
			SetShown(part, false)
		end
	elseif owned then
		hud.owned[part] = nil
		SetShown(part, true)
		Clean(hud)
		H.Fire("HUD_CHANGED", part, false)
	end
end

local function Count(set, n, part, key, add)
	local s = set[part]
	if add then
		if not s then
			s = {}
			set[part] = s
		end
		if s[key] then
			return false
		end
		s[key] = true
		n[part] = (n[part] or 0) + 1
		return true
	end
	if not s or not s[key] then
		return false
	end
	s[key] = nil
	n[part] = n[part] - 1
	return true
end

function U.Claim(part, owner)
	if not Known(part) or owner == nil then
		return false
	end
	if Count(claims, nClaims, part, owner, true) then
		H.counters.claims = H.counters.claims + 1
	end
	Apply(part)
	return true
end

function U.Release(part, owner)
	if part == nil or owner == nil then
		return false
	end
	if Count(claims, nClaims, part, owner, false) then
		H.counters.claims = H.counters.claims - 1
	end
	Apply(part)
	return true
end

function U.Cover(part, pieceId)
	if not Known(part) or pieceId == nil then
		return false
	end
	if Count(covers, nCovers, part, pieceId, true) then
		H.counters.covers = H.counters.covers + 1
	end
	Apply(part)
	return true
end

function U.Uncover(part, pieceId)
	if part == nil or pieceId == nil then
		return false
	end
	if Count(covers, nCovers, part, pieceId, false) then
		H.counters.covers = H.counters.covers - 1
	end
	Apply(part)
	return true
end

-- Скрыта ли часть сейчас по нашей воле (есть claim или покрытие полное).
function U.WantsHidden(part)
	return ShouldHide(part)
end

function U.ClaimCount(part)
	return nClaims[part] or 0
end

function U.CoverCount(part)
	return nCovers[part] or 0
end

-- Части, которые скрыли мы: отсортированный массив имен (создает таблицу, для отладки).
function U.Owned()
	local out = {}
	local hud = HudState()
	if hud then
		for k in pairs(hud.owned) do
			table.insert(out, k)
		end
		table.sort(out)
	end
	return out
end

-- Пройти по частям и повторно скрыть те, что должны быть скрыты, но кем-то показаны.
function U.Reassert()
	local list = U.Parts()
	for i = 1, table.getn(list) do
		local part = list[i]
		if (nClaims[part] or 0) > 0 or (nCovers[part] or 0) > 0 or (HudState() and HudState().owned[part]) then
			Apply(part)
		end
	end
end

-- Аварийный возврат всего: показать все, что скрыли мы, снять все claims и покрытия.
-- Возвращает число возвращенных частей.
function U.RestoreAll()
	local hud = HudState()
	local n = 0
	if hud then
		for part in pairs(hud.owned) do
			SetShown(part, true)
			n = n + 1
		end
		local names = U.Owned()
		H.Wipe(hud.owned)
		hud.cleanExit = true
		for i = 1, table.getn(names) do
			H.Fire("HUD_CHANGED", names[i], false)
		end
	end
	H.Wipe(claims)
	H.Wipe(nClaims)
	H.Wipe(covers)
	H.Wipe(nCovers)
	H.counters.claims = 0
	H.counters.covers = 0
	return n
end

-- ADDON_LOADED: после нечистого выхода вернуть части из owned, на которые нет живых claims.
function U.Recover()
	local hud = HudState()
	if not hud then
		return 0
	end
	local n = 0
	for part in pairs(hud.owned) do
		if not ShouldHide(part) then
			SetShown(part, true)
			hud.owned[part] = nil
			n = n + 1
		end
	end
	Clean(hud)
	return n
end

-- Счета для selftest: claims, covers, частей в owned.
function U.Stats()
	local hud = HudState()
	local owned = 0
	if hud then
		for _ in pairs(hud.owned) do
			owned = owned + 1
		end
	end
	return H.counters.claims, H.counters.covers, owned
end

--@frame
local function Tick()
	if H.counters.claims + H.counters.covers > 0 and H.IsCoexist() then
		U.Reassert()
	end
end

-- Для тестов: забыть claims без возврата частей (имитация нового запуска клиента).
function U.ForgetClaims()
	H.Wipe(claims)
	H.Wipe(nClaims)
	H.Wipe(covers)
	H.Wipe(nCovers)
	H.counters.claims = 0
	H.counters.covers = 0
	parts = nil
end

function U.Start()
	H.Clock.Every("hud", U.REASSERT_STEP, Tick)
end

H.Poll.AddLayer("hud", nil, U.Start)
H.On("LOADED", "hud", U.Recover)
H.On("WORLD", "hud", U.Reassert)
H.On("PHASE_CHANGED", "hud", U.Reassert)
H.On("LOGOUT", "hud", U.RestoreAll)
H.On("LOGIN", "hud", U.Start)
