-- HyoukaUI: Modules\Tracker\BossTimers, полосы боссов в стиле BigWigs, сообщения и отсчет (plan 3.2, решение 8).
--
-- Полосы (spec 3.6). Босс из расписания в пределах горизонта (120 с, настройка) получает обычную полосу
-- 228x20 под миникартой (кусок tr.bars, до 5, шаг 23): фон #080808 0.406, рамка 1 px с выступом наружу, квадрат
-- иконки слева через зазор 1, заливка #7C7C7C убывает к приходу, имя слева, время справа. За 15 с (настройка)
-- полоса переезжает в выделенную 269x22 красную (кусок tr.barsEmph, до 3, вверх от рамки цели). Бесконечный
-- режим: одна полоса "Босс" по таймеру следующего босса.
-- Сообщения. Баннеры игры (событие BANNER) показываются своим стилем: обычные 12.27 в tr.msg (рост вверх, 2.5 с
-- и затухание 1 с), финальный босс выделенным 21.3 в tr.msgEmph. Если баннер не пришел через 1.5 с после BOSS_UP
-- (режим Вместо, игровые баннеры спрятаны), сообщение "Пришел босс X" строится из расписания. Отсчет: за 5 с до
-- ближайшего босса цифры 5..1 в tr.count (29.3, #E1E1E1).
-- Журнал показанных сообщений и цифр (последние 8: текст и время показа) идет в /hui dump tracker (msgLog).
-- Режим Вместо: Claim "banners" (если включено "прятать баннеры игры").
-- Покадрово (0.05 с): раздача полос, ширина заливки, секунды из кэша, затухание сообщений. Без аллокаций.

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local ceil = math.ceil

local NB, EB, MSGS = 5, 3, 3
local NORM_H, EMPH_H = 20, 22      -- высоты полос, spec 3.6; ширины и шаги берутся из раскладки
local HOLD, FADE, FALLBACK_DELAY = 2.5, 1, 1.5
local LOG_N = 8

local BT = { tot = {}, nbars = {}, ebars = {}, list = {}, msgs = {}, cdSec = -1, endKey = "endless", pend = nil, logText = {}, logAt = {},
	logN = 0, shown = 0, nShown = 0, eShown = 0 }
Tr.BossTimers = BT

local function R(px)
	return H.R(px)
end

----------------------------------------------------------------------------------------
-- Журнал показанных сообщений
----------------------------------------------------------------------------------------

local function Log(text, at)
	BT.logN = BT.logN + 1
	local pos = BT.logN - LOG_N * math.floor((BT.logN - 1) / LOG_N)
	BT.logText[pos], BT.logAt[pos] = text, at
end

-- Строки журнала от старых к новым в out (создает строки: только для дампа и тестов).
function Tr.MsgLines(out)
	local n = BT.logN
	local first = n > LOG_N and n - LOG_N + 1 or 1
	for i = first, n do
		local pos = i - LOG_N * math.floor((i - 1) / LOG_N)
		table.insert(out, string.format("%.2f", BT.logAt[pos]).."  "..tostring(BT.logText[pos]))
	end
end

function Tr.MsgCount()
	return BT.logN
end

function Tr.MsgLast()
	if BT.logN == 0 then
		return nil
	end
	local pos = BT.logN - LOG_N * math.floor((BT.logN - 1) / LOG_N)
	return BT.logText[pos], BT.logAt[pos]
end

----------------------------------------------------------------------------------------
-- Полосы
----------------------------------------------------------------------------------------

-- Размеры и места частей полосы в ретейл-px. Зовется при сборке и на THEME: без этого полосы остаются в ширине, посчитанной
-- при старом размере пикселя, а контейнер (кусок Layout) уже пересчитан, и панель получается неверной длины.
local function SizeBar(bar)
	local f, w, h = bar.frame, bar.cw, bar.ch
	f:SetWidth(R(w))
	f:SetHeight(R(h))
	bar.icon:SetWidth(R(h))
	bar.icon:SetHeight(R(h))
	bar.body:ClearAllPoints()
	bar.body:SetPoint("TOPLEFT", f, "TOPLEFT", R(h + 1), 0)
	bar.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	local px = H.Theme.Px(1)
	bar.edge:ClearAllPoints()
	bar.edge:SetPoint("TOPLEFT", bar.body, "TOPLEFT", -px, px)
	bar.edge:SetPoint("BOTTOMRIGHT", bar.body, "BOTTOMRIGHT", px, -px)
	bar.nameFs:ClearAllPoints()
	bar.nameFs:SetPoint("LEFT", bar.body, "LEFT", R(3), 0)
	bar.timeFs:ClearAllPoints()
	bar.timeFs:SetPoint("RIGHT", bar.body, "RIGHT", -R(3), 0)
	bar.inner = R(w - h - 1)
	bar.w = -1
	bar.key = nil
	f:ClearAllPoints()
	if bar.emph then
		f:SetPoint("BOTTOMLEFT", bar.parent, "BOTTOMLEFT", 0, (bar.idx - 1) * R(bar.step))
	else
		f:SetPoint("TOPLEFT", bar.parent, "TOPLEFT", 0, -(bar.idx - 1) * R(bar.step))
	end
end

local function MakeBar(parent, w, h, emph, i, step)
	local f = CreateFrame("Frame", nil, parent)
	local ic = CreateFrame("Frame", nil, f)
	ic:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	Tr.Fill(ic, Tr.C.barBg, "BACKGROUND"):SetAllPoints(ic)
	local tex = ic:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(H.Theme.TEX.pinSkull)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	tex:SetAllPoints(ic)
	K.Border(ic, "edge")
	local body = CreateFrame("Frame", nil, f)
	Tr.Fill(body, Tr.C.barBg, "BACKGROUND"):SetAllPoints(body)
	local fill = Tr.Fill(body, emph and Tr.C.barEmph or Tr.C.barFill, "ARTWORK")
	fill:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	fill:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	local edge = CreateFrame("Frame", nil, body)
	K.Border(edge, "edge")
	local nameFs = K.Text(body, "body", nil, "LEFT")
	local timeFs = K.Text(body, "body", nil, "RIGHT")
	f:Hide()
	local bar = { frame = f, icon = ic, body = body, edge = edge, fill = fill, nameFs = nameFs, timeFs = timeFs, w = -1, sec = -1,
		key = nil, on = false, inner = 0, idx = i, cw = w, ch = h, emph = emph, parent = parent, step = step }
	SizeBar(bar)
	return bar
end

-- Привязать полосу к записи (ключ line или "endless") и обновить заливку и время. Строк не создает, кроме смены имени.
local function SetBar(bar, key, name, left, horizon)
	if bar.key ~= key then
		bar.key = key
		bar.sec = -1
		H.Text.Fit(bar.nameFs, name or "", bar.inner - R(40))
	end
	-- Заливка = остаток / полная длительность полосы (как в BigWigs): полная длительность это остаток в момент, когда
	-- полоса появилась (но не больше горизонта); при переезде в выделенную тот же ключ держит ту же длительность.
	local total = BT.tot[key]
	if not total or left > total + Tr.STEADY then
		total = left < horizon and left or horizon
		BT.tot[key] = total
	end
	local frac = left / total
	if frac > 1 then
		frac = 1
	elseif frac < 0 then
		frac = 0
	end
	local w = H.Theme.Snap(bar.inner * frac)
	if w ~= bar.w then
		bar.w = w
		if w <= 0 then
			bar.fill:Hide()
		else
			bar.fill:SetWidth(w)
			bar.fill:Show()
		end
	end
	local sec = ceil(left)
	if sec < 0 then
		sec = 0
	end
	if sec ~= bar.sec then
		bar.sec = sec
		bar.timeFs:SetText(Tr.TimeStr(sec))
	end
	if not bar.on then
		bar.on = true
		bar.frame:Show()
	end
end

local function HideFrom(pool, from)
	for i = from, table.getn(pool) do
		local bar = pool[i]
		if bar.on then
			bar.on = false
			bar.key = nil
			bar.frame:Hide()
		end
	end
end

local function Bars(now)
	local horizon = Tr.Opt("horizon")
	local relocate = Tr.Opt("relocate")
	local n, e = 0, 0
	if H.Run.IsEndless() then
		local left = H.Schedule.NextEndless()
		if left and left <= horizon then
			if left <= relocate then
				e = 1
				SetBar(BT.ebars[1], BT.endKey, Tr.T("boss_generic"), left, horizon)
			else
				n = 1
				SetBar(BT.nbars[1], BT.endKey, Tr.T("boss_generic"), left, horizon)
			end
		end
	else
		local count = H.Schedule.Bars(BT.list, horizon)
		for i = 1, count do
			local line = BT.list[i]
			local left = H.Schedule.Left(line)
			if left then
				if left <= relocate then
					if e < EB then
						e = e + 1
						SetBar(BT.ebars[e], line, line.name, left, horizon)
					end
				elseif n < NB then
					n = n + 1
					SetBar(BT.nbars[n], line, line.name, left, horizon)
				end
			end
		end
	end
	BT.nShown, BT.eShown = n, e
	HideFrom(BT.nbars, n + 1)
	HideFrom(BT.ebars, e + 1)
end

----------------------------------------------------------------------------------------
-- Сообщения
----------------------------------------------------------------------------------------

local function MakeMsg(parent, role, i)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("BOTTOM", parent, "BOTTOM", 0, (i - 1) * R(28))
	f:SetWidth(R(600))
	f:SetHeight(R(28))
	local fs = K.Text(f, role, nil, "CENTER")
	fs:SetPoint("CENTER", f, "CENTER", 0, 0)
	f:Hide()
	return { frame = f, fs = fs, born = nil }
end

-- Показать сообщение. emph: выделенное (21.3, финальный босс), иначе обычное (12.27). Возвращает true, если показано.
function Tr.Say(text, emph)
	if not BT.msgs[1] or not Tr.Opt("messages") or text == nil or text == "" then
		return false
	end
	local slot
	if emph then
		slot = BT.emph
	else
		for i = 1, MSGS do
			if not BT.msgs[i].born then
				slot = BT.msgs[i]
				break
			end
		end
		if not slot then
			slot = BT.msgs[1]
			for i = 2, MSGS do
				if BT.msgs[i].born < slot.born then
					slot = BT.msgs[i]
				end
			end
		end
	end
	local now = H.Now()
	slot.born = now
	slot.fs:SetText(text)
	slot.frame:SetAlpha(1)
	slot.frame:Show()
	Log(text, now)
	return true
end

local function Fade(slot, now)
	local age = now - slot.born
	if age >= HOLD + FADE then
		slot.born = nil
		slot.frame:Hide()
	elseif age > HOLD then
		slot.frame:SetAlpha(1 - (age - HOLD) / FADE)
	end
end

local function Messages(now)
	for i = 1, MSGS do
		local slot = BT.msgs[i]
		if slot.born then
			Fade(slot, now)
		end
	end
	if BT.emph.born then
		Fade(BT.emph, now)
	end
end

local function Fallback(now)
	local p = BT.pend
	BT.pend = nil
	Tr.Say(Tr.T("boss_arrived").." "..tostring(p.name), p.final)
end

local function OnBossUp(ev, index, name)
	if not Tr.IsReplace() or not Tr.Opt("hideBanners") then
		return
	end
	local final = false
	local list = H.Schedule.Lines()
	for i = 1, table.getn(list) do
		if list[i].index == index and list[i].final == 1 then
			final = true
		end
	end
	BT.pend = { name = name, final = final, at = H.Now() + FALLBACK_DELAY }
end

local function OnBanner(ev, banner)
	if type(banner) ~= "table" then
		return
	end
	local text = banner.text
	if text == nil or text == "" then
		text = banner.name
	end
	local emph = false
	if banner.boss == true or banner.boss == 1 then
		BT.pend = nil
		local list = H.Schedule.Lines()
		for i = 1, table.getn(list) do
			if list[i].name == banner.name and list[i].final == 1 then
				emph = true
			end
		end
	end
	Tr.Say(text, emph)
end

----------------------------------------------------------------------------------------
-- Отсчет 5..1
----------------------------------------------------------------------------------------

local function Countdown(now)
	local sec = -1
	if Tr.Opt("countdown") and H.Run.Phase() == "playing" then
		local line, left
		if H.Run.IsEndless() then
			left = H.Schedule.NextEndless()
		else
			line, left = H.Schedule.Next()
		end
		if left and left > 0 then
			local c = ceil(left)
			if c <= 5 then
				sec = c
			end
		end
	end
	if sec ~= BT.cdSec then
		BT.cdSec = sec
		if sec > 0 then
			BT.cdFs:SetText(Fm.Int(sec))
			BT.cdFrame:Show()
			Log(Fm.Int(sec), now)
		else
			BT.cdFrame:Hide()
		end
	end
end

--@frame
local function Tick(now)
	if BT.barsOn then
		Bars(now)
	end
	Messages(now)
	Countdown(now)
	if BT.pend and now >= BT.pend.at then
		Fallback(now)
	end
end

----------------------------------------------------------------------------------------
-- Кадры и часть
----------------------------------------------------------------------------------------

local function Build()
	local NORM_W, EMPH_W = Tr.Def("tr.bars", "w", 228), Tr.Def("tr.barsEmph", "w", 269)
	local STEP_N, STEP_E = Tr.Def("tr.bars", "step", 23), Tr.Def("tr.barsEmph", "step", 23)
	BT.barsFrame = CreateFrame("Frame", nil, UIParent)
	BT.emphFrame = CreateFrame("Frame", nil, UIParent)
	BT.msgFrame = CreateFrame("Frame", nil, UIParent)
	BT.emphMsgFrame = CreateFrame("Frame", nil, UIParent)
	BT.cdFrame = CreateFrame("Frame", nil, UIParent)
	for i = 1, NB do
		local bar = MakeBar(BT.barsFrame, NORM_W, NORM_H, false, i, STEP_N)
		BT.nbars[i] = bar
	end
	for i = 1, EB do
		local bar = MakeBar(BT.emphFrame, EMPH_W, EMPH_H, true, i, STEP_E)
		BT.ebars[i] = bar
	end
	for i = 1, MSGS do
		BT.msgs[i] = MakeMsg(BT.msgFrame, "msg", i)
	end
	BT.emph = MakeMsg(BT.emphMsgFrame, "msgEmph", 1)
	BT.cdFs = K.Text(BT.cdFrame, "count", nil, "CENTER")
	BT.cdFs:SetPoint("CENTER", BT.cdFrame, "CENTER", 0, 0)
	Tr.Color(BT.cdFs, Tr.C.count)
	BT.cdFrame:Hide()
end

-- Стоковые рамки эмоций босса и рейдового оповещения рисуют огромный текст по центру экрана ("Стена врагов
-- надвигается!", 2026-11-09, жалоба пользователя). В режиме Вместо при включенной опции hideBanners они паркуются
-- под скрытый кадр, как и баннеры игры; наши сообщения в стиле BigWigs остаются.
local STOCK_EMOTE = { "RaidBossEmoteFrame", "RaidWarningFrame" }
local EMOTE_OWNER = "tracker.emote"

local function SyncEmote()
	local want = Tr.IsReplace() and Tr.Opt("hideBanners") and true or false
	if want and not BT.emoteParked then
		BT.emoteParked = true
		for i = 1, table.getn(STOCK_EMOTE) do
			local fr = H.Env[STOCK_EMOTE[i]]
			if type(fr) == "table" and fr.SetParent then
				H.Park(fr, EMOTE_OWNER)
			end
		end
	elseif not want and BT.emoteParked then
		BT.emoteParked = false
		H.Unpark(EMOTE_OWNER)
	end
end

local function Place()
	SyncEmote()
	if not BT.barsFrame then
		return
	end
	local run = Tr.InRun()
	BT.barsOn = Tr.Opt("bars") and run
	Tr.Set(BT.barsFrame, BT.barsOn)
	Tr.Set(BT.emphFrame, BT.barsOn)
	Tr.Set(BT.msgFrame, Tr.Opt("messages"))
	Tr.Set(BT.emphMsgFrame, Tr.Opt("messages"))
	if not BT.barsOn then
		HideFrom(BT.nbars, 1)
		HideFrom(BT.ebars, 1)
	end
end

Tr.Part("bosstimers", {
	build = Build,
	show = function()
		Tr.Register("tr.bars", BT.barsFrame)
		-- Пока куска uf.target (модуль Frames) нет, выделенные полосы встают на то же место от центра экрана.
		Tr.Register("tr.barsEmph", BT.emphFrame, { fallback = Tr.FallbackFrom("tr.barsEmph", "uf.target") })
		Tr.Register("tr.msg", BT.msgFrame)
		Tr.Register("tr.msgEmph", BT.emphMsgFrame)
		Tr.Register("tr.count", BT.cdFrame)
		BT.cdSec = -1
	end,
	hide = function()
		SyncEmote()
		BT.pend = nil
		BT.barsOn = false
		for i = 1, MSGS do
			BT.msgs[i].born = nil
		end
		BT.emph.born = nil
	end,
	place = Place,
	tick = Tick,
	refresh = Place,
	reset = function()
		BT.pend = nil
		BT.cdSec = -1
		H.Wipe(BT.tot)
	end,
	theme = function()
		for i = 1, NB do
			SizeBar(BT.nbars[i])
		end
		for i = 1, EB do
			SizeBar(BT.ebars[i])
		end
		for i = 1, MSGS do
			BT.msgs[i].frame:ClearAllPoints()
			BT.msgs[i].frame:SetPoint("BOTTOM", BT.msgFrame, "BOTTOM", 0, (i - 1) * R(28))
			BT.msgs[i].frame:SetWidth(R(600))
			BT.msgs[i].frame:SetHeight(R(28))
		end
		BT.emph.frame:SetWidth(R(600))
		BT.emph.frame:SetHeight(R(28))
	end,
	settings = function(key)
		Place()
	end,
	on = { BOSS_UP = OnBossUp, BANNER = OnBanner },
	dump = function(out)
		table.insert(out, "полосы боссов: обычных "..BT.nShown.."  выделенных "..BT.eShown.."  отсчет "..BT.cdSec
			.."  сообщений в журнале "..BT.logN)
		Tr.MsgLines(out)
	end,
})
