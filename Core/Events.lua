-- HyoukaUI: шина событий, Safe-вызовы с изоляцией модулей и часы (Clock).
--
-- H.On(event, owner, fn)   подписка; одна на пару (событие, владелец)
-- H.Off(event, owner)      снять; event = nil снимает все подписки владельца
-- H.Fire(event, a1..a4)    позиционные аргументы, без таблиц и без ...
-- H.Safe(owner, fn, a1..a4) pcall + счетчик ошибок модуля; порог ошибок выключает модуль
-- H.Script(owner, frame, name, fn)  скрипт кадра 1.12 через обертку (this/event/arg1 читает только она)
-- H.Clock.Every / After / OnFrame / Stop: один OnUpdate на весь аддон

local H = HyoukaUI

local getn = table.getn

H.Events = { threshold = 5, window = 10 }
local EV = H.Events

-- Стоковые события 1.12: идут через один кадр ядра под своими именами.
local STOCK = {
	ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
	PLAYER_LEAVING_WORLD = true, PLAYER_LOGOUT = true, PLAYER_TARGET_CHANGED = true,
	UNIT_HEALTH = true, UNIT_AURA = true, PLAYER_AURAS_CHANGED = true,
	UNIT_INVENTORY_CHANGED = true, ACTIONBAR_UPDATE_COOLDOWN = true,
	PARTY_MEMBERS_CHANGED = true, RAID_TARGET_UPDATE = true, CHAT_MSG_ADDON = true,
	UNIT_PORTRAIT_UPDATE = true, SPELLS_CHANGED = true,
}
EV.STOCK = STOCK

local subs = {}      -- event -> массив { owner, fn }
local depth = {}     -- event -> глубина текущей рассылки
local dirty = {}     -- event -> есть мертвые записи
local frame = CreateFrame("Frame", nil)

frame:SetScript("OnEvent", function()
	H.Fire(event, arg1, arg2, arg3, arg4)
end)

-- Убрать из массива мертвые записи. Только table.remove: в Lua 5.0 присваивание nil хвосту
-- не уменьшает table.getn, и массив с дырами ломает следующие обходы.
local function Compact(list)
	for i = getn(list), 1, -1 do
		if not list[i].fn then
			table.remove(list, i)
		end
	end
end

function H.On(event, owner, fn)
	local list = subs[event]
	if not list then
		list = {}
		subs[event] = list
	end
	for i = 1, getn(list) do
		local s = list[i]
		if s.owner == owner then
			s.fn = fn
			return
		end
	end
	table.insert(list, { owner = owner, fn = fn })
	if STOCK[event] then
		frame:RegisterEvent(event)
	end
end

local function OffOne(event, list, owner)
	local marked = false
	for i = getn(list), 1, -1 do
		local s = list[i]
		if s.owner == owner and s.fn then
			if (depth[event] or 0) > 0 then
				s.fn = false
				marked = true
			else
				table.remove(list, i)
			end
		end
	end
	if marked then
		dirty[event] = true
	end
end

function H.Off(event, owner)
	if event then
		local list = subs[event]
		if list then
			OffOne(event, list, owner)
		end
		return
	end
	for name, list in pairs(subs) do
		OffOne(name, list, owner)
	end
end

function H.Fire(event, a1, a2, a3, a4)
	local list = subs[event]
	if not list then
		return
	end
	depth[event] = (depth[event] or 0) + 1
	local n = getn(list)
	for i = 1, n do
		local s = list[i]
		local fn = s.fn
		if fn and not H.IsSuspended(s.owner) then
			local ok, err = pcall(fn, event, a1, a2, a3, a4)
			if not ok then
				H.ModuleError(s.owner, err)
			end
		end
	end
	depth[event] = depth[event] - 1
	if depth[event] == 0 and dirty[event] then
		dirty[event] = nil
		Compact(list)
	end
end

-- Сколько событий и подписок сейчас (для selftest).
function EV.Stats()
	local events, count = 0, 0
	for _, list in pairs(subs) do
		local live = 0
		for i = 1, getn(list) do
			if list[i].fn then
				live = live + 1
			end
		end
		if live > 0 then
			events = events + 1
			count = count + live
		end
	end
	return events, count
end

-- Имена событий с живыми подписками: массив строк (создает таблицы, для тестов и отладки). Нужен интеграционному тесту:
-- у каждой подписанной шины должен быть отправитель.
function EV.Subscribed()
	local out = {}
	for name, list in pairs(subs) do
		for i = 1, getn(list) do
			if list[i].fn then
				table.insert(out, name)
				break
			end
		end
	end
	table.sort(out)
	return out
end

-- Только для тестов: снять все подписки.
function EV.Reset()
	subs = {}
	depth = {}
	dirty = {}
end

-- Ошибка в обработчике модуля: в журнал, в счетчик, порог ошибок за окно выключает модуль.
function H.ModuleError(owner, err)
	H.Errors.Add(owner, err)
	local M = H.modules[owner]
	if not M then
		return
	end
	M.errors = M.errors + 1
	if M.internal then
		return
	end
	local now = H.Now()
	local times = M.errTimes
	for i = getn(times), 1, -1 do
		if now - times[i] > EV.window then
			table.remove(times, i)
		end
	end
	table.insert(times, now)
	if getn(times) >= EV.threshold then
		H.Suspend(owner, tostring(err))
	end
end

function H.Safe(owner, fn, a1, a2, a3, a4)
	local ok, result = pcall(fn, a1, a2, a3, a4)
	if not ok then
		H.ModuleError(owner, result)
	end
	return ok, result
end

-- Скрипт кадра через ядро. 1.12 отдает this/event/arg1.. глобалами; обертка передает их явно:
-- OnEvent: fn(frame, event, arg1, arg2); остальные: fn(frame, arg1, arg2, arg3).
function H.Script(owner, target, name, fn)
	if name == "OnEvent" then
		target:SetScript(name, function()
			H.Safe(owner, fn, this, event, arg1, arg2)
		end)
	else
		target:SetScript(name, function()
			H.Safe(owner, fn, this, arg1, arg2, arg3)
		end)
	end
end

----------------------------------------------------------------------------------------
-- Clock: один OnUpdate на весь аддон. Драйвер выключен, пока нет подписчиков.
----------------------------------------------------------------------------------------

local C = {}
H.Clock = C

local frameSubs = {}   -- { owner, fn, dead }
local timers = {}      -- { owner, period, left, fn, once, dead }
local driver
local running = false
local ticking = false
local sweepNeeded = false

local function Sweep(list)
	for i = getn(list), 1, -1 do
		if list[i].dead then
			table.remove(list, i)
		end
	end
end

--@frame
local function Tick(dt)
	ticking = true
	local n = getn(frameSubs)
	for i = 1, n do
		local s = frameSubs[i]
		if not s.dead and not H.IsSuspended(s.owner) then
			local ok, err = pcall(s.fn, dt)
			if not ok then
				H.ModuleError(s.owner, err)
			end
		end
	end
	n = getn(timers)
	for i = 1, n do
		local t = timers[i]
		if not t.dead and not H.IsSuspended(t.owner) then
			t.left = t.left - dt
			if t.left <= 0 then
				if t.once then
					t.dead = true
					sweepNeeded = true
				else
					t.left = t.left + t.period
					if t.left <= 0 then
						t.left = t.period
					end
				end
				local ok, err = pcall(t.fn, t.period)
				if not ok then
					H.ModuleError(t.owner, err)
				end
			end
		end
	end
	ticking = false
	if sweepNeeded then
		sweepNeeded = false
		Sweep(frameSubs)
		Sweep(timers)
		if getn(frameSubs) + getn(timers) == 0 and running then
			driver:SetScript("OnUpdate", nil)
			running = false
		end
	end
end
C.Tick = Tick

local function Ensure()
	if not driver then
		driver = CreateFrame("Frame", nil)
	end
	if not running then
		driver:SetScript("OnUpdate", function()
			Tick(arg1)
		end)
		running = true
	end
end

function C.OnFrame(owner, fn)
	for i = 1, getn(frameSubs) do
		local s = frameSubs[i]
		if not s.dead and s.owner == owner and s.fn == fn then
			return
		end
	end
	table.insert(frameSubs, { owner = owner, fn = fn })
	Ensure()
end

function C.Every(owner, period, fn)
	table.insert(timers, { owner = owner, period = period, left = period, fn = fn })
	Ensure()
end

function C.After(owner, delay, fn)
	table.insert(timers, { owner = owner, period = delay, left = delay, fn = fn, once = true })
	Ensure()
end

-- Снять все таймеры и покадровые колбэки владельца.
function C.Stop(owner)
	for i = 1, getn(frameSubs) do
		if frameSubs[i].owner == owner then
			frameSubs[i].dead = true
			sweepNeeded = true
		end
	end
	for i = 1, getn(timers) do
		if timers[i].owner == owner then
			timers[i].dead = true
			sweepNeeded = true
		end
	end
	if not ticking and sweepNeeded then
		sweepNeeded = false
		Sweep(frameSubs)
		Sweep(timers)
		if getn(frameSubs) + getn(timers) == 0 and running then
			driver:SetScript("OnUpdate", nil)
			running = false
		end
	end
end

-- Для отладки и тестов: владелец -> число живых подписчиков (создает таблицу, в кадре не звать).
function C.Owners()
	local out = {}
	for i = 1, getn(frameSubs) do
		if not frameSubs[i].dead then
			out[frameSubs[i].owner] = (out[frameSubs[i].owner] or 0) + 1
		end
	end
	for i = 1, getn(timers) do
		if not timers[i].dead then
			out[timers[i].owner] = (out[timers[i].owner] or 0) + 1
		end
	end
	return out
end

-- Живые подписчики: покадровые, таймеры, работает ли драйвер.
function C.Count()
	local nf, nt = 0, 0
	for i = 1, getn(frameSubs) do
		if not frameSubs[i].dead then
			nf = nf + 1
		end
	end
	for i = 1, getn(timers) do
		if not timers[i].dead then
			nt = nt + 1
		end
	end
	return nf, nt, running
end
