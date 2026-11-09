-- HyoukaUI: Chat\Panel, плоская панель чата, кусок Layout ui.chat, размер и уголок размера (spec 3.8, plan 2.8).
--
-- Панель: 425x214 ретейл-px, фон #080808 0.80 (Theme.C.dock с альфой из настроек), рамка 1 физический пиксель.
-- Текст внутри: отступ 5 слева, справа и снизу, сверху 30 (ряд вкладок 22 и зазор): 415x179 при размере по умолчанию.
-- Кусок ui.chat: в LayoutDefaults он стоит movable = false (в v1 чат не двигали), здесь регистрируется movable = true,
-- поэтому режим перемещения (/hui move) двигает и масштабирует панель, а за ней вместе идут тексты (они привязаны к панели).
-- Размер: настройки width/height (ретейл-px) и уголок в правом нижнем углу (StartSizing "BOTTOMRIGHT"). После
-- StopMovingOrSizing движок отвязывает якоря панели, поэтому размер читается и пишется в настройки, а положение
-- пересчитывает Layout (L.SetSize -> Reflow ставит якоря заново).
-- В режиме Рядом кусок сдвинут вправо на SIDE_SHIFT ретейл-px, чтобы стоять рядом со стоковым чатом, а не на нем.

local H = HyoukaUI
local C = H.Chat
local L = H.Layout

local getn = table.getn

local P = {}
C.Panel = P

P.PAD = 5               -- отступ текста слева, справа, снизу (ретейл-px)
P.TOP = 30              -- от верха панели до текста: ряд вкладок 22 и зазор
P.TAB_H = 22            -- высота ряда вкладок
P.MIN_W, P.MIN_H, P.MAX_W, P.MAX_H = 200, 80, 900, 500
P.SIDE_SHIFT = 520      -- сдвиг по x в режиме Рядом

P.frame = nil
P.grip = nil
P.texts = {}            -- кадры, стоящие в прямоугольнике текста (стоковые окна и ленты)
P.sizing = false

local function R(px)
	return H.R(px)
end

local function BgColor()
	local c = H.Theme.C.dock
	return { c[1], c[2], c[3], C.Opt("bgAlpha") }
end

----------------------------------------------------------------------------------------
-- Уголок размера: шесть точек лесенкой в правом нижнем углу
----------------------------------------------------------------------------------------

local DOTS = { { 3, 3 }, { 6, 3 }, { 9, 3 }, { 3, 6 }, { 6, 6 }, { 3, 9 } }

local function LayoutGrip()
	local g = P.grip
	if not g then
		return
	end
	g:SetWidth(R(12))
	g:SetHeight(R(12))
	g:ClearAllPoints()
	g:SetPoint("BOTTOMRIGHT", P.frame, "BOTTOMRIGHT", -R(1), R(1))
	for i = 1, getn(g.dots) do
		local d = g.dots[i]
		d:SetWidth(R(2))
		d:SetHeight(R(2))
		d:ClearAllPoints()
		d:SetPoint("CENTER", g, "BOTTOMRIGHT", -R(DOTS[i][1]), R(DOTS[i][2]))
	end
end

local function PaintGrip(lit)
	local c = lit and H.Theme.C.text or H.Theme.C.dim
	for i = 1, getn(P.grip.dots) do
		P.grip.dots[i]:SetVertexColor(c[1], c[2], c[3], lit and 1 or 0.7)
	end
end

local function BuildGrip()
	local g = CreateFrame("Button", nil, P.frame)
	g:SetFrameStrata("MEDIUM")
	g.dots = {}
	for i = 1, getn(DOTS) do
		local d = g:CreateTexture(nil, "OVERLAY")
		d:SetTexture(H.Theme.TEX.solid)
		g.dots[i] = d
	end
	P.grip = g
	H.Script(C.M.name, g, "OnEnter", function()
		PaintGrip(true)
	end)
	H.Script(C.M.name, g, "OnLeave", function()
		PaintGrip(false)
	end)
	H.Script(C.M.name, g, "OnMouseDown", function(self, button)
		if button == "LeftButton" and not C.Opt("lock") then
			P.sizing = true
			P.frame:StartSizing("BOTTOMRIGHT")
		end
	end)
	H.Script(C.M.name, g, "OnMouseUp", function()
		P.SizeDone()
	end)
	H.Script(C.M.name, g, "OnHide", function()
		P.SizeDone()
	end)
	PaintGrip(false)
	LayoutGrip()
end

----------------------------------------------------------------------------------------
-- Размер
----------------------------------------------------------------------------------------

local function Clamp(v, lo, hi)
	return H.Clamp(math.floor(v + 0.5), lo, hi)
end

-- Размер из настроек на кадр и на Layout; тексты встают на место.
function P.Apply()
	local f = P.frame
	if not f then
		return
	end
	local w, h = C.Opt("width"), C.Opt("height")
	H.Panel.Size(f, w, h)
	f:SetMinResize(R(P.MIN_W), R(P.MIN_H))
	f:SetMaxResize(R(P.MAX_W), R(P.MAX_H))
	L.SetSize(C.ID, w, h)
	P.PlaceAll()
end

-- Новый размер в ретейл-px: зажимается, пишется в настройки (умолчание стирается). Возвращает принятые w, h.
function P.SetSize(wpx, hpx)
	local w = Clamp(wpx, P.MIN_W, P.MAX_W)
	local h = Clamp(hpx, P.MIN_H, P.MAX_H)
	H.DB.Set(C.M.name, "width", w)
	H.DB.Set(C.M.name, "height", h)
	P.Apply()
	return w, h
end

-- Отпустили уголок: размер прочитан с кадра, потому что StartSizing менял его сам.
function P.SizeDone()
	if not P.sizing then
		return
	end
	P.sizing = false
	local f = P.frame
	f:StopMovingOrSizing()
	local px = H.Kit.PX()
	local w, h = f:GetWidth(), f:GetHeight()
	if w and h and w > 0 and h > 0 then
		P.SetSize(w / px, h / px)
	else
		P.Apply()
	end
end

----------------------------------------------------------------------------------------
-- Тексты в прямоугольнике панели
----------------------------------------------------------------------------------------

function P.PlaceText(w)
	local f = P.frame
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", f, "TOPLEFT", R(P.PAD), -R(P.TOP))
	w:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -R(P.PAD), R(P.PAD))
	local level = f:GetFrameLevel() or 0
	if (w:GetFrameLevel() or 0) <= level then
		w:SetFrameLevel(level + 2)
	end
end

function P.PlaceAll()
	for i = 1, getn(P.texts) do
		P.PlaceText(P.texts[i])
	end
end

-- Поставить кадр (стоковое окно или ленту) на текст панели. Стоковому окну сперва запоминается положение.
function P.AddText(w, stock)
	for i = 1, getn(P.texts) do
		if P.texts[i] == w then
			P.PlaceText(w)
			return
		end
	end
	if stock then
		C.Stock.SavePlacement(w)
	end
	table.insert(P.texts, w)
	P.PlaceText(w)
end

function P.RemoveText(w)
	for i = getn(P.texts), 1, -1 do
		if P.texts[i] == w then
			table.remove(P.texts, i)
		end
	end
	C.Stock.RestorePlacement(w)
end

----------------------------------------------------------------------------------------
-- Жизненный цикл части
----------------------------------------------------------------------------------------

local function Build()
	local f = H.Panel.New(UIParent, { w = C.Opt("width"), h = C.Opt("height"), bg = BgColor(), strata = "BACKGROUND", level = 0 })
	f:SetResizable(true)
	P.frame = f
	BuildGrip()
end

function P.Register(mode)
	local base = H.LayoutDefaults and H.LayoutDefaults.pieces and H.LayoutDefaults.pieces[C.ID]
	local x = (base and base.x) or 1
	if mode == "side" then
		x = x + P.SIDE_SHIFT
	end
	L.Piece(C.ID, P.frame, { movable = true, label = C.T("piece"), x = x })
end

function P.Enable(mode)
	if not P.frame then
		Build()
	end
	P.Register(mode)
	P.Refresh()
	P.frame:Show()
end

function P.Disable()
	local f = P.frame
	if not f then
		return
	end
	P.SizeDone()
	for i = getn(P.texts), 1, -1 do
		C.Stock.RestorePlacement(P.texts[i])
	end
	H.Wipe(P.texts)
	f:Hide()
	L.Unpiece(C.ID)
end

function P.Refresh()
	local f = P.frame
	if not f then
		return
	end
	H.Panel.SetBg(f, BgColor())
	LayoutGrip()
	if C.Opt("lock") then
		P.grip:Hide()
	else
		P.grip:Show()
	end
	P.Apply()
end

-- Раз в секунду: стоковый код мог перевесить окно (док, переименование).
function P.Verify()
	local f = P.frame
	for i = 1, getn(P.texts) do
		local w = P.texts[i]
		local _, rel = w:GetPoint(1)
		if w:GetNumPoints() ~= 2 or rel ~= f then
			P.PlaceText(w)
		end
	end
end
