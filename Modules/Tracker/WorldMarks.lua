-- HyoukaUI: Modules\Tracker\WorldMarks, часть "worldmarks" модуля Трекер: метки в 3D-мире над сундуками, боссами, логовами
-- и стрелки у края экрана на цели за кадром (как у SurvivorUI WorldMarks.lua). Рисует WorldMarksView.lua, данные
-- (экранные точки, расстояния) отдает слой проекции H.Proj (Data\Projection.lua): модуль глобалов AZS_* не читает.
--
-- Режимы (Hub): Выкл - кадров нет; Рядом и Вместо одинаково рисуем метки, ничего у игры не забирая (Claim "flag" в плане
-- v1 не трогается). Метки показаны, пока идет забег (фаза playing): на выборе карт (Visibility), на паузе, в лобби и
-- вне забега их нет, слой проекции в это время не просит у движка ничего. Метки мышь не берут.
--
-- Настройки (ключи tracker, префикс wm): значения по умолчанию добавляются в таблицу умолчаний модуля при загрузке файла
-- (H.DB.defaults.tracker), страница настроек "Метки в мире" (порядок 41) регистрируется здесь же.
--
-- Публичное: Tr.Marks.O (рассчитанные настройки), Tr.Marks.Apply(), Tr.Marks.Place(), Tr.Marks.live, Tr.Marks.Dump(out).

local H = HyoukaUI

local Tr = H.Tr
local M = Tr.M
local Proj = H.Proj
local K = H.Kit

local getn = table.getn

local WM = Tr.Marks or {}
Tr.Marks = WM

local V = WM.View
local OWNER = "tr.marks"
local YD_TO_M = 0.9144
local BEAM_YARDS = 2.4

----------------------------------------------------------------------------------------
-- Настройки: умолчания и строки
----------------------------------------------------------------------------------------

WM.DEF = {
	wm = true, wmChest = true, wmBoss = true, wmLair = true, wmElite = false, wmOther = true,
	wmArrows = true, wmBeam = true, wmNames = true, wmDist = true, wmFade = true, wmScale = true,
	wmUnit = "m", wmMax = 250, wmMin = 4, wmAlpha = 100, wmIcon = 20, wmFont = 0, wmBeamW = 100, wmBeamH = 6,
	wmArrowSize = 28, wmInset = 70, wmMaxArrows = 4,
}

do
	local d = H.DB.defaults and H.DB.defaults.tracker
	if d then
		for k, v in pairs(WM.DEF) do
			if d[k] == nil then
				d[k] = v
			end
		end
	end
end

local STR = Tr.STR
STR.ruRU.wm_label = "Метки в мире"
STR.ruRU.wm_m, STR.ruRU.wm_yd = "м", "яр"
STR.ruRU.wm_on, STR.ruRU.wm_h_kinds, STR.ruRU.wm_h_look = "Показывать метки в мире", "Что отмечать", "Вид"
STR.ruRU.wm_chest, STR.ruRU.wm_boss, STR.ruRU.wm_lair = "Сундуки", "Боссы", "Логова и стражи"
STR.ruRU.wm_elite, STR.ruRU.wm_other = "Элитные враги", "Упавшие союзники"
STR.ruRU.wm_beam, STR.ruRU.wm_arrows, STR.ruRU.wm_names = "Луч света над сундуком", "Стрелки у края экрана", "Названия"
STR.ruRU.wm_dist, STR.ruRU.wm_fade, STR.ruRU.wm_scale = "Расстояние", "Затухание с расстоянием", "Уменьшать вдали"
STR.ruRU.wm_unit, STR.ruRU.wm_u_m, STR.ruRU.wm_u_yd = "Единицы расстояния", "Метры", "Ярды"
STR.ruRU.wm_h_dist, STR.ruRU.wm_max, STR.ruRU.wm_min = "Дальность", "Предел показа", "Прятать ближе"
STR.ruRU.wm_h_size, STR.ruRU.wm_icon, STR.ruRU.wm_font = "Размеры", "Значок", "Текст, поправка к размеру"
STR.ruRU.wm_beam_w, STR.ruRU.wm_beam_h, STR.ruRU.wm_arrow = "Ширина луча, %", "Высота луча, ярды", "Стрелка"
STR.ruRU.wm_inset, STR.ruRU.wm_arrows_n, STR.ruRU.wm_alpha = "Отступ стрелок от края", "Стрелок не больше", "Непрозрачность, %"
STR.ruRU.wm_nolimit = "без предела"
STR.ruRU.wm_note = "Метки не берут мышь и видны только в идущем забеге. Движок отдает расстояние в ярдах, метры пересчитываются (1 яр = 0.9144 м)."

STR.enUS.wm_label = "World marks"
STR.enUS.wm_m, STR.enUS.wm_yd = "m", "yd"
STR.enUS.wm_on, STR.enUS.wm_h_kinds, STR.enUS.wm_h_look = "Show marks in the world", "What to mark", "Look"
STR.enUS.wm_chest, STR.enUS.wm_boss, STR.enUS.wm_lair = "Chests", "Bosses", "Lairs and guardians"
STR.enUS.wm_elite, STR.enUS.wm_other = "Elite enemies", "Downed allies"
STR.enUS.wm_beam, STR.enUS.wm_arrows, STR.enUS.wm_names = "Light beam over chests", "Arrows at the screen edge", "Names"
STR.enUS.wm_dist, STR.enUS.wm_fade, STR.enUS.wm_scale = "Distance", "Fade with distance", "Shrink when far"
STR.enUS.wm_unit, STR.enUS.wm_u_m, STR.enUS.wm_u_yd = "Distance unit", "Meters", "Yards"
STR.enUS.wm_h_dist, STR.enUS.wm_max, STR.enUS.wm_min = "Range", "Maximum distance", "Hide when closer than"
STR.enUS.wm_h_size, STR.enUS.wm_icon, STR.enUS.wm_font = "Sizes", "Icon", "Text size offset"
STR.enUS.wm_beam_w, STR.enUS.wm_beam_h, STR.enUS.wm_arrow = "Beam width, %", "Beam height, yards", "Arrow"
STR.enUS.wm_inset, STR.enUS.wm_arrows_n, STR.enUS.wm_alpha = "Arrow inset from the edge", "Arrows at most", "Opacity, %"
STR.enUS.wm_nolimit = "no limit"
STR.enUS.wm_note = "Marks never take the mouse and show only during a run. The engine reports distance in yards, meters are converted (1 yd = 0.9144 m)."

----------------------------------------------------------------------------------------
-- Рассчитанные настройки (числа и таблицы: покадровый код не ходит в M.db)
----------------------------------------------------------------------------------------

local O = {
	kind = { chest = true, boss = true, lair = true, elite = false, other = true },
	arrowKind = { chest = true, boss = true, lair = true, elite = false, other = true },
	master = true, arrows = true, names = true, dist = true, beam = true, fade = true, scale = true,
	unit = "m", factor = YD_TO_M, minD = 4, maxD = 250, alpha = 1, icon = 10, fontDelta = 0, beamW = BEAM_YARDS,
	beamTall = 6, arrowSize = 14, inset = 40, maxArrows = 4, px = 0.5926, ipx = 1 / 0.5926,
}
WM.O = O
WM.live = false
WM.enabled = false

local spec = { kinds = O.kind, arrows = O.arrowKind, maxArrows = 4, beam = 6, maxDist = 0 }
WM.spec = spec

local function Db(key)
	return M.db[key]
end

function WM.Apply()
	O.master, O.arrows, O.names, O.dist = Db("wm"), Db("wmArrows"), Db("wmNames"), Db("wmDist")
	O.beam, O.fade, O.scale = Db("wmBeam"), Db("wmFade"), Db("wmScale")
	O.kind.chest, O.kind.boss, O.kind.lair = Db("wmChest"), Db("wmBoss"), Db("wmLair")
	O.kind.elite, O.kind.other = Db("wmElite"), Db("wmOther")
	O.arrowKind.chest = O.arrows and O.kind.chest
	O.arrowKind.boss = O.arrows and O.kind.boss
	O.arrowKind.lair = O.arrows and O.kind.lair
	O.arrowKind.other = O.arrows and O.kind.other
	O.arrowKind.elite = false
	O.unit = Db("wmUnit") == "yd" and "yd" or "m"
	O.factor = O.unit == "yd" and 1 or YD_TO_M
	O.maxD, O.minD = Db("wmMax"), Db("wmMin")
	O.alpha = Db("wmAlpha") / 100
	O.icon, O.arrowSize, O.inset = H.R(Db("wmIcon")), H.R(Db("wmArrowSize")), H.R(Db("wmInset"))
	O.fontDelta = Db("wmFont")
	O.beamW = BEAM_YARDS * Db("wmBeamW") / 100
	O.beamTall = Db("wmBeamH")
	O.maxArrows = Db("wmMaxArrows")
	O.px = H.Theme.PX
	O.ipx = 1 / O.px
	spec.maxArrows = O.arrows and O.maxArrows or 0
	spec.beam = O.beam and O.beamTall or 0
	spec.maxDist = O.maxD > 0 and O.maxD / O.factor or 0
	if V and V.layer then
		V.Restyle()
	end
	if WM.live then
		Proj.Want(OWNER, spec)
	end
end

----------------------------------------------------------------------------------------
-- Видимость: слой проекции просят только пока метки есть чем показывать
----------------------------------------------------------------------------------------

local part

function WM.OnProject()
	if not V.layer:IsVisible() then
		return
	end
	local ok, err = pcall(V.Paint)
	if not ok then
		Tr.Fail(part, err)
	end
end

local function WantLive()
	if not (WM.enabled and O.master and Proj.Available()) then
		return false
	end
	if H.Run.Phase() ~= "playing" then
		return false
	end
	return not (H.Vis and H.Vis.IsChoosing())
end

function WM.Place()
	if not V.layer then
		return
	end
	local live = WantLive()
	if live == WM.live then
		return
	end
	WM.live = live
	if live then
		Tr.Set(V.layer, true)
		Proj.Subscribe(OWNER, WM.OnProject)
		Proj.Want(OWNER, spec)
	else
		Proj.Want(OWNER, nil)
		Proj.Unsubscribe(OWNER)
		V.Clear()
		Tr.Set(V.layer, false)
	end
end

----------------------------------------------------------------------------------------
-- Часть модуля
----------------------------------------------------------------------------------------

part = Tr.Part("worldmarks", {
	build = function()
		V.Build()
		WM.Apply()
	end,
	show = function()
		WM.enabled = true
		WM.Apply()
		if V.layer then
			H.Vis.Register(V.layer, { id = "tr.worldmarks" })
		end
		WM.Place()
	end,
	hide = function()
		WM.enabled = false
		WM.Place()
		if V.layer then
			H.Vis.Unregister(V.layer)
			V.layer:Hide()
		end
	end,
	place = function()
		WM.Place()
	end,
	refresh = function()
		WM.Apply()
		WM.Place()
	end,
	dump = function(out)
		WM.Dump(out)
	end,
})

function WM.Dump(out)
	table.insert(out, "== Метки в мире ==")
	table.insert(out, "включены "..tostring(WM.enabled).."  живые "..tostring(WM.live).."  кадров меток "..getn(V.marks)
		.."  стрелок "..getn(V.arrows).."  показано "..V.shownMarks.." и "..V.shownArrows
		.."  единицы "..O.unit.."  предел "..O.maxD.."  ближе "..O.minD)
	local n, reads, passes, lastReq, maxReq, errors, lastErr = Proj.Stats()
	table.insert(out, "== Проекция якорей ==")
	table.insert(out, "доступна "..tostring(Proj.Available()).."  записей "..n.."  чтений каталога "..reads.."  проходов "..passes
		.."  запросов в кадре "..lastReq.." (наибольшее "..maxReq..")  ошибок "..errors.."  последняя "..tostring(lastErr))
end

----------------------------------------------------------------------------------------
-- Страница настроек
----------------------------------------------------------------------------------------

local function Opt(key, label)
	return { label = Tr.T(label), mod = "tracker", key = key }
end

local function Slide(key, label, lo, hi, step, fmt)
	local s = Opt(key, label)
	s.min, s.max, s.step = lo, hi, step
	s.fmt = fmt or function(v)
		return tostring(v)
	end
	return s
end

local function Limit(v)
	if v == 0 then
		return Tr.T("wm_nolimit")
	end
	return tostring(v)
end

local function BuildPage(page, f)
	f:Header(Tr.T("wm_label"))
	f:Toggle(Opt("wm", "wm_on"))
	f:Gap(4)
	f:Header(Tr.T("wm_h_kinds"))
	f:Toggle(Opt("wmChest", "wm_chest"))
	f:Toggle(Opt("wmBoss", "wm_boss"))
	f:Toggle(Opt("wmLair", "wm_lair"))
	f:Toggle(Opt("wmElite", "wm_elite"))
	f:Toggle(Opt("wmOther", "wm_other"))
	f:Gap(4)
	f:Header(Tr.T("wm_h_look"))
	f:Toggle(Opt("wmBeam", "wm_beam"))
	f:Toggle(Opt("wmArrows", "wm_arrows"))
	f:Toggle(Opt("wmNames", "wm_names"))
	f:Toggle(Opt("wmDist", "wm_dist"))
	f:Toggle(Opt("wmFade", "wm_fade"))
	f:Toggle(Opt("wmScale", "wm_scale"))
	f:Segment({ label = Tr.T("wm_unit"), bw = 50,
		options = { { value = "m", label = Tr.T("wm_u_m") }, { value = "yd", label = Tr.T("wm_u_yd") } },
		get = function()
			return H.DB.Get("tracker", "wmUnit")
		end,
		set = function(v)
			H.DB.Set("tracker", "wmUnit", v)
		end })
	f:Gap(4)
	f:Header(Tr.T("wm_h_dist"))
	f:Slider(Slide("wmMax", "wm_max", 0, 500, 10, Limit))
	f:Slider(Slide("wmMin", "wm_min", 0, 30, 1))
	f:Gap(4)
	f:Header(Tr.T("wm_h_size"))
	f:Slider(Slide("wmIcon", "wm_icon", 12, 48, 1))
	f:Slider(Slide("wmFont", "wm_font", -3, 8, 1))
	f:Slider(Slide("wmBeamW", "wm_beam_w", 30, 300, 10))
	f:Slider(Slide("wmBeamH", "wm_beam_h", 3, 12, 1))
	f:Slider(Slide("wmArrowSize", "wm_arrow", 16, 64, 2))
	f:Slider(Slide("wmInset", "wm_inset", 10, 300, 10))
	f:Slider(Slide("wmMaxArrows", "wm_arrows_n", 1, 8, 1))
	f:Slider(Slide("wmAlpha", "wm_alpha", 30, 100, 5))
	f:Note(Tr.T("wm_note"))
	f:Refresh()
end

if H.Options and H.Options.AddPage then
	H.Options.AddPage("worldmarks", function()
		return K.L("page_worldmarks", Tr.T("wm_label"))
	end, BuildPage, 41)
end
