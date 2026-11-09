-- HyoukaUI: панель. Плоская заливка и рамка в физический пиксель.
--
-- Размеры задаются в ретейл-пикселях (w, h) и хранятся на кадре: при смене PX (событие THEME)
-- панель пересчитывает размеры сама.
--
-- Panel.New(parent, opts)  opts: w, h (ретейл-px), bg (имя цвета из Theme.C или массив), border (по умолчанию да),
--                          strata, level
-- Panel.Size(f, w, h)      новые размеры в ретейл-px
-- Panel.SetBg(f, color)    цвет заливки: имя или массив { r, g, b, a }
-- Panel.Inner(f)           ширина и высота внутри рамки, AS

local H = HyoukaUI
local T = H.Theme

local P = {}
H.Panel = P

local reg = setmetatable({}, { __mode = "k" })   -- кадр -> true

local function ColorOf(color, default)
	if type(color) == "string" then
		return T.C[color] or default
	end
	return color or default
end

function P.Size(f, w, h)
	f.huiW, f.huiH = w, h
	if w then
		f:SetWidth(H.R(w))
	end
	if h then
		f:SetHeight(H.R(h))
	end
end

function P.SetBg(f, color)
	local c = ColorOf(color, T.C.panel)
	T.AddBackground(f, c)
	f.huiBgColor = c
end

function P.New(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent or UIParent)
	if opts.strata then
		f:SetFrameStrata(opts.strata)
	end
	if opts.level then
		f:SetFrameLevel(opts.level)
	end
	if opts.bg ~= false then
		P.SetBg(f, opts.bg or "panel")
	end
	if opts.border ~= false then
		T.AddBorder(f)
	end
	P.Size(f, opts.w, opts.h)
	reg[f] = true
	return f
end

function P.Inner(f)
	local b = T.Border()
	local w, h = f:GetWidth() or 0, f:GetHeight() or 0
	return w - 2 * b, h - 2 * b
end

function P.Count()
	local n = 0
	for _ in pairs(reg) do
		n = n + 1
	end
	return n
end

-- Пересчитать размеры всех панелей (THEME).
function P.Reflow()
	for f in pairs(reg) do
		P.Size(f, f.huiW, f.huiH)
	end
end

H.On("THEME", "w_panel", P.Reflow)
