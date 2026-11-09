-- HyoukaUI: Modules\Meter\DockHead.lua, шапка места дока: название страницы, итог, значки при наведении, меню страницы.
--
-- Шапка 21 ретейл-px: название страницы 14 слева, справа "сумма · в секунду" 12. ПРИ НАВЕДЕНИИ вместо итога видны значки:
-- сброс (буква) и меню (три черты); левый клик по шапке или по значку меню открывает меню страницы (Menu.Open), правый клик
-- по шапке страницы урона открывает разбивку своего героя (inv: "клик по шапке Урон"). Значки прячутся
-- через 0.05 с после ухода курсора, если GetMouseFocus уже не шапка и не значки (дочерний кадр отбирает курсор у шапки).
-- Hd.Create(sec, frame) создает шапку места sec в кадре frame; Hd.Layout(sec) расставляет размеры в AS (на создании и на THEME).

local H = HyoukaUI
local MU = H.MeterUI
local T = H.Theme
local X = H.Text
local K = H.Kit

local getn = table.getn

local Hd = {}
MU.DockHead = Hd

Hd.HEAD_H = 21
local MENU_BARS = 3

local function R(px)
	return H.R(px)
end

local function Tip(frame, key)
	GameTooltip:SetOwner(frame, "ANCHOR_TOP")
	GameTooltip:SetText(MU.S(key), 1, 1, 1)
	GameTooltip:Show()
end

-- Подсказка шапки: итог, средняя скорость и NOW (скорость за 5 с: зеленая не ниже среднего, оранжевая ниже).
function Hd.ShowTip(sec)
	local view = sec.view
	local page = view.page
	if not page or view.state ~= "ok" or view.n == 0 then
		GameTooltip:Hide()
		return false
	end
	local Fm = H.Format
	GameTooltip:SetOwner(sec.head, "ANCHOR_TOP")
	GameTooltip:SetText(MU.S(page.label), 1, 1, 1)
	GameTooltip:AddDoubleLine(MU.S(page.heal and "c_healing" or "t_total"), Fm.Small(view.total), 0.8, 0.8, 0.8, 1, 1, 1)
	if view.rate then
		GameTooltip:AddDoubleLine(MU.S("t_avg"), Fm.Small(view.rate), 0.8, 0.8, 0.8, 1, 1, 1)
		local now = MU.Model.NowRate(view, false)
		if now then
			local up = now >= view.rate
			GameTooltip:AddDoubleLine(MU.S("t_now"), Fm.Small(now), 0.8, 0.8, 0.8, up and 0.3 or 0.9, up and 0.8 or 0.75, up and 0.4 or 0.3)
		end
	end
	GameTooltip:Show()
	MU.Dock.state.tipSec = sec
	return true
end

function Hd.HideTip(sec)
	if MU.Dock.state.tipSec == sec then
		MU.Dock.state.tipSec = nil
		GameTooltip:Hide()
	end
end

function Hd.IconsOn(sec)
	sec.iconsOn = true
	sec.menuBtn:Show()
	local page = sec.view.page
	if page and page.reset then
		sec.resetBtn:Show()
	end
	sec.total:Hide()
end

function Hd.IconsOff(sec)
	sec.iconsOn = false
	sec.menuBtn:Hide()
	sec.resetBtn:Hide()
	sec.total:Show()
end

----------------------------------------------------------------------------------------
-- Меню страницы
----------------------------------------------------------------------------------------

local function MenuOptions(sec)
	local opts = {}
	local Mo = MU.Model
	if sec.slot == 2 then
		table.insert(opts, { value = "auto", label = MU.S("page_auto") })
	end
	for i = 1, getn(Mo.ORDER) do
		local id = Mo.ORDER[i]
		table.insert(opts, { value = id, label = MU.S(Mo.PAGES[id].label) })
	end
	if sec.slot == 3 then
		table.insert(opts, { value = "off", label = MU.S("page_off") })
	end
	table.insert(opts, { value = "@breakdown", label = MU.S("m_breakdown") })
	table.insert(opts, { value = "@collapse", label = MU.S(MU.opt.collapsed and "m_expand" or "m_collapse") })
	return opts
end

local function MenuPick(sec, value)
	if value == "@breakdown" then
		MU.Breakdown.OpenSelf()
	elseif value == "@collapse" then
		H.DB.Set("meter", "collapsed", not H.DB.Get("meter", "collapsed"))
	else
		H.DB.Set("meter", MU.SLOT_KEYS[sec.slot], value)
	end
end

function Hd.OpenMenu(sec)
	MU.Card.Hide()
	MU.Menu.Open(sec.head, MenuOptions(sec), H.DB.Get("meter", MU.SLOT_KEYS[sec.slot]), function(v)
		MenuPick(sec, v)
	end)
end

----------------------------------------------------------------------------------------
-- Значки
----------------------------------------------------------------------------------------

local function MenuIcon(head)
	local b = CreateFrame("Button", nil, head)
	b.bars = {}
	for k = 1, MENU_BARS do
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetTexture(T.TEX.solid)
		b.bars[k] = t
	end
	return b
end

local function PaintMenuIcon(b, token)
	local r, g, bl, a = K.Color(token)
	for k = 1, MENU_BARS do
		b.bars[k]:SetVertexColor(r, g, bl, a)
	end
end

-- Размеры и якоря в AS: зависят от PX, поэтому вызываются и на создании, и на THEME.
function Hd.Layout(sec)
	local head = sec.head
	head:SetHeight(R(Hd.HEAD_H))
	sec.title:ClearAllPoints()
	sec.title:SetPoint("LEFT", head, "LEFT", R(4), 0)
	sec.total:ClearAllPoints()
	sec.total:SetPoint("RIGHT", head, "RIGHT", -R(4), 0)
	local m = sec.menuBtn
	m:SetWidth(R(14))
	m:SetHeight(R(14))
	m:ClearAllPoints()
	m:SetPoint("RIGHT", head, "RIGHT", -R(4), 0)
	for k = 1, MENU_BARS do
		local t = m.bars[k]
		t:SetWidth(R(10))
		t:SetHeight(R(1))
		t:ClearAllPoints()
		t:SetPoint("CENTER", m, "CENTER", 0, R(3 * (2 - k)))
	end
	local r = sec.resetBtn
	r:SetWidth(R(14))
	r:SetHeight(R(14))
	r:ClearAllPoints()
	r:SetPoint("RIGHT", head, "RIGHT", -R(20), 0)
end

function Hd.Create(sec, fr)
	local head = CreateFrame("Button", nil, fr)
	head:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", fr, "TOPRIGHT", 0, 0)
	head:EnableMouse(true)
	head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	sec.head = head
	sec.title = X.New(head, "title", { layer = "OVERLAY" })
	sec.total = X.New(head, "small", { layer = "OVERLAY", justify = "RIGHT", color = "dim" })
	sec.menuBtn = MenuIcon(head)
	PaintMenuIcon(sec.menuBtn, "muted")
	sec.menuBtn:Hide()
	local reset = CreateFrame("Button", nil, head)
	reset.glyph = X.New(reset, "title", { layer = "OVERLAY", justify = "CENTER", color = "dim" })
	reset.glyph:SetPoint("CENTER", reset, "CENTER", 0, 0)
	reset.glyph:SetText(MU.S("reset_glyph"))
	reset:Hide()
	sec.resetBtn = reset
	Hd.Layout(sec)
	sec.checkFn = function()
		local f = GetMouseFocus and GetMouseFocus()
		if f == head or f == sec.menuBtn or f == reset then
			return
		end
		Hd.IconsOff(sec)
	end
	local hold = function()
		H.Clock.After(MU.OWNER, 0.05, sec.checkFn)
	end
	H.Script(MU.OWNER, head, "OnEnter", function()
		Hd.IconsOn(sec)
		Hd.ShowTip(sec)
	end)
	H.Script(MU.OWNER, head, "OnLeave", function()
		Hd.HideTip(sec)
		hold()
	end)
	H.Script(MU.OWNER, head, "OnClick", function(self, button)
		local page = sec.view.page
		if button == "RightButton" and page and not page.party and not page.heal then
			Hd.HideTip(sec)
			MU.Breakdown.OpenSelf()
		else
			Hd.OpenMenu(sec)
		end
	end)
	H.Script(MU.OWNER, sec.menuBtn, "OnEnter", function()
		Hd.IconsOn(sec)
		PaintMenuIcon(sec.menuBtn, "accent")
		Tip(sec.menuBtn, "menu_tip")
	end)
	H.Script(MU.OWNER, sec.menuBtn, "OnLeave", function()
		PaintMenuIcon(sec.menuBtn, "muted")
		GameTooltip:Hide()
		hold()
	end)
	H.Script(MU.OWNER, sec.menuBtn, "OnClick", function()
		Hd.OpenMenu(sec)
	end)
	H.Script(MU.OWNER, reset, "OnEnter", function()
		Hd.IconsOn(sec)
		K.TextColor(reset.glyph, "accent")
		Tip(reset, "reset_tip")
	end)
	H.Script(MU.OWNER, reset, "OnLeave", function()
		K.TextColor(reset.glyph, "muted")
		GameTooltip:Hide()
		hold()
	end)
	H.Script(MU.OWNER, reset, "OnClick", function()
		MU.Dock.Reset(sec.slot)
	end)
end
