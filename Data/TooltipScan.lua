-- HyoukaUI: Data\TooltipScan, чтение текста подсказок через один скрытый тултип (plan 2.2).
--
-- Тултип с глобальным именем HyoukaUI_ScanTip (шаблон GameTooltipTemplate, нужен для строк
-- HyoukaUI_ScanTipTextLeft1.. и ...TextRight1..) создается при первом чтении, не при загрузке.
-- Scan.Spell(slot) читает подсказку кнопки действия, Scan.Item(slot) подсказку предмета героя
-- клиента (SetInventoryItem). Результат: запись { n, left = {..}, right = {..} } или строка
-- "pending", если игра еще не отдала текст (предметы подгружаются асинхронно).
-- "Не готово" ставится в очередь повторов: лимит MAX_QUEUE записей, MAX_TRIES попыток раз в
-- RETRY секунд, потом запись снимается. Готовность объявляется событием SCAN_READY(kind, slot).
-- Кэш сбрасывается по SPELLS_CHANGED, LOADOUT_CHANGED и UNIT_INVENTORY_CHANGED.
-- Шаблоны string.find только ASCII; числа вытаскиваются по соседним словам (Scan.NumberAfter).

local H = HyoukaUI

local T = {}
H.TooltipScan = T

T.MAX_LINES = 30
T.MAX_QUEUE = 8
T.MAX_TRIES = 6
T.RETRY = 0.5

local tip
local cache = { spell = {}, item = {} }
local queue = {}      -- { kind, slot, tries }
local leftNames, rightNames = {}, {}
for i = 1, T.MAX_LINES do
	leftNames[i] = "HyoukaUI_ScanTipTextLeft"..i
	rightNames[i] = "HyoukaUI_ScanTipTextRight"..i
end
T.stats = { reads = 0, pending = 0, ready = 0, dropped = 0 }

-- Сам скрытый тултип (создается при первом вызове).
function T.Frame()
	if not tip then
		tip = CreateFrame("GameTooltip", "HyoukaUI_ScanTip", nil, "GameTooltipTemplate")
	end
	return tip
end

local function Text(names, i)
	local fs = H.Env[names[i]]
	if fs and fs.GetText then
		return fs:GetText()
	end
	return nil
end

-- Прочитать подсказку в запись rec. true, если текст есть.
local function Read(kind, slot, rec)
	local t = T.Frame()
	T.stats.reads = T.stats.reads + 1
	t:SetOwner(UIParent, "ANCHOR_NONE")
	t:ClearLines()
	if kind == "spell" then
		t:SetAction(slot)
	else
		t:SetInventoryItem("player", slot)
	end
	local n = t:NumLines() or 0
	if n > T.MAX_LINES then
		n = T.MAX_LINES
	end
	if n == 0 or Text(leftNames, 1) == nil then
		return false
	end
	rec.n = n
	for i = 1, n do
		rec.left[i] = Text(leftNames, i)
		rec.right[i] = Text(rightNames, i)
	end
	return true
end

local function Result(kind, slot)
	local rec = cache[kind][slot]
	if rec then
		return rec
	end
	rec = { n = 0, left = {}, right = {} }
	if Read(kind, slot, rec) then
		cache[kind][slot] = rec
		return rec
	end
	for i = 1, table.getn(queue) do
		if queue[i].kind == kind and queue[i].slot == slot then
			return "pending"
		end
	end
	if table.getn(queue) < T.MAX_QUEUE then
		table.insert(queue, { kind = kind, slot = slot, tries = 1 })
		T.stats.pending = T.stats.pending + 1
	end
	return "pending"
end

function T.Spell(slot)
	return Result("spell", slot)
end

function T.Item(slot)
	return Result("item", slot)
end

function T.QueueSize()
	return table.getn(queue)
end

-- Первая строка записи (левый текст), где сработал шаблон: индекс строки и до трех захватов.
function T.Grep(rec, pattern)
	if type(rec) ~= "table" then
		return nil
	end
	for i = 1, rec.n do
		local txt = rec.left[i]
		if txt then
			local s, e, a, b, c = string.find(txt, pattern)
			if s then
				return i, a, b, c
			end
		end
	end
	return nil
end

-- Число рядом с словом: первая строка, где есть слово (обычный поиск, любые буквы), и первое число
-- после него. Возвращает число и индекс строки. Подходит для текстов на любом языке игры.
function T.NumberAfter(rec, word)
	if type(rec) ~= "table" then
		return nil
	end
	for i = 1, rec.n do
		local txt = rec.left[i]
		if txt then
			local s, e = string.find(txt, word, 1, true)
			if s then
				local _, _, num = string.find(txt, "(%d+%.?%d*)", e + 1)
				if num then
					return tonumber(num), i
				end
			end
		end
	end
	return nil
end

function T.Invalidate()
	H.Wipe(cache.spell)
	H.Wipe(cache.item)
end

-- Очередь пуста - ничего не создается; повтор создает запись только пока есть "не готово".
local function Tick()
	local n = table.getn(queue)
	if n == 0 then
		return
	end
	for i = n, 1, -1 do
		local q = queue[i]
		local rec = { n = 0, left = {}, right = {} }
		q.tries = q.tries + 1
		if Read(q.kind, q.slot, rec) then
			cache[q.kind][q.slot] = rec
			table.remove(queue, i)
			T.stats.ready = T.stats.ready + 1
			H.Fire("SCAN_READY", q.kind, q.slot)
		elseif q.tries >= T.MAX_TRIES then
			table.remove(queue, i)
			T.stats.dropped = T.stats.dropped + 1
		end
	end
end

function T.Reset()
	T.Invalidate()
	H.Wipe(queue)
	T.stats.reads, T.stats.pending, T.stats.ready, T.stats.dropped = 0, 0, 0, 0
end

function T.Start()
	H.Clock.Every("tooltipscan", T.RETRY, Tick)
end

H.Poll.AddLayer("tooltipscan", T.Reset, T.Start)
H.On("SPELLS_CHANGED", "tooltipscan", T.Invalidate)
H.On("LOADOUT_CHANGED", "tooltipscan", T.Invalidate)
H.On("UNIT_INVENTORY_CHANGED", "tooltipscan", T.Invalidate)
H.On("LOGIN", "tooltipscan", T.Start)
