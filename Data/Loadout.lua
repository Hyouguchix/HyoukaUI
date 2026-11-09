-- HyoukaUI: Data\Loadout, снаряжение, способности и бижутерия героя из AZS_GetMeterLoadout (plan 2.2).
--
-- Ответ: { loadoutRevision, ownerId, abilities, equipment, talents, runJewelry, sources, actors, ... }.
-- Факты проб 0.8: у abilities НЕТ abilityKey и icon.status; ключ способности лежит в sourceKey вида
-- "ability:<key>:r<rank>" (и в effectSourceKeys); поля: learned, passive, rank, selected, slotId,
-- sourceKey. equipment: 20 записей (slotId, supported, occupied, effectSourceKeys, itemInstanceKey?,
-- sourceKey?, itemLink?); itemKey и rank живут в sources[sourceKey], пока пусто - nil.
--
-- КЭШ по loadoutRevision. Запрос идет по триггерам (Request), не опросом: смена состава способностей
-- (SPELLS_CHANGED), UNIT_INVENTORY_CHANGED игрока, начало забега, явный запрос модуля для другого
-- владельца. Раз в 0.5 с обрабатывается очередь запросов, не чаще MIN_INTERVAL на владельца.
-- Ответ разбирается заново, только если ревизия сменилась; тогда LOADOUT_CHANGED(ownerId, revision).
-- Ошибка с retryable: повтор не раньше retryAfterSeconds. Допущение: slotId способности это номер
-- слота действий (проверить по /hui dump spells, там видны оба слота).

local H = HyoukaUI

local L = {}
H.Loadout = L

L.MIN_INTERVAL = 0.5
L.JEWELRY_SLOTS = { 2, 11, 12, 13, 14 }

local EMPTY = {}
local SELF = "self"
local cache = {}     -- ключ владельца -> { rev, data, abilities, slots, at, retryAt, err }
local pending = {}   -- ключ владельца -> ownerId или true
local req = { apiVersion = 1 }

L.stats = { requests = 0, changed = 0, errors = 0 }

-- "ability:fireball:r3" -> "fireball", 3. Ранг может отсутствовать. Не способность -> nil.
function L.ParseSource(sourceKey)
	if type(sourceKey) ~= "string" then
		return nil
	end
	local _, _, key, rank = string.find(sourceKey, "^ability:([^:]+):r(%d+)$")
	if key then
		return key, tonumber(rank)
	end
	_, _, key = string.find(sourceKey, "^ability:([^:]+)$")
	return key, nil
end

-- Ключ способности из записи loadout.abilities: abilityKey, если когда-то появится, иначе sourceKey.
function L.AbilityKey(row)
	if not row then
		return nil
	end
	if type(row.abilityKey) == "string" then
		return row.abilityKey
	end
	local key = L.ParseSource(row.sourceKey)
	return key
end

local function Entry(ownerId)
	local k = ownerId or SELF
	local c = cache[k]
	if not c then
		c = { abilities = {}, slots = {} }
		cache[k] = c
	end
	return c
end

local function Parse(c, data)
	H.Wipe(c.abilities)
	H.Wipe(c.slots)
	local list = data.abilities or EMPTY
	for i = 1, table.getn(list) do
		local row = list[i]
		local key = L.AbilityKey(row)
		if key then
			c.abilities[key] = row
			local s = row.slotId
			if type(s) == "number" and s >= 1 and s <= 12 and math.floor(s) == s then
				c.slots[key] = s
			end
		end
	end
end

-- Запросить loadout владельца (nil = герой клиента). force обходит MIN_INTERVAL. Возвращает true,
-- если ревизия сменилась; вторым значением "wait", если запрос не мог уйти (пауза или нет runId
-- контекста счетчика), очередь тогда оставит его.
function L.Refresh(ownerId, force)
	local c = Entry(ownerId)
	local now = H.Now()
	if not force and ((c.retryAt and now < c.retryAt) or (c.at and now - c.at < L.MIN_INTERVAL)) then
		return false, "wait"
	end
	local runId = H.MeterData.RunId()
	if not runId then
		return false, "wait"
	end
	req.runId = runId
	req.ownerId = ownerId
	c.at = now
	L.stats.requests = L.stats.requests + 1
	local ok, r, e = false, nil, nil
	if AZS_GetMeterLoadout then
		ok, r, e = pcall(AZS_GetMeterLoadout, req)
		if not ok then
			H.Errors.Add("loadout", tostring(r))
			r, e = nil, { code = "LUA_ERROR", retryable = false }
		end
	else
		e = { code = "UNAVAILABLE", retryable = false }
	end
	if not r then
		L.stats.errors = L.stats.errors + 1
		c.err = e
		c.retryAt = now + ((e and e.retryable and e.retryAfterSeconds) or 5)
		return false
	end
	c.err, c.retryAt = nil, nil
	if c.data and c.rev == r.loadoutRevision then
		return false
	end
	c.rev = r.loadoutRevision
	c.data = r
	Parse(c, r)
	L.stats.changed = L.stats.changed + 1
	H.Fire("LOADOUT_CHANGED", r.ownerId or ownerId, c.rev)
	return true
end

-- Поставить запрос в очередь (выполнится в ближайшие 0.5 с).
function L.Request(ownerId)
	pending[ownerId or SELF] = ownerId or true
end

-- Кэшированный разбор ответа или nil, пока не получен.
function L.Get(ownerId)
	local c = cache[ownerId or SELF]
	return c and c.data or nil
end

function L.Revision(ownerId)
	local c = cache[ownerId or SELF]
	return c and c.rev or nil
end

-- Последняя ошибка запроса или nil.
function L.Error(ownerId)
	local c = cache[ownerId or SELF]
	return c and c.err or nil
end

-- Слот действия способности героя клиента по ключу или nil (целое 1..12 из slotId).
function L.SlotOf(key)
	local c = cache[SELF]
	return c and c.slots[key] or nil
end

function L.AbilityRow(key)
	local c = cache[SELF]
	return c and c.abilities[key] or nil
end

local function SourceOf(data, sourceKey)
	return data and data.sources and sourceKey and data.sources[sourceKey] or nil
end

function L.Source(sourceKey, ownerId)
	local c = cache[ownerId or SELF]
	return SourceOf(c and c.data, sourceKey)
end

function L.AbilityName(key)
	local c = cache[SELF]
	local row = c and c.abilities[key]
	local src = row and SourceOf(c.data, row.sourceKey)
	return src and src.name or nil
end

-- Путь иконки способности из sources[...].icon, только если она готова (status "ready").
function L.AbilityIcon(key)
	local c = cache[SELF]
	local row = c and c.abilities[key]
	local src = row and SourceOf(c.data, row.sourceKey)
	local icon = src and src.icon
	if icon and icon.status == "ready" then
		return icon.path
	end
	return nil
end

-- Запись экипировки по слоту (2 шея, 11-12 кольца, 13-14 тринкеты...) или nil.
function L.Item(slotId, ownerId)
	local c = cache[ownerId or SELF]
	local list = c and c.data and c.data.equipment
	if not list then
		return nil
	end
	for i = 1, table.getn(list) do
		if list[i].slotId == slotId then
			return list[i]
		end
	end
	return nil
end

-- itemKey предмета в слоте (из записи или из sources). nil, пока слот пуст или поле неизвестно.
function L.ItemKey(slotId, ownerId)
	local row = L.Item(slotId, ownerId)
	if not row then
		return nil
	end
	if row.itemKey then
		return row.itemKey
	end
	local c = cache[ownerId or SELF]
	local src = SourceOf(c.data, row.sourceKey)
	return src and src.itemKey or nil
end

function L.ItemRank(slotId, ownerId)
	local row = L.Item(slotId, ownerId)
	if not row then
		return nil
	end
	if row.rank then
		return row.rank
	end
	local c = cache[ownerId or SELF]
	local src = SourceOf(c.data, row.sourceKey)
	return src and src.rank or nil
end

-- Бижутерия забега: список runJewelry ({ itemInstanceKey, sourceKey, category, slotId, effectSourceKeys }).
function L.Jewelry(ownerId)
	local c = cache[ownerId or SELF]
	return c and c.data and c.data.runJewelry or EMPTY
end

--@frame
local function Tick()
	for k, owner in pairs(pending) do
		if owner == true then
			owner = nil
		end
		local _, status = L.Refresh(owner, false)
		if status ~= "wait" then
			pending[k] = nil
		end
	end
end

local function OnSpellsChanged()
	L.Request(nil)
end

local function OnInventory(ev, unit)
	if unit == nil or unit == "player" then
		L.Request(nil)
	end
end

local function OnRunStarted()
	H.Wipe(cache)
	H.Wipe(pending)
	L.Request(nil)
end

local function OnPartyChanged()
	for k in pairs(cache) do
		if k ~= SELF then
			cache[k] = nil
		end
	end
end

function L.Reset()
	H.Wipe(cache)
	H.Wipe(pending)
	L.stats.requests, L.stats.changed, L.stats.errors = 0, 0, 0
end

function L.Start()
	H.Clock.Every("loadout", 0.5, Tick)
end

H.Poll.AddLayer("loadout", L.Reset, L.Start)
H.On("SPELLS_CHANGED", "loadout", OnSpellsChanged)
H.On("UNIT_INVENTORY_CHANGED", "loadout", OnInventory)
H.On("RUN_STARTED", "loadout", OnRunStarted)
H.On("PARTY_CHANGED", "loadout", OnPartyChanged)
H.On("LOGIN", "loadout", L.Start)
