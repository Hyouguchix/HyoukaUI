-- HyoukaUI: Modules\Tracker\WorldMarksView, рисование мировых меток: пул кадров меток (значок, луч света и пятно у сундука,
-- название, расстояние) и пул стрелок у края экрана. Данные берутся у H.Proj (Data\Projection.lua), настройки лежат в
-- WM.O (WorldMarks.lua считает их из M.db). Все кадры мышь не берут: ни один не вызывает EnableMouse(true).
--
-- Пул фиксированный: MAX_MARKS меток и MAX_ARROWS стрелок, кадры создаются по мере спроса и больше не удаляются.
-- Покадровый код (Paint*) таблиц и строк не создает: строки расстояний лежат в кэше (по ярду или метру от 0 до 999).
-- Точка метки лежит в единицах UIParent от BOTTOMLEFT (так отвечает слой проекции) и прижимается к физическому
-- пикселю, чтобы текст не дрожал на дробных координатах. Стрелка не имеет поворота у текстуры 1.12: поворот делает
-- SetTexCoord с восемью углами (угол по часовой от "вверх" дает направление (ax, ay): синус = ax, косинус = ay).

local H = HyoukaUI

local Tr = H.Tr
local Proj = H.Proj

local getn = table.getn
local floor = math.floor

local WM = Tr.Marks or {}
Tr.Marks = WM

local V = {}
WM.View = V

V.MAX_MARKS, V.MAX_ARROWS = 48, 8
local MAX_MARKS, MAX_ARROWS = V.MAX_MARKS, V.MAX_ARROWS

local TEXD = "Interface\\AddOns\\HyoukaUI\\Media\\Textures\\"
V.TEX = {
	chest = TEXD.."mark_chest", boss = TEXD.."mark_skull", lair = TEXD.."mark_lair", elite = TEXD.."mark_elite",
	other = TEXD.."mark_cross", arrow = TEXD.."mark_arrow", beam = TEXD.."mark_beam", pool = TEXD.."mark_pool",
}
local TEX = V.TEX

local marks, arrows = {}, {}
V.marks, V.arrows = marks, arrows
V.shownMarks, V.shownArrows = 0, 0
V.layer = nil

----------------------------------------------------------------------------------------
-- Цвета и строки
----------------------------------------------------------------------------------------

-- Цвет значка и названия по виду и записи: финальный босс оранжевый, бодрый страж оранжевый, спящий белый.
local function ColorOf(rec)
	local C = Tr.C
	local kind = rec.kind
	if kind == "chest" then
		return C.gold
	elseif kind == "boss" then
		if rec.raw == "finalBoss" then
			return C.orange
		end
		return C.purple
	elseif kind == "lair" then
		if rec.state == "awake" or rec.raw == "guardian" then
			return C.orange
		end
		return C.white
	elseif kind == "elite" then
		return C.green
	end
	return C.red
end
V.ColorOf = ColorOf

local DSTR = {}
local builtLang

-- Строки "NN м" / "NN m" для 0..999 и "999+": покадровый код берет их по индексу.
function V.BuildStrings()
	local lang = H.Locale and H.Locale.code
	if builtLang == lang and DSTR.m then
		return
	end
	builtLang = lang
	DSTR.m, DSTR.yd = {}, {}
	local sm, sy = Tr.T("wm_m"), Tr.T("wm_yd")
	for i = 0, 999 do
		DSTR.m[i] = i.." "..sm
		DSTR.yd[i] = i.." "..sy
	end
	DSTR.m[1000] = "999+ "..sm
	DSTR.yd[1000] = "999+ "..sy
end

--@frame
local function DistText(unit, d)
	local n = floor(d + 0.5)
	if n > 999 then
		n = 1000
	elseif n < 0 then
		n = 0
	end
	return DSTR[unit][n]
end

--@frame
local function Snap(O, v)
	return floor(v * O.ipx + 0.5) * O.px
end

----------------------------------------------------------------------------------------
-- Кадры
----------------------------------------------------------------------------------------

function V.Build()
	if V.layer then
		return
	end
	local layer = CreateFrame("Frame", nil, UIParent)
	layer:SetAllPoints(UIParent)
	layer:SetFrameStrata("LOW")
	layer:EnableMouse(false)
	layer:Hide()
	V.layer = layer
	V.BuildStrings()
end

local function NewMark()
	local f = CreateFrame("Frame", nil, V.layer)
	f:SetWidth(1)
	f:SetHeight(1)
	f:EnableMouse(false)
	local m = { f = f, kind = false, raw = false, state = false }
	m.pool = f:CreateTexture(nil, "BACKGROUND")
	m.pool:SetTexture(TEX.pool)
	m.pool:SetBlendMode("ADD")
	m.beam = f:CreateTexture(nil, "BORDER")
	m.beam:SetTexture(TEX.beam)
	m.beam:SetBlendMode("ADD")
	m.icon = f:CreateTexture(nil, "ARTWORK")
	m.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
	m.name = H.Text.New(f, "small", { justify = "CENTER", layer = "OVERLAY" })
	m.name:SetPoint("BOTTOM", m.icon, "TOP", 0, H.R(1))
	m.dist = H.Text.New(f, "small", { justify = "CENTER", layer = "OVERLAY", delta = -1 })
	m.dist:SetPoint("TOP", m.icon, "BOTTOM", 0, -H.R(1))
	f:Hide()
	return m
end

local function NewArrow()
	local f = CreateFrame("Frame", nil, V.layer)
	f:EnableMouse(false)
	local a = { f = f, kind = false, raw = false, state = false }
	a.tex = f:CreateTexture(nil, "ARTWORK")
	a.tex:SetTexture(TEX.arrow)
	a.tex:SetAllPoints(f)
	a.icon = f:CreateTexture(nil, "OVERLAY")
	a.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
	a.dist = H.Text.New(f, "small", { justify = "CENTER", layer = "OVERLAY", delta = -1 })
	a.dist:SetPoint("TOP", f, "BOTTOM", 0, -H.R(1))
	f:Hide()
	return a
end

-- Размеры и шрифты уже созданных кадров по настройкам (смена настроек, смена масштаба интерфейса).
function V.Restyle()
	local O = WM.O
	if not O then
		return
	end
	for i = 1, getn(marks) do
		H.Fonts.Apply(marks[i].name, "small", O.fontDelta)
		H.Fonts.Apply(marks[i].dist, "small", O.fontDelta - 1)
	end
	for i = 1, getn(arrows) do
		local a = arrows[i]
		a.f:SetWidth(O.arrowSize)
		a.f:SetHeight(O.arrowSize)
		a.icon:SetWidth(O.arrowSize * 0.5)
		a.icon:SetHeight(O.arrowSize * 0.5)
		H.Fonts.Apply(a.dist, "small", O.fontDelta - 1)
	end
	V.BuildStrings()
end

local function GetMark(i)
	local m = marks[i]
	if not m then
		m = NewMark()
		marks[i] = m
		local O = WM.O
		H.Fonts.Apply(m.name, "small", O.fontDelta)
		H.Fonts.Apply(m.dist, "small", O.fontDelta - 1)
	end
	return m
end

local function GetArrow(i)
	local a = arrows[i]
	if not a then
		a = NewArrow()
		arrows[i] = a
		local O = WM.O
		a.f:SetWidth(O.arrowSize)
		a.f:SetHeight(O.arrowSize)
		a.icon:SetWidth(O.arrowSize * 0.5)
		a.icon:SetHeight(O.arrowSize * 0.5)
		H.Fonts.Apply(a.dist, "small", O.fontDelta - 1)
	end
	return a
end

-- Внешний вид, зависящий от вида и состояния записи: текстура и цвет (раз при смене).
local function StyleMark(m, rec)
	m.kind, m.raw, m.state = rec.kind, rec.raw, rec.state
	local c = ColorOf(rec)
	m.icon:SetTexture(TEX[rec.kind])
	m.icon:SetVertexColor(c[1], c[2], c[3], 1)
	H.Text.SetColor(m.name, c)
	H.Text.SetColor(m.dist, "text")
	local g = Tr.C.gold
	m.beam:SetVertexColor(g[1], g[2], g[3], 0.9)
	m.pool:SetVertexColor(g[1], g[2], g[3], 0.7)
end

local function StyleArrow(a, rec)
	a.kind, a.raw, a.state = rec.kind, rec.raw, rec.state
	local c = ColorOf(rec)
	a.tex:SetVertexColor(c[1], c[2], c[3], 1)
	a.icon:SetTexture(TEX[rec.kind])
	a.icon:SetVertexColor(c[1], c[2], c[3], 1)
	H.Text.SetColor(a.dist, "text")
end

----------------------------------------------------------------------------------------
-- Покадровая отрисовка
----------------------------------------------------------------------------------------

-- Метка: значок по точке, расстояние под ним, название над ним; у сундука луч и пятно от основания до значка.
--@frame
local function PaintMark(m, rec, d, alpha, scale, O)
	local f = m.f
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", Snap(O, rec.sx), Snap(O, rec.sy))
	if m.kind ~= rec.kind or m.raw ~= rec.raw or m.state ~= rec.state then
		StyleMark(m, rec)
	end
	local size = O.icon * scale
	m.icon:SetWidth(size)
	m.icon:SetHeight(size)
	f:SetAlpha(alpha)
	if O.names and rec.name then
		H.Text.Set(m.name, rec.name)
	else
		H.Text.Set(m.name, "")
	end
	if O.dist and d >= 0 then
		H.Text.Set(m.dist, DistText(O.unit, d))
	else
		H.Text.Set(m.dist, "")
	end
	if rec.hasFoot and O.beam and rec.yard > 0 and rec.sy - rec.fy > 2 then
		local w = O.beamW * rec.yard
		m.beam:ClearAllPoints()
		m.beam:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", Snap(O, rec.fx), Snap(O, rec.fy))
		m.beam:SetWidth(w)
		m.beam:SetHeight(rec.sy - rec.fy)
		m.beam:Show()
		local pw = w * 1.4
		m.pool:ClearAllPoints()
		m.pool:SetPoint("CENTER", UIParent, "BOTTOMLEFT", Snap(O, rec.fx), Snap(O, rec.fy))
		m.pool:SetWidth(pw)
		m.pool:SetHeight(pw * 0.4)
		m.pool:Show()
	else
		m.beam:Hide()
		m.pool:Hide()
	end
	if not f:IsShown() then
		f:Show()
	end
end

-- Стрелка: от точки героя по направлению (ax, ay) до прямоугольника экрана, втянутого на O.inset.
--@frame
local function PaintArrow(a, rec, d, alpha, O, sw, sh)
	local ax, ay = rec.ax, rec.ay
	local hx, hy = Proj.hx, Proj.hy
	local lo_x, hi_x, lo_y, hi_y = O.inset, sw - O.inset, O.inset, sh - O.inset
	local k = 1e30
	if ax > 0.0001 then
		k = (hi_x - hx) / ax
	elseif ax < -0.0001 then
		k = (lo_x - hx) / ax
	end
	local ky = 1e30
	if ay > 0.0001 then
		ky = (hi_y - hy) / ay
	elseif ay < -0.0001 then
		ky = (lo_y - hy) / ay
	end
	if ky < k then
		k = ky
	end
	if k < 0 then
		k = 0
	end
	local x, y = hx + ax * k, hy + ay * k
	if x < lo_x then
		x = lo_x
	elseif x > hi_x then
		x = hi_x
	end
	if y < lo_y then
		y = lo_y
	elseif y > hi_y then
		y = hi_y
	end
	local f = a.f
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", Snap(O, x), Snap(O, y))
	if a.kind ~= rec.kind or a.raw ~= rec.raw or a.state ~= rec.state then
		StyleArrow(a, rec)
	end
	f:SetAlpha(alpha)
	-- поворот по часовой на угол с sin = ax, cos = ay: углы UL, LL, UR, LR в пространстве текстуры
	local s, c = ax * 0.5, ay * 0.5
	a.tex:SetTexCoord(0.5 - c - s, 0.5 + s - c, 0.5 - c + s, 0.5 + s + c, 0.5 + c - s, 0.5 - s - c, 0.5 + c + s, 0.5 - s + c)
	if O.dist and d >= 0 then
		H.Text.Set(a.dist, DistText(O.unit, d))
	else
		H.Text.Set(a.dist, "")
	end
	if not f:IsShown() then
		f:Show()
	end
end
V.PaintMark, V.PaintArrow = PaintMark, PaintArrow

--@frame
local function HideFrom(list, first, last)
	for i = first, last do
		local item = list[i]
		if item.f:IsShown() then
			item.f:Hide()
		end
	end
end

-- Один проход: метки и стрелки по записям слоя проекции. Расстояние d в единицах показа (метры или ярды), -1 если неизвестно.
--@frame
function V.Paint()
	local O = WM.O
	local recs = Proj.recs
	local nm, na = 0, 0
	local sw, sh = H.Layout.Screen()
	local fx = O.fade and O.maxD > 0
	for i = 1, Proj.n do
		local rec = recs[i]
		if O.kind[rec.kind] then
			local d = -1
			if rec.dist then
				d = rec.dist * O.factor
			end
			local inRange = d < 0 or (d >= O.minD and (O.maxD <= 0 or d <= O.maxD))
			if inRange then
				local alpha, scale = O.alpha, 1
				if d >= 0 and O.maxD > 0 then
					local t = d / O.maxD
					if fx and t > 0.5 then
						alpha = alpha * (1 - 0.65 * (t - 0.5) * 2)
					end
					if O.scale then
						scale = 1 - 0.35 * t
					end
				end
				if rec.vis == 1 then
					if nm < MAX_MARKS then
						nm = nm + 1
						PaintMark(GetMark(nm), rec, d, alpha, scale, O)
					end
				elseif rec.arrow and na < O.maxArrows and na < MAX_ARROWS then
					na = na + 1
					PaintArrow(GetArrow(na), rec, d, O.alpha, O, sw, sh)
				end
			end
		end
	end
	HideFrom(marks, nm + 1, V.shownMarks)
	HideFrom(arrows, na + 1, V.shownArrows)
	V.shownMarks, V.shownArrows = nm, na
end

function V.Clear()
	HideFrom(marks, 1, getn(marks))
	HideFrom(arrows, 1, getn(arrows))
	V.shownMarks, V.shownArrows = 0, 0
end
