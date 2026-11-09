-- HyoukaUI: Frames\Buttons, свои кнопки-индикаторы способностей и пулы иконок (plan 3.1).
--
-- Способности срабатывают сами, кнопки только показывают состояние: иконка (рамка 1 px, кроп 8%, подложка
-- #141414 0.6), шторка и цифры отката, ранг справа снизу (6.4 AS), бинд справа сверху (по умолчанию скрыт).
-- UseAction не нужен. Подсказка по наведению: GameTooltip:SetAction(слот).
-- Данные: H.Spells (кулдаун из строки AZS_SPELLS с полом 0.25 с, второй источник GetActionCooldown слота).
--
-- Откат короче порога cdMin (по умолчанию 1.5 с, GameRules.cdShortShutter) не рисуется ни шторкой, ни цифрами,
-- ни серостью: при полу 0.25 иконки вечно мигали бы (plan 3.1). Счетчик F.stats.shortShutter считает показы
-- шторки короче порога: он должен остаться 0.
--
-- B.Pool(parent, opts) / B.Get(pool, k) / B.Finish(pool, n) / B.PlaceCentered(frame, pool, n, sizePx, gapPx):
-- пул иконок одного размера и раскладка по центру кадра (баффы, таймеры, призывы).

local H = HyoukaUI
local F = H.Frames
local I = H.Icon

local B = {}
F.Buttons = B

B.UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
B.SIZE = 45
B.GAP = 1

----------------------------------------------------------------------------------------
-- Пул иконок
----------------------------------------------------------------------------------------

function B.Pool(parent, opts)
	return { parent = parent, opts = opts, list = {}, shown = 0 }
end

-- k-я иконка пула; создается при первом обращении и сразу показывается.
function B.Get(pool, k)
	local ic = pool.list[k]
	if not ic then
		ic = I.New(pool.parent, pool.opts)
		pool.list[k] = ic
	end
	if not ic:IsShown() then
		ic:Show()
	end
	return ic
end

-- После заполнения n иконок: лишние снимаются и прячутся.
function B.Finish(pool, n)
	for k = n + 1, pool.shown do
		local ic = pool.list[k]
		if ic then
			I.Clear(ic)
			ic:Hide()
		end
	end
	pool.shown = n
end

function B.Count(pool)
	return pool.shown
end

-- Нужна ли перекладка пула: число иконок или ключ (шаг в AS) изменились с прошлого раза. Запоминает новые.
function B.NeedPlace(pool, n, key)
	if pool.placedN == n and pool.placedKey == key then
		return false
	end
	pool.placedN, pool.placedKey = n, key
	return true
end

-- Иконки 1..n в ряд по центру кадра: шаг = размер + зазор (ретейл-px), позиция на сетке физических пикселей.
-- Без смены числа иконок и шага ничего не переставляется.
function B.PlaceCentered(frame, pool, n, sizePx, gapPx)
	local step = H.R(sizePx) + H.R(gapPx)
	if not B.NeedPlace(pool, n, step) then
		return
	end
	for k = 1, n do
		local ic = pool.list[k]
		ic:ClearAllPoints()
		ic:SetPoint("CENTER", frame, "CENTER", H.Theme.Snap((k - (n + 1) / 2) * step), 0)
	end
end

-- Шторка по данным: старт и длительность в часах GetTime. Откат короче порога снимается.
-- Шторка запускается ТОЛЬКО на настоящем начале отката (plan 3.1, жалоба "кнопки мигают"):
--  1) уже идущий откат не перезапускается, пока его конец сдвинут меньше чем на Icon.RESTART_TOL (дрожь
--     AZS_SPELLS между обновлениями раз в ~2 с, start пересчитывается от AZS_SPELLS_UPDATED);
--  2) новый откат, у которого осталось меньше порога cdMin, не показывается: это хвост условной способности
--     ("при здоровье ниже 85%": cd 0.5 при cdmax 11.1 приходит постоянно), настоящий откат после каста
--     приходит с остатком, близким к cdmax. Без этого такая кнопка перезапускала шторку каждое обновление.
function B.SetCooldown(ic, start, dur)
	local now = GetTime()
	local minDur = F.Opt("cdMin")
	if start and dur and start > 0 and dur >= minDur and start + dur > now then
		if ic.cdKind == 0 and start + dur - now < minDur then
			return
		end
		if I.SetCooldown(ic, start, dur) then
			F.stats.shutterShown = F.stats.shutterShown + 1
		end
	else
		I.Clear(ic)
	end
end

-- То же по моменту конца: откат кончится через rem секунд, полная длительность dur. Пока заявленный конец
-- совпадает с прежним (допуск 0.35 с), шторка не перезапускается.
function B.SetEnds(ic, dur, rem)
	if not dur or dur <= 0 or not rem or rem <= 0 then
		I.Clear(ic)
		return
	end
	local endsAt = GetTime() + rem
	if ic.cdKind and ic.cdKind > 0 and math.abs(ic.cdStart + ic.cdDur - endsAt) < 0.35 then
		return
	end
	B.SetCooldown(ic, endsAt - dur, dur)
end

----------------------------------------------------------------------------------------
-- Бинд
----------------------------------------------------------------------------------------

-- Короткая запись клавиши: SHIFT- -> S, CTRL- -> C, ALT- -> A, NUMPAD -> N. Шаблоны только ASCII.
local function Short(key)
	key = string.gsub(key, "SHIFT%-", "S")
	key = string.gsub(key, "CTRL%-", "C")
	key = string.gsub(key, "ALT%-", "A")
	key = string.gsub(key, "NUMPAD", "N")
	key = string.gsub(key, "BUTTON", "M")
	return key
end

function B.KeyText(slot)
	local fn = H.Env.GetBindingKey
	if type(fn) ~= "function" or not slot then
		return ""
	end
	local ok, key = pcall(fn, "ACTIONBUTTON"..slot)
	if ok and type(key) == "string" and key ~= "" then
		return Short(key)
	end
	return ""
end

----------------------------------------------------------------------------------------
-- Кнопка ряда способностей
----------------------------------------------------------------------------------------

local function Tip(btn)
	local tip = H.Env.GameTooltip
	if not tip or not btn.huiSlot then
		return
	end
	local anchor = H.Env.GameTooltip_SetDefaultAnchor
	if type(anchor) == "function" then
		anchor(tip, btn)
	else
		tip:SetOwner(btn, "ANCHOR_RIGHT")
	end
	local ok = pcall(tip.SetAction, tip, btn.huiSlot)
	if ok then
		tip:Show()
	end
end

local function TipOff()
	local tip = H.Env.GameTooltip
	if tip then
		tip:Hide()
	end
end

function B.NewMain(parent, pos)
	local btn = I.New(parent, { size = B.SIZE, button = true, digitsRole = "numL", stackRole = "small",
		greyOnCd = F.Opt("greyCd") == true })
	btn.huiPos = pos
	btn:EnableMouse(true)
	local key = H.Text.New(btn, "small", { justify = "RIGHT", layer = "OVERLAY" })
	key:SetPoint("TOPRIGHT", btn, "TOPRIGHT", H.R(2), -H.R(1))
	btn.huiKey = key
	F.M:Script(btn, "OnEnter", function(self)
		Tip(btn)
	end)
	F.M:Script(btn, "OnLeave", function(self)
		TipOff()
	end)
	B.Assign(btn, nil)
	return btn
end

-- Привязать кнопку к способности i (индекс AZS_SPELLS) или сделать пустым слотом (nil).
function B.Assign(btn, i)
	btn.huiSpell = i
	if not i then
		btn.huiSlot = nil
		I.Clear(btn)
		I.SetStack(btn, 0)
		btn.huiTex:Hide()
		H.Panel.SetBg(btn, "dock")
		btn.huiKey:SetText("")
		btn.huiEmpty = true
		return
	end
	btn.huiEmpty = false
	btn.huiTex:Show()
	H.Panel.SetBg(btn, "iconBg")
	I.SetTexture(btn, H.Spells.Icon(i) or B.UNKNOWN)
	btn.huiSlot = H.Spells.SlotOf(i)
	if F.Opt("rank") then
		I.SetStack(btn, H.Spells.Rank(i) or 0)
	else
		I.SetStack(btn, 0)
	end
	if F.Opt("binds") then
		btn.huiKey:SetText(B.KeyText(btn.huiSlot))
	else
		btn.huiKey:SetText("")
	end
end

-- Серость на откате у кнопок способностей по настройке greyCd (ауры и таймеры не серые никогда).
function B.ApplyGrey(btn)
	I.SetGreyOnCooldown(btn, F.Opt("greyCd") == true)
end

-- Кулдаун кнопки: расчет из AZS_SPELLS, если он молчит - живой GetActionCooldown слота.
function B.UpdateCd(btn)
	local i = btn.huiSpell
	if not i then
		return
	end
	local start, dur = H.Spells.Cooldown(i)
	if not dur or dur <= 0 then
		start, dur = H.Spells.ActionCooldown(i)
	end
	B.SetCooldown(btn, start, dur)
end
