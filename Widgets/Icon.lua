-- HyoukaUI: иконка. Рамка 1 физический пиксель, кроп 8%, подложка #141414 0.6, шторка отката через
-- модель Cooldown (если движок ее дает), цифры отката, стаки, серость на настоящем откате.
--
-- Icon.New(parent, opts)       opts: size (ретейл-px, по умолчанию 45), zoom (0.08), border, digits (по умолчанию да),
--                              digitsRole, stackRole, button (Button вместо Frame), digitsMin (минимум длительности для цифр)
-- Icon.SetTexture(icon, path)
-- Icon.SetStack(icon, n)       n меньше 2 прячет текст
-- Icon.SetCharges(icon, n)     заряды как стаки; пока заряды есть, иконка не серая
-- Icon.SetCooldown(icon, start, duration)   возвращает true, если шторка (пере)запущена; duration 0 снимает откат. Короткий (до GCD_MAX) - шторка GCD без цифр и серости
-- Icon.Update(icon, now)       один шаг: цифры, конец отката; true, пока откат идет
-- Icon.SetDesaturated(icon, on) / Icon.SetBorderColor(icon, r, g, b, a)
-- Состояние отката: icon.cdKind = 0 нет, 1 GCD, 2 настоящий откат.
-- Серость на откате (retail 3.3) по умолчанию ВЫКЛЮЧЕНА: иконка с откатом не серая никогда (ауры, баффы, таймеры,
-- кольца). Включается по иконке: opts.greyOnCd или Icon.SetGreyOnCooldown(icon, on); так делают только кнопки
-- способностей, и только по настройке "Серые иконки на откате". Шторка и цифры от этого не зависят.
-- SetCooldown не перезапускает шторку, если конец отката сдвинулся меньше чем на RESTART_TOL при той же длительности
-- (дрожь данных AZS_SPELLS между обновлениями).
--
-- Цифры обновляются раз в секунду (при цифрах после точки - раз в десятую) одним общим покадровым
-- колбэком ядра: он работает, только пока есть активные откаты. Таблиц и строк в нем не создается.

local H = HyoukaUI
local T = H.Theme
local P = H.Panel
local Fm = H.Format

local I = {}
H.Icon = I

I.GCD_MAX = 1.5
I.GCD_SLACK = 0.05
I.SHADE_ALPHA = 0.7
I.RESTART_TOL = 0.35
I.DUR_TOL = 0.15

local active = {}      -- иконки с идущим откатом
local reg = setmetatable({}, { __mode = "k" })
local hasModel = nil   -- модель Cooldown доступна (проверяется один раз)

-- Принудительно включить или выключить модель Cooldown (тесты; nil возвращает проверку по движку).
function I.SetModelMode(on)
	hasModel = on
end

local function ModelOk()
	if hasModel == nil then
		hasModel = (type(CooldownFrame_SetTimer) == "function") and true or false
	end
	return hasModel
end

function I.New(parent, opts)
	opts = opts or {}
	local size = opts.size or 45
	local icon = CreateFrame(opts.button and "Button" or "Frame", nil, parent or UIParent)
	icon.huiOpts = opts
	icon.huiGrey = opts.greyOnCd == true
	local bgOn = opts.bg ~= false
	if bgOn then
		P.SetBg(icon, "iconBg")
	end
	if opts.border ~= false then
		T.AddBorder(icon, nil, nil, nil, nil, "OVERLAY")
	end
	local tex = icon:CreateTexture(nil, "ARTWORK")
	local b = T.Border()
	tex:SetPoint("TOPLEFT", icon, "TOPLEFT", b, -b)
	tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -b, b)
	local z = opts.zoom or 0.08
	tex:SetTexCoord(z, 1 - z, z, 1 - z)
	icon.huiTex = tex
	icon.huiZoom = z
	icon.cdKind, icon.cdStart, icon.cdDur = 0, 0, 0
	icon.huiDigitKey = -1
	icon.huiCharges = 0
	P.Size(icon, size, size)
	if opts.digits ~= false then
		local role = opts.digitsRole or (size >= 40 and "numL") or (size >= 34 and "num") or "body"
		icon.huiDigits = H.Text.New(icon, role, { justify = "CENTER", layer = "OVERLAY" })
		icon.huiDigits:SetPoint("CENTER", icon, "CENTER", 0, 0)
		icon.huiDigits:Hide()
	end
	local stack = H.Text.New(icon, opts.stackRole or "small", { justify = "RIGHT", layer = "OVERLAY" })
	stack:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", H.R(2), H.R(1))
	stack:Hide()
	icon.huiStack = stack
	icon.huiStackN = 0
	reg[icon] = true
	return icon
end

function I.SetTexture(icon, path)
	icon.huiTex:SetTexture(path)
end

function I.SetBorderColor(icon, r, g, b, a)
	T.SetBorderColor(icon, r, g, b, a)
end

function I.SetDesaturated(icon, on)
	if icon.huiDesat == on then
		return
	end
	icon.huiDesat = on
	local tex = icon.huiTex
	if tex.SetDesaturated then
		tex:SetDesaturated(on and 1 or nil)
	end
	if on then
		tex:SetVertexColor(0.55, 0.55, 0.55, 1)
	else
		tex:SetVertexColor(1, 1, 1, 1)
	end
end

function I.SetStack(icon, n)
	n = n or 0
	if icon.huiStackN == n then
		return
	end
	icon.huiStackN = n
	if n >= 2 then
		icon.huiStack:SetText(Fm.Int(n))
		icon.huiStack:Show()
	else
		icon.huiStack:Hide()
	end
end

local function Redesat(icon)
	I.SetDesaturated(icon, icon.huiGrey == true and icon.cdKind == 2 and icon.huiCharges <= 0)
end

-- Серость на настоящем откате для этой иконки (по умолчанию выкл).
function I.SetGreyOnCooldown(icon, on)
	icon.huiGrey = on and true or false
	Redesat(icon)
end

function I.SetCharges(icon, n)
	n = n or 0
	icon.huiCharges = n
	I.SetStack(icon, n)
	Redesat(icon)
end

----------------------------------------------------------------------------------------
-- Шторка
----------------------------------------------------------------------------------------

local function Shutter(icon, start, duration)
	if ModelOk() then
		local m = icon.huiModel
		if not m then
			local ok, made = pcall(CreateFrame, "Model", nil, icon, "CooldownFrameTemplate")
			if ok and made then
				m = made
				m:SetAllPoints(icon)
				icon.huiModel = m
			else
				hasModel = false
			end
		end
		if m then
			CooldownFrame_SetTimer(m, start, duration, 1)
			return
		end
	end
	-- запасной вид: затемнение на настоящем откате, без вращения
	local shade = icon.huiShade
	if not shade then
		shade = icon:CreateTexture(nil, "OVERLAY")
		shade:SetTexture(T.TEX.solid)
		shade:SetAllPoints(icon.huiTex)
		shade:SetVertexColor(0, 0, 0, I.SHADE_ALPHA)
		icon.huiShade = shade
	end
	if duration > 0 and duration > I.GCD_MAX + I.GCD_SLACK then
		shade:Show()
	else
		shade:Hide()
	end
end

local function Track(icon)
	if icon.huiTracked then
		return
	end
	icon.huiTracked = true
	table.insert(active, icon)
	if table.getn(active) == 1 then
		H.Clock.OnFrame("w_icon", I.Tick)
	end
end

local function Untrack(icon)
	if not icon.huiTracked then
		return
	end
	icon.huiTracked = nil
	for i = table.getn(active), 1, -1 do
		if active[i] == icon then
			table.remove(active, i)
			break
		end
	end
	if table.getn(active) == 0 then
		H.Clock.Stop("w_icon")
	end
end

function I.Clear(icon)
	if icon.cdKind == 0 then
		return
	end
	icon.cdKind, icon.cdStart, icon.cdDur = 0, 0, 0
	icon.huiDigitKey = -1
	if icon.huiModel then
		CooldownFrame_SetTimer(icon.huiModel, 0, 0, 0)
	end
	if icon.huiShade then
		icon.huiShade:Hide()
	end
	if icon.huiDigits then
		icon.huiDigits:Hide()
	end
	Redesat(icon)
	Untrack(icon)
end

function I.SetCooldown(icon, start, duration)
	if not start or not duration or duration <= 0 or start <= 0 then
		I.Clear(icon)
		return false
	end
	if icon.cdKind > 0 and math.abs(icon.cdDur - duration) < I.DUR_TOL
		and math.abs(icon.cdStart + icon.cdDur - (start + duration)) < I.RESTART_TOL then
		return false
	end
	local kind = 2
	if duration <= I.GCD_MAX + I.GCD_SLACK then
		kind = 1
	end
	icon.cdKind, icon.cdStart, icon.cdDur = kind, start, duration
	icon.huiDigitKey = -1
	Shutter(icon, start, duration)
	Redesat(icon)
	Track(icon)
	return true
end

-- Ключ цифр: меняется ровно тогда, когда меняется видимый текст (секунды, минуты, часы или десятые).
local function DigitKey(rem, below)
	if rem >= 3600 then
		return 2000000 + math.ceil(rem / 3600)
	end
	if rem >= 60 then
		return 1000000 + math.ceil(rem / 60)
	end
	if below > 0 and rem < below then
		return math.floor(rem * 10)
	end
	return math.ceil(rem)
end

-- Один шаг. Возвращает true, пока откат идет.
--@frame
function I.Update(icon, now)
	local rem = icon.cdStart + icon.cdDur - now
	if rem <= 0 then
		I.Clear(icon)
		return false
	end
	local digits = icon.huiDigits
	if digits and icon.cdKind == 2 and icon.cdDur >= (icon.huiOpts.digitsMin or 0) then
		local below = I.DECIMAL_BELOW
		local key = DigitKey(rem, below)
		if key ~= icon.huiDigitKey then
			icon.huiDigitKey = key
			digits:SetText(Fm.CdText(rem, below))
			digits:Show()
		end
	end
	return true
end

I.DECIMAL_BELOW = 0

-- Общий покадровый колбэк: идет по активным иконкам с конца, закончившиеся убираются.
--@frame
function I.Tick(dt)
	local now = GetTime()
	for i = table.getn(active), 1, -1 do
		local icon = active[i]
		if icon then
			I.Update(icon, now)
		end
	end
end

function I.ActiveCount()
	return table.getn(active)
end

-- THEME: иконки пересчитывают размер и положение картинки.
function I.Reflow()
	local b = T.Border()
	for icon in pairs(reg) do
		P.Size(icon, icon.huiW, icon.huiH)
		local tex = icon.huiTex
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", icon, "TOPLEFT", b, -b)
		tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -b, b)
	end
end

H.On("THEME", "w_icon", I.Reflow)
