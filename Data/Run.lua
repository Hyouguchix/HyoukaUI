-- HyoukaUI: Data\Run, забег: фаза, часы, runId, начало и конец (plan 2.2).
--
-- Читает AZS_RUN, AZS_ZONE, AZS_END, AZS_REVIVE (только слои данных видят AZS_*).
-- События: RUN_STARTED(runId, oldRunId), RUN_LEFT(oldRunId), RUN_ENDED(result, runId) ровно один
-- раз на runId, PHASE_CHANGED(new, old), LEVEL_CHANGED(lvl, stored).
--
-- Порядок строк сервера не известен (проба 0.5), поэтому все четыре сырых события (ZONE, RUN, END,
-- REVIVE) вызывают один и тот же идемпотентный Update, который сверяет все сразу.
-- Конец забега (plan 2.3): новый AZS_END с result. Победа (victory) - сразу. Поражение и выход -
-- через CONFIRM секунд, и только если герой не играет (фаза не playing, choosing, paused) и не лежит
-- (AZS_REVIVE.down ~= 1): в коопе фаза dead и result=defeat идут каждые 0.2 с, пока героя еще можно
-- поднять, это не конец; после подъема устаревший defeat тоже не конец.
-- Свежесть данных: список или счетчик свежий, если его метка не старше строки AZS_ZONE нового забега
-- (с допуском FRESH_GRACE на строки, пришедшие чуть раньше).

local H = HyoukaUI

local R = {}
H.Run = R

R.CONFIRM = 0.4
R.FRESH_GRACE = 0.5
R.CLOCK_REFRESH = 600
-- Допуск устойчивых часов и отсчетов, секунды: строки сервера приходят раз в ~2 с с дрожью до 0.05 с, и пересчет часов и
-- остатков от каждой новой строки гнал текст туда-сюда на границе секунды (59, 60, 59) и дергал полосы и шторки. Новая
-- точка отсчета принимается, только если она ушла от прежней больше чем на допуск (настоящая пауза, скачок сервера).
-- 1.0 с: строки сервера идут пачками раз в ~2 с, разброс момента прихода легко больше 0.35 с, и цифры на границе секунды
-- мигали (жалоба пользователя 2026-11-09: откаты сборки, возрождение особых мобов, таймеры).
R.STEADY_TOL = 1.0

local S = {}
local function ResetState()
	S.runId = nil
	S.phase = nil
	S.startStamp = nil
	S.startedAt = nil
	S.endBase = nil
	S.endedId = nil
	S.endedResult = nil
	S.pendingAt = nil
	S.lvl = nil
	S.stored = nil
	S.reloaded = false
	S.clockMin = nil      -- минут от полуночи в опорной точке
	S.clockAt = nil       -- GetTime опорной точки
	S.start, S.rawStamp = nil, nil    -- устойчивое начало часов забега (GetTime) и метка строки, по которой оно принято
	S.ends = S.ends or {}
	for k in pairs(S.ends) do
		S.ends[k] = nil
	end
end
ResetState()
R.state = S

local function Global()
	return H.DB and H.DB.ready and H.DB.Global() or nil
end

----------------------------------------------------------------------------------------
-- Чтение
----------------------------------------------------------------------------------------

function R.Phase()
	return AZS_RUN.ph
end

-- Идентификатор забега из AZS_ZONE.run (строка) или nil вне забега.
function R.Id()
	return S.runId
end

function R.Get(key)
	return AZS_RUN[key]
end

-- Значение из AZS_ZONE; пока строка зоны в этой сессии не приходила (после /reload), берется снимок.
function R.Zone(key)
	local v = AZS_ZONE[key]
	if v ~= nil then
		return v
	end
	if AZS_ZONE_UPDATED == nil then
		local g = Global()
		local snap = g and g.zone
		if snap then
			return snap[key]
		end
	end
	return nil
end

-- Часы забега в секундах (как AZS_GetRunTime): стоят на паузе и выборе карты.
-- Часы идут от устойчивого начала: пока новая строка сервера согласуется со старым началом в пределах STEADY_TOL,
-- начало не меняется и текст секунд не дрожит. На паузе и выборе карты часы стоят (берется t строки).
function R.Time()
	local run = AZS_RUN
	local t = run.t
	if not t then
		return nil
	end
	if run.ph == "playing" and AZS_RUN_UPDATED then
		local now = GetTime()
		if S.rawStamp ~= AZS_RUN_UPDATED or S.start == nil then
			local start = AZS_RUN_UPDATED - t
			if S.start == nil or math.abs(start - S.start) >= R.STEADY_TOL then
				S.start = start
			end
			S.rawStamp = AZS_RUN_UPDATED
		end
		return now - S.start
	end
	S.start = nil
	return t
end

-- Устойчивый конец отсчета: rawEnd (часы GetTime) принимается, только если он ушел от прежнего больше чем на STEADY_TOL.
-- Ключ: число или короткая строка (таблица S.ends переиспользуется, на кадр ничего не создается после прогрева).
function R.SteadyEnd(key, rawEnd)
	local old = S.ends[key]
	if old and math.abs(rawEnd - old) < R.STEADY_TOL then
		return old
	end
	S.ends[key] = rawEnd
	return rawEnd
end

-- Секунда прихода финального босса: AZS_ZONE.len, иначе снимок, иначе AZS_RUN.fin.
function R.Length()
	local len = R.Zone("len")
	if type(len) == "number" and len > 0 then
		return len
	end
	local fin = AZS_RUN.fin
	if type(fin) == "number" and fin > 0 then
		return fin
	end
	return nil
end

function R.IsEndless()
	return AZS_RUN.endl == 1
end

-- Секунд до финального босса (AZS_RUN.left, на момент строки; часы забега тикают с ней) или nil.
function R.Left()
	local run = AZS_RUN
	local left = run.left
	if type(left) ~= "number" or left < 0 then
		return nil
	end
	if run.ph == "playing" and AZS_RUN_UPDATED then
		left = R.SteadyEnd("left", AZS_RUN_UPDATED + left) - GetTime()
	end
	if left < 0 then
		left = 0
	end
	return left
end

-- Ближайший босс: строка расписания и секунды до нее (Schedule), в бесконечном режиме см. Schedule.
function R.NextBoss()
	if H.Schedule then
		return H.Schedule.Next()
	end
	return nil
end

-- Аффиксы забега строкой "sanguine,explosive" или nil. Только AZS_ZONE.affixes.
function R.Affixes()
	local a = R.Zone("affixes")
	if type(a) == "string" and a ~= "" then
		return a
	end
	return nil
end

-- Итоги (AZS_END) только когда есть result.
function R.Summary()
	if AZS_END.result then
		return AZS_END
	end
	return nil
end

-- Два числа под разными именами (audit meter-44): урон счетчика (сумма строк AZS_METER, без
-- оверкилла) и урон экрана итогов (AZS_END.dmg, с оверкиллом). Сравнивать с экраном итогов
-- только вторым. Чего нет, то nil.
function R.Damage()
	local list = AZS_METER
	local meter
	for i = 1, table.getn(list) do
		meter = (meter or 0) + (list[i].dmg or 0)
	end
	return meter, AZS_END.dmg
end

function R.Level()
	return AZS_RUN.lvl
end

function R.StoredLevels()
	return AZS_RUN.sl or 0
end

-- Открыть накопленные уровни, как кнопка Level Up! игры (AZS_OpenStoredLevels ставит CVar spendLevels).
-- true, если вызов состоялся. Без функции движка ставит тот же CVar сам.
function R.OpenLevels()
	if AZS_OpenStoredLevels then
		local ok = pcall(AZS_OpenStoredLevels)
		return ok
	end
	if SetCVar then
		return pcall(SetCVar, "spendLevels", "1")
	end
	return false
end

-- Клавиша привязки "Open Level-Ups" (BINDING_NAME_AZS_OPENLEVELS) строкой вида "SHIFT-L" или nil.
function R.LevelKey()
	if not GetBindingKey then
		return nil
	end
	local ok, key = pcall(GetBindingKey, "AZS_OPENLEVELS")
	if ok and type(key) == "string" and key ~= "" then
		return key
	end
	return nil
end

function R.StartStamp()
	return S.startStamp
end

function R.StartedAt()
	return S.startedAt
end

-- Свежа ли метка данных относительно начала текущего забега.
function R.IsFresh(stamp)
	if stamp == nil then
		return false
	end
	if S.startStamp == nil then
		return true
	end
	return stamp >= S.startStamp - R.FRESH_GRACE
end

-- Герой лежит и его можно поднять (кооп): фаза dead, но забег идет.
function R.IsDowned()
	return AZS_REVIVE.down == 1
end

-- Забег для наших модулей закончен (RUN_ENDED уже был для текущего runId): result или nil.
function R.Ended()
	if S.runId and S.endedId == S.runId then
		return S.endedResult
	end
	return nil
end

-- Забег подхвачен после /reload посреди забега (audit tracker-23).
function R.ReloadedMidRun()
	return S.reloaded
end

-- Часы устройства: час и минута, без таблиц. Опорная точка берется из AZS_GetLocalTime
-- (date() в игре отдает UTC), между опорными точками минуты считаются от GetTime.
function R.LocalClock()
	if not S.clockMin then
		return nil
	end
	local total = S.clockMin + math.floor((H.Now() - S.clockAt) / 60)
	return H.Mod(math.floor(total / 60), 24), H.Mod(total, 60)
end

local function RefreshClock()
	if not AZS_GetLocalTime then
		return
	end
	local ok, lt = pcall(AZS_GetLocalTime)
	if ok and lt and type(lt.hour) == "number" and type(lt.minute) == "number" then
		S.clockMin = lt.hour * 60 + lt.minute
		S.clockAt = H.Now()
	end
end

----------------------------------------------------------------------------------------
-- Разбор изменений
----------------------------------------------------------------------------------------

local function SaveSnapshot()
	local g = Global()
	if g and S.runId then
		g.zone = H.Copy(AZS_ZONE, 1)
	end
end

local function ChangeRun(id)
	local old = S.runId
	S.runId = id
	S.pendingAt = nil
	if id then
		S.startStamp = AZS_ZONE_UPDATED
		S.startedAt = H.Now()
		S.endBase = AZS_END_UPDATED
		local g = Global()
		local snap = g and g.zone
		local t = R.Time()
		S.reloaded = (snap ~= nil and snap.run == id) or (S.phase ~= nil and S.phase ~= "ready" and t ~= nil and t > 3)
		SaveSnapshot()
		H.Fire("RUN_STARTED", id, old)
	else
		S.startStamp = nil
		S.startedAt = nil
		S.reloaded = false
		H.Fire("RUN_LEFT", old)
	end
end

local function Finish(result)
	local id = S.runId
	S.endedId = id
	S.endedResult = result
	S.pendingAt = nil
	local g = Global()
	if g then
		g.endedRun = id
	end
	H.Fire("RUN_ENDED", result, id)
end

local function CheckEnd()
	local id = S.runId
	if not id or S.endedId == id then
		return
	end
	local result = AZS_END.result
	if not result then
		S.pendingAt = nil
		return
	end
	-- Экран итогов того же забега, что уже закончился до /reload.
	local g = Global()
	if g and g.endedRun == id then
		S.endedId = id
		S.endedResult = result
		return
	end
	-- Старый экран итогов (до начала этого забега).
	if AZS_END_UPDATED == S.endBase then
		return
	end
	if result == "victory" then
		Finish(result)
		return
	end
	-- Герой снова играет (в коопе его подняли): экран итогов с defeat устарел, это не конец.
	local ph = AZS_RUN.ph
	if ph == "playing" or ph == "choosing" or ph == "paused" or AZS_REVIVE.down == 1 then
		S.pendingAt = nil
		return
	end
	local now = H.Now()
	if not S.pendingAt then
		S.pendingAt = now
		return
	end
	if now - S.pendingAt >= R.CONFIRM then
		Finish(result)
	end
end

local function Update()
	local zone, run = AZS_ZONE, AZS_RUN
	local id = zone.run
	if type(id) ~= "string" or id == "" then
		id = nil
	end
	if id ~= S.runId then
		ChangeRun(id)
	end
	local ph = run.ph
	if ph ~= S.phase then
		local old = S.phase
		S.phase = ph
		H.Fire("PHASE_CHANGED", ph, old)
	end
	if run.lvl ~= S.lvl or run.sl ~= S.stored then
		S.lvl = run.lvl
		S.stored = run.sl
		H.Fire("LEVEL_CHANGED", run.lvl, run.sl or 0)
	end
	CheckEnd()
end
R.Update = Update

--@frame
local function Tick()
	if S.pendingAt then
		CheckEnd()
	end
end

function R.Reset()
	ResetState()
end

function R.Start()
	RefreshClock()
	H.Clock.Every("run", R.CLOCK_REFRESH, RefreshClock)
	H.Clock.Every("run", 0.25, Tick)
end

H.Poll.AddLayer("run", R.Reset, R.Start)
H.On("ZONE", "run", Update)
H.On("RUN", "run", Update)
H.On("END", "run", Update)
H.On("REVIVE", "run", Update)
H.On("LOGOUT", "run", SaveSnapshot)
H.On("LOGIN", "run", R.Start)
