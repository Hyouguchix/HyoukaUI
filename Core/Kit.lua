-- HyoukaUI: тонкий слой для окон ядра (Mover, Demo, Options): цвета, заливки, рамка 1 px, текст, кнопка.
--
-- Предпочитает слои Theme/Fonts (H.Color, H.R, H.Theme.PX, H.Text), если они загружены, и имеет
-- запасные значения из plan 2.2 и spec 1.2, чтобы окна работали и без них (тесты, порядок загрузки).
-- Файл только определения: ничего не рисует при загрузке.
--
-- K.PX()                     AS на физический пиксель
-- K.R(px)                    ретейл-пиксели -> AS со снапом к физическому пикселю
-- K.Color(token)             r, g, b, a (токены spec 1.2 + mover)
-- K.Fill(frame, token, layer) -> текстура на всю площадь кадра; K.Paint(tex, token)
-- K.Border(frame, token)     -> объект рамки в 1 физический пиксель; b:SetColor(token); K.RefreshBorders()
-- K.Text(parent, role, delta, justify) -> FontString; K.TextColor(fs, token)
-- K.Button(parent, label, w, h, onClick, owner) -> кнопка с рамкой и подсветкой наведения
-- K.T(text)                  русская строка как есть; K.L(key, ru) строка из H.L, если ключ есть, иначе ru

local H = HyoukaUI

local K = {}
H.Kit = K

K.FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
K.FALLBACK_PX = 0.5333

local PALETTE = {
	bg = { 0.0314, 0.0314, 0.0314, 0.85 },
	bgBar = { 0.0314, 0.0314, 0.0314, 0.80 },
	inner = { 0.055, 0.055, 0.055, 0.90 },
	iconBg = { 0.08, 0.08, 0.08, 0.60 },
	edge = { 0, 0, 0, 1 },
	muted = { 0.486, 0.486, 0.486, 1 },
	note = { 0.5, 0.5, 0.5, 1 },
	text = { 1, 1, 1, 1 },
	ok = { 0.30, 0.80, 0.40, 1 },
	err = { 0.90, 0.30, 0.30, 1 },
	warn = { 0.90, 0.75, 0.30, 1 },
	gold = { 1, 0.788, 0.137, 1 },
	hover = { 0.851, 0.851, 0.851, 0.15 },
	accent = { 0.451, 0.506, 1, 1 },
	accentSel = { 0.451, 0.506, 1, 0.35 },
	accentDim = { 0.451, 0.506, 1, 0.6 },
	mover = { 0.0745, 0.114, 0.141, 0.95 },
	gridLine = { 0.451, 0.506, 1, 0.15 },
	gridCenter = { 0.451, 0.506, 1, 0.25 },
	white = { 1, 1, 1, 1 },
}
K.PALETTE = PALETTE

local FONT_SIZES = { small = 6.4, normal = 7, chat = 7.5, cd = 8, big = 9.07, msg = 12.27 }

function K.T(text)
	return text
end

-- Строка из Locale (H.L), если такой ключ там есть; иначе переданная русская строка.
function K.L(key, ru)
	local L = H.L
	if L then
		local v = L[key]
		if v ~= nil and v ~= key then
			return v
		end
	end
	return ru
end

function K.PX()
	local t = H.Theme
	local p = t and t.PX
	if type(p) == "function" then
		p = p()
	end
	if type(p) ~= "number" or p <= 0 then
		return K.FALLBACK_PX
	end
	return p
end

function K.R(px)
	if H.R then
		return H.R(px)
	end
	local pxs = K.PX()
	return math.floor(px * pxs / pxs + 0.5) * pxs
end

-- Токены, которые берут цвет у текущего акцента и свою прозрачность.
local ACCENT_ALPHA = { accentSel = 0.35, accentDim = 0.6, gridLine = 0.15, gridCenter = 0.25 }

function K.Color(token)
	if H.Color then
		local r, g, b, a = H.Color(token)
		if r then
			return r, g, b, a or 1
		end
		local alpha = ACCENT_ALPHA[token]
		if alpha then
			r, g, b = H.Color("accent")
			if r then
				return r, g, b, alpha
			end
		end
	end
	local c = PALETTE[token] or PALETTE.text
	return c[1], c[2], c[3], c[4]
end

function K.Paint(tex, token)
	local r, g, b, a = K.Color(token)
	tex:SetVertexColor(r, g, b, a)
end

function K.Fill(frame, token, layer)
	local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
	tex:SetTexture(K.FLAT)
	tex:SetAllPoints(frame)
	K.Paint(tex, token or "bg")
	return tex
end

----------------------------------------------------------------------------------------
-- Рамка: четыре полоски толщиной ровно в один физический пиксель.
----------------------------------------------------------------------------------------

local borders = setmetatable({}, { __mode = "k" })

local function BorderSet(b, token)
	local r, g, b2, a = K.Color(token)
	b.token = token
	for i = 1, 4 do
		b[i]:SetVertexColor(r, g, b2, a)
	end
end

local function BorderSize(b)
	local t = K.PX()
	local th = H.Theme
	if th and type(th.Border) == "function" then
		t = th.Border() or t
	end
	b[1]:SetHeight(t)
	b[2]:SetHeight(t)
	b[3]:SetWidth(t)
	b[4]:SetWidth(t)
	b.thickness = t
end

function K.Border(frame, token)
	local b = { frame = frame, SetColor = BorderSet }
	local top = frame:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	local bottom = frame:CreateTexture(nil, "BORDER")
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	local left = frame:CreateTexture(nil, "BORDER")
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	local right = frame:CreateTexture(nil, "BORDER")
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	b[1], b[2], b[3], b[4] = top, bottom, left, right
	for i = 1, 4 do
		b[i]:SetTexture(K.FLAT)
	end
	BorderSize(b)
	BorderSet(b, token or "edge")
	borders[b] = true
	return b
end

-- Пересчет толщины при смене масштаба и разрешения (событие THEME).
function K.RefreshBorders()
	for b in pairs(borders) do
		BorderSize(b)
		BorderSet(b, b.token)
	end
end

----------------------------------------------------------------------------------------
-- Текст
----------------------------------------------------------------------------------------

function K.TextColor(fs, token)
	local r, g, b, a = K.Color(token)
	fs:SetTextColor(r, g, b, a)
end

function K.Text(parent, role, delta, justify)
	local fs
	local ht = H.Text
	if type(ht) == "function" then
		fs = ht(parent, role or "normal", delta)
	elseif type(ht) == "table" and ht.New then
		fs = ht.New(parent, role or "normal", { delta = delta, justify = justify or "LEFT" })
	end
	if not fs then
		fs = parent:CreateFontString(nil, "OVERLAY")
		fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", FONT_SIZES[role or "normal"] or 7, "OUTLINE")
	end
	fs:SetJustifyH(justify or "LEFT")
	K.TextColor(fs, "text")
	return fs
end

----------------------------------------------------------------------------------------
-- Кнопка: #0E0E0E 0.90, рамка 1 px, наведение #D9D9D9 0.15 мгновенно, без смещения текста.
----------------------------------------------------------------------------------------

function K.Button(parent, label, w, h, onClick, owner)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetWidth(w)
	btn:SetHeight(h)
	btn.fill = K.Fill(btn, "inner", "BACKGROUND")
	btn.border = K.Border(btn, "edge")
	btn.hover = btn:CreateTexture(nil, "ARTWORK")
	btn.hover:SetTexture(K.FLAT)
	btn.hover:SetAllPoints(btn)
	K.Paint(btn.hover, "hover")
	btn.hover:Hide()
	btn.label = K.Text(btn, "normal", nil, "CENTER")
	btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)
	btn.label:SetText(label or "")
	H.Script(owner or "ui", btn, "OnEnter", function()
		btn.hover:Show()
	end)
	H.Script(owner or "ui", btn, "OnLeave", function()
		btn.hover:Hide()
	end)
	if onClick then
		H.Script(owner or "ui", btn, "OnClick", function(self, button)
			onClick(btn, button)
		end)
	end
	function btn.SetLabel(self, text)
		self.label:SetText(text)
	end
	return btn
end

H.On("THEME", "kit", function()
	K.RefreshBorders()
end)
