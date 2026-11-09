-- HyoukaUI: Core\Park, парковка стоковых кадров под скрытым родителем (plan 2.2).
--
-- H.Park(frame, owner) переносит кадр под скрытый кадр (SetParent), запоминая родителя, страту,
-- уровень и все точки привязки; H.Unpark(owner) возвращает все кадры владельца. Проба 0.2:
-- MainMenuBar под скрытым кадром исчезает с экрана, слоты 1-5 и 12 читаются (HasAction, текстура,
-- GetActionCooldown), способности идут сами, при /reload панель возвращается.
-- НЕ ПРОВЕРЕНО: вернется ли стоковая панель сама после уровня и карточек. Поэтому есть Reassert():
-- кадры, чей родитель перестал быть скрытым кадром, переносятся обратно под него. Он идет раз в
-- секунду, но только пока что-то запарковано (таймер стоит, пока парковок нет).
-- Гарантированные пути возврата: Unpark(owner), UnparkFrame(frame), на PLAYER_LOGOUT и на LOGOUT ядра
-- возвращается все (UnparkAll). Парковка нужна только модулю в режиме "Вместо" (в других режимах
-- кадры не трогаются). Прецедент в движке: AZS_HiddenBar (framexml_fixes.lua:169-173).
-- Счетчик H.counters.parks - число запаркованных кадров сейчас (его читает selftest).

local H = HyoukaUI

local K = {}
H.Parking = K

K.REASSERT_STEP = 1
K.stats = { reasserted = 0, parked = 0, unparked = 0 }

local hidden
local reg = {}      -- кадр -> запись
local list = {}     -- кадры по порядку
local timerOn = false

local function Hidden()
	if not hidden then
		hidden = CreateFrame("Frame", nil, UIParent)
		hidden:Hide()
	end
	return hidden
end

-- Скрытый кадр-родитель (создается при первой парковке).
function K.HiddenFrame()
	return hidden
end

--@frame
local function Tick()
	if table.getn(list) > 0 then
		K.Reassert()
	end
end

local function StartTimer()
	if not timerOn then
		timerOn = true
		H.Clock.Every("park", K.REASSERT_STEP, Tick)
	end
end

local function StopTimer()
	if timerOn then
		timerOn = false
		H.Clock.Stop("park")
	end
end

-- Запарковать кадр. true, если кадр теперь под скрытым родителем. Повтор тем же владельцем безвреден.
function K.Park(frame, owner)
	if type(frame) ~= "table" or frame == UIParent or not frame.SetParent or owner == nil then
		return false
	end
	local rec = reg[frame]
	if rec then
		if rec.owner ~= owner then
			return false
		end
		if frame:GetParent() ~= hidden then
			frame:SetParent(hidden)
		end
		return true
	end
	rec = { owner = owner, parent = frame:GetParent(), strata = frame:GetFrameStrata(),
		level = frame:GetFrameLevel(), points = {} }
	local n = frame:GetNumPoints() or 0
	for i = 1, n do
		local p, rel, rp, x, y = frame:GetPoint(i)
		rec.points[i] = { p, rel, rp, x, y }
	end
	reg[frame] = rec
	table.insert(list, frame)
	frame:SetParent(Hidden())
	H.counters.parks = H.counters.parks + 1
	K.stats.parked = K.stats.parked + 1
	StartTimer()
	return true
end

function K.IsParked(frame)
	return reg[frame] ~= nil
end

function K.Count()
	return table.getn(list)
end

-- Вернуть один кадр: родитель, страта, уровень, точки.
function K.UnparkFrame(frame)
	local rec = reg[frame]
	if not rec then
		return false
	end
	reg[frame] = nil
	for i = table.getn(list), 1, -1 do
		if list[i] == frame then
			table.remove(list, i)
		end
	end
	if rec.parent then
		frame:SetParent(rec.parent)
	end
	if rec.strata then
		frame:SetFrameStrata(rec.strata)
	end
	if rec.level then
		frame:SetFrameLevel(rec.level)
	end
	local n = table.getn(rec.points)
	if n > 0 then
		frame:ClearAllPoints()
		for i = 1, n do
			local p = rec.points[i]
			frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	end
	H.counters.parks = H.counters.parks - 1
	K.stats.unparked = K.stats.unparked + 1
	if table.getn(list) == 0 then
		StopTimer()
	end
	return true
end

-- Вернуть все кадры владельца. Возвращает число возвращенных.
function K.Unpark(owner)
	local n = 0
	for i = table.getn(list), 1, -1 do
		local frame = list[i]
		if frame and reg[frame] and reg[frame].owner == owner then
			if K.UnparkFrame(frame) then
				n = n + 1
			end
		end
	end
	return n
end

function K.UnparkAll()
	local n = 0
	for i = table.getn(list), 1, -1 do
		if list[i] and K.UnparkFrame(list[i]) then
			n = n + 1
		end
	end
	return n
end

-- Вернуть под скрытый родитель кадры, которые стоковый код перевесил. Возвращает число перенесенных.
function K.Reassert()
	local moved = 0
	for i = 1, table.getn(list) do
		local frame = list[i]
		if frame:GetParent() ~= hidden then
			frame:SetParent(hidden)
			moved = moved + 1
		end
	end
	K.stats.reasserted = K.stats.reasserted + moved
	return moved
end

-- Для отладки: имена запаркованных кадров ("<без имени>", если имени нет) с владельцами.
function K.Describe()
	local out = {}
	for i = 1, table.getn(list) do
		local f = list[i]
		table.insert(out, (f:GetName() or "<без имени>").." ("..tostring(reg[f].owner)..")")
	end
	return out
end

function H.Park(frame, owner)
	return K.Park(frame, owner)
end

function H.Unpark(owner)
	return K.Unpark(owner)
end

H.On("LOGOUT", "park", K.UnparkAll)
