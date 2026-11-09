-- HyoukaUI: Data\Xp, темп опыта забега (plan 2.8, inv frames#25): опыт в минуту и время до следующего уровня.
-- Читает только H.Run (AZS_RUN.xp, xpn, lvl). Окно 45 секунд часов забега (стоят на паузе и выборе карты),
-- опыт считается сквозь уровни (при смене уровня к накопленному добавляется xpn прежнего), цифра появляется после
-- 10 секунд наблюдения. Отсчет раз в 3 секунды, откат часов забега назад (новый забег) обнуляет кольцо.
--   H.Xp.Pace()    опыт в минуту или nil
--   H.Xp.NextIn()  секунд до следующего уровня по темпу или nil
--   H.Xp.Sample()  один отсчет (таймер и тесты)
-- Читают Frames (подсказка полосы) и Трекер (строка уровня). Без аллокаций на вызов.

local H = HyoukaUI

local X = {}
H.Xp = X

X.WINDOW = 45
X.MIN_SPAN = 10
X.STEP = 3

local RING = 16
local rt, rc = {}, {}       -- кольцо отсчетов: время забега и опыт сквозь уровни (массивы заполнены заранее)
for i = 1, RING do
	rt[i], rc[i] = 0, 0
end
local S = { n = 0, head = 0, base = 0, lvl = nil, xpn = nil }

local function Wipe()
	S.n, S.head, S.base, S.lvl, S.xpn = 0, 0, 0, nil, nil
end

-- Следит за сменой уровня: к накопленному добавляется xpn прежнего уровня.
local function TrackLevel()
	local lvl, xpn = H.Run.Level(), H.Run.Get("xpn")
	if S.lvl and lvl and lvl > S.lvl then
		S.base = S.base + (S.xpn or 0) * (lvl - S.lvl)
	end
	S.lvl, S.xpn = lvl, xpn
end

function X.Sample()
	local t = H.Run.Time()
	if not t or H.Run.Phase() == "ready" then
		return
	end
	if S.n > 0 and t < rt[S.head] then
		Wipe()
	end
	TrackLevel()
	S.head = S.head + 1
	if S.head > RING then
		S.head = 1
	end
	rt[S.head], rc[S.head] = t, S.base + (H.Run.Get("xp") or 0)
	if S.n < RING then
		S.n = S.n + 1
	end
end

function X.Pace()
	if S.n < 2 then
		return nil
	end
	local newest = rt[S.head]
	local oldest, oc = newest, rc[S.head]
	for k = 1, S.n do
		local idx = S.head - k + 1
		if idx < 1 then
			idx = idx + RING
		end
		if newest - rt[idx] <= X.WINDOW then
			oldest, oc = rt[idx], rc[idx]
		end
	end
	local span = newest - oldest
	if span < X.MIN_SPAN then
		return nil
	end
	local gained = rc[S.head] - oc
	if gained < 0 then
		return nil
	end
	return gained / span * 60
end

function X.NextIn()
	local pace = X.Pace()
	local xpn, xp = H.Run.Get("xpn"), H.Run.Get("xp") or 0
	if not pace or pace <= 0 or not xpn then
		return nil
	end
	return (xpn - xp) / (pace / 60)
end

function X.Reset()
	Wipe()
end

--@frame
local function Tick()
	X.Sample()
end

function X.Start()
	H.Clock.Every("xp", X.STEP, Tick)
end

H.Poll.AddLayer("xp", X.Reset, X.Start)
H.On("RUN_STARTED", "xp", X.Reset)
H.On("LOGIN", "xp", X.Start)
