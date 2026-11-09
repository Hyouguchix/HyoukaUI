-- HyoukaUI: Data\MeterData, обертка над meter API v1 (plan 2.2): контекст, снимки, чекпойнты.
--
-- Контракт движка: функции возвращают result, err и сами не бросают (ошибка = nil, { code, message,
-- retryable, retryAfterSeconds? }). Мы все равно зовем их под pcall: функции может не быть в старой
-- версии игры, а исключение не должно ронять кадр.
--
-- ЗАПРОСЫ. Модуль создает запрос один раз (MeterData.NewQuery) и дальше только Fetch: таблица
-- запроса для движка переиспользуется, runId подставляется на каждом Fetch из контекста.
-- Снимок запрашивается, когда counterRevision контекста отличается от увиденного запросом, не чаще
-- раза в MIN_INTERVAL (0.5 с) на запрос и не больше BUDGET (8) снимков на окно 0.5 с на ВСЕХ.
-- Справедливость: запрос, которому в окне отказали (qo.starved), получает место в следующем окне: из BUDGET столько мест, сколько
-- отказанных, закрыто для остальных. Пять потребителей (три места дока, окно разбивки, подсказка NOW) помещаются в одно окно, а
-- если запросов больше бюджета, отказанные идут первыми и никто не голодает.
-- Ошибка с retryable: следующая попытка не раньше retryAfterSeconds, до тех пор отдается
-- последний удачный результат. Остальные ошибки: пауза 5 с.
-- Контекст (AZS_GetMeterContext) читается раз в 0.5 с, пока кто-то смотрит (MeterData.Watch).
-- Событие METER_CHANGED(counterRevision) при смене ревизии; METER_RESET(key) после нового чекпойнта.
--
-- ЧЕКПОЙНТ ("Reset" колонки): AZS_CreateMeterCheckpoint(runId) привязывается к запросу
-- (query.checkpointId), прежний освобождается. Лимит 64 (caps.maxCheckpoints). На смене забега
-- чекпойнты считаются сброшенными (движок снимает их вместе с журналом).
--
-- АДАПТЕРЫ строк: сумма строки лежит в displayAmount (поля amount у строки нет), порядок движка:
-- displayAmount по убыванию, затем tieOrder. Sort повторяет его и отбрасывает нули.

local H = HyoukaUI

local M = {}
H.MeterData = M

M.STEP = 0.5
M.MIN_INTERVAL = 0.5
M.BUDGET = 8
M.BUDGET_WINDOW = 0.5
M.CTX_TTL = 0.2
M.ERROR_PAUSE = 5

local EMPTY = {}
local E_NOFUNC = { code = "UNAVAILABLE", message = "function not present", retryable = false }
local E_LUA = { code = "LUA_ERROR", message = "call raised an error", retryable = false }

local S = {
	ctx = {}, ctxOk = false, ctxAt = nil, ctxRetry = nil, ctxErr = nil, rev = nil,
	caps = nil, capsLang = nil,
	watch = {}, nWatch = 0,
	queries = {}, cps = {}, nCp = 0,
	budgetAt = -1000, budgetN = 0, nStarved = 0,
}
M.stats = { snapshots = 0, errors = 0, skipped = 0, contexts = 0, lastCode = nil }

local function Call0(fn)
	if type(fn) ~= "function" then
		return nil, E_NOFUNC
	end
	local ok, r, e = pcall(fn)
	if not ok then
		H.Errors.Add("meterdata", tostring(r))
		return nil, E_LUA
	end
	return r, e
end

local function Call1(fn, a)
	if type(fn) ~= "function" then
		return nil, E_NOFUNC
	end
	local ok, r, e = pcall(fn, a)
	if not ok then
		H.Errors.Add("meterdata", tostring(r))
		return nil, E_LUA
	end
	return r, e
end

----------------------------------------------------------------------------------------
-- Контекст и возможности
----------------------------------------------------------------------------------------

local function CopyContext(r)
	local c = S.ctx
	H.Wipe(c)
	for k, v in pairs(r) do
		if type(v) ~= "table" then
			c[k] = v
		end
	end
	local enc = r.encounter
	if enc then
		c.encounterId, c.encounterState = enc.encounterId, enc.state
		c.encounterStart, c.encounterEnd = enc.startRunSeconds, enc.endRunSeconds
	end
end

-- Контекст: таблица со скалярами (runId, counterRevision, phase, localOwnerId, partyState,
-- languageRevision, encounterId, encounterState...). Кэш на CTX_TTL. nil, err, если не получен.
function M.Context(force)
	local now = H.Now()
	if not force and S.ctxOk and S.ctxAt and now - S.ctxAt < M.CTX_TTL then
		return S.ctx
	end
	if S.ctxRetry and now < S.ctxRetry then
		if S.ctxOk then
			return S.ctx
		end
		return nil, S.ctxErr
	end
	local r, e = Call0(AZS_GetMeterContext)
	M.stats.contexts = M.stats.contexts + 1
	if not r then
		S.ctxOk = false
		S.ctxErr = e
		S.ctxRetry = now + ((e and e.retryable and e.retryAfterSeconds) or M.ERROR_PAUSE)
		M.stats.lastCode = e and e.code
		return nil, e
	end
	S.ctxRetry = nil
	S.ctxErr = nil
	CopyContext(r)
	S.ctxOk = true
	S.ctxAt = now
	local rev = S.ctx.counterRevision
	if rev ~= S.rev then
		S.rev = rev
		H.Fire("METER_CHANGED", rev)
	end
	return S.ctx
end

function M.RunId()
	local c = M.Context()
	return c and c.runId or nil
end

-- Идентификатор героя клиента в журнале (ownerId из контекста).
function M.LocalOwner()
	local c = M.Context()
	return c and c.localOwnerId or nil
end

-- Возможности API (apiVersion, languageCode, features, maxCheckpoints...). Кэш, перечитывается
-- при смене languageRevision контекста.
function M.Caps()
	local lang = S.ctxOk and S.ctx.languageRevision or nil
	if S.caps and (lang == nil or lang == S.capsLang) then
		return S.caps
	end
	local r = Call0(AZS_GetMeterCapabilities)
	if r then
		S.caps = r
		S.capsLang = lang
	end
	return S.caps
end

function M.AtomicCheckpoints()
	local c = M.Caps()
	return c ~= nil and c.features ~= nil and c.features.atomicCheckpoints == true
end

-- Смотрят ли сейчас на счетчик: пока есть наблюдатели, контекст читается раз в STEP.
function M.Watch(owner, on)
	if on then
		if not S.watch[owner] then
			S.watch[owner] = true
			S.nWatch = S.nWatch + 1
		end
	elseif S.watch[owner] then
		S.watch[owner] = nil
		S.nWatch = S.nWatch - 1
	end
end

--@frame
local function Tick()
	if S.nWatch > 0 then
		M.Context(true)
	end
end

----------------------------------------------------------------------------------------
-- Запросы и снимки
----------------------------------------------------------------------------------------

-- spec = { metric, scope, groupBy, period, window, perspective, ownerId, key }. Значения по умолчанию:
-- damage, self, source, run, окно 0 (весь забег).
function M.NewQuery(spec)
	local q = { apiVersion = 1, metric = spec.metric or "damage", scope = spec.scope or "self",
		period = spec.period or "run", groupBy = spec.groupBy or "source", windowSeconds = spec.window or 0 }
	if q.metric == "healing" and spec.perspective then
		q.healingPerspective = spec.perspective
	end
	if q.scope == "owner" then
		q.ownerId = spec.ownerId
	end
	local qo = { q = q, key = spec.key, result = nil, err = nil, rev = nil, at = nil, retryAt = nil, checkpointId = nil }
	table.insert(S.queries, qo)
	return qo
end

function M.DropQuery(qo)
	for i = table.getn(S.queries), 1, -1 do
		if S.queries[i] == qo then
			table.remove(S.queries, i)
		end
	end
end

-- Сменить владельца у запроса scope = owner: прежний результат недействителен.
function M.SetOwner(qo, ownerId)
	if qo.q.ownerId ~= ownerId then
		qo.q.ownerId = ownerId
		qo.result, qo.rev, qo.at, qo.retryAt, qo.err = nil, nil, nil, nil, nil
	end
end

local CP_ERRORS = { CHECKPOINT_EXPIRED = true, CHECKPOINT_INVALIDATED = true, INVALID_CHECKPOINT = true }

-- Снимок по запросу. Возвращает result (последний удачный, если новый не получен) и err последней попытки.
function M.Fetch(qo, force)
	local now = H.Now()
	if qo.retryAt and now < qo.retryAt then
		return qo.result, qo.err
	end
	local ctx, cerr = M.Context()
	if not ctx then
		return qo.result, cerr
	end
	if not force and qo.result then
		if qo.rev == ctx.counterRevision or (qo.at and now - qo.at < M.MIN_INTERVAL) then
			return qo.result, nil
		end
	end
	if now - S.budgetAt >= M.BUDGET_WINDOW then
		S.budgetAt = now
		S.budgetN = 0
		-- Пересчет отказанных: пометка живет два окна (запрос, который больше не спрашивают, место не держит).
		S.nStarved = 0
		for i = 1, table.getn(S.queries) do
			local o = S.queries[i]
			if o.starved then
				if now - o.starvedAt > 2 * M.BUDGET_WINDOW + 0.01 then
					o.starved = nil
				else
					S.nStarved = S.nStarved + 1
				end
			end
		end
	end
	local limit = M.BUDGET
	if not qo.starved then
		limit = limit - S.nStarved
	end
	if S.budgetN >= limit then
		if not qo.starved then
			qo.starved = true
			S.nStarved = S.nStarved + 1
		end
		qo.starvedAt = now
		M.stats.skipped = M.stats.skipped + 1
		return qo.result, qo.err
	end
	if qo.starved then
		qo.starved = nil
		S.nStarved = S.nStarved - 1
	end
	S.budgetN = S.budgetN + 1
	local q = qo.q
	q.runId = ctx.runId
	q.checkpointId = qo.checkpointId
	local r, e = Call1(AZS_GetMeterSnapshot, q)
	if r then
		M.stats.snapshots = M.stats.snapshots + 1
		qo.result, qo.err, qo.retryAt = r, nil, nil
		qo.rev = (r.context and r.context.counterRevision) or ctx.counterRevision
		qo.at = now
		return r, nil
	end
	M.stats.errors = M.stats.errors + 1
	M.stats.lastCode = e and e.code
	qo.err = e
	if e and e.retryable then
		qo.retryAt = now + (e.retryAfterSeconds or 1)
	else
		qo.retryAt = now + M.ERROR_PAUSE
	end
	if e and CP_ERRORS[e.code] then
		qo.checkpointId = nil
		qo.retryAt = now
		qo.rev = nil
	end
	return qo.result, e
end

----------------------------------------------------------------------------------------
-- Чекпойнты
----------------------------------------------------------------------------------------

function M.CheckpointCount()
	return S.nCp
end

function M.Release(id)
	if not id then
		return
	end
	Call1(AZS_ReleaseMeterCheckpoint, id)
	if S.cps[id] then
		S.cps[id] = nil
		S.nCp = S.nCp - 1
	end
end

-- "Reset" запроса: новый чекпойнт, прежний освобождается. Возвращает id или nil, причина.
function M.Checkpoint(qo)
	local caps = M.Caps()
	if caps and caps.features and caps.features.atomicCheckpoints == false then
		return nil, "unsupported"
	end
	local limit = (caps and caps.maxCheckpoints) or 64
	if S.nCp >= limit then
		return nil, "limit"
	end
	local runId = M.RunId()
	if not runId then
		return nil, "no run"
	end
	local cp, err = Call1(AZS_CreateMeterCheckpoint, runId)
	if not cp then
		return nil, err and err.code or "error"
	end
	local old = qo.checkpointId
	qo.checkpointId = cp.checkpointId
	S.cps[cp.checkpointId] = true
	S.nCp = S.nCp + 1
	if old then
		M.Release(old)
	end
	qo.rev, qo.retryAt, qo.at = nil, nil, nil
	H.Fire("METER_RESET", qo.key)
	return cp.checkpointId
end

-- Вернуть запрос к полному забегу (снять чекпойнт).
function M.ClearCheckpoint(qo)
	if qo.checkpointId then
		M.Release(qo.checkpointId)
		qo.checkpointId = nil
		qo.rev, qo.retryAt, qo.at = nil, nil, nil
		H.Fire("METER_RESET", qo.key)
	end
end

----------------------------------------------------------------------------------------
-- Адаптеры результата
----------------------------------------------------------------------------------------

function M.Rows(result)
	return result and result.rows or EMPTY
end

-- Сумма строки: displayAmount (поля amount нет), запасное periodAmount.
function M.RowAmount(row)
	return row.displayAmount or row.periodAmount or 0
end

-- Значение скорости строки (displayRate.value, если status ready) или nil.
function M.RowRate(row)
	local r = row.displayRate
	if r and r.status == "ready" then
		return r.value
	end
	return nil
end

function M.Total(result)
	if not result then
		return 0
	end
	local t = result.totals
	if t and (t.displayAmount or t.periodAmount) then
		return t.displayAmount or t.periodAmount
	end
	local sum = 0
	local rows = M.Rows(result)
	for i = 1, table.getn(rows) do
		sum = sum + M.RowAmount(rows[i])
	end
	return sum
end

-- Доля строки 0..1: row.share от движка, иначе сумма / итог.
function M.RowShare(row, total)
	if type(row.share) == "number" then
		return row.share
	end
	if total and total > 0 then
		return M.RowAmount(row) / total
	end
	return 0
end

local function Less(a, b)
	local x, y = M.RowAmount(a), M.RowAmount(b)
	if x ~= y then
		return x > y
	end
	return (a.tieOrder or 0) < (b.tieOrder or 0)
end

-- Строки с ненулевой суммой в out (очищается на месте), по убыванию суммы, затем tieOrder. Возвращает число.
function M.Sort(result, out)
	H.Wipe(out)
	local rows = M.Rows(result)
	for i = 1, table.getn(rows) do
		if M.RowAmount(rows[i]) > 0 then
			table.insert(out, rows[i])
		end
	end
	table.sort(out, Less)
	return table.getn(out)
end

-- Имя источника строки: sources[sourceKey].name или nil.
function M.SourceName(result, sourceKey)
	local s = result and result.sources and result.sources[sourceKey]
	return s and s.name or nil
end

-- Путь иконки источника, если она готова (icon.status == "ready"), иначе nil и статус.
function M.SourceIcon(result, sourceKey)
	local s = result and result.sources and result.sources[sourceKey]
	local icon = s and s.icon
	if icon and icon.status == "ready" then
		return icon.path
	end
	return nil, icon and icon.status or nil
end

-- Отладка: источники последнего результата первого запроса с данными (ключ, имя, статус иконки) в out.
function M.DebugActors(out)
	for i = 1, table.getn(S.queries) do
		local r = S.queries[i].result
		local ids = r and r.ownerIds
		if r and r.actors and ids and table.getn(ids) > 0 then
			table.insert(out, "ЗАПРОС "..i.." ownerIds: "..table.concat(ids, ","))
			local rows = M.Rows(r)
			for j = 1, math.min(table.getn(rows), 4) do
				table.insert(out, "  строка owner="..tostring(rows[j].ownerId))
			end
			for id, a in pairs(r.actors) do
				table.insert(out, "  актор "..tostring(id).." kind="..tostring(a.kind).." имя="..tostring(a.name).." класс="..tostring(a.classKey).." владелец="..tostring(a.currentOwnerId))
			end
		end
	end
end

function M.DebugSources(out)
	for i = 1, table.getn(S.queries) do
		local r = S.queries[i].result
		if r and r.sources then
			local rows = M.Rows(r)
			for j = 1, table.getn(rows) do
				if j <= 6 then
					table.insert(out, "  строка "..j.." sourceKey="..tostring(rows[j].sourceKey).." actor="..tostring(rows[j].actorId))
				end
			end
			for key, s in pairs(r.sources) do
				local ic = s.icon
				table.insert(out, "  "..tostring(key).." | "..tostring(s.name).." | "..(ic and (tostring(ic.status).." "..tostring(ic.path)) or "нет иконки"))
			end
			return
		end
	end
end

-- ownerId участников из снимка scope = party: result.ownerIds, иначе различные row.ownerId.
function M.Owners(result, out)
	H.Wipe(out)
	local ids = result and result.ownerIds
	if type(ids) == "table" and table.getn(ids) > 0 then
		for i = 1, table.getn(ids) do
			table.insert(out, ids[i])
		end
		return table.getn(out)
	end
	local rows = M.Rows(result)
	for i = 1, table.getn(rows) do
		local id = rows[i].ownerId
		if id ~= nil then
			local seen = false
			for j = 1, table.getn(out) do
				if out[j] == id then
					seen = true
				end
			end
			if not seen then
				table.insert(out, id)
			end
		end
	end
	return table.getn(out)
end

-- Имя героя владельца: актор kind = "hero" с currentOwnerId.
function M.OwnerName(result, ownerId)
	local actors = result and result.actors
	if actors then
		for id, a in pairs(actors) do
			if a.name and (a.kind == nil or a.kind == "hero") and (a.currentOwnerId == ownerId or a.actorId == ownerId or id == ownerId) then
				return a.name, a.classKey
			end
		end
	end
	-- Запасной путь: свой герой (владелец из контекста) всегда известен по имени и классу.
	local ctx = result and result.context
	if ctx and ctx.localOwnerId ~= nil and ctx.localOwnerId == ownerId and UnitName then
		local name = UnitName("player")
		local _, class
		if UnitClass then
			_, class = UnitClass("player")
		end
		return name, class
	end
	return nil
end

----------------------------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------------------------

local function OnRunStarted()
	for i = 1, table.getn(S.queries) do
		local qo = S.queries[i]
		qo.checkpointId = nil
		qo.result, qo.rev, qo.at, qo.retryAt, qo.err = nil, nil, nil, nil, nil
	end
	H.Wipe(S.cps)
	S.nCp = 0
	S.ctxOk, S.ctxAt, S.ctxRetry = false, nil, nil
end

local function OnLogout()
	for id in pairs(S.cps) do
		Call1(AZS_ReleaseMeterCheckpoint, id)
	end
	H.Wipe(S.cps)
	S.nCp = 0
end

function M.Reset()
	H.Wipe(S.ctx)
	S.ctxOk, S.ctxAt, S.ctxRetry, S.ctxErr, S.rev = false, nil, nil, nil, nil
	S.caps, S.capsLang = nil, nil
	H.Wipe(S.watch)
	S.nWatch = 0
	H.Wipe(S.queries)
	H.Wipe(S.cps)
	S.nCp = 0
	S.budgetAt, S.budgetN, S.nStarved = -1000, 0, 0
	M.stats.snapshots, M.stats.errors, M.stats.skipped, M.stats.contexts, M.stats.lastCode = 0, 0, 0, 0, nil
end

function M.Start()
	H.Clock.Every("meterdata", M.STEP, Tick)
end

H.Poll.AddLayer("meterdata", M.Reset, M.Start)
H.On("RUN_STARTED", "meterdata", OnRunStarted)
H.On("LOGOUT", "meterdata", OnLogout)
H.On("LOGIN", "meterdata", M.Start)
