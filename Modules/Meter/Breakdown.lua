-- HyoukaUI: Modules\Meter\Breakdown.lua, окно "урон героя по способностям" в духе Details (кусок mt.breakdown).
--
-- Клик по строке героя на странице Группа (или пункт меню шапки "Разбивка по способностям" для своего героя)
-- открывает окно над доком той же ширины: заголовок "Имя: урон по способностям" цветом класса, итог "сумма · в секунду",
-- полоса на каждую способность (значок, имя, СКОРОСТЬ, СУММА из displayAmount, ДОЛЯ), под полосами бижутерия героя.
-- Данные: снимок scope = "owner", groupBy = "source" через Model (ownerId берется из строки снимка PARTY, не из имени и
-- класса: исправление прототипа Details.lua). Своего OnUpdate нет: Tick зовет Dock раз в 0.5 с, пока окно открыто.
-- Высота окна 21 + 24 x строк (до 10, дальше прокрутка колесом), Layout.SetSize("mt.breakdown"); якорь подсказок игры
-- поднимается над окном (Tooltip.SetLift). Закрыть: повторный клик по герою, правый клик, кнопка закрытия, Esc (UISpecialFrames,
-- [НЕ ПРОВЕРЕНО в игре]), смена забега. Ничего не захватывает с клавиатуры.

local H = HyoukaUI
local MU = H.MeterUI
local T = H.Theme
local P = H.Panel
local X = H.Text
local K = H.Kit
local Fm = H.Format
local L = H.Layout

local B = {}
MU.Breakdown = B

B.HEAD_H, B.ROW_H, B.GAP, B.MAX_ROWS, B.FOOT_H, B.INSET = 21, 23, 1, 10, 14, 1

local S = { frame = nil, view = nil, list = nil, open = false, owner = nil, name = nil, class = nil, built = false,
	titleKey = nil, tTotal = nil, tRate = nil, loc = 0, height = 0, footer = nil, loRev = nil }

local function R(px)
	return H.R(px)
end

function B.IsOpen()
	return S.open
end

function B.Owner()
	return S.owner
end

function B.Frame()
	return S.frame
end

function B.View()
	return S.view
end

-- Для тестов: title, total, foot, list, empty, close.
function B.Parts()
	return S.title, S.total, S.foot, S.list, S.empty, S.close
end

-- Окно стоит на 1 px над доком (якорь на кусок mt.dock): в режиме Рядом, при сворачивании дока и при его переносе
-- окно идет за ним; на умолчаниях это то же место, что BOTTOMRIGHT(-1, 216) в LayoutDefaults. Нет дока - запасная точка.
function B.PieceDef()
	return { point = "BOTTOMRIGHT", rel = "mt.dock", relPoint = "TOPRIGHT", x = 0, y = 1,
		fallback = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -1, y = 216 } }
end

function B.RegisterPiece()
	if S.frame then
		L.Piece("mt.breakdown", S.frame, B.PieceDef())
	end
end

-- Якоря внутри окна в AS: зависят от PX, поэтому вызываются на создании и на THEME.
function B.Relayout()
	if not S.built then
		return
	end
	local f = S.frame
	S.title:ClearAllPoints()
	S.title:SetPoint("LEFT", f, "TOPLEFT", R(6), -R(B.HEAD_H / 2))
	S.total:ClearAllPoints()
	S.total:SetPoint("RIGHT", f, "TOPRIGHT", -R(B.HEAD_H + 6), -R(B.HEAD_H / 2))
	S.close:SetWidth(R(B.HEAD_H))
	S.close:SetHeight(R(B.HEAD_H))
	S.close:ClearAllPoints()
	S.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	S.empty:ClearAllPoints()
	S.empty:SetPoint("TOP", f, "TOP", 0, -R(B.HEAD_H + 6))
	S.foot:ClearAllPoints()
	S.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", R(6), R(3))
	S.list:ClearAllPoints()
	S.list:SetPoint("TOPLEFT", f, "TOPLEFT", R(B.INSET), -R(B.HEAD_H))
	MU.Rows.RelayoutList(S.list)
	S.titleName, S.footer = nil, nil
	S.height = 0
	if S.open then
		B.Refresh(true)
	end
end

local function Build()
	if S.built then
		return
	end
	S.built = true
	local f = CreateFrame("Frame", "HyoukaUI_Breakdown", UIParent)
	f:SetFrameStrata("MEDIUM")
	P.SetBg(f, "panel")
	T.AddBorder(f)
	f:EnableMouse(true)
	f:Hide()
	S.frame = f
	table.insert(UISpecialFrames, "HyoukaUI_Breakdown")
	S.view = MU.Model.NewOwnerView("bd")
	S.title = X.New(f, "title", { layer = "OVERLAY" })
	S.total = X.New(f, "small", { layer = "OVERLAY", justify = "RIGHT", color = "dim" })
	local close = CreateFrame("Button", nil, f)
	close.glyph = X.New(close, "title", { layer = "OVERLAY", justify = "CENTER", color = "dim" })
	close.glyph:SetPoint("CENTER", close, "CENTER", 0, 0)
	close.glyph:SetText("x")
	S.close = close
	H.Script(MU.OWNER, close, "OnEnter", function()
		K.TextColor(close.glyph, "accent")
	end)
	H.Script(MU.OWNER, close, "OnLeave", function()
		K.TextColor(close.glyph, "muted")
	end)
	H.Script(MU.OWNER, close, "OnClick", function()
		B.Close()
	end)
	S.empty = X.New(f, "body", { layer = "OVERLAY", justify = "CENTER", color = "dim" })
	S.foot = X.New(f, "small", { layer = "OVERLAY", color = "dim" })
	local def = L.Defs()["mt.breakdown"] or {}
	local w = def.w or 427
	local spec = { wpx = w - 2 * B.INSET - 3, hpx = B.ROW_H, wide = true }
	local listH = B.MAX_ROWS * (B.ROW_H + B.GAP) - B.GAP
	local list = H.List.New(f, { w = w - 2 * B.INSET, h = listH, row = B.ROW_H, gap = B.GAP, owner = MU.OWNER,
		create = function(row, lst)
			MU.Rows.Create(row, lst, spec)
		end,
		update = MU.Rows.Update })
	list.huiView = S.view
	list.huiTop = 0
	S.list = list
	B.Relayout()
	H.Script(MU.OWNER, f, "OnMouseUp", function(self, button)
		if button == "RightButton" then
			B.Close()
		end
	end)
	-- Esc закрывает окно через FrameXML (UISpecialFrames): состояние сводится на OnHide.
	H.Script(MU.OWNER, f, "OnHide", function()
		if S.open and not H.Vis.IsChoosing() then
			B.Close()
		end
	end)
	B.RegisterPiece()
end

local function Resize(n, hasFoot)
	local rows = n
	if rows > B.MAX_ROWS then
		rows = B.MAX_ROWS
	end
	if rows < 1 then
		rows = 1
	end
	local h = B.HEAD_H + rows * (B.ROW_H + B.GAP) + (hasFoot and B.FOOT_H or 0)
	if h ~= S.height then
		S.height = h
		L.SetSize("mt.breakdown", nil, h)
		H.Tooltip.SetLift(h + 1)
	end
end

local function Paint()
	local view = S.view
	local data = H.Loadout.Get(S.owner)
	local jewelry = MU.Model.JewelryNames(data)
	if S.titleName ~= S.name or S.loc ~= MU.locGen then
		S.titleName, S.loc = S.name, MU.locGen
		S.title:SetText(MU.Sf("bd_title", S.name or "?"))
		local r, g, b = H.Hero.ColorOf(S.class)
		S.title:SetTextColor(r, g, b, 1)
	end
	if S.tTotal ~= view.total or S.tRate ~= view.rate or S.tN ~= view.n then
		S.tTotal, S.tRate, S.tN = view.total, view.rate, view.n
		if view.n > 0 then
			S.total:SetText(MU.S("bd_total").." "..Fm.Small(view.total).." "..H.Fonts.SYM.dot.." "..(view.rate and Fm.Small(view.rate) or "-")..MU.S("per_sec"))
		else
			S.total:SetText("")
		end
	end
	S.list.huiTop = view.top
	H.List.SetItems(S.list, view.items, view.n)
	if view.n == 0 then
		S.empty:SetText(MU.S(MU.Model.EmptyKey(view) or "bd_empty"))
		S.empty:Show()
	else
		S.empty:Hide()
	end
	if S.footer ~= jewelry then
		S.footer = jewelry
		if jewelry then
			X.Fit(S.foot, MU.Sf("bd_footer", jewelry), R(413))
			S.foot:Show()
		else
			S.foot:Hide()
		end
	end
	Resize(view.n, jewelry ~= nil)
end

function B.Refresh(force)
	if not S.open then
		return
	end
	local changed = MU.Model.UpdateOwner(S.view, force)
	local rev = H.Loadout.Revision(S.owner)
	if changed or force or rev ~= S.loRev then
		S.loRev = rev
		Paint()
	end
end

function B.Tick()
	if S.open then
		B.Refresh(false)
	end
end

function B.Open(ownerId, name, class)
	if not ownerId then
		return false
	end
	Build()
	B.RegisterPiece()
	S.owner, S.name, S.class = ownerId, name, class
	S.titleName, S.footer, S.tTotal = nil, nil, nil
	MU.Model.SetOwner(S.view, ownerId)
	MU.Model.Dirty(S.view)
	S.open = true
	H.Vis.Register(S.frame, { id = "mt.breakdown" })
	H.Loadout.Request(ownerId)
	if not H.Vis.IsChoosing() then
		S.frame:Show()
	end
	MU.Card.Hide()
	B.Refresh(true)
	return true
end

function B.Close()
	if not S.open then
		return
	end
	S.open = false
	H.Vis.Unregister(S.frame)
	S.frame:Hide()
	H.Tooltip.SetLift(0)
	S.height = 0
	MU.Model.Dispose(S.view)
	S.view.owner = false
	S.owner = nil
end

function B.Toggle(ownerId, name, class)
	if S.open and S.owner == ownerId then
		B.Close()
		return false
	end
	return B.Open(ownerId, name, class)
end

-- Разбивка своего героя (пункт меню, /hui meter open).
function B.OpenSelf()
	local id = H.MeterData.LocalOwner()
	if not id then
		H.Print(MU.S("no_data"))
		return false
	end
	return B.Toggle(id, H.Hero.Name() or MU.S("c_you"), H.Hero.Class())
end

function B.RowClick(row, button)
	if button == "RightButton" then
		B.Close()
	end
end

function B.Disable()
	B.Close()
	if S.built then
		L.Unpiece("mt.breakdown")
	end
end
