-- HyoukaUI: Data\CombatText, курсор по AZS_GetCombatTextEvents и криты по источнику (plan 2.2).
--
-- ВНИМАНИЕ: поля отдельных событий в игре НЕ ПРОВЕРЕНЫ (проба 0.9 прочитала 0 событий). Известно
-- по SurvivorUI и по пулу имен exe: kind ("damage"), anchorId, targetName, amount, critical,
-- abilityName, meterSource, sourceId; остальное (eventId, meterSourceKey, periodic, miss...) только
-- предположение. Поэтому событие разбирает адаптер Adapt с проверкой присутствия полей и
-- запасными именами, а все остальное слоя работает с нормализованной записью. Снять настоящие
-- поля: /hui record в бою с попаданиями и сверить с Adapt.
-- Ответ чтения (проверено): apiVersion, clockSeconds, cursor, droppedCount, events, hasMore,
-- streamId, worldId; capabilities: eventCapacity 4096, retention 5 с, maxEventsPerRead 256.
--
-- Слой не стартует сам: модуль счетчика включает чтение через CombatText.Watch(owner, true).
-- Раз в STEP (0.2 с) читаются страницы по LIMIT (256) событий, не больше MAX_PAGES за тик.
-- Ошибки: NOT_READY - ждем, STREAM_CHANGED - курсор сбрасывается и чтение идет с начала потока.
-- События шины: COMBAT_EVENT(kind, amount, critical, source); вся запись в CombatText.Last().
-- Криты по источнику: CombatText.Crits(source) -> crits, hits. "Reset" счетчика (событие METER_RESET)
-- обнуляет эти счета, если ключ сброса совпал (SetResetKey) или не задан.

local H = HyoukaUI

local C = {}
H.CombatText = C

C.STEP = 0.2
C.LIMIT = 256
C.MAX_PAGES = 4

local S = { cursor = nil, streamId = nil, watch = {}, nWatch = 0, tally = {}, resetKey = nil }
local rec = { kind = nil, amount = 0, critical = false, source = nil, sourceId = nil, target = nil,
	ability = nil, anchorId = nil, periodic = false, miss = false }
C.stats = { reads = 0, events = 0, errors = 0, dropped = 0, pages = 0, lastCode = nil }

local function Flag(v)
	return v == true or v == 1
end

-- Нормализация одного события в общую запись rec. Все поля читаются с проверкой присутствия.
local function Adapt(e)
	rec.kind = e.kind or "damage"
	local amount = e.amount
	if type(amount) ~= "number" then
		amount = e.damage
	end
	rec.amount = type(amount) == "number" and amount or 0
	local crit = e.critical
	if crit == nil then
		crit = e.crit
	end
	rec.critical = Flag(crit)
	rec.source = e.meterSourceKey or e.sourceKey or e.meterSource
	rec.sourceId = e.sourceId
	rec.target = e.targetName
	rec.ability = e.abilityName
	rec.anchorId = e.anchorId
	rec.periodic = Flag(e.periodic)
	rec.miss = Flag(e.miss)
	return rec
end
C.Adapt = Adapt

-- Последняя нормализованная запись (переиспользуемая таблица: поля, не ссылку, брать сразу).
function C.Last()
	return rec
end

-- Разобрать одно сырое событие: счет критов и событие шины. Пригодно для фикстур без API.
function C.Feed(e)
	if type(e) ~= "table" then
		return
	end
	Adapt(e)
	C.stats.events = C.stats.events + 1
	if rec.kind == "damage" and not rec.miss and rec.source ~= nil then
		local t = S.tally[rec.source]
		if not t then
			t = { hits = 0, crits = 0 }
			S.tally[rec.source] = t
		end
		t.hits = t.hits + 1
		if rec.critical then
			t.crits = t.crits + 1
		end
	end
	H.Fire("COMBAT_EVENT", rec.kind, rec.amount, rec.critical, rec.source)
end

-- Криты и попадания источника с последнего сброса.
function C.Crits(source)
	local t = S.tally[source]
	if t then
		return t.crits, t.hits
	end
	return 0, 0
end

function C.ResetCounts()
	H.Wipe(S.tally)
end

-- Какой ключ METER_RESET обнуляет счета (nil - любой).
function C.SetResetKey(key)
	S.resetKey = key
end

function C.Watch(owner, on)
	if on then
		if not S.watch[owner] then
			S.watch[owner] = true
			S.nWatch = S.nWatch + 1
		end
	elseif S.watch[owner] then
		S.watch[owner] = nil
		S.nWatch = S.nWatch - 1
	end
end

-- Прочитать новые события (до MAX_PAGES страниц). Возвращает число разобранных.
function C.Read()
	if type(AZS_GetCombatTextEvents) ~= "function" then
		return 0
	end
	local total = 0
	for page = 1, C.MAX_PAGES do
		local ok, r, e = pcall(AZS_GetCombatTextEvents, S.cursor, C.LIMIT)
		C.stats.reads = C.stats.reads + 1
		if not ok then
			H.Errors.Add("combattext", tostring(r))
			C.stats.errors = C.stats.errors + 1
			return total
		end
		if not r then
			C.stats.errors = C.stats.errors + 1
			C.stats.lastCode = e and e.code
			if e and e.code == "STREAM_CHANGED" then
				S.cursor = nil
			end
			return total
		end
		C.stats.pages = C.stats.pages + 1
		if r.streamId ~= S.streamId then
			S.streamId = r.streamId
		end
		if type(r.droppedCount) == "number" and r.droppedCount > 0 then
			C.stats.dropped = C.stats.dropped + r.droppedCount
		end
		local list = r.events or {}
		for i = 1, table.getn(list) do
			C.Feed(list[i])
		end
		total = total + table.getn(list)
		if r.cursor ~= nil then
			S.cursor = r.cursor
		end
		if not r.hasMore then
			break
		end
	end
	return total
end

--@frame
local function Tick()
	if S.nWatch > 0 then
		C.Read()
	end
end

local function OnMeterReset(ev, key)
	if S.resetKey == nil or key == nil or key == S.resetKey then
		C.ResetCounts()
	end
end

function C.Reset()
	S.cursor, S.streamId, S.resetKey = nil, nil, nil
	H.Wipe(S.watch)
	S.nWatch = 0
	H.Wipe(S.tally)
	C.stats.reads, C.stats.events, C.stats.errors, C.stats.dropped, C.stats.pages, C.stats.lastCode = 0, 0, 0, 0, 0, nil
end

function C.Start()
	H.Clock.Every("combattext", C.STEP, Tick)
end

H.Poll.AddLayer("combattext", C.Reset, C.Start)
H.On("METER_RESET", "combattext", OnMeterReset)
H.On("LOGIN", "combattext", C.Start)
