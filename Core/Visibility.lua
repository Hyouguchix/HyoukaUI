-- HyoukaUI: Core\Visibility, поведение кусков на экране выбора карточек (plan 2.2).
--
-- H.Vis.Register(frame, { overCards = bool, id = "имя куска" }):
--  * без overCards кусок прячется, пока фаза "choosing" (выбор карты при повышении уровня), и
--    возвращается на выходе (прячем и возвращаем только то, что скрыли мы);
--  * с overCards кусок остается и передается движку: AZS_SetOnTopOfScreens(имя, true) держит кадр и
--    его детей поверх затемнения карточек с кликами.
-- AZS_SetOnTopOfScreens принимает кадр или СТРОКУ с его глобальным именем, у кадра без глобального
-- имени бросает error: мы отдаем имя и вызываем под pcall, кадр без имени остается без передачи
-- (счет в stats.noName), исключения нет. Имена кадров только из списка H.FRAME_NAMES.
-- ОТКЛОНЕНИЕ ОТ ПЛАНА (раздел 2.2): план говорит "передаются в AZS_SetOnTopOfScreens и снимаются при
-- выходе из фазы". Игра читает AZS_ON_TOP_FRAMES в момент открытия карточек, а фазу "choosing" мы
-- видим на кадр позже, поэтому кусок с overCards передается сразу при Register и снимается только
-- при Unregister; на экране без карточек флаг ни на что не влияет. [НЕ ПРОВЕРЕНО в игре.]
-- Подсказки (GameTooltip, у него глобальное имя есть) передаются, пока зарегистрирован хотя бы
-- один кусок с overCards (подсказки строк сборки иначе уйдут под затемнение).
-- Фаза "choosing" - единственный признак карточек; экран карточек бижутерии отдельной фазой не
-- подтвержден. [НЕ ПРОВЕРЕНО]
-- Событие CARDS(shown) на входе и выходе из фазы.

local H = HyoukaUI

local V = {}
H.Vis = V

local entries = {}      -- { frame, overCards, id, hid }
local choosing = false
local tooltipOn = false
V.stats = { noName = 0, errors = 0, hides = 0 }

local function NameOf(frame)
	if type(frame) == "string" then
		return frame
	end
	if type(frame) == "table" and frame.GetName then
		return frame:GetName()
	end
	return nil
end

local function SetTop(frame, on)
	if not AZS_SetOnTopOfScreens then
		return false
	end
	local name = NameOf(frame)
	if type(name) ~= "string" or name == "" then
		V.stats.noName = V.stats.noName + 1
		return false
	end
	local ok, err = pcall(AZS_SetOnTopOfScreens, name, on)
	if not ok then
		V.stats.errors = V.stats.errors + 1
		H.Errors.Add("vis", tostring(err))
		return false
	end
	return true
end

local function UpdateTooltip()
	local any = false
	for i = 1, table.getn(entries) do
		if entries[i].overCards then
			any = true
		end
	end
	if any ~= tooltipOn then
		tooltipOn = any
		SetTop("GameTooltip", any)
	end
end

local function Find(frame)
	for i = 1, table.getn(entries) do
		if entries[i].frame == frame then
			return i
		end
	end
	return nil
end

local function HideNow(e)
	if e.frame:IsShown() then
		e.frame:Hide()
		e.hid = true
		V.stats.hides = V.stats.hides + 1
	end
end

local function ShowBack(e)
	if e.hid then
		e.hid = false
		e.frame:Show()
	end
end

function V.Register(frame, opts)
	if frame == nil then
		return false
	end
	local overCards = opts ~= nil and opts.overCards and true or false
	local i = Find(frame)
	local e
	if i then
		e = entries[i]
		if e.overCards and not overCards then
			SetTop(frame, false)
		end
		e.overCards = overCards
	else
		e = { frame = frame, overCards = overCards, id = opts and opts.id, hid = false }
		table.insert(entries, e)
	end
	if overCards then
		SetTop(frame, true)
		ShowBack(e)
	elseif choosing then
		HideNow(e)
	end
	UpdateTooltip()
	return true
end

function V.Unregister(frame)
	local i = Find(frame)
	if not i then
		return false
	end
	local e = entries[i]
	table.remove(entries, i)
	ShowBack(e)
	if e.overCards then
		SetTop(frame, false)
	end
	UpdateTooltip()
	return true
end

function V.Count()
	return table.getn(entries)
end

function V.IsChoosing()
	return choosing
end

local function OnPhase(ev, new)
	local now = (new == "choosing")
	if now == choosing then
		return
	end
	choosing = now
	for i = 1, table.getn(entries) do
		local e = entries[i]
		if not e.overCards then
			if choosing then
				HideNow(e)
			else
				ShowBack(e)
			end
		end
	end
	H.Fire("CARDS", choosing)
end

function V.Reset()
	for i = table.getn(entries), 1, -1 do
		V.Unregister(entries[i].frame)
	end
	choosing = false
	V.stats.noName, V.stats.errors, V.stats.hides = 0, 0, 0
end

H.Poll.AddLayer("vis", V.Reset)
H.On("PHASE_CHANGED", "vis", OnPhase)
H.On("LOGOUT", "vis", function()
	for i = 1, table.getn(entries) do
		ShowBack(entries[i])
	end
end)
