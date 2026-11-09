-- HyoukaUI: Modules\Plates\Style, вид плашки: размеры и шрифты по виду, цвета, полоса долей, метка, рамка, метка рейда.
--
-- Размеры настроек лежат в ретейл-пикселях (физический пиксель при 1440p). Плашка живет в единицах WorldFrame, не
-- UIParent: физический пиксель в ее единицах o.u = Theme.PX * (масштаб UIParent) / (масштаб плашки). Размеры берутся
-- целым числом физических пикселей, чтобы рамка была ровно в 1 пиксель.
--
-- St.Rescale(o, es)        масштаб плашки изменился: пересчитать o.u (вид перерисуется следом)
-- St.Dress(o, kind)        размеры, шрифты, рамка и метка под вид; сбрасывает кэш доли и цвета
-- St.SetShare(o, share)    ширина заливки и текст доли (кэш: пишет только при изменении)
-- St.Paint(o)              цвета по виду, цели (белая рамка) и прозрачности (кэш o.pEdge, o.pAlpha)
-- St.Marker(o, kind, cfg)  режим Рядом: только метка вида над плашкой
-- St.PlaceRaid(o)          значок рейдовой метки клиента слева от полосы
-- Покадровые функции без аллокаций: таблиц, строк и замыканий в них нет.

local H = HyoukaUI

local Pl = H.Plates

local St = {}
Pl.Style = St

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local TEX = "Interface\\AddOns\\HyoukaUI\\Media\\Textures\\"
St.FLAT, St.TEX = FLAT, TEX

local floor = math.floor

local EDGE = { 0, 0, 0 }          -- рамка: черная, у цели белая, у друзей золотая
local TARGET_EDGE = { 1, 1, 1 }
local RIM = { 0.85, 0.68, 0.20 }
local BACK = { 0.031, 0.031, 0.031 }

-- Физический пиксель в единицах плашки.
function St.Unit(plate)
	local ui = UIParent:GetEffectiveScale()
	local es = plate:GetEffectiveScale()
	if not es or es <= 0 then
		es = ui
	end
	return H.Theme.PX * ui / es
end

function St.Rescale(o, es)
	o.escale = es
	o.u = St.Unit(o.plate)
	o.kind = nil
end

local function Px(n, u)
	return floor(n + 0.5) * u
end

-- Одна из четырех полосок рамки снаружи полосы, толщиной e.
local function Strip(o, i, e)
	local t = o.edge[i]
	t:ClearAllPoints()
	if i == 1 then
		t:SetPoint("BOTTOMLEFT", o.bar, "TOPLEFT", -e, 0)
		t:SetPoint("BOTTOMRIGHT", o.bar, "TOPRIGHT", e, 0)
		t:SetHeight(e)
	elseif i == 2 then
		t:SetPoint("TOPLEFT", o.bar, "BOTTOMLEFT", -e, 0)
		t:SetPoint("TOPRIGHT", o.bar, "BOTTOMRIGHT", e, 0)
		t:SetHeight(e)
	elseif i == 3 then
		t:SetPoint("TOPRIGHT", o.bar, "TOPLEFT", 0, 0)
		t:SetPoint("BOTTOMRIGHT", o.bar, "BOTTOMLEFT", 0, 0)
		t:SetWidth(e)
	else
		t:SetPoint("TOPLEFT", o.bar, "TOPRIGHT", 0, 0)
		t:SetPoint("BOTTOMLEFT", o.bar, "BOTTOMRIGHT", 0, 0)
		t:SetWidth(e)
	end
end

-- Значок рейдовой метки клиента слева от полосы (клиент возвращает его якорь при смене размера окна).
function St.PlaceRaid(o)
	local raid = o.stock.raid
	if not raid or not o.st then
		return
	end
	local u = o.u
	local size = floor(o.st.h + 8 + 0.5)
	if size < 16 then
		size = 16
	end
	raid:ClearAllPoints()
	raid:SetPoint("RIGHT", o.bar, "LEFT", -3 * u, 0)
	raid:SetWidth(size * u)
	raid:SetHeight(size * u)
end

-- Метка вида над именем (Вместо) или над плашкой (Рядом).
local function PlaceMark(o, st, replace)
	local skull = o.skull
	local u = o.u
	skull:ClearAllPoints()
	if replace then
		skull:SetPoint("BOTTOM", o.name, "TOP", 0, u)
	else
		skull:SetPoint("BOTTOM", o.frame, "TOP", 0, 2 * u)
	end
	if st.skull then
		skull:SetTexture(TEX..st.skull)
		skull:SetWidth(floor(st.mark + 0.5) * u)
		skull:SetHeight(floor(st.mark + 0.5) * u)
	end
end

function St.Dress(o, kind)
	local cfg = Pl.cfg
	local st = cfg.st[kind]
	local u = o.u
	o.kind, o.st = kind, st
	local replace = Pl.S.eff == "replace"
	o.wpx = floor(st.w + 0.5)
	o.hpx = floor(st.h + 0.5)
	o.across, o.percent, o.painted = nil, nil, nil
	o.bar:SetWidth(o.wpx * u)
	o.bar:SetHeight(o.hpx * u)
	o.fill:SetHeight(o.hpx * u)
	local e = (st.rim and 2 or 1) * u
	for i = 1, 4 do
		Strip(o, i, e)
	end
	local path = H.Fonts.Path()
	o.name:SetFont(path, Px(st.name, u), "OUTLINE")
	o.share:SetFont(path, Px(st.share, u), "OUTLINE")
	o.share:ClearAllPoints()
	o.share:SetPoint("RIGHT", o.bar, "RIGHT", -3 * u, 0)
	if cfg.shareText then
		o.share:Show()
	else
		o.share:Hide()
	end
	local named = cfg.names == "all" or (cfg.names == "special" and kind ~= "normal")
	o.named = named
	if named then
		o.name:Show()
	else
		o.name:Hide()
	end
	PlaceMark(o, st, replace)
	o.markOn = false
	if replace and st.skull and cfg.marks and named then
		o.skull:Show()
	else
		o.skull:Hide()
	end
	-- Подъем кадров: боссы над стражами, стражи над элитами, они над остальными; наведенная над всеми.
	Pl.Target.Raise(o)
	if replace then
		St.PlaceRaid(o)
	end
end

function St.SetShare(o, share)
	local filled = floor(share * o.wpx + 0.5)
	if filled ~= o.across then
		o.across = filled
		if filled <= 0 then
			o.fill:Hide()
		else
			o.fill:SetWidth(filled * o.u)
			o.fill:Show()
		end
	end
	local percent = floor(share * 100 + 0.5)
	if percent == 0 and share > 0 then
		percent = 1
	end
	if percent ~= o.percent then
		o.percent = percent
		o.share:SetText(Pl.PCT[percent])
	end
end

-- Цвета: заливка цветом вида (у союзника из группы цветом класса), темная подложка, рамка, тексты, метка. Все с
-- прозрачностью плашки: в этой игре альфа кадра не умножается на альфу детей, затемнение лежит в цветах.
function St.Paint(o)
	local st = o.st
	local a = o.pAlpha
	local r, g, b = st.r, st.g, st.b
	if o.cr then
		r, g, b = o.cr, o.cg, o.cb
	end
	o.fill:SetVertexColor(r, g, b, a)
	o.back:SetVertexColor(BACK[1], BACK[2], BACK[3], 0.85 * a)
	local c = EDGE
	if st.rim then
		c = RIM
	end
	if o.pEdge == 1 then
		c = TARGET_EDGE
	end
	for i = 1, 4 do
		o.edge[i]:SetVertexColor(c[1], c[2], c[3], a)
	end
	o.name:SetTextColor(1, 1, 1, a)
	o.share:SetTextColor(1, 1, 1, a)
	o.skull:SetVertexColor(r, g, b, a)
	o.painted = true
end

-- Режим Рядом: полосы нет, поверх стоковой плашки одна метка вида у элит, стражей и боссов.
function St.Marker(o, kind, cfg)
	local st = o.st
	local on = st.skull and cfg.marks
	if on and not o.markOn then
		o.markOn = true
		o.skull:SetVertexColor(st.r, st.g, st.b, 1)
		o.skull:Show()
	elseif not on and o.markOn then
		o.markOn = false
		o.skull:Hide()
	end
end
