-- HyoukaUI: окно настроек (plan 5). Боковое меню 80 AS, страницы, заголовок для перетаскивания,
-- Esc закрывает (HyoukaUI_Options в UISpecialFrames). Фон #080808 0.85, рамка 1 px, акцент #7381FF.
-- Из прототипа SurvivorUITweaks\Options.lua взят каркас (окно, полоса заголовка, боковая колонка,
-- элементы с обновлением); стиль и код свои. Окно создается при первом открытии, не при загрузке.
--
-- O.AddPage(key, label, build, order, stale)   label: строка или функция, возвращающая строку (язык меняется);
--     build(page, flow) вызывается один раз при первом показе
--     страницы под H.Safe; stale() -> true заставляет пересобрать страницу при открытии.
-- O.Open([key]) O.Close() O.Toggle() O.IsOpen() O.Select(key) O.Refresh() O.Rebuild(key) O.Current()

local H = HyoukaUI
local K = H.Kit
local C = H.Controls

local getn = table.getn

local O = {}
H.Options = O

O.pages = {}
O.order = {}
O.current = nil

local WIDTH, HEIGHT, SIDE, TITLE, PAD = 400, 420, 80, 16, 8
local BAR_W, STEP = 3, 24         -- полоса прокрутки и шаг колеса, AS

local S = { win = nil, menu = {}, body = nil, scroll = nil, content = nil, bar = nil, thumb = nil, off = 0, total = 0 }

local function SortPages()
	table.sort(O.order, function(a, b)
		local pa, pb = O.pages[a], O.pages[b]
		if pa.order ~= pb.order then
			return pa.order < pb.order
		end
		return pa.seq < pb.seq
	end)
end

local seq = 0

function O.AddPage(key, label, build, order, stale)
	local p = O.pages[key]
	if not p then
		seq = seq + 1
		p = { key = key, seq = seq }
		O.pages[key] = p
		table.insert(O.order, key)
	end
	p.label, p.build, p.order, p.stale = label, build, order or 50, stale
	SortPages()
	if S.win then
		O.LayoutMenu()
	end
end

function O.Current()
	return O.current
end

function O.IsOpen()
	return S.win ~= nil and S.win:IsShown() and true or false
end

----------------------------------------------------------------------------------------
-- Меню слева
----------------------------------------------------------------------------------------

local function PaintMenu()
	if S.title then
		K.TextColor(S.title, "accent")
	end
	for key, b in pairs(S.menu) do
		local on = (key == O.current)
		K.Paint(b.fill, on and "accentSel" or "bgBar")
		K.TextColor(b.label, on and "accent" or "text")
	end
end

function O.LayoutMenu()
	for i = 1, getn(O.order) do
		local key = O.order[i]
		local p = O.pages[key]
		local b = S.menu[key]
		local text = p.label
		if type(text) == "function" then
			text = text()
		end
		if not b then
			b = K.Button(S.side, text, SIDE - 2, 14, function()
				O.Select(key)
			end, "options")
			b.border:SetColor("bgBar")
			b.label:ClearAllPoints()
			b.label:SetPoint("LEFT", b, "LEFT", 6, 0)
			b.label:SetJustifyH("LEFT")
			S.menu[key] = b
		end
		b:SetLabel(text)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", S.side, "TOPLEFT", 1, -(4 + (i - 1) * 15))
	end
	PaintMenu()
end

----------------------------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------
-- Прокрутка страницы (жалоба пользователя 2026-11-09: страница Трекер длиннее окна). ScrollFrame движка режет то, что
-- не влезло (SurvivorUI так же держит окно статов); колесо мыши листает, справа тонкая полоса.
----------------------------------------------------------------------------------------

local function ViewH()
	return HEIGHT - TITLE - 2 * PAD
end

local function UpdateScroll()
	if not S.scroll then
		return
	end
	local view = ViewH()
	local total = S.total
	if total < view then
		total = view
	end
	S.max = total - view
	if S.off > S.max then
		S.off = S.max
	end
	if S.off < 0 then
		S.off = 0
	end
	S.scroll:SetVerticalScroll(S.off)
	if S.max <= 0 then
		S.bar:Hide()
		return
	end
	S.bar:Show()
	local th = view * view / total
	if th < 14 then
		th = 14
	end
	S.thumb:SetHeight(th)
	S.thumb:ClearAllPoints()
	S.thumb:SetPoint("TOP", S.bar, "TOP", 0, -(S.off / S.max) * (view - th))
end

-- Высота страницы по раскладке; offset сохраняется, если reset не задан.
local function SyncPage(p, reset)
	if not S.content then
		return
	end
	local view = ViewH()
	local h = (p and p.flow and p.flow:Height() or 0) + PAD
	S.total = h
	S.content:SetHeight(h < view and view or h)
	if reset then
		S.off = 0
	end
	UpdateScroll()
end

local function Build()
	if S.win then
		return
	end
	local win = CreateFrame("Frame", "HyoukaUI_Options", UIParent)
	win:SetWidth(WIDTH)
	win:SetHeight(HEIGHT)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:Hide()
	K.Fill(win, "bg", "BACKGROUND")
	win.border = K.Border(win, "edge")
	if UISpecialFrames then
		table.insert(UISpecialFrames, "HyoukaUI_Options")
	end
	S.win = win

	local bar = CreateFrame("Frame", nil, win)
	bar:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
	bar:SetHeight(TITLE)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	K.Fill(bar, "bgBar", "BACKGROUND")
	H.Script("options", bar, "OnDragStart", function()
		win:StartMoving()
	end)
	H.Script("options", bar, "OnDragStop", function()
		win:StopMovingOrSizing()
	end)
	local title = K.Text(bar, "normal")
	title:SetPoint("LEFT", bar, "LEFT", 6, 0)
	title:SetText("HyoukaUI "..H.version)
	K.TextColor(title, "accent")
	S.title = title
	local close = K.Button(bar, "x", 12, 12, function()
		O.Close()
	end, "options")
	close:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

	local side = CreateFrame("Frame", nil, win)
	side:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -TITLE)
	side:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE)
	K.Fill(side, "bgBar", "BACKGROUND")
	S.side = side

	local scroll = CreateFrame("ScrollFrame", nil, win)
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE + PAD, -(TITLE + PAD))
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(PAD + BAR_W + 2), PAD)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(WIDTH - SIDE - 2 * PAD - BAR_W - 2)
	content:SetHeight(ViewH())
	scroll:SetScrollChild(content)
	S.scroll, S.content, S.body = scroll, content, content
	local bar = CreateFrame("Frame", nil, win)
	bar:SetWidth(BAR_W)
	bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD / 2, -(TITLE + PAD))
	bar:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD / 2, PAD)
	K.Fill(bar, "bgBar", "BACKGROUND")
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetTexture(K.FLAT)
	thumb:SetWidth(BAR_W)
	K.Paint(thumb, "accent")
	bar:Hide()
	S.bar, S.thumb = bar, thumb
	win:EnableMouseWheel(true)
	H.Script("options", win, "OnMouseWheel", function(self, delta)
		S.off = S.off - (delta or 0) * STEP
		UpdateScroll()
	end)
	O.LayoutMenu()
end

local function BuildPage(p)
	local pf = CreateFrame("Frame", nil, S.body)
	pf:SetAllPoints(S.body)
	pf:Hide()
	p.frame = pf
	p.flow = C.Flow(pf, WIDTH - SIDE - 2 * PAD - BAR_W - 2)
	H.Safe("options", p.build, pf, p.flow)
	p.builtAt = H.Now()
end

function O.Rebuild(key)
	local p = O.pages[key]
	if not p then
		return
	end
	if p.frame then
		p.frame:Hide()
		p.frame = nil
		p.flow = nil
	end
	if S.win and O.current == key then
		O.Select(key)
	end
end

function O.Select(key)
	local p = O.pages[key]
	if not p then
		return false
	end
	Build()
	C.ClosePopup()
	local old = O.pages[O.current]
	if old and old.frame and old ~= p then
		old.frame:Hide()
	end
	if p.frame and p.stale and p.stale() then
		p.frame:Hide()
		p.frame, p.flow = nil, nil
	end
	O.current = key
	if not p.frame then
		BuildPage(p)
	end
	p.frame:Show()
	if p.flow then
		p.flow:Refresh()
	end
	SyncPage(p, true)
	PaintMenu()
	return true
end

function O.Refresh()
	local p = O.pages[O.current]
	if S.win and p and p.flow then
		p.flow:Refresh()
		SyncPage(p, false)
	end
end

function O.Open(key)
	Build()
	if not key then
		key = O.current or O.order[1]
	end
	if key then
		O.Select(key)
	end
	S.win:Show()
end

function O.Close()
	C.ClosePopup()
	if S.win then
		S.win:Hide()
	end
end

function O.Toggle()
	if O.IsOpen() then
		O.Close()
	else
		O.Open()
	end
end

-- Только для тестов и selftest: кадр окна и пункты меню.
function O.Frame()
	return S.win
end

function O.MenuButton(key)
	return S.menu[key]
end

local function Refresh()
	if O.IsOpen() then
		O.LayoutMenu()
		O.Refresh()
	end
end

H.On("SETTING", "options", Refresh)
H.On("MODULE", "options", Refresh)
H.On("LAYOUT", "options", Refresh)
H.On("MOVE_MODE", "options", Refresh)
H.On("DEMO", "options", Refresh)
H.On("THEME", "options", Refresh)
-- Смена языка: страницы строятся один раз с готовыми надписями, поэтому все собранные страницы выбрасываются и текущая
-- собирается заново; меню берет названия страниц заново.
H.On("LOCALE", "options", function()
	for i = 1, getn(O.order) do
		local p = O.pages[O.order[i]]
		if p.frame then
			p.frame:Hide()
			p.frame = nil
			p.flow = nil
		end
	end
	if O.IsOpen() then
		C.ClosePopup()
		O.Select(O.current or O.order[1])
		O.LayoutMenu()
	elseif S.win then
		O.LayoutMenu()
	end
end)
