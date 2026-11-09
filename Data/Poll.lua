-- HyoukaUI: Data\Poll, единственный опросчик меток *_UPDATED (plan 2.2). Больше нигде в аддоне
-- метки не читаются.
--
-- ИДЕЯ. Движок разбирает строку сервера и ставит глобал AZS_X и метку AZS_X_UPDATED = GetTime().
-- Событий у движка нет. Порядок обработчиков CHAT_MSG_ADDON (наш против AZSApiFrame) не проверен
-- в игре (проба 0.5), поэтому от него ничего не зависит: на сообщение с префиксом AZS* мы только
-- ставим флаг, а сами метки сравниваем в следующем кадре. Кроме того, раз в SAMPLE_STEP (0.2 с,
-- шаг движка AZS_ML_STEP) метки сравниваются и без сообщений: страховка.
-- На каждую изменившуюся метку - одно событие, без таблиц. Нет смены - нет событий.
--
-- СОБЫТИЯ (H.On(event, owner, fn); fn(event, a1, a2, a3, a4)):
--  Сырые, от Poll, аргумент stamp (новое значение метки). Порядок рассылки = порядок STAMPS ниже:
--   ZONE RUN END REVIVE SCHEDULE UNITS DEBUFFS TARGET SPELLS TIMERS BUFFS PETS TOTEMS METER
--   HEALING BOSSMETER PARTY DOWNED CHESTS LAIRS TAKEN
--   BANNER(banner)  - от AZS_RegisterBannerHandler, один раз на баннер, не метка.
--  Производные, их шлют слои после разбора (читать данные через API слоя; "_CHANGED" в имени):
--   Run:      RUN_STARTED(runId, oldRunId)  RUN_ENDED(result, runId)  RUN_LEFT(oldRunId)
--             PHASE_CHANGED(new, old)  LEVEL_CHANGED(lvl, stored)
--   Hero:     HERO_CHANGED(classKey, heroName)
--   Party:    PARTY_CHANGED(n)  DOWN_CHANGED(down)  DOWNED_CHANGED(n)
--   Units:    UNITS_CHANGED(n)  UNIT_GONE(id, kind, name)
--   Schedule: SCHEDULE_CHANGED(n)  BOSS_UP(index, name)  BOSS_DEAD(index, name)  LAIRS_CHANGED(n)
--   Spells:   SPELLS_CHANGED(n)      только состав: ключи, ранги, число (кулдауны идут в сыром SPELLS)
--   Buffs:    BUFFS_CHANGED(n)
--   Loadout:  LOADOUT_CHANGED(ownerId, revision)
--   MeterData: METER_CHANGED(counterRevision)  METER_RESET(queryKey)
--   TooltipScan: SCAN_READY(kind, slot)   CombatText: COMBAT_EVENT(kind, amount, critical, source)
--   Visibility: CARDS(shown)
--   Hud:      HUD_CHANGED(part, hidden)
--  Отличия от таблицы 2.3 плана: PHASE -> PHASE_CHANGED, HERO -> HERO_CHANGED, LEVEL -> LEVEL_CHANGED,
--  DOWN -> DOWN_CHANGED, LOADOUT -> LOADOUT_CHANGED, METER_REV -> METER_CHANGED (единый суффикс).
--
-- СЛОЙ ДАННЫХ в целом: читает AZS_* только Data\* (и Hud, Visibility). Модули (Modules\) глобалов
-- AZS_ не видят (lint azs-in-module). Каждый слой отдает функции, а не сырые таблицы.

local H = HyoukaUI

local P = {}
H.Poll = P

P.SAMPLE_STEP = 0.2

-- Описания: { имя события, имя метки }. Массивы, не таблицы-описания: тик ничего не создает.
local EVENTS = { "ZONE", "RUN", "END", "REVIVE", "SCHEDULE", "UNITS", "DEBUFFS", "TARGET", "SPELLS",
	"TIMERS", "BUFFS", "PETS", "TOTEMS", "METER", "HEALING", "BOSSMETER", "PARTY", "DOWNED", "CHESTS",
	"LAIRS", "TAKEN" }
local STAMPS = {}
for i = 1, table.getn(EVENTS) do
	STAMPS[i] = "AZS_"..EVENTS[i].."_UPDATED"
end
P.EVENTS = EVENTS
P.STAMPS = STAMPS
local N = table.getn(EVENTS)

local env = H.Env
local last = {}          -- последняя увиденная метка по индексу
local dirty = false
local acc = 0
local started = false

local RING = 8
local ringName, ringStamp = {}, {}
local ringPos = 0

P.stats = { samples = 0, events = 0, messages = 0, seen = 0 }
local layers = {}        -- { name, reset, start }: слои регистрируют сброс и запуск часов

-- Слой регистрирует сброс своего состояния (H.DataReset) и запуск своих часов (H.DataStart).
-- Имя слоя = владелец его таймеров в Clock: H.DataStop снимает их по имени.
function P.AddLayer(name, resetFn, startFn)
	table.insert(layers, { name = name, reset = resetFn, start = startFn })
end

--@frame
local function Sample()
	local stats = P.stats
	stats.samples = stats.samples + 1
	for i = 1, N do
		local v = env[STAMPS[i]]
		if v ~= last[i] then
			if last[i] == nil then
				stats.seen = stats.seen + 1
			end
			last[i] = v
			if v ~= nil then
				stats.events = stats.events + 1
				ringPos = ringPos + 1
				if ringPos > RING then
					ringPos = 1
				end
				ringName[ringPos] = EVENTS[i]
				ringStamp[ringPos] = v
				H.Fire(EVENTS[i], v)
			end
		end
	end
end
P.Sample = Sample

--@frame
local function Frame(dt)
	acc = acc + dt
	if dirty or acc >= P.SAMPLE_STEP then
		dirty = false
		acc = 0
		Sample()
	end
end

local function OnMessage(ev, prefix)
	if type(prefix) == "string" and string.sub(prefix, 1, 3) == "AZS" then
		dirty = true
		P.stats.messages = P.stats.messages + 1
	end
end

local function OnBanner(banner)
	H.Fire("BANNER", banner)
end

function P.Start()
	if started then
		return
	end
	started = true
	H.On("CHAT_MSG_ADDON", "poll", OnMessage)
	H.Clock.OnFrame("poll", Frame)
	if AZS_RegisterBannerHandler then
		pcall(AZS_RegisterBannerHandler, OnBanner)
	end
	-- Метки, уже существующие к этому моменту (аддон поднялся после данных), пройдут как новые
	-- при первом кадре: last пуст.
	dirty = true
end

function P.IsStarted()
	return started
end

-- Снять опрос и подписку на кадры (тесты, отладка). Start запускает заново.
function P.Stop()
	H.Clock.Stop("poll")
	started = false
end

-- Сколько меток видели с начала сессии (из 21).
function P.SeenCount()
	return P.stats.seen
end

-- Последние события: строки "ИМЯ@метка" от старых к новым. Вызывать из отладки, не из кадра.
function P.LastEvents()
	local out = {}
	for i = 1, RING do
		local pos = ringPos + i
		if pos > RING then
			pos = pos - RING
		end
		if ringName[pos] then
			table.insert(out, ringName[pos].."@"..string.format("%.2f", ringStamp[pos]))
		end
	end
	return out
end

-- Видна ли метка (для dump): индекс по имени события.
function P.LastStamp(event)
	for i = 1, N do
		if EVENTS[i] == event then
			return last[i]
		end
	end
	return nil
end

-- Сбросить опрос: следующий кадр заново пройдет по всем существующим меткам. Слои сброшены отдельно.
function P.Reset()
	for i = 1, N do
		last[i] = nil
	end
	for i = 1, RING do
		ringName[i] = nil
		ringStamp[i] = nil
	end
	ringPos = 0
	dirty = true       -- ближайший кадр заново пройдет по всем меткам
	acc = 0
	P.stats.samples, P.stats.events, P.stats.messages, P.stats.seen = 0, 0, 0, 0
end

-- Сбросить все слои данных и опрос (тесты, смена мира). Глобалы AZS_* не трогает.
function H.DataReset()
	for i = 1, table.getn(layers) do
		if layers[i].reset then
			layers[i].reset()
		end
	end
	P.Reset()
end

-- Остановить все часы слоев данных (Poll и таймеры слоев). Только для тестов и отладки.
function H.DataStop()
	P.Stop()
	for i = 1, table.getn(layers) do
		H.Clock.Stop(layers[i].name)
	end
end

-- Запустить часы слоев заново (после DataStop).
function H.DataStart()
	P.Start()
	for i = 1, table.getn(layers) do
		if layers[i].start then
			layers[i].start()
		end
	end
end

H.On("LOGIN", "poll", P.Start)
