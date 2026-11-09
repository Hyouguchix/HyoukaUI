-- HyoukaUI: Data\Units, особые враги забега (plan 2.2): боссы, стражи, элиты из AZS_UNITS.
--
-- Глобал движка не меняется (audit frames-02): слой собирает свои массивы ссылок на строки
-- { kind, id, name, hp, hpm, state } и отдает их функциями. Кроме боссов и стражей kind бывает
-- "final" (финальный босс, входит в Bosses) и "elite".
-- Свежесть: список виден, только если фаза не ready и метка не старше строки зоны текущего забега
-- (Run.IsFresh). Движок не очищает AZS_UNITS после забега, поэтому без фильтра остались бы призраки.
-- События: UNITS_CHANGED(n) после разбора, UNIT_GONE(id, kind, name) для юнита, который был в
-- прошлом списке и пропал (разность двух множеств, очищаемых на месте, audit tracker-51).
--
-- GUID в движке нет, юнит опознается по имени и доле здоровья с допуском (audit tracker-40).

local H = HyoukaUI

local U = {}
H.Units = U

local S = {
	all = {}, bosses = {}, guardians = {}, elites = {},
	cur = {}, prev = {},     -- множества id -> строка (prev только на время сборки)
	fresh = false,
}

function U.IsFresh()
	local ph = AZS_RUN.ph
	if ph == nil or ph == "ready" then
		return false
	end
	return H.Run.IsFresh(AZS_UNITS_UPDATED)
end

-- Массивы ссылок на строки. Действительны до следующего UNITS_CHANGED. Читать table.getn(массив).
function U.Bosses()
	return S.bosses
end

function U.Guardians()
	return S.guardians
end

function U.Elites()
	return S.elites
end

function U.All()
	return S.all
end

function U.Count()
	return table.getn(S.all)
end

function U.Get(id)
	return S.cur[id]
end

-- В бою: босс разъярен, страж проснулся, либо здоровье ниже максимума (audit tracker-24).
function U.InFight(u)
	if not u then
		return false
	end
	return u.state == 1 or (u.hp ~= nil and u.hpm ~= nil and u.hp < u.hpm)
end

-- Опознать юнит клиента (token вроде "target") в списке по имени и доле здоровья.
-- Возвращает id и уверенность (доля совпала в допуске). nil, если имени нет в списке или
-- кандидатов несколько и доля не выбирает ни одного.
function U.IdOf(token, tolerance)
	local name = UnitName and UnitName(token)
	if not name then
		return nil
	end
	tolerance = tolerance or H.Rules.fractionTolerance
	local hp, mx = UnitHealth(token), UnitHealthMax(token)
	local frac
	if mx and mx > 0 and hp then
		frac = hp / mx
	end
	local list = S.all
	local count, bestId, bestD = 0, nil, nil
	for i = 1, table.getn(list) do
		local row = list[i]
		if row.name == name then
			count = count + 1
			local d
			if frac and row.hpm and row.hpm > 0 and row.hp then
				d = math.abs(frac - row.hp / row.hpm)
			end
			if bestId == nil or (d ~= nil and (bestD == nil or d < bestD)) then
				bestId, bestD = row.id, d
			end
		end
	end
	if count == 0 then
		return nil
	end
	if count == 1 then
		return bestId, (bestD == nil or bestD <= tolerance)
	end
	if bestD ~= nil and bestD <= tolerance then
		return bestId, true
	end
	return nil
end

-- Дебаффы: по id босса или стража через AZS_GetDebuffs (записи { spell, name, icon, stacks,
-- duration, remaining, permanent, dispelType }), по токену клиента для элиты через UnitDebuff
-- (записи { icon, stacks, dispelType }). Каждый вызов создает таблицу: звать по событию DEBUFFS, не в кадре.
function U.Debuffs(idOrToken)
	local row = S.cur[idOrToken]
	local token
	if not row then
		token = idOrToken
		local id = U.IdOf(token)
		row = id and S.cur[id]
	end
	if row and (row.kind == "boss" or row.kind == "final" or row.kind == "guardian") then
		return AZS_GetDebuffs(row.id)
	end
	local out = {}
	if token and UnitDebuff then
		for i = 1, 16 do
			local icon, stacks, dispel = UnitDebuff(token, i)
			if not icon then
				break
			end
			table.insert(out, { icon = icon, stacks = stacks, dispelType = dispel })
		end
	end
	return out
end

-- Настоящие HP цели из AZS_TARGET, если имя совпадает с клиентской целью (api 2.5): hp, hpm, name, kind.
function U.Target()
	local t = AZS_TARGET
	if not t.name or t.kind == "none" then
		return nil
	end
	local n = UnitName and UnitName("target")
	if n ~= t.name or t.hp == nil then
		return nil
	end
	return t.hp, t.hpm, t.name, t.kind
end

-- Взять в цель юнита по id (из OnClick): TargetByName, сверка IdOf, при промахе TargetLastTarget.
-- Возвращает true, если цель опознана. Защищенность вызова проверила проба 0.10.
function U.TargetById(id)
	local row = S.cur[id]
	if not row or not row.name then
		return false
	end
	TargetByName(row.name)
	if U.IdOf("target") == id then
		return true
	end
	TargetLastTarget()
	return false
end

-- Это имя босса: среди текущих боссов или в расписании (в текстовом логе есть только имя цели).
function U.IsBossName(name)
	if not name then
		return false
	end
	local list = S.bosses
	for i = 1, table.getn(list) do
		if list[i].name == name then
			return true
		end
	end
	return H.Schedule ~= nil and H.Schedule.HasName(name)
end

-- Владеет ли герой заклинанием (audit tracker-26): через Spells.
function U.Owns(spellId)
	return H.Spells ~= nil and H.Spells.Owns(spellId)
end

----------------------------------------------------------------------------------------
-- Сборка
----------------------------------------------------------------------------------------

local function Rebuild(fromEvent)
	local before = table.getn(S.all)
	-- Прошлое множество id копируется в prev, чтобы найти пропавших после сборки нового.
	H.Wipe(S.prev)
	for id, row in pairs(S.cur) do
		S.prev[id] = row
	end
	H.Wipe(S.all)
	H.Wipe(S.bosses)
	H.Wipe(S.guardians)
	H.Wipe(S.elites)
	H.Wipe(S.cur)
	S.fresh = U.IsFresh()
	if S.fresh then
		local list = AZS_UNITS
		for i = 1, table.getn(list) do
			local row = list[i]
			if row.id ~= nil then
				S.cur[row.id] = row
				table.insert(S.all, row)
				local kind = row.kind
				if kind == "boss" or kind == "final" then
					table.insert(S.bosses, row)
				elseif kind == "guardian" then
					table.insert(S.guardians, row)
				elseif kind == "elite" then
					table.insert(S.elites, row)
				end
			end
		end
	end
	for id, row in pairs(S.prev) do
		if S.cur[id] == nil then
			H.Fire("UNIT_GONE", id, row.kind, row.name)
		end
	end
	if fromEvent or before ~= table.getn(S.all) then
		H.Fire("UNITS_CHANGED", table.getn(S.all))
	end
end
U.Rebuild = Rebuild

local function OnUnits()
	Rebuild(true)
end

local function OnOther()
	Rebuild(false)
end

function U.Reset()
	H.Wipe(S.all)
	H.Wipe(S.bosses)
	H.Wipe(S.guardians)
	H.Wipe(S.elites)
	H.Wipe(S.cur)
	H.Wipe(S.prev)
end

H.Poll.AddLayer("units", U.Reset)
H.On("UNITS", "units", OnUnits)
H.On("PHASE_CHANGED", "units", OnOther)
H.On("RUN_STARTED", "units", OnOther)
H.On("RUN_LEFT", "units", OnOther)
