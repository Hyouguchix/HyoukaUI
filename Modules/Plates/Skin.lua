-- HyoukaUI: Modules\Plates\Skin, захват стоковых плашек клиента 1.12 и их оформление.
--
-- Клиент владеет кадрами плашек: это безымянные дети WorldFrame, опознаются по первому региону, текстуре рамки
-- Interface\Tooltips\Nameplate-Border. Новые плашки только дописываются в конец детей WorldFrame, поэтому каждый кадр
-- сравнивается число детей (Scan), а список просматривается только при его росте. Клиент держит пул плашек и передает
-- их от юнита к юниту, поэтому наш кадр-оверлей живет столько же, сколько плашка, а вид перечитывается каждый кадр.
--
-- Оверлей o (создается один раз на плашку): o.plate, o.stock { health, name, level, raid, сохраненные регионы },
-- o.frame (на всю плашку), o.bar (полоса по центру), o.back, o.fill, o.edge[1..4], o.hl (наведение), o.name, o.share,
-- o.skull (метка вида), o.debuffs (лениво, Targeting). Стоковая графика гасится (текстуры пустые, строки шириной 0.001,
-- текстура полосы пустая) и возвращается Unblank из сохраненного: путь текстуры, текстурные координаты (если игра их
-- отдает, иначе полный квадрат), ширина строки. Плашка SurvivorPlates (plate.survivorOverlay) не трогается никогда.
--
-- Sk.Scan()           найти новые плашки (покадрово: одно сравнение числа детей)
-- Sk.Collect() -> n, bright    видимые плашки в Pl.S.vis; bright = сколько из них с альфой 1 (цель клиента видна одна)
-- Sk.Yield(o)         плашка занята SurvivorPlates: наши кадры на ней скрыты
-- Sk.Engage(o, eff)   привести плашку к режиму: "replace" гасит стоковое и показывает полосу, "side" возвращает стоковое и
--                     оставляет метку, "off" возвращает все и скрывает наши кадры

local H = HyoukaUI

local Pl = H.Plates

local Sk = {}
Pl.Skin = Sk

local BORDER_TEXTURE = "Interface\\Tooltips\\Nameplate-Border"
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local getn = table.getn

local function IsNameplate(frame)
	local region = frame:GetRegions()
	return region and region.GetObjectType and region:GetObjectType() == "Texture" and region:GetTexture() == BORDER_TEXTURE
end

-- Что стоит в стоковых регионах плашки: чтобы вернуть как было.
local function Remember(stock, regions, count)
	stock.regions, stock.paths, stock.coords, stock.widths = regions, {}, {}, {}
	for i = 1, count do
		local region = regions[i]
		local kind = region:GetObjectType()
		if kind == "Texture" then
			stock.paths[i] = region:GetTexture()
			if region.GetTexCoord then
				local a, b, c, d, e, f, g, h = region:GetTexCoord()
				if a then
					stock.coords[i] = { a, b, c, d, e, f, g, h }
				end
			end
		elseif kind == "FontString" then
			stock.widths[i] = region:GetWidth()
		end
	end
	local tex = stock.health.GetStatusBarTexture and stock.health:GetStatusBarTexture()
	stock.barTex = tex and tex.GetTexture and tex:GetTexture() or nil
end

local function Blank(o)
	local stock = o.stock
	local regions = stock.regions
	for i = 1, getn(regions) do
		local region = regions[i]
		local kind = region:GetObjectType()
		if kind == "Texture" then
			if region ~= stock.raid then
				region:SetTexture("")
				region:SetTexCoord(0, 0, 0, 0)
			end
		elseif kind == "FontString" then
			region:SetWidth(0.001)
		end
	end
	stock.health:SetStatusBarTexture("")
	o.blanked = true
end

local function Unblank(o)
	local stock = o.stock
	local regions = stock.regions
	for i = 1, getn(regions) do
		local region = regions[i]
		local kind = region:GetObjectType()
		if kind == "Texture" then
			if region ~= stock.raid and stock.paths[i] then
				region:SetTexture(stock.paths[i])
				local c = stock.coords[i]
				if c then
					region:SetTexCoord(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
				else
					region:SetTexCoord(0, 1, 0, 1)
				end
			end
		elseif kind == "FontString" then
			region:SetWidth(stock.widths[i] or 0)
		end
	end
	if stock.barTex then
		stock.health:SetStatusBarTexture(stock.barTex)
	end
	if stock.raid then
		stock.raid:SetAlpha(1)
	end
	o.blanked = false
end

local function Flat(parent, layer)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(FLAT)
	return t
end

-- Построить оверлей на плашке. Возвращает nil, если плашка не похожа на ожидаемую (нет полосы или имени).
local function Make(plate)
	local stock = {}
	stock.health = plate:GetChildren()
	if not stock.health or not stock.health.GetMinMaxValues then
		return nil
	end
	local regions = { plate:GetRegions() }
	local count = getn(regions)
	-- Регионы: рамка, свечение, имя, уровень, значок уровня, значок рейдовой метки. Две строки идут в этом порядке,
	-- значок метки это последняя текстура: он остается и переставляется.
	if count > 0 and regions[count]:GetObjectType() == "Texture" then
		stock.raid = regions[count]
	end
	for i = 1, count do
		if regions[i]:GetObjectType() == "FontString" then
			if not stock.name then
				stock.name = regions[i]
			elseif not stock.level then
				stock.level = regions[i]
			end
		end
	end
	if not stock.name then
		return nil
	end
	Remember(stock, regions, count)

	local o = { plate = plate, stock = stock, u = 1, level = plate:GetFrameLevel(), shown = false, claimAt = -100,
		edge = {}, kindsVer = 0 }
	plate.huiOverlay = o
	o.frame = CreateFrame("Frame", nil, plate)
	o.frame:SetAllPoints(plate)
	o.bar = CreateFrame("Frame", nil, o.frame)
	o.bar:SetPoint("CENTER", o.frame, "CENTER", 0, 0)
	o.back = Flat(o.bar, "BACKGROUND")
	o.back:SetAllPoints(o.bar)
	o.fill = Flat(o.bar, "BORDER")
	o.fill:SetPoint("TOPLEFT", o.bar, "TOPLEFT", 0, 0)
	o.fill:SetPoint("BOTTOMLEFT", o.bar, "BOTTOMLEFT", 0, 0)
	for i = 1, 4 do
		o.edge[i] = Flat(o.bar, "ARTWORK")
	end
	o.hl = Flat(o.bar, "ARTWORK")
	o.hl:SetAllPoints(o.bar)
	o.hl:SetVertexColor(1, 1, 1, 0.3)
	o.hl:Hide()
	o.name = o.bar:CreateFontString(nil, "OVERLAY")
	o.name:SetPoint("BOTTOM", o.bar, "TOP", 0, 2)
	o.name:SetFont(H.Fonts.Path(), 12, "OUTLINE")
	o.share = o.bar:CreateFontString(nil, "OVERLAY")
	o.share:SetFont(H.Fonts.Path(), 11, "OUTLINE")
	o.share:SetShadowOffset(0, 0)
	o.skull = o.frame:CreateTexture(nil, "OVERLAY")
	o.skull:Hide()
	o.bar:Hide()
	return o
end

-- Привести плашку к режиму (Pl.Apply зовет для каждой, Scan для новых).
function Sk.Engage(o, eff)
	o.eff = eff
	o.kind, o.lastName = nil, nil
	o.shown, o.markOn = false, false
	o.bar:Hide()
	if eff == "replace" then
		if not o.blanked then
			Blank(o)
		end
		o.frame:Show()
	else
		if o.blanked then
			Unblank(o)
		end
		o.skull:Hide()
		o.hl:Hide()
		o.plate:EnableMouse(true)
		if eff == "off" then
			o.frame:Hide()
		else
			o.frame:Show()
		end
	end
	if Pl.S.hovered == o then
		Pl.S.hovered = nil
	end
end

-- Плашку взял SurvivorPlates: наши кадры на ней прячутся, стоковая графика остается как есть (ее гасит он).
function Sk.Yield(o)
	o.eff = "foreign"
	o.kind, o.lastName = nil, nil
	o.shown, o.markOn = false, false
	o.bar:Hide()
	o.skull:Hide()
	o.hl:Hide()
	o.frame:Hide()
	if Pl.S.hovered == o then
		Pl.S.hovered = nil
	end
end

-- Новые плашки: только дописываются в конец детей WorldFrame. Список создается только при росте числа детей.
function Sk.Scan()
	local S = Pl.S
	local count = WorldFrame:GetNumChildren() or 0
	if count == S.scanned then
		return
	end
	local children = { WorldFrame:GetChildren() }
	for i = S.scanned + 1, count do
		local child = children[i]
		if child and not child.huiOverlay then
			if child.survivorOverlay then
				S.foreignSkipped = S.foreignSkipped + 1
			elseif IsNameplate(child) then
				local o = Make(child)
				if o then
					table.insert(S.list, o)
					Sk.Engage(o, S.eff)
				end
			end
		end
	end
	S.scanned = count
end

-- Видимые плашки в массив S.vis (без аллокаций) и число плашек с альфой 1.
--@frame
function Sk.Collect()
	local S = Pl.S
	local list, vis = S.list, S.vis
	local n, bright = 0, 0
	for i = 1, getn(list) do
		local o = list[i]
		if o.plate:IsVisible() then
			n = n + 1
			vis[n] = o
			if o.plate:GetAlpha() == 1 then
				bright = bright + 1
			end
		elseif o.shown then
			o.shown = false
			o.bar:Hide()
		end
	end
	S.visN = n
	return n, bright
end
