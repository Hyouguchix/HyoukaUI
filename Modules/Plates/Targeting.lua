-- HyoukaUI: Modules\Plates\Targeting, цель, наведение, сквозные клики, порядок кадров и дебаффы цели.
--
-- Цель клиента: плашка цели единственная с альфой 1 (остальные клиент затемняет), с именем цели (Plates.Update решает
-- по S.hasTarget, S.targetName; здесь они обновляются по событию PLAYER_TARGET_CHANGED и раз в 0.25 с вместе с видом цели
-- по AZS_UnitKind). Рамка цели белая, остальные плашки при цели с альфой dimPct.
-- Клики сквозь плашки: камера поворачивается из-под плашки, а клик идет в мир и берет в цель то, на что попал. Клиент
-- возвращает мышь каждой плашке в конце поворота камеры, поэтому в кадре (Plates.Update) мышь забирается снова у всех,
-- кроме плашки под курсором: она одна ловит клик и поднимается над остальными. Плашка под курсором считается руками, раз в
-- 0.05 с: у остальных мыши нет, а у наведенной есть, и подсвечивается белой заливкой 30%.
-- Порядок кадров: боссы над стражами, стражи над элитами, они над остальными, плашка под курсором выше всех. Уровень кадра
-- детей от уровня родителя не наследуется, поэтому поднимается и плашка, и оверлей, и полоса, и иконки.
-- Дебаффы на плашке цели: до 6 иконок над именем из UnitDebuff("target") раз в 0.2 с, только пока включено в настройках.
--
-- Tg.Refresh()     цель клиента и ее вид    Tg.HoverTick()   наведение    Tg.DebuffTick()   дебаффы цели
-- Tg.Raise(o)      уровни кадров плашки     Tg.Reset()       снять наведение и иконки (Выкл)

local H = HyoukaUI

local Pl = H.Plates

local Tg = {}
Pl.Target = Tg

local HOVER_RISE = 40
local MAX_DEBUFFS = 6
local ICON = 18
local FLAT = "Interface\ChatFrame\ChatFrameBackground"

function Tg.Refresh()
	local S = Pl.S
	if UnitExists("target") then
		S.targetName = UnitName("target")
		S.targetKind = H.PlatesData.UnitKind("target")
	else
		S.targetName, S.targetKind = nil, nil
	end
end

function Tg.Raise(o)
	local S = Pl.S
	local rise = o.level + (o.st and o.st.rise or 0)
	if o == S.hovered then
		rise = rise + HOVER_RISE
	end
	o.plate:SetFrameLevel(rise)
	o.frame:SetFrameLevel(rise + 1)
	o.bar:SetFrameLevel(rise + 2)
	local icons = o.debuffs
	if icons then
		for i = 1, MAX_DEBUFFS do
			if icons[i] then
				icons[i]:SetFrameLevel(rise + 3)
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- Наведение
----------------------------------------------------------------------------------------

-- Ближайшая к курсору плашка среди нарисованных, на полосе или имени которой он стоит; никакой, если мышь над окном.
local function PlateUnderMouse()
	local S = Pl.S
	local focus = GetMouseFocus and GetMouseFocus()
	if focus and focus ~= WorldFrame and not focus.huiOverlay then
		return nil
	end
	local x, y = H.PlatesData.Cursor()
	if not x then
		return nil
	end
	local best, bestGap
	for i = 1, S.visN do
		local o = S.vis[i]
		if o.shown then
			local scale = o.bar:GetEffectiveScale()
			local atX, atY = x / scale, y / scale
			local left, right = o.bar:GetLeft(), o.bar:GetRight()
			local bottom, top = o.bar:GetBottom(), o.bar:GetTop()
			if left and bottom then
				if o.named then
					top = o.name:GetTop() or top
				end
				if atX >= left - 2 and atX <= right + 2 and atY >= bottom - 2 and atY <= top + 2 then
					local gap = math.abs(atX - (left + right) / 2) + math.abs(atY - (top + bottom) / 2)
					if not bestGap or gap < bestGap then
						best, bestGap = o, gap
					end
				end
			end
		end
	end
	return best
end

local function SetHovered(o)
	local S = Pl.S
	if o == S.hovered then
		return
	end
	local was = S.hovered
	S.hovered = o
	if was then
		was.hl:Hide()
		Tg.Raise(was)
		if Pl.cfg.clickThrough then
			was.plate:EnableMouse(false)
		end
	end
	if o then
		o.hl:Show()
		Tg.Raise(o)
		o.plate:EnableMouse(true)
	end
end

function Tg.HoverTick()
	if Pl.S.eff ~= "replace" then
		return
	end
	SetHovered(PlateUnderMouse())
end

----------------------------------------------------------------------------------------
-- Дебаффы цели
----------------------------------------------------------------------------------------

local function Icon(o, i)
	local icons = o.debuffs
	if not icons then
		icons = {}
		o.debuffs = icons
	end
	local icon = icons[i]
	if icon then
		return icon
	end
	icon = CreateFrame("Frame", nil, o.bar)
	icon:SetFrameLevel(o.bar:GetFrameLevel() + 1)
	icon.edge = icon:CreateTexture(nil, "BACKGROUND")
	icon.edge:SetTexture(FLAT)
	icon.edge:SetVertexColor(0, 0, 0, 1)
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	icon.tex:SetAllPoints(icon)
	icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon.count = icon:CreateFontString(nil, "OVERLAY")
	icon.count:SetFont(H.Fonts.Path(), 10, "OUTLINE")
	icons[i] = icon
	return icon
end

local function HideIcons(o)
	local icons = o.debuffs
	if icons then
		for i = 1, MAX_DEBUFFS do
			if icons[i] then
				icons[i]:Hide()
			end
		end
	end
end

function Tg.DebuffTick()
	local S = Pl.S
	local o = S.tOverlay
	if S.eff ~= "replace" or not Pl.cfg.debuffs or (o and not o.shown) then
		o = nil
	end
	if S.dbOverlay and S.dbOverlay ~= o then
		HideIcons(S.dbOverlay)
	end
	S.dbOverlay = o
	if not o then
		return
	end
	local u, st = o.u, o.st
	local size = ICON * u
	local lift = 4
	if o.named then
		lift = lift + st.name + 3
	end
	if st.skull and o.skull:IsShown() then
		lift = lift + st.mark
	end
	local path = H.Fonts.Path()
	for i = 1, MAX_DEBUFFS do
		local texture, count = UnitDebuff("target", i)
		if texture then
			local icon = Icon(o, i)
			if icon.u ~= u then
				icon.u = u
				icon:SetWidth(size)
				icon:SetHeight(size)
				icon.edge:ClearAllPoints()
				icon.edge:SetPoint("TOPLEFT", icon, "TOPLEFT", -u, u)
				icon.edge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", u, -u)
				icon.count:SetFont(path, 9 * u, "OUTLINE")
				icon.count:ClearAllPoints()
				icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2 * u, -u)
			end
			local x, y = (i - 1) * (ICON + 3) * u, lift * u
			if icon.px ~= x or icon.py ~= y then
				icon.px, icon.py = x, y
				icon:ClearAllPoints()
				icon:SetPoint("BOTTOMLEFT", o.bar, "TOPLEFT", x, y)
			end
			if icon.path ~= texture then
				icon.path = texture
				icon.tex:SetTexture(texture)
			end
			local stacks = count and count > 1 and count or 0
			if icon.stacks ~= stacks then
				icon.stacks = stacks
				icon.count:SetText(stacks > 1 and stacks or "")
			end
			if not icon:IsShown() then
				icon:Show()
			end
		elseif o.debuffs and o.debuffs[i] then
			o.debuffs[i]:Hide()
		end
	end
end

function Tg.Reset()
	local S = Pl.S
	if S.hovered then
		S.hovered.hl:Hide()
		S.hovered = nil
	end
	if S.dbOverlay then
		HideIcons(S.dbOverlay)
		S.dbOverlay = nil
	end
	for i = 1, table.getn(S.list) do
		HideIcons(S.list[i])
	end
end
