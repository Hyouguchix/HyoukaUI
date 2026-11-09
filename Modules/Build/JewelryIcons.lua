-- HyoukaUI: модуль Build, ряд значков бижутерии над рамкой игрока (кусок uf.jewelry, plan 3.1).
--
-- 5 значков 34 ретейл-px через 1, рост влево от правого края рамки игрока: шея, кольцо, кольцо, аксессуар,
-- аксессуар. Рамка значка цвета качества (выше обычного, иначе черная, плоский стиль spec 1.3), ранг римской
-- цифрой цветом качества в углу, шторка внутреннего кулдауна из таймеров движка (H.Buffs.Timers: таймер вида
-- "cooldown" сопоставляется со слотом по пути значка, запасной вариант - имя таймера внутри имени предмета),
-- подсказка предмета (SetInventoryItem). Данные слотов дает Jewelry.lua.
-- Кадр с глобальным именем HyoukaUI_JewelryList (нужно AZS_SetOnTopOfScreens: значки видны и кликабельны
-- на экране карточек). Создается при первом Ensure, не при загрузке файла.
-- Якорь куска задает Layout по LayoutDefaults (BOTTOMRIGHT к TOPRIGHT uf.player). Если куска uf.player нет
-- (модуль рамок выключен), Layout берет fallback: он считается здесь из тех же LayoutDefaults, без чисел в коде.
-- [НЕ ПРОВЕРЕНО] что путь значка таймера совпадает с путем значка предмета (см. handoff_build.md).

local H = HyoukaUI
local B = H.Build
local J = B.Jewelry

local I = {}
B.JewelryIcons = I

local ICON, GAP = 34, 1
local frame
local icons = {}
local cdRem, cdDur = { 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0 }
local laidOut = false

-- Запасной якорь от центра экрана: правый верхний угол рамки игрока из LayoutDefaults.
local function Fallback()
	local pieces = H.LayoutDefaults and H.LayoutDefaults.pieces
	local p = pieces and pieces["uf.player"]
	local me = pieces and pieces["uf.jewelry"]
	if not p or not me then
		return nil
	end
	return { point = "BOTTOMRIGHT", relPoint = p.relPoint or "CENTER",
		x = (p.x or 0) + (p.w or 0) / 2, y = (p.y or 0) + (p.h or 0) / 2 + (me.y or 1) }
end

local function Place()
	for i = 1, 5 do
		icons[i]:ClearAllPoints()
		icons[i]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(i - 1) * H.R(ICON + GAP), 0)
	end
end

local function MakeIcon(i)
	local icon = H.Icon.New(frame, { size = ICON })
	icon.rank = H.Text.New(icon, "small", { justify = "RIGHT", layer = "OVERLAY" })
	icon.rank:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -H.R(2), H.R(2))
	icon.slotIndex = i
	icon:EnableMouse(true)
	H.Script("build", icon, "OnEnter", function(self)
		local rec = J.Slot(i)
		if rec.link then
			GameTooltip:SetOwner(icon, "ANCHOR_TOPRIGHT")
			GameTooltip:SetInventoryItem("player", rec.id)
			GameTooltip:Show()
		end
	end)
	H.Script("build", icon, "OnLeave", function(self)
		GameTooltip:Hide()
	end)
	return icon
end

-- Создать кадр и значки (один раз) и зарегистрировать кусок в Layout.
function I.Ensure()
	if not frame then
		frame = CreateFrame("Frame", "HyoukaUI_JewelryList", UIParent)
		frame:SetFrameStrata("MEDIUM")
		for i = 1, 5 do
			icons[i] = MakeIcon(i)
		end
		Place()
	end
	H.Layout.Piece("uf.jewelry", frame, { fallback = Fallback() })
	return frame
end

function I.Frame()
	return frame
end

function I.Icon(i)
	return icons[i]
end

function I.Remove()
	if frame then
		frame:Hide()
		H.Layout.Unpiece("uf.jewelry")
	end
end

-- Внешний вид значка i по данным слота. showEmpty: пустой слот остается бледным значком.
function I.UpdateIcon(i, showEmpty)
	local icon = icons[i]
	local rec = J.Slot(i)
	if rec.link then
		icon:Show()
		icon:SetAlpha(1)
		H.Icon.SetTexture(icon, rec.tex)
		if rec.quality > 1 then
			H.Icon.SetBorderColor(icon, rec.r, rec.g, rec.b, 1)
		else
			local c = H.Theme.C.border
			H.Icon.SetBorderColor(icon, c[1], c[2], c[3], c[4])
		end
		if rec.rank then
			icon.rank:SetTextColor(rec.r, rec.g, rec.b, 1)
			icon.rank:SetText(H.Format.Roman(rec.rank))
		else
			icon.rank:SetText("")
		end
	elseif showEmpty then
		icon:Show()
		icon:SetAlpha(0.35)
		H.Icon.SetTexture(icon, nil)
		H.Icon.Clear(icon)
		icon.rank:SetText("")
	else
		icon:Hide()
	end
end

function I.Update(showEmpty)
	if not frame then
		return
	end
	for i = 1, 5 do
		I.UpdateIcon(i, showEmpty)
	end
end

-- Число показанных значков.
function I.ShownCount()
	local n = 0
	for i = 1, 5 do
		if icons[i] and icons[i]:IsShown() then
			n = n + 1
		end
	end
	return n
end

----------------------------------------------------------------------------------------
-- Внутренние кулдауны (шторка)
----------------------------------------------------------------------------------------

local function OnTimer(name, texture, kind, duration, remaining, ready)
	if kind ~= "cooldown" or ready or remaining <= 0 then
		return
	end
	for i = 1, 5 do
		local rec = J.Slot(i)
		if rec.link and cdRem[i] == 0 then
			if (texture ~= nil and rec.tex == texture) or (name ~= nil and rec.name and string.find(rec.name, name, 1, true)) then
				cdRem[i], cdDur[i] = remaining, duration or remaining
				return
			end
		end
	end
end

-- Шторка по таймерам: без таблиц, повторная установка только при заметном сдвиге начала.
function I.Tick()
	if not frame then
		return
	end
	for i = 1, 5 do
		cdRem[i], cdDur[i] = 0, 0
	end
	H.Buffs.Timers(OnTimer)
	local now = H.Now()
	for i = 1, 5 do
		local icon = icons[i]
		if cdRem[i] > 0 then
			local start = now - (cdDur[i] - cdRem[i])
			if icon.cdKind == 0 or math.abs(start - icon.cdStart) > 0.3 or icon.cdDur ~= cdDur[i] then
				H.Icon.SetCooldown(icon, start, cdDur[i])
			end
		elseif icon.cdKind ~= 0 then
			H.Icon.Clear(icon)
		end
	end
end

function I.Reflow()
	if frame then
		Place()
	end
end

B.AddPart("icons", function(M)
	B.Listen("THEME", I.Reflow)
	B.Listen("LOCALE", I.Reflow)
end, function()
	I.Remove()
end)
