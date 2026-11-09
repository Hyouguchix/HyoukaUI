-- HyoukaUI: Frames\UnitFrame, общий каркас рамки юнита для игрока и цели (plan 3.1, spec 3.1).
--
-- Рамка 272x45 ретейл-px (145.1x24.0 AS при PX 0.5333): полоса здоровья без плавности (Widgets\Bar), рамка 1 px,
-- тексты, щит (полосатая текстура акцентом от края заливки, излишек от левого края), необязательные полоска
-- ресурса 5 ретейл-px (около 3 AS) и портрет. Стиль полосы: "dark" (ретейл dark mode: остаток #111111 0.9 на
-- потерянном #4F4F4F) или "class" (цвет класса и красный враг на #111111). Клики: левый - выбор цели, правый -
-- стоковое меню (TargetUnit и ToggleDropDownMenu из OnClick проверены пробой 0.10).
--
-- Тексты заданы относительно кадра в ретейл-px: right (RIGHT -1,+2), left (LEFT +3,+15), sub (LEFT +3,-12),
-- res (RIGHT -3,-12). Все установки текста кэшируются: строка собирается только при смене показываемого.
--
-- U.New(unit, dropdownName) -> uf; U.Style(uf); U.SetFill(uf, r, g, b); U.SetHp(fs, cur, max, mode, label);
-- U.SetName(fs, text, r, g, b, maxWidth); U.Power(uf); U.Portrait(uf); U.Shield(uf, amount, max).

local H = HyoukaUI
local F = H.Frames
local T = H.Theme
local P = H.Panel
local Bar = H.Bar
local Fm = H.Format

local U = {}
F.UnitFrame = U

U.W, U.H = 272, 45
U.POWER_H = 5
U.ENEMY = { 0.80, 0.22, 0.22 }

local CLICK_NAMES = { player = "HyoukaUI_PlayerClick", target = "HyoukaUI_TargetClick" }
local POWER_KIND = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy" }

local function Label(bar, point, x, y, justify)
	local fs = H.Text.New(bar, "body", { justify = justify })
	fs:SetPoint(point, bar, point, H.R(x), H.R(y))
	return fs
end

-- Меню по правому клику: стоковое выпадающее меню юнита.
local function Menu(uf)
	local toggle = H.Env.ToggleDropDownMenu
	local dd = uf.dropdown and H.Env[uf.dropdown]
	if type(toggle) == "function" and dd then
		pcall(toggle, 1, nil, dd, uf.bar, uf.menuX, uf.menuY)
	end
end

local function OnClick(uf, button)
	if button == "RightButton" then
		Menu(uf)
	elseif uf.unit == "player" then
		local pick = H.Env.TargetUnit
		if type(pick) == "function" then
			pcall(pick, "player")
		end
	end
end

function U.New(unit, dropdown, menuX, menuY)
	local uf = { unit = unit, dropdown = dropdown, menuX = menuX or 0, menuY = menuY or 0 }
	local bar = Bar.New(UIParent, { w = U.W, h = U.H, bg = T.C.darkLost })
	bar:SetFrameStrata("LOW")
	bar:Hide()
	uf.bar = bar
	-- полосатые текстуры щита создаются до текстов, чтобы лежать под ними
	Bar.SetOverlay(bar, 0, 1)
	uf.shield, uf.shieldMax = 0, 0
	uf.right = Label(bar, "RIGHT", -1, 2, "RIGHT")
	uf.left = Label(bar, "LEFT", 3, 15, "LEFT")
	uf.sub = Label(bar, "LEFT", 3, -12, "LEFT")
	uf.res = Label(bar, "RIGHT", -3, -12, "RIGHT")
	-- Стоковое меню читает имя кадра-источника (this:GetName() внутри ToggleDropDownMenu в 1.12) [НЕ ПРОВЕРЕНО]:
	-- кнопке клика нужно имя, оно допустимо только из H.FRAME_NAMES (CORE REQUEST в записке). Без записи в
	-- списке кнопка остается безымянной, и если меню не откроется, в игре проверить это.
	local name = CLICK_NAMES[unit]
	if not (name and H.FRAME_NAMES and H.FRAME_NAMES[name]) then
		name = nil
	end
	local btn = CreateFrame("Button", name, bar)
	btn:SetAllPoints(bar)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	F.M:Script(btn, "OnClick", function(self, button)
		OnClick(uf, button)
	end)
	uf.btn = btn
	U.Style(uf)
	return uf
end

-- Стиль полосы по настройке: фон и цвет заливки по умолчанию.
function U.Style(uf)
	uf.fillKey = nil
	if F.Opt("barStyle") == "class" then
		P.SetBg(uf.bar, "darkRest")
	else
		P.SetBg(uf.bar, "darkLost")
		local d = T.C.darkRest
		Bar.SetColor(uf.bar, d[1], d[2], d[3])
	end
end

-- Цвет заливки: только в стиле class (в dark цвет остается остатком #111111).
function U.SetFill(uf, r, g, b)
	if F.Opt("barStyle") ~= "class" then
		return
	end
	local key = r * 1000000 + g * 1000 + b
	if uf.fillKey ~= key then
		uf.fillKey = key
		Bar.SetColor(uf.bar, r, g, b)
	end
end

-- Текст здоровья: mode 0 "315K | 100%", 1 только процент, label (DEAD, DOWN) вместо чисел.
function U.SetHp(fs, cur, max, mode, label)
	if fs.uCur == cur and fs.uMax == max and fs.uMode == mode and fs.uLabel == label then
		return
	end
	fs.uCur, fs.uMax, fs.uMode, fs.uLabel = cur, max, mode, label
	local text
	if label then
		text = label
	elseif not max or max <= 0 then
		text = ""
	elseif mode == 1 then
		text = Fm.Pct(cur, max).."%"
	else
		text = Fm.HpText(cur, max)
	end
	H.Text.Set(fs, text)
end

-- Имя с обрезкой по ширине и цветом; пересчет только при смене строки или цвета.
function U.SetName(fs, text, r, g, b, maxWidth)
	if fs.uName ~= text then
		fs.uName = text
		H.Text.Fit(fs, text, maxWidth)
	end
	local key = r * 1000000 + g * 1000 + b
	if fs.uColor ~= key then
		fs.uColor = key
		fs:SetTextColor(r, g, b, 1)
	end
end

function U.Shield(uf, amount, max)
	if not F.Opt("shield") then
		amount = 0
	end
	if uf.shield == amount and uf.shieldMax == max then
		return
	end
	uf.shield, uf.shieldMax = amount, max
	if amount > 0 and max > 0 then
		Bar.SetOverlay(uf.bar, amount, max)
	else
		Bar.ClearOverlay(uf.bar)
	end
end

----------------------------------------------------------------------------------------
-- Ресурс и портрет (необязательные)
----------------------------------------------------------------------------------------

function U.Power(uf)
	if not F.Opt("power") then
		if uf.power then
			uf.power:Hide()
		end
		return
	end
	local pb = uf.power
	if not pb then
		pb = Bar.New(uf.bar, { w = U.W, h = U.POWER_H, bg = "dock" })
		pb:SetPoint("BOTTOMLEFT", uf.bar, "BOTTOMLEFT", 0, 0)
		uf.power = pb
	end
	local unit = uf.unit
	local cur, max = F.Unit("UnitMana", unit), F.Unit("UnitManaMax", unit)
	if not max or max <= 0 then
		pb:Hide()
		return
	end
	pb:Show()
	local kind = POWER_KIND[F.Unit("UnitPowerType", unit) or 0]
	Bar.SetColor(pb, T.ResourceColor(kind))
	Bar.Set(pb, cur or 0, max)
end

function U.Portrait(uf)
	if not F.Opt("portrait") then
		if uf.portrait then
			uf.portrait:Hide()
		end
		return
	end
	local pf = uf.portrait
	if not pf then
		pf = CreateFrame("Frame", nil, uf.bar)
		pf:SetWidth(H.R(U.H))
		pf:SetHeight(H.R(U.H))
		if uf.unit == "player" then
			pf:SetPoint("RIGHT", uf.bar, "LEFT", -H.R(1), 0)
		else
			pf:SetPoint("LEFT", uf.bar, "RIGHT", H.R(1), 0)
		end
		P.SetBg(pf, "iconBg")
		T.AddBorder(pf, nil, nil, nil, nil, "OVERLAY")
		local tex = pf:CreateTexture(nil, "ARTWORK")
		local b = T.Border()
		tex:SetPoint("TOPLEFT", pf, "TOPLEFT", b, -b)
		tex:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -b, b)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		pf.huiTex = tex
		uf.portrait = pf
	end
	pf:Show()
	local set = H.Env.SetPortraitTexture
	if type(set) == "function" then
		pcall(set, pf.huiTex, uf.unit)
	end
end
