-- HyoukaUI: плоский скин подсказок (spec 3.10) и якорь у правого нижнего угла.
--
-- Скин: фон #080808 0.85, рамка 1 физический пиксель, тексты роли body (шапка title). Шрифты ставятся
-- на шрифтовые объекты игры (GameTooltipText, GameTooltipHeaderText, GameTooltipTextSmall): так они
-- действуют до расчета размера подсказки, а не после.
--
-- Якорь: BOTTOMRIGHT к BOTTOMRIGHT экрана, (-1, 216) ретейл-px (= (-0.5, 115.2) AS при PX 0.5333).
-- Хук ОДИН и без hooksecurefunc (его в игре нет): глобальная GameTooltip_SetDefaultAnchor
-- оборачивается вручную, повторная обертка исключена меткой. Скрипт OnShow подсказок
-- оборачивается так же, с меткой на кадре.
--
-- Tooltip.Skin(tip)        нарисовать скин на подсказке
-- Tooltip.Anchor(tip)      поставить якорь
-- Tooltip.SetLift(px)      поднять якорь на px ретейл-пикселей (окно разбивки над доком)
-- Tooltip.SetProvider(fn)  fn() -> point, relPoint, x, y (ретейл-px) вместо умолчания (Layout)
-- Tooltip.Install() / Tooltip.Remove()

local H = HyoukaUI
local T = H.Theme
local F = H.Fonts

local Tip = {}
H.Tooltip = Tip

Tip.NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }
Tip.FONT_OBJECTS = { GameTooltipHeaderText = "title", GameTooltipText = "body", GameTooltipTextSmall = "small" }
Tip.lift = 0
Tip.provider = nil
Tip.wrapper = nil
Tip.orig = nil
Tip.active = false

local BACKDROP = {
	bgFile = T.TEX.solid, tile = false, tileSize = 0, edgeSize = 0,
	insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function Defaults()
	local d = H.LayoutDefaults
	local p = d and d.pieces and d.pieces["ui.tooltip"]
	if p then
		return p.point or "BOTTOMRIGHT", p.relPoint or "BOTTOMRIGHT", p.x or -1, p.y or 216
	end
	return "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 216
end

function Tip.SetLift(px)
	Tip.lift = px or 0
end

function Tip.SetProvider(fn)
	Tip.provider = fn
end

function Tip.Anchor(tip)
	if not tip or not UIParent then
		return
	end
	local point, relPoint, x, y
	if Tip.provider then
		point, relPoint, x, y = Tip.provider()
	end
	if not point then
		point, relPoint, x, y = Defaults()
	end
	tip:ClearAllPoints()
	tip:SetPoint(point, UIParent, relPoint, H.R(x), H.R(y + Tip.lift))
end

-- Фон и рамка. Рамка создается один раз и красится в черный при каждом показе: игра
-- красит край подсказки по качеству предмета.
function Tip.Skin(tip)
	if not tip.huiSkin then
		tip.huiSkin = true
		tip:SetBackdrop(BACKDROP)
		T.AddBorder(tip, nil, nil, nil, nil, "OVERLAY")
	end
	local c = T.C.panel
	tip:SetBackdropColor(c[1], c[2], c[3], c[4])
	tip:SetBackdropBorderColor(0, 0, 0, 0)
	local b = T.C.border
	T.SetBorderColor(tip, b[1], b[2], b[3], b[4])
end

-- Шрифты тела, шапки и мелкого текста подсказок.
function Tip.ApplyFonts()
	for name, role in pairs(Tip.FONT_OBJECTS) do
		local obj = H.Env[name]
		if obj and obj.SetFont then
			local path, size, flags = F.Role(role)
			obj:SetFont(path, size, flags)
		end
	end
end

local function WrapShow(tip)
	if tip.huiShowHooked then
		return
	end
	tip.huiShowHooked = true
	local old = tip:GetScript("OnShow")
	tip:SetScript("OnShow", function()
		if old then
			old()
		end
		if Tip.active then
			H.Safe("tooltip", Tip.Skin, this)
		end
	end)
end

-- Одна обертка GameTooltip_SetDefaultAnchor. Метка в H.hooks не дает обернуть второй раз.
function Tip.InstallAnchorHook()
	if H.hooks.GameTooltip_SetDefaultAnchor then
		return "exists"
	end
	local orig = H.Env.GameTooltip_SetDefaultAnchor
	if type(orig) ~= "function" then
		return "none"
	end
	local wrapper = function(tooltip, parent)
		orig(tooltip, parent)
		if Tip.active then
			Tip.Anchor(tooltip)
		end
	end
	Tip.orig, Tip.wrapper = orig, wrapper
	H.Env.GameTooltip_SetDefaultAnchor = wrapper
	H.RegisterHook("GameTooltip_SetDefaultAnchor", H.name)
	return "own"
end

function Tip.Install()
	Tip.active = true
	local result = Tip.InstallAnchorHook()
	for i = 1, table.getn(Tip.NAMES) do
		local tip = H.Env[Tip.NAMES[i]]
		if tip and tip.SetBackdrop then
			WrapShow(tip)
			Tip.Skin(tip)
		end
	end
	Tip.ApplyFonts()
	return result
end

-- Снять: обертка возвращается, если поверх нее никто не обернул; иначе она молчит.
function Tip.Remove()
	Tip.active = false
	if Tip.wrapper and H.Env.GameTooltip_SetDefaultAnchor == Tip.wrapper then
		H.Env.GameTooltip_SetDefaultAnchor = Tip.orig
		H.hooks.GameTooltip_SetDefaultAnchor = nil
		Tip.wrapper, Tip.orig = nil, nil
	end
end

H.On("LOGIN", "tooltip", function()
	if not H.DB or H.DB.Get("general", "tooltipSkin") ~= false then
		Tip.Install()
	end
end)

H.On("THEME", "tooltip", function()
	if Tip.active then
		Tip.ApplyFonts()
		for i = 1, table.getn(Tip.NAMES) do
			local tip = H.Env[Tip.NAMES[i]]
			if tip and tip.huiSkin then
				Tip.Skin(tip)
			end
		end
	end
end)

H.On("FONTS", "tooltip", function()
	if Tip.active then
		Tip.ApplyFonts()
	end
end)
