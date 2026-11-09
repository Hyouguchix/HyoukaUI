-- HyoukaUI: Modules\Meter\Crits.lua, криты и обычные удары по способностям для карточки (plan 3.4, раздел критов).
--
-- ИСТОЧНИК: события боевого текста через H.CombatText (шина COMBAT_EVENT(kind, amount, critical, source)). Поля
-- настоящих событий в игре НЕ ПРОВЕРЕНЫ (проба 0.9 прочитала 0 событий), поэтому модуль пишет счета под ДВУМЯ ключами:
-- под тем, что пришло как источник (meterSourceKey или meterSource), и под именем способности (abilityName), если оно есть.
-- Карточка ищет сначала по sourceKey строки, потом по ее имени. Если событий нет или поля другие, статистики нет и
-- карточка просто не показывает раздел критов: функция выключается тихо.
--
-- СЧЕТА ПО МЕСТАМ. У каждого места дока свой Reset (свой чекпойнт), поэтому у каждого места свой набор счетов:
-- tallies[место]. Событие METER_RESET с ключом запроса "meter:<место>:<вид>" обнуляет счета этого места ("криты живут от
-- того же чекпойнта", critic meter). Новый забег обнуляет все.
--
-- Без таблиц на событие: запись по ключу создается один раз, дальше только числа.

local H = HyoukaUI
local MU = H.MeterUI

local C = {}
MU.Crits = C

local tallies = { {}, {}, {} }
C.events = 0

local function Stat(t, key)
	local s = t[key]
	if not s then
		s = { hits = 0, crits = 0, critSum = 0, critMax = 0, critMin = 0, critLast = 0, normSum = 0, normLast = 0 }
		t[key] = s
	end
	return s
end

local function Add(s, amount, critical)
	s.hits = s.hits + 1
	if critical then
		s.crits = s.crits + 1
		s.critSum = s.critSum + amount
		s.critLast = amount
		if amount > s.critMax then
			s.critMax = amount
		end
		if s.crits == 1 or amount < s.critMin then
			s.critMin = amount
		end
	else
		s.normSum = s.normSum + amount
		s.normLast = amount
	end
end

--@frame
function C.OnEvent(ev, kind, amount, critical, source)
	if kind ~= "damage" or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local rec = H.CombatText.Last()
	if rec.miss then
		return
	end
	local ability = rec.ability
	if source == nil and ability == nil then
		return
	end
	C.events = C.events + 1
	for i = 1, MU.SLOTS do
		local t = tallies[i]
		if source ~= nil then
			Add(Stat(t, source), amount, critical)
		end
		if ability ~= nil and ability ~= source then
			Add(Stat(t, ability), amount, critical)
		end
	end
end

-- Статистика способности места: сначала по ключу источника, потом по имени. nil, если событий не было.
function C.Get(slot, sourceKey, name)
	local t = tallies[slot]
	if not t then
		return nil
	end
	local s = sourceKey and t[sourceKey]
	if not s and name then
		s = t[name]
	end
	return s
end

function C.Reset(slot)
	local t = tallies[slot]
	if t then
		H.Wipe(t)
	end
end

function C.ResetAll()
	for i = 1, MU.SLOTS do
		H.Wipe(tallies[i])
	end
	C.events = 0
end

-- Номер места из ключа запроса "meter:<место>:<вид>" или nil.
function C.SlotOfKey(key)
	if type(key) ~= "string" then
		return nil
	end
	local _, _, n = string.find(key, "^meter:(%d):")
	return n and tonumber(n) or nil
end

-- Событие METER_RESET(ключ запроса): обнуляет счета места. Подписку держит Dock (одна на модуль).
function C.OnReset(ev, key)
	local slot = C.SlotOfKey(key)
	if slot then
		C.Reset(slot)
	end
end

-- Включить чтение боевого текста (только пока док виден и опция включена).
function C.Enable(on)
	if on then
		H.On("COMBAT_EVENT", MU.OWNER, C.OnEvent)
		H.CombatText.Watch(MU.OWNER, true)
	else
		H.Off("COMBAT_EVENT", MU.OWNER)
		H.CombatText.Watch(MU.OWNER, false)
	end
end
