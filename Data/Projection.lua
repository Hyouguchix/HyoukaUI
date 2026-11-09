-- HyoukaUI: Data\Projection, слой проекции мировых якорей на экран (мировые метки). Только этот файл читает
-- AZS_GetWorldAnchors, AZS_ProjectWorldAnchors, AZS_RegisterWorldAnchorFrameHandler и AZS_GetPlayerPosition. Ничего не
-- рисует: отдает экранные точки, расстояния и признаки "на экране / за краем / за камерой".
--
-- Раз в 0.25 с читается каталог якорей (до 6 страниц по 256) и раскладывается по видам chest (cache), boss (boss, finalBoss),
-- lair (guardianLair, guardian), elite, other (downedPartyMember). Каждый кадр ПОСЛЕ камеры (обработчик без аргументов, раз в кадр)
-- одним вызовом AZS_ProjectWorldAnchors проецируются нужные записи и зовутся подписчики. Пока никто не просит (Want), обработчик
-- движку не регистрируется и вызовов движка нет. Записи и запросы лежат в пулах: покадровый код таблиц не создает.
--
--   H.Proj.Available()          все функции движка есть
--   H.Proj.Want(owner, spec)    spec = { kinds = { chest = true ... }, arrows = { chest = true ... }, maxArrows, beam = ярдов
--                               луча вверх (0 нет), maxDist = ярдов (0 без предела) }; nil снимает запрос
--   H.Proj.Subscribe(owner, fn) fn() после каждого прохода под pcall; H.Proj.Unsubscribe(owner)
--   H.Proj.n, H.Proj.recs[i]    записи, только чтение: kind, raw (kind движка), name, state, unit, x, y, z (мир, ярды, чтение раз
--        в 0.25 с); vis P.NONE 0 | P.ON 1 | P.OFF 2 (за краем) | P.BEHIND 3 (за камерой); sx, sy точка метки (единицы UIParent
--        от BOTTOMLEFT, с подъемом над якорем); fx, fy, hasFoot основание луча; yard единиц экрана на ярд (0 не известно);
--        dist ярды до героя (nil, пока не известно); arrow, ax, ay единичный вектор на экране от героя к цели (ближайшие за кадром)
--   H.Proj.heroOk, hx, hy       точка героя на экране (пока считаются стрелки); H.Proj.Stats(); H.Proj.Reset() (DataReset)
-- Мир (SurvivorUI MapPins.lua, WorldMarks.lua): x на север, y на запад, z вверх. Ответ проекции в единицах WorldFrame, к UIParent
-- он приводится множителем WorldFrame:GetEffectiveScale() / UIParent:GetEffectiveScale() (так делает SurvivorUI).
-- Прием: проецировать можно якорь со смещением (offset в ярдах, любой), поэтому точка героя и точка в 6 ярдах от героя в сторону
-- цели берутся от неподвижного якоря (сундук, логово): линия между ними на экране - направление стрелки.
-- Лимит движка 256 запросов на вызов (больше - вся пачка отклоняется, hack-audit tracker-35): кадр держит не больше 250.
-- AZS_GetPlayerPosition отдает новую таблицу на вызов: он зовется только пока есть стрелки (и раз в 0.25 с для элитных).

local H = HyoukaUI

local P = {}
H.Proj = P

local getn = table.getn
local sqrt = math.sqrt

P.NONE, P.ON, P.OFF, P.BEHIND = 0, 1, 2, 3
P.KINDS = { "chest", "boss", "lair", "elite", "other" }

local READ_EVERY, PAGE, MAX_PAGES = 0.25, 256, 6
local MAX_RECS, MAX_ELITES = 64, 24
local MAX_REQ, MAX_WAYS, WAY = 250, 8, 6
local MAX_SPOT = MAX_REQ - 1 - MAX_WAYS
local VIS_OF = { onScreen = 1, offscreen = 2, behindCamera = 3 }

local KIND_OF = { cache = "chest", boss = "boss", finalBoss = "boss", guardianLair = "lair", guardian = "lair",
	elite = "elite", downedPartyMember = "other" }
local RAW_OF = { chest = { "cache" }, boss = { "boss", "finalBoss" }, lair = { "guardianLair", "guardian" },
	elite = { "elite" }, other = { "downedPartyMember" } }
local ATTACH = { cache = "position", guardianLair = "position", downedPartyMember = "position", boss = "overhead",
	finalBoss = "overhead", guardian = "overhead", elite = "overhead" }
local LIFT = { cache = 1.2, guardianLair = 3, downedPartyMember = 2.5, boss = 0.4, finalBoss = 0.4, guardian = 0.6,
	elite = 0.4 }
local OK_STATE = { cache = { present = true }, boss = { alive = true }, finalBoss = { alive = true }, guardian = { alive = true },
	elite = { alive = true }, guardianLair = { asleep = true, awake = true } }

local S = {
	n = 0, recs = {}, nxt = {}, byId = {}, spare = {}, spareN = 0, elites = {}, eliteN = 0,
	owners = {}, pages = {}, subs = {}, subN = 0, active = 0, registered = false,
	want = {}, arrowKind = {}, maxArrows = 0, beam = 0, maxDist = 0, query = { kinds = {} }, hasQuery = false,
	readAt = -100, dirty = true, baseId = nil, bx = 0, by = 0, bz = 0,
	reqs = {}, pool = {}, cand = {}, candQ = {}, candN = 0,
	reads = 0, passes = 0, errors = 0, lastReq = 0, maxReq = 0, lastErr = nil,
}
P.S = S
P.recs = S.recs
P.n = 0
P.heroOk, P.hx, P.hy = false, 0, 0

function P.Available()
	return AZS_GetWorldAnchors ~= nil and AZS_ProjectWorldAnchors ~= nil and AZS_RegisterWorldAnchorFrameHandler ~= nil
		and AZS_GetPlayerPosition ~= nil
end

local function NewRec()
	return { vis = 0, sx = 0, sy = 0, fx = 0, fy = 0, hasFoot = false, yard = 0, arrow = false, ax = 0, ay = 0, q = 0, qf = 0 }
end

-- Запись по id: прежняя (хранит vis и расстояние между чтениями), запасная или новая; seen - номер чтения.
local function Take(id)
	local r = S.byId[id]
	if not r then
		if S.spareN > 0 then
			r = S.spare[S.spareN]
			S.spare[S.spareN] = nil
			S.spareN = S.spareN - 1
			r.vis, r.dist, r.arrow, r.hasFoot, r.yard = 0, nil, false, false, 0
		else
			r = NewRec()
		end
		S.byId[id] = r
	end
	r.seen = S.reads
	return r
end

local function Free(r)
	S.spareN = S.spareN + 1
	S.spare[S.spareN] = r
end

local function Fill(r, e, raw)
	r.id, r.raw, r.kind, r.name, r.state, r.unit = e.anchorId, raw, KIND_OF[raw], e.name, e.state, e.unitId
	r.occupant = e.occupantUnitId
	r.x, r.y, r.z = e.x, e.y, e.z
	r.attach, r.lift = ATTACH[raw], LIFT[raw]
end

local function Make(e, raw)
	local r = Take(e.anchorId)
	Fill(r, e, raw)
	return r
end

local function Fail(ok, res, err)
	S.errors = S.errors + 1
	S.lastErr = (not ok and tostring(res)) or (type(err) == "table" and tostring(err.code)) or "no result"
end

local function Accept(raw, state)
	local ok = OK_STATE[raw]
	if ok then
		return ok[state] == true
	end
	return state ~= "departed" and state ~= "expired"
end

local function HeroPos()
	if not AZS_GetPlayerPosition then
		return nil
	end
	local ok, p = pcall(AZS_GetPlayerPosition)
	if not ok or type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then
		return nil
	end
	return p.x, p.y, p.z or 0, p.facing
end

-- Самые близкие к (px, py) MAX_ELITES элитных записей остаются; без героя - первые по порядку.
local function CutElites(px, py)
	local el, m = S.elites, S.eliteN
	if m <= MAX_ELITES then
		return m
	end
	if px then
		for i = 1, MAX_ELITES do
			local best, bd = i, nil
			for j = i, m do
				local dx, dy = el[j].x - px, el[j].y - py
				local d = dx * dx + dy * dy
				if not bd or d < bd then
					best, bd = j, d
				end
			end
			el[i], el[best] = el[best], el[i]
		end
	end
	for j = MAX_ELITES + 1, m do
		el[j].seen = -1
		el[j] = nil
	end
	return MAX_ELITES
end

-- Логово с бодрствующим стражем, который есть в этом чтении, отдает метку самому стражу.
local function DropOccupied(nxt, n)
	local keep = 0
	for i = 1, n do
		local r = nxt[i]
		local drop = false
		if r.raw == "guardianLair" then
			-- Бодрое логово и его живой страж - одна цель: по id юнита, а если движок его не отдал, по имени и близости (15 ярдов).
			for j = 1, n do
				local g = nxt[j]
				if g.raw == "guardian" then
					if r.occupant ~= nil and g.unit == r.occupant then
						drop = true
					elseif r.name ~= nil and g.name == r.name and r.x and g.x then
						local dx, dy = r.x - g.x, r.y - g.y
						if dx * dx + dy * dy < 225 then
							drop = true
						end
					end
				end
			end
		end
		if drop then
			r.seen = -1
		else
			keep = keep + 1
			nxt[keep] = r
		end
	end
	for i = n, keep + 1, -1 do
		nxt[i] = nil
	end
	return keep
end

local function ReadPages()
	local pages, cursor, count = S.pages, nil, 0
	for page = 1, MAX_PAGES do
		local ok, res, err = pcall(AZS_GetWorldAnchors, S.query, cursor, PAGE)
		if not ok or type(res) ~= "table" then
			Fail(ok, res, err)
			S.dirty = true
			return nil
		end
		count = page
		pages[page] = res
		if not res.hasMore or not res.nextCursor then
			break
		end
		cursor = res.nextCursor
	end
	return count
end

local function ReadCatalog()
	if not S.hasQuery or not AZS_GetWorldAnchors then
		return
	end
	S.reads = S.reads + 1
	local count = ReadPages()
	if not count then
		return
	end
	local recs, nxt = S.recs, S.nxt
	local n, base, px, py = 0, nil, nil, nil
	S.eliteN = 0
	if S.want.elite then
		px, py = HeroPos()
	end
	for page = 1, count do
		local entries = S.pages[page].entries
		S.pages[page] = nil
		if type(entries) == "table" then
			for i = 1, getn(entries) do
				local e = entries[i]
				local raw = type(e) == "table" and e.kind
				local kind = raw and KIND_OF[raw]
				if kind and type(e.x) == "number" and type(e.y) == "number" and Accept(raw, e.state) then
					if not base and (raw == "cache" or raw == "guardianLair") then
						S.baseId, S.bx, S.by, S.bz = e.anchorId, e.x, e.y, e.z or 0
						base = true
					end
					if S.want[kind] and kind == "elite" then
						S.eliteN = S.eliteN + 1
						S.elites[S.eliteN] = Make(e, raw)
					elseif S.want[kind] and n < MAX_RECS then
						n = n + 1
						nxt[n] = Make(e, raw)
					end
				end
			end
		end
	end
	if not base then
		S.baseId = nil
	end
	local m = CutElites(px, py)
	for j = 1, m do
		n = n + 1
		nxt[n] = S.elites[j]
		S.elites[j] = nil
	end
	n = DropOccupied(nxt, n)
	for id, r in pairs(S.byId) do
		if r.seen ~= S.reads then
			S.byId[id] = nil
			Free(r)
		end
	end
	S.recs, S.nxt = nxt, recs
	P.recs = nxt
	S.n, P.n = n, n
	S.lastErr = nil
end

local function NewReq()
	return { anchorId = false, attachment = "position", offset = { x = 0, y = 0, z = 0 } }
end

--@frame
local function Req(n, id, attach, ox, oy, oz)
	local r = S.pool[n]
	if not r then
		r = NewReq()
		S.pool[n] = r
	end
	r.anchorId, r.attachment = id, attach
	local o = r.offset
	o.x, o.y, o.z = ox, oy, oz
	-- Lua 5.0: у таблицы после table.remove есть поле n, getn читает его: рост только через table.insert
	local reqs = S.reqs
	if n <= getn(reqs) then
		reqs[n] = r
	else
		table.insert(reqs, r)
	end
	return n
end

--@frame
local function Decode(rec, e, ratio)
	local vis = VIS_OF[e.state]
	if vis == 1 then
		if type(e.x) == "number" and type(e.y) == "number" then
			rec.vis, rec.sx, rec.sy = 1, e.x * ratio, e.y * ratio
		else
			rec.vis = 0
		end
	else
		rec.vis = vis or 0
	end
	local d = e.playerDistance
	if type(d) == "number" then
		rec.dist = d
	end
	local y = e.uiUnitsPerYard
	if type(y) == "number" and y > 0 then
		rec.yard = y * ratio
	end
end

-- До MAX_WAYS ближайших записей с r.pick (вид просит стрелку, в прошлом кадре не на экране, не дальше предела).
--@frame
local function PickArrows()
	local limit, recs, k = S.maxArrows, S.recs, 0
	if limit > MAX_WAYS then
		limit = MAX_WAYS
	end
	while S.baseId and k < limit do
		local best, bd = nil, 0
		for i = 1, S.n do
			local r = recs[i]
			if r.pick and (not best or (r.dist or 0) < bd) then
				best, bd = i, r.dist or 0
			end
		end
		if not best then
			break
		end
		recs[best].pick = false
		k = k + 1
		S.cand[k] = best
	end
	return k
end

-- Запросы героя и точек в WAY ярдах от него к целям; возвращает число запросов.
--@frame
local function Ways(m)
	local k = PickArrows()
	S.candN = k
	S.heroQ = 0
	if k == 0 then
		return m
	end
	local hx, hy, hz = HeroPos()
	if not hx then
		S.candN = 0
		return m
	end
	m = Req(m + 1, S.baseId, "position", hx - S.bx, hy - S.by, hz - S.bz)
	S.heroQ = m
	local recs = S.recs
	for c = 1, k do
		local r = recs[S.cand[c]]
		local dx, dy = r.x - hx, r.y - hy
		local len = sqrt(dx * dx + dy * dy)
		local dz = (r.z or hz) - hz
		r.wd = sqrt(len * len + dz * dz)
		r.dist = r.wd
		if len > 0.5 then
			m = Req(m + 1, S.baseId, "position", hx + dx / len * WAY - S.bx, hy + dy / len * WAY - S.by, hz - S.bz)
			S.candQ[c] = m
		else
			S.candQ[c] = 0
		end
	end
	return m
end

--@frame
local function Notify()
	local subs = S.subs
	for i = 1, S.subN do
		local ok, err = pcall(subs[i].fn)
		if not ok then
			S.errors = S.errors + 1
			H.Errors.Add("proj", err)
		end
	end
end

--@frame
function P.Frame()
	if S.active == 0 then
		return
	end
	local now = GetTime()
	if S.dirty or now - S.readAt >= READ_EVERY then
		S.dirty = false
		S.readAt = now
		ReadCatalog()
	end
	S.passes = S.passes + 1
	local reqs, recs = S.reqs, S.recs
	local m, beam = 0, S.beam
	for i = 1, S.n do
		local r = recs[i]
		r.arrow, r.hasFoot, r.q, r.qf, r.yard, r.pick = false, false, 0, 0, 0, false
		if S.want[r.kind] then
			r.pick = S.arrowKind[r.kind] and r.vis ~= 1 and (S.maxDist <= 0 or (r.dist or 0) <= S.maxDist)
			if m >= MAX_SPOT then
				r.vis = 0
			elseif r.kind == "chest" and beam > 0 then
				r.q = Req(m + 1, r.id, r.attach, 0, 0, beam)
				r.qf = Req(m + 2, r.id, r.attach, 0, 0, 0)
				m = m + 2
			else
				r.q = Req(m + 1, r.id, r.attach, 0, 0, r.lift)
				m = m + 1
			end
		else
			r.vis = 0
		end
	end
	local total = Ways(m)
	for i = getn(reqs), total + 1, -1 do
		table.remove(reqs, i)
	end
	S.lastReq = total
	if total > S.maxReq then
		S.maxReq = total
	end
	P.heroOk = false
	if total > 0 then
		local ok, res, err = pcall(AZS_ProjectWorldAnchors, reqs)
		local entries = ok and type(res) == "table" and res.entries
		if not entries then
			Fail(ok, res, err)
			for i = 1, S.n do
				recs[i].vis = 0
			end
		else
			local ratio = WorldFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
			P.ratio = ratio
			for i = 1, S.n do
				local r = recs[i]
				if r.q > 0 then
					local e = entries[r.q]
					if e then
						Decode(r, e, ratio)
						if r.qf > 0 and r.vis == 1 then
							local f = entries[r.qf]
							if f and f.state == "onScreen" and type(f.x) == "number" and type(f.y) == "number" then
								r.hasFoot, r.fx, r.fy = true, f.x * ratio, f.y * ratio
								if r.yard <= 0 and beam > 0 then
									r.yard = (r.sy - r.fy) / beam
								end
							end
						end
					else
						r.vis = 0
					end
				end
			end
			local hq = S.heroQ
			if hq > 0 then
				local he = entries[hq]
				if he and he.state == "onScreen" and type(he.x) == "number" and type(he.y) == "number" then
					local hx, hy = he.x * ratio, he.y * ratio
					P.heroOk, P.hx, P.hy = true, hx, hy
					for c = 1, S.candN do
						local r = recs[S.cand[c]]
						local we = S.candQ[c] > 0 and entries[S.candQ[c]]
						if we and type(we.x) == "number" and type(we.y) == "number" then
							local dx, dy = we.x * ratio - hx, we.y * ratio - hy
							local len = sqrt(dx * dx + dy * dy)
							if len > 0.001 then
								r.arrow, r.ax, r.ay = true, dx / len, dy / len
								r.dist = r.wd
							end
						end
					end
				end
			end
		end
	end
	Notify()
end

-- Подписки и запросы

local function Merge()
	local want, arrows = S.want, S.arrowKind
	for i = 1, getn(P.KINDS) do
		want[P.KINDS[i]], arrows[P.KINDS[i]] = false, false
	end
	S.maxArrows, S.beam, S.maxDist, S.active = 0, 0, 0, 0
	local needBase = false
	for _, o in pairs(S.owners) do
		for i = 1, getn(P.KINDS) do
			local k = P.KINDS[i]
			want[k] = want[k] or (o.kinds and o.kinds[k]) or false
			if o.arrows and o.arrows[k] then
				arrows[k], needBase = true, true
			end
		end
		S.maxArrows = math.max(S.maxArrows, o.maxArrows or 0)
		S.beam = math.max(S.beam, o.beam or 0)
		-- предел расстояния: 0 у любого просящего (без предела) снимает предел у всех
		local md = o.maxDist or 0
		if S.active == 0 then
			S.maxDist = md
		elseif md <= 0 or S.maxDist <= 0 then
			S.maxDist = 0
		elseif md > S.maxDist then
			S.maxDist = md
		end
		S.active = S.active + 1
	end
	local kinds = S.query.kinds
	for i = getn(kinds), 1, -1 do
		table.remove(kinds, i)
	end
	for i = 1, getn(P.KINDS) do
		if want[P.KINDS[i]] then
			for j = 1, getn(RAW_OF[P.KINDS[i]]) do
				table.insert(kinds, RAW_OF[P.KINDS[i]][j])
			end
		end
	end
	if needBase then
		table.insert(kinds, "cache")
		table.insert(kinds, "guardianLair")
	end
	S.hasQuery = getn(kinds) > 0
	S.dirty = true
end

local function Engine()
	local should = S.active > 0 and S.subN > 0
	local fn = should and AZS_RegisterWorldAnchorFrameHandler or AZS_UnregisterWorldAnchorFrameHandler
	if should == S.registered or not fn then
		return
	end
	local ok, res = pcall(fn, P.Frame)
	S.registered = should and ok and res ~= nil
	if should and not S.registered then
		S.lastErr = "register failed"
	end
end

function P.Want(owner, spec)
	if spec == nil then
		S.owners[owner] = nil
	else
		local o = S.owners[owner]
		if not o then
			o = {}
			S.owners[owner] = o
		end
		o.kinds, o.arrows, o.maxArrows, o.beam, o.maxDist = spec.kinds, spec.arrows, spec.maxArrows, spec.beam, spec.maxDist
	end
	Merge()
	Engine()
end

function P.Subscribe(owner, fn)
	for i = 1, S.subN do
		if S.subs[i].owner == owner then
			S.subs[i].fn = fn
			return
		end
	end
	S.subN = S.subN + 1
	S.subs[S.subN] = { owner = owner, fn = fn }
	Engine()
end

function P.Unsubscribe(owner)
	for i = S.subN, 1, -1 do
		if S.subs[i].owner == owner then
			table.remove(S.subs, i)
			S.subN = S.subN - 1
		end
	end
	Engine()
end

function P.Reset()
	for id, r in pairs(S.byId) do
		S.byId[id] = nil
		Free(r)
	end
	for i = 1, S.n do
		S.recs[i] = nil
	end
	S.n, P.n = 0, 0
	S.baseId, S.readAt, S.dirty = nil, -100, true
	P.heroOk = false
end

function P.Stats()
	return S.n, S.reads, S.passes, S.lastReq, S.maxReq, S.errors, S.lastErr
end

H.Poll.AddLayer("proj", P.Reset)

-- Стоковые метки SurvivorUI (кружок с названием и расстоянием) дублируют наши. В режиме Вместо гасим их через его же
-- публичные функции (SurvivorUI_WorldOn / SurvivorUI_ToggleWorld) и возвращаем как было при выходе из режима и из игры.
local STOCK_KEYS = { "markDrawn", "worldOrbs", "worldBeams" }
local stockOff = {}

function P.SuppressStock(on)
	local env = H.Env
	local isOn, toggle = env.SurvivorUI_WorldOn, env.SurvivorUI_ToggleWorld
	if type(isOn) ~= "function" or type(toggle) ~= "function" then
		return
	end
	if on then
		for i = 1, table.getn(STOCK_KEYS) do
			local k = STOCK_KEYS[i]
			if not stockOff[k] and isOn(k) then
				toggle(k)
				stockOff[k] = true
			end
		end
	else
		for i = 1, table.getn(STOCK_KEYS) do
			local k = STOCK_KEYS[i]
			if stockOff[k] then
				stockOff[k] = nil
				if not isOn(k) then
					toggle(k)
				end
			end
		end
	end
end

H.On("LOGOUT", "proj", function()
	P.SuppressStock(false)
end)
