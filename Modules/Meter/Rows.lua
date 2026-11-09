-- HyoukaUI: Modules\Meter\Rows.lua, строка-полоса счетчика в плоском стиле (spec 3.7, 1.5).
--
-- Строка: полоса H.Bar (белая текстура x 0.76 цвета источника или класса, рамка 1 физический пиксель), слева значок
-- (иконка источника из снимка или значок класса героя), имя 13 белым, тег "(proc)" светло-синим, справа число.
-- Строки создает H.List (пул), здесь только содержимое: R.Create(row, list, spec) один раз на строку-кадр,
-- R.Update(row, item, idx, list) на каждое обновление. Update не создает таблиц, замыканий и строк, пока строка
-- модели не изменилась: тексты ставятся только при смене показанных чисел.
--
-- spec = { wpx, hpx (ретейл-px), wide (разбивка: три числа справа: скорость, сумма, доля) }.
-- list.huiView и list.huiTop ставит владелец списка (Dock, Breakdown) перед List.SetItems.
-- Число справа в доке (MU.opt.right): "dps" только в секунду (решение 6, ретейл), "total" сумма, "full" сумма (в сек, %).

local H = HyoukaUI
local MU = H.MeterUI
local T = H.Theme
local B = H.Bar
local X = H.Text
local Fm = H.Format

local R = {}
MU.Rows = R

local TAG_COLOR = { 0.6235, 0.749, 1.0, 1 }
local ZOOM = 0.08

-- Ширины колонок разбивки, ретейл-px.
R.WIDE_PCT, R.WIDE_AMOUNT, R.WIDE_RATE = 40, 62, 62

local function Pad()
	return H.R(3)
end

-- Размеры и якорь значка, якоря чисел: зависят от PX, поэтому вызываются и на создании, и на THEME.
function R.Relayout(row)
	local spec = row.huiSpec
	local bar = row.huiBar
	local b = T.Border()
	local pad = Pad()
	local side = H.R(spec.hpx) - 2 * b
	row.huiSide = side
	local icon = row.huiIcon
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", bar, "TOPLEFT", b, -b)
	icon:SetWidth(side)
	icon:SetHeight(side)
	row.huiRight:ClearAllPoints()
	row.huiRight:SetPoint("RIGHT", bar, "RIGHT", -pad, 0)
	if spec.wide then
		row.huiMid:ClearAllPoints()
		row.huiMid:SetPoint("RIGHT", bar, "RIGHT", -(pad + H.R(R.WIDE_PCT)), 0)
		row.huiRate:ClearAllPoints()
		row.huiRate:SetPoint("RIGHT", bar, "RIGHT", -(pad + H.R(R.WIDE_PCT + R.WIDE_AMOUNT)), 0)
	end
	row.huiNameText = nil
end

function R.RelayoutList(list)
	for i = 1, table.getn(list.huiRows) do
		R.Relayout(list.huiRows[i])
	end
end

function R.Create(row, list, spec)
	local hpx = spec.hpx
	local bar = B.New(row, { w = spec.wpx, h = hpx, bg = "dock" })
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.huiBar = bar
	row.huiSpec = spec
	-- Значок на своем кадре выше полосы: порядок слоев одного кадра у заливки и значка нестабилен (часть значков пропадала).
	local iconHost = CreateFrame("Frame", nil, bar)
	iconHost:SetAllPoints(bar)
	iconHost:SetFrameLevel(bar:GetFrameLevel() + 3)
	local icon = iconHost:CreateTexture(nil, "OVERLAY")
	icon:Hide()
	row.huiIcon = icon
	local name = X.New(bar, "body", { layer = "OVERLAY" })
	row.huiNameFS = name
	local right = X.New(bar, "body", { layer = "OVERLAY", justify = "RIGHT" })
	row.huiRight = right
	local tag = X.New(bar, "small", { layer = "OVERLAY", justify = "RIGHT", color = TAG_COLOR })
	tag:Hide()
	row.huiTag = tag
	if spec.wide then
		row.huiMid = X.New(bar, "body", { layer = "OVERLAY", justify = "RIGHT" })
		row.huiRate = X.New(bar, "body", { layer = "OVERLAY", justify = "RIGHT" })
	end
	R.Relayout(row)
	local btn = CreateFrame("Button", nil, row)
	btn:SetAllPoints(row)
	btn:SetFrameLevel(bar:GetFrameLevel() + 3)
	btn:EnableMouse(true)
	btn:EnableMouseWheel(true)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hover = btn:CreateTexture(nil, "ARTWORK")
	hover:SetTexture(T.TEX.solid)
	hover:SetAllPoints(btn)
	local hc = T.C.hover
	hover:SetVertexColor(hc[1], hc[2], hc[3], hc[4])
	hover:Hide()
	row.huiBtn, row.huiHover = btn, hover
	H.Script(MU.OWNER, btn, "OnEnter", function()
		hover:Show()
		MU.Card.Hover(row)
	end)
	H.Script(MU.OWNER, btn, "OnLeave", function()
		hover:Hide()
		MU.Card.Unhover(row)
	end)
	H.Script(MU.OWNER, btn, "OnClick", function(self, button)
		if spec.wide then
			MU.Breakdown.RowClick(row, button)
		else
			MU.Dock.RowClick(row, button)
		end
	end)
	H.Script(MU.OWNER, btn, "OnMouseWheel", function(self, delta)
		H.List.Scroll(list, delta or 0)
	end)
end

-- Значок строки. true, если он появился, исчез или сменился (тогда имя надо подвинуть).
local function SetIcon(row, item)
	local key = item.classKey or item.icon
	if row.huiIconKey == key and row.huiIconSet then
		return false
	end
	row.huiIconKey, row.huiIconSet = key, true
	local tex = row.huiIcon
	local has = false
	if item.classKey then
		local c = MU.Model.CLASS_COORDS[item.classKey]
		if c then
			tex:SetTexture(MU.Model.CLASS_ATLAS)
			tex:SetTexCoord(c[1], c[2], c[3], c[4])
			has = true
		end
	elseif item.icon then
		tex:SetTexture(item.icon)
		tex:SetTexCoord(ZOOM, 1 - ZOOM, ZOOM, 1 - ZOOM)
		has = true
	end
	if has then
		tex:Show()
	else
		tex:Hide()
	end
	row.huiHasIcon = has
	return true
end

-- Число справа (доковая строка). true, если текст поменялся.
local function SetRight(row, item, mode)
	local fs = row.huiRight
	local a, r, p = item.amount, item.rate, item.pct
	if row.huiRMode == mode and row.huiRA == a and row.huiRR == r and row.huiRP == p then
		return false
	end
	row.huiRMode, row.huiRA, row.huiRR, row.huiRP = mode, a, r, p
	local rate = r and Fm.Small(r) or "..."
	if mode == "total" then
		fs:SetText(Fm.Small(a))
	elseif mode == "full" then
		fs:SetText(Fm.Small(a).." ("..(r and Fm.Small(r) or "-")..", "..Fm.Int(p).."%)")
	else
		fs:SetText(rate)
	end
	return true
end

-- Три числа разбивки: скорость, сумма, доля.
local function SetWide(row, item)
	local a, r, p = item.amount, item.rate, item.pct
	if row.huiRA == a and row.huiRR == r and row.huiRP == p then
		return false
	end
	row.huiRA, row.huiRR, row.huiRP = a, r, p
	row.huiRight:SetText(Fm.Int(p).."%")
	row.huiMid:SetText(Fm.Small(a))
	row.huiRate:SetText(r and Fm.Small(r) or "-")
	return true
end

local function SetTag(row, item)
	local on = item.proc and true or false
	local count = item.count
	if row.huiTagOn == on and row.huiTagCount == count and row.huiTagSet then
		return false
	end
	row.huiTagOn, row.huiTagCount, row.huiTagSet = on, count, true
	if count then
		row.huiTag:SetText("("..Fm.Int(count)..")")
		row.huiTag:Show()
	elseif on then
		row.huiTag:SetText(MU.S("proc"))
		row.huiTag:Show()
	else
		row.huiTag:Hide()
	end
	return true
end

-- Положение имени, тега и обрезка имени по свободной ширине.
local function Place(row, item)
	local spec = row.huiSpec
	local b = T.Border()
	local pad = Pad()
	local left = b + pad
	if row.huiHasIcon then
		left = left + row.huiSide + pad
	end
	local name = row.huiNameFS
	name:ClearAllPoints()
	name:SetPoint("LEFT", row.huiBar, "LEFT", left, 0)
	local rightW
	if spec.wide then
		rightW = H.R(R.WIDE_PCT + R.WIDE_AMOUNT + R.WIDE_RATE) + pad
	else
		rightW = (row.huiRight:GetStringWidth() or 0) + pad
	end
	local tag = row.huiTag
	local tagW = 0
	if tag:IsShown() then
		tagW = (tag:GetStringWidth() or 0) + pad
		tag:ClearAllPoints()
		tag:SetPoint("RIGHT", row.huiBar, "RIGHT", -(rightW + pad), 0)
	end
	local avail = H.R(spec.wpx) - left - rightW - tagW - pad
	if avail < H.R(8) then
		avail = H.R(8)
	end
	X.Fit(name, item.name or "", avail)
end

--@frame
function R.Update(row, item, idx, list)
	row.huiItem, row.huiView = item, list.huiView
	local bar = row.huiBar
	if row.huiR ~= item.r or row.huiG ~= item.g or row.huiB ~= item.b then
		row.huiR, row.huiG, row.huiB = item.r, item.g, item.b
		B.SetColor(bar, item.r, item.g, item.b)
	end
	B.Set(bar, item.sortKey, list.huiTop)
	local changed = SetIcon(row, item)
	if row.huiSpec.wide then
		if SetWide(row, item) then
			changed = true
		end
	elseif SetRight(row, item, MU.opt.right) then
		changed = true
	end
	if SetTag(row, item) then
		changed = true
	end
	if row.huiNameText ~= item.name then
		row.huiNameText = item.name
		changed = true
	end
	if changed then
		Place(row, item)
	end
end

-- Пересчитать подписи и размеры (THEME, смена языка): забыть кэши показанного.
function R.Forget(row)
	row.huiIconSet, row.huiRMode, row.huiRA, row.huiTagSet, row.huiNameText = nil, nil, nil, nil, nil
	row.huiR = nil
end

function R.ForgetList(list)
	for i = 1, table.getn(list.huiRows) do
		R.Forget(list.huiRows[i])
	end
end
