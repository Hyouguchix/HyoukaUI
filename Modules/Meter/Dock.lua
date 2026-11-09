-- HyoukaUI: Modules\Meter\Dock.lua, док счетчика урона (куски mt.dock, plan 2.8, 3.4, spec 3.7).
--
-- Док 427 x 214 ретейл-px у правого нижнего угла (BOTTOMRIGHT(-1, 1), страта MEDIUM), фон #080808 0.85, рамка 1 px.
-- Внутри отступ 1: две колонки по 212 с зазором 1. Колонка 1 (место 1) на всю высоту: шапка 21, затем 8 полос по 23 с шагом 24.
-- Колонка 2 делится 55% / 45% на места 2 и 3 (4 и 3 полосы). Страницы мест: Урон, Скорость, Лечение, Группа, Босс, 30 с
-- (Model.PAGES); настройки slot1, slot2 (по умолчанию auto), slot3 (по умолчанию healing, "off" скрывает место).
-- Размеры внутри дока считаются от размера куска из Layout (H.Layout.Def), положение дока дает Layout, своих позиций нет.
-- Шапка места (DockHead.lua): название страницы 14 слева, справа "сумма · в секунду" 12; ПРИ НАВЕДЕНИИ вместо суммы значки:
-- сброс и меню. Клик по шапке открывает меню страницы (вместо пилюль SurvivorUI). Прокрутка колесом над строками (List).
-- "Свернуть" сводит док к шапкам (высота 23): страницы не показываются, итоги видны.
--
-- Три места - это "окна" плана 3.4 (лишние окна SurvivorUI заменены тремя местами одного дока).
-- Режимы: Рядом - док сдвинут влево на свою ширину + 5, без Claim; Вместо - ретейл-место и Claim "meter".
-- Видимость: идет забег (фаза не ready) или включена настройка always; на экране выбора карточек (choosing) прячет Vis.
-- Покадровой работы нет: Tick раз в 0.5 с (шаг опроса счетчика движка), пока док виден.

local H = HyoukaUI
local MU = H.MeterUI
local T = H.Theme
local P = H.Panel
local X = H.Text
local K = H.Kit
local Fm = H.Format
local L = H.Layout

local getn = table.getn
local floor = math.floor

local D = {}
MU.Dock = D

D.HEAD_H, D.ROW_H, D.GAP, D.INSET = 21, 23, 1, 1
D.SPLIT = 0.5545            -- верх второй колонки (spec 3.7)
D.SIDE_GAP = 5

local S = { frame = nil, secs = {}, enabled = false, shown = false, eff = "off", claimed = false, cfg = nil, warned = false, rot = 1, tipSec = nil }
D.state = S

local function R(px)
	return H.R(px)
end

function D.Frame()
	return S.frame
end

function D.Section(i)
	return S.secs[i]
end

function D.IsShown()
	return S.shown
end

function D.Views()
	local out = {}
	for i = 1, MU.SLOTS do
		if S.secs[i] then
			table.insert(out, S.secs[i].view)
		end
	end
	return out
end

----------------------------------------------------------------------------------------
-- Место: название, итог, список (шапка и меню в DockHead.lua)
----------------------------------------------------------------------------------------

local function Paint(sec)
	local view = sec.view
	local page = view.page
	local key = page and page.label or "page_damage"
	if view.pageId == "boss" then
		local c = H.MeterData.Context()
		if c and c.encounterState == "active" then
			key = "boss_active"
		end
	end
	if sec.titleKey ~= key or sec.loc ~= MU.locGen then
		sec.titleKey, sec.loc = key, MU.locGen
		sec.title:SetText(MU.S(key))
	end
	local total, rate = view.total, view.rate
	if sec.tTotal ~= total or sec.tRate ~= rate or sec.tN ~= view.n then
		sec.tTotal, sec.tRate, sec.tN = total, rate, view.n
		if view.n > 0 then
			sec.total:SetText(Fm.Small(total).." "..H.Fonts.SYM.dot.." "..(rate and Fm.Small(rate) or "-"))
		else
			sec.total:SetText("")
		end
	end
	local list = sec.list
	list.huiTop = view.top
	H.List.SetItems(list, view.items, view.n)
	local empty = MU.Model.EmptyKey(view)
	if empty and not MU.opt.collapsed then
		sec.empty:SetText(MU.S(empty))
		sec.empty:Show()
	else
		sec.empty:Hide()
	end
	if sec.iconsOn then
		MU.DockHead.IconsOn(sec)
	end
end

local function Refresh(force)
	for i = 1, MU.SLOTS do
		local sec = S.secs[i]
		if sec.active then
			MU.Model.Update(sec.view, force)
			Paint(sec)
		end
	end
end
D.Refresh = Refresh

local function NewSection(i)
	local sec = { slot = i, view = MU.Model.NewView(i), active = false }
	local fr = CreateFrame("Frame", nil, S.frame)
	sec.frame = fr
	MU.DockHead.Create(sec, fr)
	sec.rowSpec = { wpx = 0, hpx = D.ROW_H, wide = false }
	sec.list = nil
	return sec
end

-- Список места создается при первой раскладке, когда известна ширина колонки.
local function EnsureList(sec, colW)
	if sec.list then
		return
	end
	local spec = sec.rowSpec
	spec.wpx = colW - 3
	local list = H.List.New(sec.frame, { w = colW, h = 20, row = D.ROW_H, gap = D.GAP, owner = MU.OWNER,
		create = function(row, lst)
			MU.Rows.Create(row, lst, spec)
		end,
		update = MU.Rows.Update })
	list.huiView = sec.view
	list.huiTop = 0
	sec.list = list
	sec.empty = X.New(sec.frame, "body", { layer = "OVERLAY", justify = "CENTER", color = "dim" })
	sec.empty:SetPoint("CENTER", list, "CENTER", 0, 0)
	sec.empty:Hide()
end

----------------------------------------------------------------------------------------
-- Раскладка мест
----------------------------------------------------------------------------------------

local function Place(sec, x, y, w, h, listH, active)
	sec.active = active
	if not active then
		sec.frame:Hide()
		return
	end
	local fr = sec.frame
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", S.frame, "TOPLEFT", R(x), -R(y))
	fr:SetWidth(R(w))
	fr:SetHeight(R(h))
	EnsureList(sec, w)
	sec.list:ClearAllPoints()
	sec.list:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, -R(D.HEAD_H))
	if listH > 0 then
		P.Size(sec.list, w, listH)
		sec.list:Show()
	else
		sec.list:Hide()
		sec.empty:Hide()
	end
	fr:Show()
end

-- Размеры мест по размеру куска и по настройкам (slot3, collapsed). force пересчитывает всегда (THEME).
function D.Arrange(force)
	local def = L.Def("mt.dock") or {}
	local w, h = def.w or 427, def.h or 214
	local colW = floor((w - 2 * D.INSET - D.GAP) / 2)
	local innerH = h - 2 * D.INSET
	local collapsed = MU.opt.collapsed
	local three = H.DB.Get("meter", "slot3") ~= "off"
	local key = (collapsed and 1 or 0) + (three and 2 or 0)
	if S.cfg == key and not force then
		return
	end
	S.cfg = key
	local x2 = D.INSET + colW + D.GAP
	local headH = D.HEAD_H
	if collapsed then
		L.SetSize("mt.dock", nil, headH + 2 * D.INSET)
		Place(S.secs[1], D.INSET, D.INSET, colW, headH, 0, true)
		Place(S.secs[2], x2, D.INSET, colW, headH, 0, true)
		Place(S.secs[3], x2, D.INSET, colW, headH, 0, false)
	else
		L.SetSize("mt.dock", nil, nil)
		local top = three and floor(innerH * D.SPLIT + 0.5) or innerH
		Place(S.secs[1], D.INSET, D.INSET, colW, innerH, innerH - headH, true)
		Place(S.secs[2], x2, D.INSET, colW, top, top - headH, true)
		Place(S.secs[3], x2, D.INSET + top + D.GAP, colW, innerH - top - D.GAP, innerH - top - D.GAP - headH, three)
	end
	H.List.Reflow()
end

----------------------------------------------------------------------------------------
-- Видимость
----------------------------------------------------------------------------------------

function D.WantShown()
	if not S.enabled then
		return false
	end
	if MU.opt.always then
		return true
	end
	local ph = H.Run.Phase()
	return ph ~= nil and ph ~= "ready"
end

-- Док виден, пока идет забег. Кадром на экране выбора карточек владеет Vis: ему не мешаем.
function D.UpdateShown()
	if not S.frame then
		return
	end
	local want = D.WantShown()
	if want ~= S.shown then
		S.shown = want
		H.MeterData.Watch(MU.OWNER, want)
		MU.Crits.Enable(want and MU.opt.crits)
		if want then
			Refresh(true)
		else
			MU.Card.Hide()
			MU.Menu.Close()
			S.tipSec = nil
		end
	end
	if not H.Vis.IsChoosing() then
		if want and not S.frame:IsShown() then
			S.frame:Show()
		elseif not want and S.frame:IsShown() then
			S.frame:Hide()
		end
	else
		MU.Card.Hide()
		MU.Menu.Close()
	end
end

----------------------------------------------------------------------------------------
-- Режимы, куски Layout, Claim
----------------------------------------------------------------------------------------

-- Определение куска поверх умолчаний: в режиме Рядом сдвиг влево на ширину дока + зазор.
function D.PieceDef()
	if S.eff ~= "side" then
		return nil
	end
	local def = L.Defs()["mt.dock"] or {}
	return { x = -((def.w or 427) + D.SIDE_GAP) }
end

function D.ApplyMode()
	local eff, why = MU.EffectiveMode()
	if why == "survivor" and not S.warned then
		S.warned = true
		H.Print(MU.S("sui_meter_visible"))
	end
	S.eff = eff
	if S.frame then
		L.Piece("mt.dock", S.frame, D.PieceDef())
	end
	MU.Breakdown.RegisterPiece()
	if eff == "replace" and not S.claimed then
		H.Hud.Claim("meter", MU.OWNER)
		S.claimed = true
	elseif eff ~= "replace" and S.claimed then
		H.Hud.Release("meter", MU.OWNER)
		S.claimed = false
	end
end

----------------------------------------------------------------------------------------
-- Тик и события
----------------------------------------------------------------------------------------

--@frame
function D.Tick()
	if not S.shown then
		return
	end
	-- Снимков не больше трех на 0.5 с (H.MeterData): сначала то, на что смотрят (окно разбивки, подсказка шапки с NOW),
	-- затем места по кругу, чтобы никто не голодал.
	MU.Breakdown.Tick()
	if S.tipSec then
		MU.DockHead.ShowTip(S.tipSec)
	end
	local first = S.rot
	S.rot = first + 1
	if S.rot > MU.SLOTS then
		S.rot = 1
	end
	for k = 0, MU.SLOTS - 1 do
		local i = first + k
		if i > MU.SLOTS then
			i = i - MU.SLOTS
		end
		local sec = S.secs[i]
		if sec.active and MU.Model.Update(sec.view, false) then
			Paint(sec)
		end
	end
	if MU.Card.IsShown() then
		MU.Card.Refresh()
	end
end

function D.Reset(slot)
	local sec = S.secs[slot]
	if not sec then
		return
	end
	local ok, why = MU.Model.Reset(sec.view)
	if not ok then
		local key = (why == "limit" and "reset_limit") or (why == "unsupported" and "reset_unsupported") or "reset_none"
		H.Print(MU.S(key))
		return
	end
	MU.Model.Update(sec.view, true)
	Paint(sec)
end

function D.ResetAll()
	for i = 1, MU.SLOTS do
		if S.secs[i] and S.secs[i].active then
			D.Reset(i)
		end
	end
end

function D.RowClick(row, button)
	local item = row.huiItem
	if item and button == "LeftButton" and item.kind == "owner" and item.ownerId then
		MU.Breakdown.Toggle(item.ownerId, item.name, item.classKey)
	end
end

local function Forget()
	for i = 1, MU.SLOTS do
		local sec = S.secs[i]
		sec.titleKey, sec.tTotal, sec.tN = nil, nil, nil
		MU.Model.Dirty(sec.view)
		if sec.list then
			MU.Rows.ForgetList(sec.list)
		end
	end
end

local function OnRunStarted()
	MU.Crits.ResetAll()
	for i = 1, MU.SLOTS do
		MU.Model.Dirty(S.secs[i].view)
	end
	MU.Breakdown.Close()
	MU.Card.Hide()
	D.UpdateShown()
	Refresh(true)
end

local function OnSetting(ev, mod, key)
	if mod ~= "meter" then
		return
	end
	MU.LoadOptions()
	if key == "rightText" then
		for i = 1, MU.SLOTS do
			if S.secs[i].list then
				MU.Rows.ForgetList(S.secs[i].list)
			end
		end
	elseif key == "pets" then
		MU.Model.RegroupViews(D.Views())
	elseif key == "crits" then
		MU.Crits.Enable(S.shown and MU.opt.crits)
	elseif key == "slot1" or key == "slot2" or key == "slot3" or key == "foldPct" then
		for i = 1, MU.SLOTS do
			MU.Model.Dirty(S.secs[i].view)
		end
	end
	if key == "always" then
		D.UpdateShown()
	elseif key == "slot3" or key == "collapsed" then
		D.Arrange(true)
	end
	Refresh(true)
end

local function OnMeterReset(ev, key)
	MU.Crits.OnReset(ev, key)
	local slot = MU.Crits.SlotOfKey(key)
	if slot and S.secs[slot] then
		S.secs[slot].view.dirty = true
	end
end

local function OnLocale()
	MU.locGen = MU.locGen + 1
	Forget()
	for i = 1, MU.SLOTS do
		S.secs[i].resetBtn.glyph:SetText(MU.S("reset_glyph"))
	end
	Refresh(true)
end

-- PX сменился (разрешение, масштаб): размеры шапок, значков и строк пересчитываются, места и списки раскладываются заново.
local function OnTheme()
	if S.frame then
		L.Reflow()   -- Layout сам на THEME не перекладывает: размеры и якоря кусков в AS пересчитываем здесь
		for i = 1, MU.SLOTS do
			MU.DockHead.Layout(S.secs[i])
			if S.secs[i].list then
				MU.Rows.RelayoutList(S.secs[i].list)
			end
		end
		D.Arrange(true)
		Forget()
		MU.Breakdown.Relayout()
		Refresh(true)
	end
end

local function Ensure()
	if S.frame then
		return
	end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	P.SetBg(f, "panel")
	T.AddBorder(f)
	f:Hide()
	S.frame = f
	for i = 1, MU.SLOTS do
		S.secs[i] = NewSection(i)
	end
end

function D.Enable()
	Ensure()
	S.enabled = true
	S.cfg = nil
	local M = MU.M
	D.ApplyMode()
	H.Vis.Register(S.frame, { id = "mt.dock" })
	M:On("PHASE_CHANGED", D.UpdateShown)
	M:On("RUN_STARTED", OnRunStarted)
	M:On("RUN_ENDED", function()
		Refresh(true)
	end)
	M:On("CARDS", D.UpdateShown)
	M:On("LAYOUT", function(ev, id)
		if id == nil or id == "mt.dock" then
			D.UpdateShown()
		end
	end)
	M:On("SETTING", OnSetting)
	M:On("METER_RESET", OnMeterReset)
	M:On("LOCALE", OnLocale)
	M:On("THEME", OnTheme)
	M:Every(0.5, D.Tick)
	D.Arrange(true)
	D.UpdateShown()
end

function D.Disable()
	S.enabled, S.shown = false, false
	if not S.frame then
		return
	end
	H.Vis.Unregister(S.frame)
	S.frame:Hide()
	L.Unpiece("mt.dock")
	if S.claimed then
		H.Hud.Release("meter", MU.OWNER)
		S.claimed = false
	end
	MU.Breakdown.Disable()
	MU.Card.Drop()
	MU.Menu.Close()
	MU.Crits.Enable(false)
	H.MeterData.Watch(MU.OWNER, false)
	for i = 1, MU.SLOTS do
		MU.Model.Dispose(S.secs[i].view)
	end
	MU.Crits.ResetAll()
end
