-- HyoukaUI: Modules\Tracker\Tally, панель итогов забега tr.tally: убийства, золото, сундуки (plan 3.2, tracker#9).
--
-- Раньше это была строка внизу панели tr.tracker: подписи и числа сливались ("Убийства 33Золото 256/31 Сундуки 1").
-- Теперь отдельная плоская панель того же вида (фон 0.85, рамка 1 физический пиксель) прямо под tr.tracker, той же
-- ширины, высотой 22 ретейл-px. Три ячейки с тонкими разделителями: подпись серая, число белое; золото при
-- достаточной сумме на сундук золотое. Данные те же (H.Run.Get kills, gold, chest, ck), по событию RUN, без опроса.
-- Режим Вместо: часть игры tally закрывается самим существованием этого куска (Claims: { "tally", "tr.tally", "tally" }).
-- В фазе выбора карт панель скрыта вместе с остальными кусками (Visibility, Tr.Set).

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local PW = 230
local SEP = { 0.31, 0.31, 0.31, 0.9 }

local TY = { cells = {}, seps = {} }
Tr.Tally = TY

local function R(px)
	return H.R(px)
end

-- Три равные ячейки: подпись сверху, значение снизу, оба по центру ячейки (решение пользователя 2026-11-09 после
-- скриншота: в одну строку фиксированные ширины резали числа разделителем). Места считаются от ширины панели,
-- вызывается при сборке и смене размера пикселя, не покадрово.
local function Layout()
	local panel = TY.panel
	if not panel then
		return
	end
	local pw = panel:GetWidth() or 0
	if pw <= 0 then
		pw = R(PW)
	end
	local third = pw / 3
	for i = 1, 3 do
		local cell = TY.cells[i]
		local cx = third * (i - 0.5)
		cell.label:ClearAllPoints()
		cell.label:SetPoint("TOP", panel, "TOPLEFT", cx, -R(5))
		cell.val:ClearAllPoints()
		cell.val:SetPoint("BOTTOM", panel, "BOTTOMLEFT", cx, R(5))
		local sep = TY.seps[i]
		if sep then
			sep:ClearAllPoints()
			sep:SetPoint("TOPLEFT", panel, "TOPLEFT", third * i, -R(4))
			sep:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", third * i, R(4))
			sep:SetWidth(H.Theme.Px(1))
		end
	end
end

local function Refresh()
	if not TY.panel then
		return
	end
	local run = H.Run
	local kills, gold, chest, opened = run.Get("kills") or 0, run.Get("gold") or 0, run.Get("chest"), run.Get("ck") or 0
	if kills ~= TY.tk then
		TY.tk = kills
		TY.cells[1].val:SetText(Fm.Short(kills))
	end
	if gold ~= TY.tg or chest ~= TY.tc then
		TY.tg, TY.tc = gold, chest
		local txt = Fm.Short(gold)
		local enough = false
		if type(chest) == "number" and chest > 0 then
			txt = txt.."/"..Fm.Short(chest)
			enough = gold >= chest
		end
		TY.cells[2].val:SetText(txt)
		Tr.Color(TY.cells[2].val, enough and Tr.C.gold or Tr.C.white)
	end
	if opened ~= TY.to then
		TY.to = opened
		TY.cells[3].val:SetText(Fm.Int(opened))
	end
end

local KEYS = { "kills", "gold", "chests" }

local function Labels()
	for i = 1, 3 do
		TY.cells[i].label:SetText(Tr.T(KEYS[i]))
	end
end

local function Build()
	PW = Tr.Def("tr.tally", "w", PW)
	local panel = CreateFrame("Frame", nil, UIParent)
	panel:SetFrameStrata("MEDIUM")
	TY.panel = panel
	TY.bg = K.Fill(panel, "bg", "BACKGROUND")
	TY.border = K.Border(panel, "edge")
	for i = 1, 3 do
		local label = K.Text(panel, "small", nil, "CENTER")
		Tr.Color(label, Tr.C.gray)
		local val = K.Text(panel, "body", nil, "CENTER")
		Tr.Color(val, Tr.C.white)
		TY.cells[i] = { label = label, val = val }
		if i < 3 then
			TY.seps[i] = Tr.Fill(panel, SEP, "ARTWORK")
		end
	end
	Labels()
	Layout()
end

local function Place()
	if not TY.panel then
		return
	end
	Tr.Set(TY.panel, Tr.Opt("tally") and Tr.InRun())
end

Tr.Part("tally", {
	build = Build,
	show = function()
		Tr.Register("tr.tally", TY.panel)
	end,
	refresh = function()
		Labels()
		Refresh()
	end,
	place = Place,
	theme = Layout,
	reset = function()
		-- false, не nil: пустое новое значение должно отличаться от сброшенного кэша и перерисоваться.
		TY.tk, TY.tg, TY.tc, TY.to = false, false, false, false
	end,
	on = { RUN = Refresh, LEVEL_CHANGED = Refresh, LOCALE = Labels },
	dump = function(out)
		local c = TY.cells
		table.insert(out, "итоги: показана "..tostring(TY.panel and TY.panel:IsShown()).."  "
			..tostring(c[1] and c[1].val:GetText()).." / "..tostring(c[2] and c[2].val:GetText()).." / "..tostring(c[3] and c[3].val:GetText()))
	end,
})
