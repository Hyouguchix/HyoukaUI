-- HyoukaUI: Data\Spells, способности героя из AZS_SPELLS (plan 2.2).
--
-- Запись { key, spell, rank, cd, cdmax }: key - английский ключ ("fireball"), spell - id заклинания,
-- cd - осталось на момент строки, cdmax - полный кулдаун (округлен до 0.1 с). Способности срабатывают
-- сами, кнопки только показывают состояние. Раскладка: записи 1..n-1 лежат в слотах действий 1..6,
-- последняя (расовая) в слоте 12 (проба 0.7 подтвердила конвенцию).
--
-- КУЛДАУН. Основной источник - расчет из AZS_SPELLS: start = AZS_SPELLS_UPDATED - (dur - cd),
-- dur = cdmax с полом (0.2 приходит как 0.25, GameRules). Он не зависит от кадров стокового бара
-- и считается одинаково в тестах и в игре. Второй источник - GetActionCooldown(слот): проба 0.7
-- показала расхождение 0.01-0.06 с. Spells.Reconcile() сравнивает их для selftest и dump
-- (stats.maxDelta), в кадре он не вызывается.
-- СЛОТ. SlotOf берет slotId способности из Loadout (если это целое 1..12), иначе конвенцию.
-- Допущение для проверки в игре: slotId из AZS_GetMeterLoadout это номер слота действий (проба 0.8
-- показала только наличие поля). /hui dump spells печатает оба варианта и расхождение.
-- Событие SPELLS_CHANGED(n) - только смена состава (ключи, ранги, id, число). Обновления кулдаунов
-- идут сырым событием SPELLS.

local H = HyoukaUI

local P = {}
H.Spells = P

local S = { n = 0, keys = {}, ranks = {}, ids = {}, names = {} }
P.stats = { maxDelta = 0, lastDelta = 0, samples = 0 }

function P.Count()
	return table.getn(AZS_SPELLS)
end

function P.Row(i)
	return AZS_SPELLS[i]
end

function P.Key(i)
	local r = AZS_SPELLS[i]
	return r and r.key
end

function P.Rank(i)
	local r = AZS_SPELLS[i]
	return r and r.rank
end

function P.SpellId(i)
	local r = AZS_SPELLS[i]
	return r and r.spell
end

-- Последняя запись списка - расовая способность (слот 12).
function P.IsRacial(i)
	return i ~= nil and i == table.getn(AZS_SPELLS)
end

function P.Find(key)
	local list = AZS_SPELLS
	if not list then
		return nil
	end
	for i = 1, table.getn(list) do
		if list[i].key == key then
			return i
		end
	end
	return nil
end

-- Есть ли у героя заклинание с таким id (audit tracker-26).
function P.Owns(spellId)
	local list = AZS_SPELLS
	for i = 1, table.getn(list) do
		if list[i].spell == spellId then
			return true
		end
	end
	return false
end

-- Слот по конвенции: 1..6 для обычных, 12 для последней.
function P.ConventionSlot(i)
	local n = table.getn(AZS_SPELLS)
	if i == nil or i < 1 or i > n then
		return nil
	end
	if i == n then
		return 12
	end
	if i <= 6 then
		return i
	end
	return nil
end

-- Слот действия способности i и откуда он: "loadout" или "convention". Без таблиц.
function P.SlotOf(i)
	local key = P.Key(i)
	if not key then
		return nil
	end
	local slot = H.Loadout and H.Loadout.SlotOf(key)
	if slot then
		return slot, "loadout"
	end
	return P.ConventionSlot(i), "convention"
end

-- Кулдаун способности i: start, duration (GetTime-часы). 0, 0, если откат не идет или уже закончился.
-- Пол: cdmax 0.2 (так приходит 0.25) показывается как 0.25.
function P.Cooldown(i)
	local r = AZS_SPELLS[i]
	if not r or type(r.cd) ~= "number" or type(r.cdmax) ~= "number" or r.cd <= 0 or r.cdmax <= 0 then
		return 0, 0
	end
	local stamp = AZS_SPELLS_UPDATED
	if not stamp then
		return 0, 0
	end
	local dur = H.Rules.CooldownDuration(r.cdmax)
	local start = stamp - (dur - r.cd)
	if start + dur <= H.Now() then
		return 0, 0
	end
	return start, dur
end

-- Сколько секунд осталось до конца отката (0, если нет).
function P.Remaining(i)
	local start, dur = P.Cooldown(i)
	if dur == 0 then
		return 0
	end
	return start + dur - H.Now()
end

-- Откат короче пола считать шторкой не нужно: способность с cdmax на уровне пола.
function P.IsFloor(i)
	local r = AZS_SPELLS[i]
	return r ~= nil and type(r.cdmax) == "number" and r.cdmax > 0 and r.cdmax <= H.Rules.cdFloorRaw + 0.0001
end

-- Второй источник: GetActionCooldown(слот). start, duration или nil.
function P.ActionCooldown(i)
	local slot = P.SlotOf(i)
	if not slot or not GetActionCooldown then
		return nil
	end
	local start, dur = GetActionCooldown(slot)
	return start, dur
end

-- Сверка двух источников по остатку отката, секунды. Для selftest и dump, не для кадра.
-- Возвращает максимальное расхождение за проход и число сравненных способностей.
function P.Reconcile()
	local now = H.Now()
	local worst, count = 0, 0
	for i = 1, table.getn(AZS_SPELLS) do
		local aStart, aDur = P.ActionCooldown(i)
		if aStart then
			local calc = P.Remaining(i)
			local act = 0
			if aDur and aDur > 0 and aStart > 0 then
				act = aStart + aDur - now
				if act < 0 then
					act = 0
				end
			end
			local d = math.abs(calc - act)
			count = count + 1
			if d > worst then
				worst = d
			end
		end
	end
	P.stats.lastDelta = worst
	P.stats.samples = P.stats.samples + count
	if worst > P.stats.maxDelta then
		P.stats.maxDelta = worst
	end
	return worst, count
end

local function Title(key)
	local s = S.names[key]
	if not s then
		s = string.gsub(key, "_", " ")
		s = string.gsub(s, "(%a)(%w*)", function(a, b)
			return string.upper(a)..b
		end)
		S.names[key] = s
	end
	return s
end

-- Имя способности: из loadout (sources), иначе из ключа ("fire_blast" -> "Fire Blast").
function P.Name(i)
	local key = P.Key(i)
	if not key then
		return nil
	end
	local n = H.Loadout and H.Loadout.AbilityName(key)
	if n then
		return n
	end
	return Title(key)
end

-- Текстура кнопки действия способности i (то, что рисует стоковая панель): сама игра гарантирует, что файл существует.
function P.ActionIcon(i)
	local slot = P.SlotOf(i)
	if slot and GetActionTexture then
		return GetActionTexture(slot)
	end
	return nil
end

-- Иконка: из loadout (sources[...].icon.path, если готова), иначе текстура кнопки действия.
function P.Icon(i)
	local key = P.Key(i)
	if not key then
		return nil
	end
	local path = H.Loadout and H.Loadout.AbilityIcon(key)
	if path then
		return path
	end
	local slot = P.SlotOf(i)
	if slot and GetActionTexture then
		return GetActionTexture(slot)
	end
	return nil
end

local function OnSpells()
	local list = AZS_SPELLS
	local n = table.getn(list)
	local changed = n ~= S.n
	for i = 1, n do
		local r = list[i]
		if S.keys[i] ~= r.key or S.ranks[i] ~= r.rank or S.ids[i] ~= r.spell then
			changed = true
			S.keys[i], S.ranks[i], S.ids[i] = r.key, r.rank, r.spell
		end
	end
	for i = n + 1, S.n do
		S.keys[i], S.ranks[i], S.ids[i] = nil, nil, nil
	end
	S.n = n
	if changed then
		H.Fire("SPELLS_CHANGED", n)
	end
end

function P.Reset()
	H.Wipe(S.keys)
	H.Wipe(S.ranks)
	H.Wipe(S.ids)
	S.n = 0
	P.stats.maxDelta, P.stats.lastDelta, P.stats.samples = 0, 0, 0
end

H.Poll.AddLayer("spells", P.Reset)
H.On("SPELLS", "spells", OnSpells)
