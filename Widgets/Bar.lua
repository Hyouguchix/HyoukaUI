-- HyoukaUI: полосы. Обычная (Bar) и сегментированная (SegBar).
--
-- Заливка - белая текстура flat, окрашенная в цвет x 0.76 (spec 1.5). Значение меняется скачком, без
-- плавности. Ширина заливки привязана к сетке физических пикселей.
--
-- Bar.New(parent, opts)       opts: w, h (ретейл-px), color (массив rgb, тинт 0.76 применяется), bg, border, strata
-- Bar.Set(bar, value, max)    ставит долю; ничего не делает, если значение не менялось
-- Bar.SetColor(bar, r, g, b)  цвет заливки (тинт внутри); Bar.SetBg(bar, color)
-- Bar.Label(bar, side, role)  строка текста слева ("LEFT") или справа ("RIGHT")
-- Bar.SetOverlay(bar, amount, max)   щит: полосатая текстура от края заливки, излишек от левого края
-- Bar.FillWidth(inner, frac)  чистая функция: ширина заливки в AS
-- Bar.NewSeg(parent, opts)    сегментированная: opts как у Bar плюс gap (ретейл-px, по умолчанию 1)
-- Bar.SegSet(seg, n, max)     n зажженных сегментов из max
-- Bar.SegColor(seg, r, g, b)  цвет зажженных сегментов

local H = HyoukaUI
local T = H.Theme
local P = H.Panel

local B = {}
H.Bar = B

local reg = setmetatable({}, { __mode = "k" })

-- Ширина заливки: доля внутренней ширины, привязанная к пикселю. 0 -> 0, доля 1 -> вся ширина.
function B.FillWidth(inner, frac)
	if frac <= 0 or inner <= 0 then
		return 0
	end
	if frac >= 1 then
		return inner
	end
	local w = T.Snap(inner * frac)
	if w > inner then
		w = inner
	end
	return w
end

local function Frac(value, max)
	if not max or max <= 0 or not value or value <= 0 then
		return 0
	end
	local f = value / max
	if f > 1 then
		f = 1
	end
	return f
end

local function PlaceFill(bar)
	local b = T.Border()
	local fill = bar.huiFill
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", bar, "TOPLEFT", b, -b)
	fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", b, b)
	bar.huiInner = (bar:GetWidth() or 0) - 2 * b
end

local function ApplyFill(bar)
	local w = B.FillWidth(bar.huiInner, bar.huiFrac)
	bar.huiFillW = w
	if w <= 0 then
		bar.huiFill:Hide()
	else
		bar.huiFill:SetWidth(w)
		bar.huiFill:Show()
	end
end

function B.SetColor(bar, r, g, b)
	local fr, fg, fb = T.Tint(r, g, b)
	bar.huiFill:SetVertexColor(fr, fg, fb, 1)
	bar.huiColor = bar.huiColor or {}
	bar.huiColor[1], bar.huiColor[2], bar.huiColor[3] = r, g, b
end

function B.SetBg(bar, color)
	P.SetBg(bar, color)
end

function B.New(parent, opts)
	opts = opts or {}
	local bar = P.New(parent, { w = opts.w, h = opts.h, bg = opts.bg or "dock", border = opts.border, strata = opts.strata })
	local fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(T.TEX.flat)
	bar.huiFill = fill
	bar.huiVal, bar.huiMax, bar.huiFrac, bar.huiFillW = nil, nil, 0, 0
	PlaceFill(bar)
	local c = opts.color or T.C.accent
	B.SetColor(bar, c[1], c[2], c[3])
	fill:Hide()
	reg[bar] = true
	return bar
end

--@frame
function B.Set(bar, value, max)
	if bar.huiVal == value and bar.huiMax == max then
		return
	end
	bar.huiVal, bar.huiMax = value, max
	local frac = Frac(value, max)
	bar.huiFrac = frac
	local w = B.FillWidth(bar.huiInner, frac)
	if w ~= bar.huiFillW then
		bar.huiFillW = w
		if w <= 0 then
			bar.huiFill:Hide()
		else
			bar.huiFill:SetWidth(w)
			bar.huiFill:Show()
		end
	end
end

function B.Label(bar, side, role)
	local key = side == "RIGHT" and "huiRight" or "huiLeft"
	local fs = bar[key]
	if not fs then
		fs = H.Text.New(bar, role or "body", { justify = side == "RIGHT" and "RIGHT" or "LEFT" })
		local pad = H.R(2)
		if side == "RIGHT" then
			fs:SetPoint("RIGHT", bar, "RIGHT", -pad, 0)
		else
			fs:SetPoint("LEFT", bar, "LEFT", pad, 0)
		end
		bar[key] = fs
	end
	return fs
end

----------------------------------------------------------------------------------------
-- Щит: полосатая текстура
----------------------------------------------------------------------------------------

local function MakeStripes(bar, key)
	local t = bar[key]
	if not t then
		t = bar:CreateTexture(nil, "OVERLAY")
		t:SetTexture(T.TEX.stripes)
		local r, g, b = T.AccentRGB()
		t:SetVertexColor(r, g, b, 0.8)
		bar[key] = t
	end
	return t
end

-- Размер плитки полос: 16 ретейл-пикселей.
local TILE = 16

local function PlaceStripes(bar, t, left, w)
	t:ClearAllPoints()
	local b = T.Border()
	t:SetPoint("TOPLEFT", bar, "TOPLEFT", left, -b)
	t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left, b)
	t:SetWidth(w)
	local tile = TILE * T.PX
	t:SetTexCoord(0, w / tile, 0, ((bar:GetHeight() or 0) - 2 * b) / tile)
	t:Show()
end

-- amount: щит в тех же единицах, что max. Рисуется от конца заливки; что не поместилось - от левого края.
function B.SetOverlay(bar, amount, max)
	local over = MakeStripes(bar, "huiOver")
	local rest = MakeStripes(bar, "huiOverflow")
	local w = B.FillWidth(bar.huiInner, Frac(amount, max))
	if w <= 0 then
		over:Hide()
		rest:Hide()
		return
	end
	local b = T.Border()
	local fillW = bar.huiFillW or 0
	local room = bar.huiInner - fillW
	if w <= room then
		PlaceStripes(bar, over, b + fillW, w)
		rest:Hide()
	else
		if room > 0 then
			PlaceStripes(bar, over, b + fillW, room)
		else
			over:Hide()
		end
		local extra = w - room
		if extra > bar.huiInner then
			extra = bar.huiInner
		end
		PlaceStripes(bar, rest, b, extra)
	end
end

function B.ClearOverlay(bar)
	if bar.huiOver then
		bar.huiOver:Hide()
	end
	if bar.huiOverflow then
		bar.huiOverflow:Hide()
	end
end

----------------------------------------------------------------------------------------
-- Сегментированная полоса (класс-ресурс, XP по уровням)
----------------------------------------------------------------------------------------

-- Ширины сегментов: суммарно ровно inner, каждый привязан к пикселю, остаток уходит последним.
function B.SegWidths(inner, count, gap, out)
	if count <= 0 then
		return out
	end
	local each = T.Snap((inner - gap * (count - 1)) / count)
	local used = 0
	for i = 1, count do
		local w = each
		if i == count then
			w = inner - used - gap * (count - 1)
		end
		out[i] = w
		used = used + w
	end
	return out
end

local function SegLayout(seg)
	local max = seg.huiSegMax or 0
	local b = T.Border()
	local gap = H.R(seg.huiGap or 1)
	local inner = (seg:GetWidth() or 0) - 2 * b
	B.SegWidths(inner, max, gap, seg.huiWidths)
	local x = b
	for i = 1, max do
		local t = seg.huiSegs[i]
		if not t then
			t = seg:CreateTexture(nil, "ARTWORK")
			t:SetTexture(T.TEX.flat)
			seg.huiSegs[i] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", seg, "TOPLEFT", x, -b)
		t:SetPoint("BOTTOMLEFT", seg, "BOTTOMLEFT", x, b)
		t:SetWidth(seg.huiWidths[i])
		t:Show()
		x = x + seg.huiWidths[i] + gap
	end
	for i = max + 1, table.getn(seg.huiSegs) do
		seg.huiSegs[i]:Hide()
	end
end

local function SegPaint(seg)
	local lr, lg, lb = T.Tint(seg.huiLit[1], seg.huiLit[2], seg.huiLit[3])
	local dim = T.C.darkRest
	for i = 1, seg.huiSegMax or 0 do
		local t = seg.huiSegs[i]
		if i <= (seg.huiSegN or 0) then
			t:SetVertexColor(lr, lg, lb, 1)
		else
			t:SetVertexColor(dim[1], dim[2], dim[3], dim[4])
		end
	end
end

function B.NewSeg(parent, opts)
	opts = opts or {}
	local seg = P.New(parent, { w = opts.w, h = opts.h, bg = opts.bg or "dock", border = opts.border, strata = opts.strata })
	seg.huiSegs, seg.huiWidths, seg.huiGap = {}, {}, opts.gap or 1
	seg.huiLit = { 0.451, 0.506, 1.0 }
	local c = opts.color
	if c then
		seg.huiLit[1], seg.huiLit[2], seg.huiLit[3] = c[1], c[2], c[3]
	end
	seg.huiSegN, seg.huiSegMax = 0, 0
	reg[seg] = true
	return seg
end

function B.SegColor(seg, r, g, b)
	seg.huiLit[1], seg.huiLit[2], seg.huiLit[3] = r, g, b
	SegPaint(seg)
end

--@frame
function B.SegSet(seg, n, max)
	if seg.huiSegN == n and seg.huiSegMax == max then
		return
	end
	if seg.huiSegMax ~= max then
		seg.huiSegMax = max
		SegLayout(seg)
	end
	seg.huiSegN = n
	SegPaint(seg)
end

-- Пересчитать геометрию (THEME): панели уже пересчитали свои размеры.
function B.Reflow()
	for bar in pairs(reg) do
		if bar.huiFill then
			PlaceFill(bar)
			ApplyFill(bar)
		elseif bar.huiSegs then
			SegLayout(bar)
		end
	end
end

H.On("THEME", "w_bar", function()
	P.Reflow()
	B.Reflow()
end)
