-- HyoukaUI: Data\Hero, герой забега (plan 2.2). Класс, имя, раса, пол и цвет берутся из AZS_ZONE:
-- клиентские UnitClass/UnitName("player") в этом движке отдают героя, с которым открыт клиент,
-- а не героя забега (azs-api.md 2.2). Глобальные Unit* не подменяются.
-- После /reload, пока строка зоны не пришла, берется снимок из DB (через Run.Zone).
-- Событие: HERO_CHANGED(classKey, heroName) при смене класса или имени в AZS_ZONE.
--
-- H.Hero.SafeUnit(fn, unit, a): вызов стоковой функции Unit* под pcall (party-юниты бросают
-- ошибки, например UnitIsDead("partyN") в 0.113, audit frames-44). Возвращает значение или nil.

local H = HyoukaUI

local O = {}
H.Hero = O

local S = { class = nil, name = nil }

-- Цвета классов 1.12, если глобального RAID_CLASS_COLORS нет (в клиенте он есть).
local COLORS = {
	warrior = { 0.78, 0.61, 0.43 }, mage = { 0.41, 0.80, 0.94 }, rogue = { 1.00, 0.96, 0.41 },
	druid = { 1.00, 0.49, 0.04 }, hunter = { 0.67, 0.83, 0.45 }, shaman = { 0.00, 0.44, 0.87 },
	priest = { 1.00, 1.00, 1.00 }, warlock = { 0.58, 0.51, 0.79 }, paladin = { 0.96, 0.55, 0.73 },
}
O.COLORS = COLORS

local function ZoneString(key)
	local v = H.Run.Zone(key)
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

-- Ключ класса в нижнем регистре ("mage") или nil.
function O.Class()
	local c = ZoneString("class")
	return c and string.lower(c) or nil
end

-- Локализованное имя класса.
function O.ClassName()
	return ZoneString("cname")
end

function O.Name()
	return ZoneString("hero")
end

-- Раса по-английски ("Tauren") и локализованная.
function O.Race()
	return ZoneString("race"), ZoneString("rname")
end

-- 0 мужской, 1 женский, nil неизвестно.
function O.Sex()
	local g = H.Run.Zone("gender")
	if type(g) == "number" then
		return g
	end
	return nil
end

-- r, g, b цвета класса героя; серый, если класс неизвестен. Без таблиц на вызов.
function O.ClassColor()
	local c = O.Class()
	if c then
		-- Сначала свои цвета (ретейл): в таблице клиента 1.12 шаман розовый, как паладин.
		local t = COLORS[c]
		if t then
			return t[1], t[2], t[3]
		end
		local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[string.upper(c)]
		if rc then
			return rc.r, rc.g, rc.b
		end
	end
	return 0.62, 0.62, 0.62
end

-- r, g, b цвета класса по ключу ("warrior"), для строк группы.
function O.ColorOf(classKey)
	local c = type(classKey) == "string" and string.lower(classKey) or nil
	if c then
		-- Сначала свои цвета (ретейл): в таблице клиента 1.12 шаман розовый, как паладин.
		local t = COLORS[c]
		if t then
			return t[1], t[2], t[3]
		end
		local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[string.upper(c)]
		if rc then
			return rc.r, rc.g, rc.b
		end
	end
	return 0.62, 0.62, 0.62
end

-- Здоровье и щит героя из AZS_RUN: hp, hpm, sh. UnitHealth("player") тот же в числах (проба 0.12).
function O.Health()
	local run = AZS_RUN
	return run.hp, run.hpm, run.sh or 0
end

-- pcall для стоковых функций с юнитом: Hero.SafeUnit(UnitIsDead, "party1").
function O.SafeUnit(fn, unit, a)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, unit, a)
	if ok then
		return value
	end
	return nil
end

local function OnZone()
	local c, n = O.Class(), O.Name()
	if c ~= S.class or n ~= S.name then
		S.class, S.name = c, n
		H.Fire("HERO_CHANGED", c, n)
	end
end

function O.Reset()
	S.class, S.name = nil, nil
end

H.Poll.AddLayer("hero", O.Reset)
H.On("ZONE", "hero", OnZone)
