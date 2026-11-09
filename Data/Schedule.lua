-- HyoukaUI: Data\Schedule, расписание боссов, логова стражей, бесконечный режим (plan 2.2).
--
-- AZS_SCHEDULE: { index, at, name, final, state }, state = due | up | dead. at - секунда забега.
-- AZS_LAIRS: { index, state = asleep | awake | empty, name, id, left, x, y, z, mx, my, flag }.
-- События: SCHEDULE_CHANGED(n), BOSS_UP(index, name), BOSS_DEAD(index, name) (только переходы
-- между двумя увиденными состояниями: первая строка забега и строка после /reload событий не шлет),
-- LAIRS_CHANGED(n).
-- Допущение для проверки в игре: AZS_RUN.nb и AZS_RUN.left отсчитаны от часов забега AZS_RUN.t в
-- момент строки, поэтому текущее значение = значение минус (Run.Time() - AZS_RUN.t); lair.left
-- отсчитан от часов забега в момент строки логов.
-- Свежесть: расписание не старше строки зоны текущего забега (Run.IsFresh).

local H = HyoukaUI

local C = {}
H.Schedule = C

local EMPTY = {}
local S = { states = {}, lairT = nil }

function C.IsFresh()
	return H.Run.IsFresh(AZS_SCHEDULE_UPDATED)
end

-- Строки расписания (живая таблица движка) или пустой список, если данные не свежие. Только чтение.
function C.Lines()
	if C.IsFresh() then
		return AZS_SCHEDULE
	end
	return EMPTY
end

function C.Count()
	return table.getn(C.Lines())
end

function C.HasName(name)
	local list = C.Lines()
	for i = 1, table.getn(list) do
		if list[i].name == name then
			return true
		end
	end
	return false
end

-- Секунд до прихода строки (только для state == due) или nil.
function C.Left(line)
	if not line or line.state ~= "due" then
		return nil
	end
	local t = H.Run.Time()
	if not t then
		return nil
	end
	return line.at - t
end

-- Ближайший придущий босс: строка и секунды до него. В бесконечном режиме расписание замерло на
-- победе: строки нет, секунды до следующего босса из NextEndless.
function C.Next()
	if H.Run.IsEndless() then
		return nil, C.NextEndless()
	end
	local list = C.Lines()
	local best, bestLeft
	for i = 1, table.getn(list) do
		local line = list[i]
		if line.state == "due" then
			local left = C.Left(line)
			if left and (bestLeft == nil or left < bestLeft) then
				best, bestLeft = line, left
			end
		end
	end
	return best, bestLeft
end

-- Секунд до следующего босса в бесконечном режиме (AZS_RUN.nb, -1 = нет) или nil.
function C.NextEndless()
	local run = AZS_RUN
	local nb = run.nb
	if run.endl ~= 1 or type(nb) ~= "number" or nb < 0 then
		return nil
	end
	if run.ph == "playing" and AZS_RUN_UPDATED then
		nb = H.Run.SteadyEnd("nb", AZS_RUN_UPDATED + nb) - GetTime()
	end
	if nb < 0 then
		nb = 0
	end
	return nb
end

-- Полосы расписания: due-строки в горизонте horizon секунд (по умолчанию 120), по возрастанию
-- at, в массив out (очищается на месте). Возвращает число. Без таблиц на вызов.
function C.Bars(out, horizon)
	H.Wipe(out)
	horizon = horizon or H.Rules.scheduleHorizon
	local list = C.Lines()
	for i = 1, table.getn(list) do
		local line = list[i]
		local left = C.Left(line)
		if left and left <= horizon then
			-- вставка с сохранением порядка по at
			local pos = table.getn(out) + 1
			while pos > 1 and out[pos - 1].at > line.at do
				pos = pos - 1
			end
			table.insert(out, pos, line)
		end
	end
	return table.getn(out)
end

-- Полоса переезжает на выделенное место за relocateWithin (15) секунд до прихода.
function C.Relocating(line)
	local left = C.Left(line)
	return left ~= nil and left <= H.Rules.relocateWithin
end

-- Логова: живая таблица AZS_LAIRS (только чтение). У строки state asleep, awake или empty.
function C.Lairs()
	return AZS_LAIRS
end

function C.LairCount()
	return table.getn(AZS_LAIRS)
end

-- Логово, на которое указывает флажок миникарты, или nil.
function C.Flagged()
	local list = AZS_LAIRS
	for i = 1, table.getn(list) do
		if list[i].flag == 1 then
			return list[i]
		end
	end
	return nil
end

-- Секунд до возрождения стража в пустом логове i. Только в фазе playing (на паузе и выборе
-- карты часы стоят, audit tracker-25); иначе и для логова не в состоянии empty - nil.
function C.RespawnIn(i)
	local lair = AZS_LAIRS[i]
	if not lair or lair.state ~= "empty" or type(lair.left) ~= "number" then
		return nil
	end
	if AZS_RUN.ph ~= "playing" or not S.lairT then
		return nil
	end
	local t = H.Run.Time()
	if not t then
		return nil
	end
	local left = H.Run.SteadyEnd(i + 1000, H.Now() + lair.left - (t - S.lairT)) - H.Now()
	if left < 0 then
		left = 0
	end
	return left
end

----------------------------------------------------------------------------------------
-- Обновления
----------------------------------------------------------------------------------------

local function OnSchedule()
	if not C.IsFresh() then
		return
	end
	local list = AZS_SCHEDULE
	for i = 1, table.getn(list) do
		local line = list[i]
		local prev = S.states[line.index]
		if prev ~= nil and prev ~= line.state then
			if line.state == "up" then
				H.Fire("BOSS_UP", line.index, line.name)
			elseif line.state == "dead" then
				H.Fire("BOSS_DEAD", line.index, line.name)
			end
		end
		S.states[line.index] = line.state
	end
	H.Fire("SCHEDULE_CHANGED", table.getn(list))
end

local function OnLairs()
	S.lairT = H.Run.Time()
	H.Fire("LAIRS_CHANGED", table.getn(AZS_LAIRS))
end

local function OnRunStarted()
	H.Wipe(S.states)
end

function C.Reset()
	H.Wipe(S.states)
	S.lairT = nil
end

H.Poll.AddLayer("schedule", C.Reset)
H.On("SCHEDULE", "schedule", OnSchedule)
H.On("LAIRS", "schedule", OnLairs)
H.On("RUN_STARTED", "schedule", OnRunStarted)
