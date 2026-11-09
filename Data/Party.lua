-- HyoukaUI: Data\Party, группа и воскрешение (plan 2.2): AZS_PARTY, AZS_REVIVE, AZS_DOWNED.
--
-- События: PARTY_CHANGED(n) при смене состава (имена, классы, число), DOWN_CHANGED(down) когда
-- герой упал или поднят (AZS_REVIVE.down), DOWNED_CHANGED(n) при смене списка лежащих соратников.
-- Кооп: лежащий герой или соратник не конец забега (это решает Run). Здесь только состояния.
--
-- Лежащие соратники читаются из сырого AZS_DOWNED (state == "down"), расстояние в ярдах считается
-- от AZS_GetPlayerPosition в одном пространстве (spaceId), раз в 0.5 с и только пока кто-то лежит.
-- Допущение, которое нужно проверить в игре: x, y, z в AZS_DOWNED и в AZS_GetPlayerPosition в
-- одних единицах (ярды мира, как у логов и сундуков).
-- Снимок группы на переходе героя в dead или victory (audit frames-45): Party.Snapshot().

local H = HyoukaUI

local P = {}
H.Party = P

P.DIST_STEP = 0.5

local S = {}
local function ResetState()
	S.n = 0
	S.names = {}
	S.classes = {}
	S.down = 0
	S.by = ""
	S.downed = {}
	S.nDowned = 0
	S.snapshot = {}
end
ResetState()

-- Участники: строки { name, class, dmg, dps, share, top, topdps }. Это живая таблица движка, только чтение.
function P.Members()
	return AZS_PARTY
end

function P.Count()
	return table.getn(AZS_PARTY)
end

function P.Member(i)
	return AZS_PARTY[i]
end

-- В группе, если героев в строках счетчика двое и больше (вне группы список пуст).
function P.InParty()
	return table.getn(AZS_PARTY) >= 2
end

-- Метка группы свежа относительно начала забега (через Run).
function P.IsFresh()
	return H.Run.IsFresh(AZS_PARTY_UPDATED)
end

-- Герой лежит (AZS_REVIVE.down == 1).
function P.IsDown()
	return AZS_REVIVE.down == 1
end

-- down (0/1), share (0..1, насколько героя подняли), by (кто поднимает или nil), reviving (кого
-- поднимает герой или nil), rshare. Пустые имена движка "" отдаются как nil.
function P.Revive()
	local r = AZS_REVIVE
	local by, reviving = r.by, r.reviving
	if by == "" then
		by = nil
	end
	if reviving == "" then
		reviving = nil
	end
	return r.down or 0, r.share or 0, by, reviving, r.rshare or 0
end

-- Лежащие соратники: массив записей { id, name, x, y, z, dist }, действительны первые DownedCount().
-- dist в ярдах или nil, если позиция недоступна. Таблицы переиспользуются: не хранить ссылки.
function P.Downed()
	return S.downed
end

function P.DownedCount()
	return S.nDowned
end

function P.IsMemberDown(name)
	for i = 1, S.nDowned do
		if S.downed[i].name == name then
			return true
		end
	end
	return false
end

-- Снимок группы, сделанный при переходе героя в dead или victory: массив копий строк.
function P.Snapshot()
	return S.snapshot
end

----------------------------------------------------------------------------------------
-- Обновления
----------------------------------------------------------------------------------------

local function RefreshDistances()
	local n = S.nDowned
	if n == 0 then
		return
	end
	local ok, pos = pcall(AZS_GetPlayerPosition)
	local valid = ok and type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
	for i = 1, n do
		local e = S.downed[i]
		e.dist = nil
		if valid and e.spaceId == pos.spaceId and type(e.x) == "number" and type(e.y) == "number" then
			local dx, dy = e.x - pos.x, e.y - pos.y
			e.dist = math.sqrt(dx * dx + dy * dy)
		end
	end
end

local function OnDowned()
	local list = AZS_DOWNED
	local n = 0
	for i = 1, table.getn(list) do
		local d = list[i]
		if d.state == "down" then
			n = n + 1
			local e = S.downed[n]
			if not e then
				e = {}
				S.downed[n] = e
			end
			e.id, e.name, e.x, e.y, e.z, e.spaceId, e.dist = d.id, d.name, d.x, d.y, d.z, d.spaceId, nil
		end
	end
	for i = n + 1, table.getn(S.downed) do
		local e = S.downed[i]
		e.id, e.name, e.x, e.y, e.z, e.spaceId, e.dist = nil, nil, nil, nil, nil, nil, nil
	end
	local changed = n ~= S.nDowned
	S.nDowned = n
	RefreshDistances()
	if changed or n > 0 then
		H.Fire("DOWNED_CHANGED", n)
	end
end

local function OnParty()
	local list = AZS_PARTY
	local n = table.getn(list)
	local changed = n ~= S.n
	for i = 1, n do
		local row = list[i]
		if S.names[i] ~= row.name or S.classes[i] ~= row.class then
			changed = true
			S.names[i] = row.name
			S.classes[i] = row.class
		end
	end
	for i = n + 1, S.n do
		S.names[i] = nil
		S.classes[i] = nil
	end
	S.n = n
	if changed then
		H.Fire("PARTY_CHANGED", n)
	end
end

local function OnRevive()
	local down = AZS_REVIVE.down or 0
	if down ~= S.down then
		S.down = down
		H.Fire("DOWN_CHANGED", down)
	end
	S.by = AZS_REVIVE.by or ""
end

local function OnPhase(ev, new)
	if new == "dead" or new == "victory" then
		local snap = {}
		local list = AZS_PARTY
		for i = 1, table.getn(list) do
			snap[i] = H.Copy(list[i], 1)
		end
		S.snapshot = snap
	end
end

local function OnRunStarted()
	S.snapshot = {}
end

--@frame
local function Tick()
	if S.nDowned > 0 then
		RefreshDistances()
	end
end

function P.Reset()
	ResetState()
end

function P.Start()
	H.Clock.Every("party", P.DIST_STEP, Tick)
end

H.Poll.AddLayer("party", P.Reset, P.Start)
H.On("PARTY", "party", OnParty)
H.On("REVIVE", "party", OnRevive)
H.On("DOWNED", "party", OnDowned)
H.On("PHASE_CHANGED", "party", OnPhase)
H.On("RUN_STARTED", "party", OnRunStarted)
H.On("LOGIN", "party", P.Start)
