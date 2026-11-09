-- HyoukaUI: вид режима перемещения (дополнение к Core\Mover.lua): сетка, перекрестие, муверы, карточка.
-- Кадры создаются при первом включении режима, не при загрузке файла. Состояние общее с Mover: Mover.S.

local H = HyoukaUI
local K = H.Kit
local L = H.Layout
local Mv = H.Mover

local getn = table.getn
local C, S = Mv.C, Mv.S

----------------------------------------------------------------------------------------
-- Кадры: сетка, перекрестие, муверы, карточка (создаются при первом включении)
----------------------------------------------------------------------------------------

local function Line(root, token)
	local t = root:CreateTexture(nil, "BACKGROUND")
	t:SetTexture(K.FLAT)
	K.Paint(t, token)
	return t
end

function Mv.BuildGrid()
	local root = S.root
	local sw, sh = L.Screen()
	local step = K.R(C.GRID)
	local px = K.PX()
	local cx, cy = sw / 2, sh / 2
	local nx, ny = math.floor(sw / step) + 1, math.floor(sh / step) + 1
	for i = 1, nx do
		local t = S.gridV[i]
		if not t then
			t = Line(root, "gridLine")
			S.gridV[i] = t
		end
		K.Paint(t, "gridLine")
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * step, 0)
		t:SetWidth(px)
		t:SetHeight(sh)
		t:Show()
	end
	for i = nx + 1, getn(S.gridV) do
		S.gridV[i]:Hide()
	end
	for i = 1, ny do
		local t = S.gridH[i]
		if not t then
			t = Line(root, "gridLine")
			S.gridH[i] = t
		end
		K.Paint(t, "gridLine")
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(i - 1) * step)
		t:SetWidth(sw)
		t:SetHeight(px)
		t:Show()
	end
	for i = ny + 1, getn(S.gridH) do
		S.gridH[i]:Hide()
	end
	if not S.cross[1] then
		S.cross[1] = Line(root, "gridCenter")
		S.cross[2] = Line(root, "gridCenter")
		S.cross[3] = Line(root, "white")
		S.cross[4] = Line(root, "white")
	end
	K.Paint(S.cross[1], "gridCenter")
	K.Paint(S.cross[2], "gridCenter")
	S.cross[1]:ClearAllPoints()
	S.cross[1]:SetPoint("TOPLEFT", root, "TOPLEFT", cx, 0)
	S.cross[1]:SetWidth(px)
	S.cross[1]:SetHeight(sh)
	S.cross[2]:ClearAllPoints()
	S.cross[2]:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -cy)
	S.cross[2]:SetWidth(sw)
	S.cross[2]:SetHeight(px)
	local len = K.R(C.CROSS)
	S.cross[3]:ClearAllPoints()
	S.cross[3]:SetPoint("CENTER", root, "TOPLEFT", cx, -cy)
	S.cross[3]:SetWidth(len)
	S.cross[3]:SetHeight(px)
	S.cross[4]:ClearAllPoints()
	S.cross[4]:SetPoint("CENTER", root, "TOPLEFT", cx, -cy)
	S.cross[4]:SetWidth(px)
	S.cross[4]:SetHeight(len)
end

function Mv.PaintMover(m)
	local sel = (Mv.sel == m.id)
	m.border:SetColor(sel and "accent" or "accentDim")
	if L.IsHiddenByUser(m.id) then
		m:SetAlpha(C.IDLE * 0.5)
	elseif S.drag == m.id then
		m:SetAlpha(C.DRAG)
	elseif m.hovered or sel then
		m:SetAlpha(C.HOVER)
	else
		m:SetAlpha(C.IDLE)
	end
end

function Mv.PlaceMover(m, id)
	local l, t, w, h = L.Rect(id)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", S.root, "TOPLEFT", l, -t)
	m:SetWidth(math.max(w, K.R(C.MIN)))
	m:SetHeight(math.max(h, K.R(C.MIN)))
end

local function DragStop(m)
	m:StopMovingOrSizing()
	if m.SetUserPlaced then
		m:SetUserPlaced(false)
	end
	local id = m.id
	S.drag = nil
	local left = m:GetLeft()
	local top = m:GetTop()
	if left and top then
		local _, sh = L.Screen()
		Mv.Commit(id, left, sh - top)
	else
		Mv.PlaceMover(m, id)
	end
	Mv.PaintMover(m)
end

function Mv.NewMover(id)
	local m = CreateFrame("Button", nil, S.root)
	m.id = id
	K.Fill(m, "mover", "BACKGROUND")
	m.border = K.Border(m, "accentDim")
	m:SetMovable(true)
	m:EnableMouse(true)
	m:SetClampedToScreen(true)
	m:RegisterForDrag("LeftButton")
	m.label = K.Text(m, "small", nil, "CENTER")
	m.label:SetPoint("CENTER", m, "CENTER", 0, 0)
	m.label:SetShadowOffset(1, -1)
	m.label:SetShadowColor(0, 0, 0, 1)
	H.Script("mover", m, "OnEnter", function()
		m.hovered = true
		Mv.PaintMover(m)
	end)
	H.Script("mover", m, "OnLeave", function()
		m.hovered = false
		Mv.PaintMover(m)
	end)
	H.Script("mover", m, "OnClick", function()
		Mv.Select(m.id)
	end)
	H.Script("mover", m, "OnDragStart", function()
		Mv.Select(m.id)
		S.drag = m.id
		Mv.PaintMover(m)
		m:StartMoving()
	end)
	H.Script("mover", m, "OnDragStop", function()
		DragStop(m)
	end)
	S.movers[id] = m
	return m
end

----------------------------------------------------------------------------------------
-- Карточка выбранного куска: координаты, масштаб, показ, "на место", привязка
----------------------------------------------------------------------------------------

function Mv.BuildCard()
	local card = CreateFrame("Frame", nil, S.root)
	card:SetWidth(K.R(300))
	card:SetHeight(K.R(150))
	card:SetFrameStrata("TOOLTIP")
	card:EnableMouse(true)
	K.Fill(card, "bg", "BACKGROUND")
	card.border = K.Border(card, "edge")
	card.title = K.Text(card, "normal")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", K.R(6), -K.R(5))
	card.coords = K.Text(card, "normal")
	card.coords:SetPoint("TOPLEFT", card, "TOPLEFT", K.R(6), -K.R(24))
	card.scaleText = K.Text(card, "normal")
	card.scaleText:SetPoint("TOPLEFT", card, "TOPLEFT", K.R(6), -K.R(42))
	card.attach = K.Text(card, "small")
	card.attach:SetPoint("TOPLEFT", card, "TOPLEFT", K.R(6), -K.R(62))
	K.TextColor(card.attach, "note")
	local bw, bh = K.R(26), K.R(20)
	card.minus = K.Button(card, "-", bw, bh, function()
		Mv.SetScale(Mv.sel, L.Scale(Mv.sel) - 0.05)
	end, "mover")
	card.minus:SetPoint("TOPRIGHT", card, "TOPRIGHT", -K.R(36), -K.R(40))
	card.plus = K.Button(card, "+", bw, bh, function()
		Mv.SetScale(Mv.sel, L.Scale(Mv.sel) + 0.05)
	end, "mover")
	card.plus:SetPoint("TOPRIGHT", card, "TOPRIGHT", -K.R(6), -K.R(40))
	card.showBtn = K.Button(card, H.L.btn_show, K.R(90), bh, function()
		Mv.ToggleShown(Mv.sel)
	end, "mover")
	card.showBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", K.R(6), K.R(6))
	card.reset = K.Button(card, H.L.btn_put_back, K.R(90), bh, function()
		Mv.ResetPiece(Mv.sel)
	end, "mover")
	card.reset:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -K.R(6), K.R(6))
	card:Hide()
	S.card = card
end

function Mv.RefreshCard()
	local card, id = S.card, Mv.sel
	if not card then
		return
	end
	if not id or not L.Has(id) then
		card:Hide()
		return
	end
	local l, t, w, h = L.Rect(id)
	local px = K.PX()
	local def = L.Def(id)
	card.title:SetText(L.PieceLabel(id, def).."  ("..id..")")
	card.coords:SetText(string.format("X %d   Y %d   %d x %d px", H.Round(l / px), H.Round(t / px), H.Round(w / px), H.Round(h / px)))
	card.scaleText:SetText(H.L.opt_scale.." "..H.Round(L.Scale(id) * 100).."%")
	if L.IsDetached(id) then
		card.attach:SetText(H.L.mv_detached..L.Saved(id).p)
	elseif def and def.rel and def.rel ~= "UIParent" then
		card.attach:SetText(H.L.mv_attached..def.rel)
	else
		card.attach:SetText(H.L.mv_attached_screen)
	end
	local sw, sh = L.Screen()
	local cw, ch = card:GetWidth(), card:GetHeight()
	local cx = H.Clamp(l, 0, math.max(0, sw - cw))
	local cy = t + h + K.R(4)
	if cy + ch > sh then
		cy = t - ch - K.R(4)
	end
	cy = H.Clamp(cy, 0, math.max(0, sh - ch))
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", S.root, "TOPLEFT", cx, -cy)
	card:Show()
end
