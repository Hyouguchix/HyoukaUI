-- HyoukaUI: Modules\Meter\Model.lua, модель представления над H.MeterData (без кадров).
--
-- ВИД (view) - то, что показывает одно место дока (колонка 1, колонка 2 сверху, колонка 2 снизу) или окно разбивки:
-- страница, строки по убыванию, итог, состояние ошибки. Каждое место имеет СВОИ запросы (по одному на вид запроса:
-- dmg, heal, party, boss, win), поэтому Reset одного места не трогает другое: чекпойнт привязан к запросу места.
--
-- СТРАНИЦЫ (plan 3.4):
--   damage   свои источники, сумма displayAmount            dps    те же данные, порядок и длина полосы по скорости
--   healing  выданное лечение (performed)                   party  герои группы (scope party, groupBy owner)
--   boss     бой с боссом (period encounter)                last30 окно windowSeconds = 30, сумма windowAmount
--   auto     (только настройка места) группа -> party, соло -> boss
-- Строка модели (item) - переиспользуемая таблица: name, r, g, b, icon, classKey, amount, rate, pct, sortKey, proc,
-- kind ("src", "owner", "others"), ownerId, sourceKey, actorId, row (сырая строка снимка). Таблицы живут между
-- обновлениями: на неизменных данных Update ничего не создает.
--
-- Значения ТОЛЬКО из полей снимка: displayAmount (сумма строки, поля amount нет), displayRate.value (скорость,
-- когда status ready), windowAmount (окно), share. Свою математику Reset не ведет: чекпойнты движка.

local H = HyoukaUI
local MU = H.MeterUI
local D = H.MeterData

local getn = table.getn
local floor = math.floor

local Mo = {}
MU.Model = Mo

local EMPTY = {}

Mo.ORDER = { "damage", "dps", "healing", "party", "boss", "last30" }
Mo.PAGES = {
	damage = { qkey = "dmg", measure = "amount", reset = true, label = "page_damage", empty = "empty_damage" },
	dps = { qkey = "dmg", measure = "rate", reset = true, label = "page_dps", empty = "empty_damage" },
	healing = { qkey = "heal", measure = "amount", reset = true, heal = true, label = "page_healing", empty = "empty_healing" },
	party = { qkey = "party", measure = "amount", reset = true, label = "page_party", empty = "empty_party", party = true },
	boss = { qkey = "boss", measure = "amount", reset = false, label = "page_boss", empty = "empty_boss" },
	last30 = { qkey = "win", measure = "window", reset = true, label = "page_last30", empty = "empty_damage" },
}
Mo.PAGE_OWNER = { qkey = "owner", measure = "amount", reset = false, label = "page_damage", empty = "bd_empty" }

local SPECS = {
	dmg = function(g) return { metric = "damage", scope = "self", groupBy = g, period = "run" } end,
	heal = function(g) return { metric = "healing", perspective = "performed", scope = "self", groupBy = g, period = "run" } end,
	party = function(g) return { metric = "damage", scope = "party", groupBy = "owner", period = "run" } end,
	boss = function(g) return { metric = "damage", scope = "self", groupBy = g, period = "encounter" } end,
	win = function(g) return { metric = "damage", scope = "self", groupBy = g, period = "run", window = 30 } end,
	owner = function(g) return { metric = "damage", scope = "owner", groupBy = "source", period = "run" } end,
	now = function(g) return { metric = "damage", scope = "self", groupBy = "source", period = "run", window = 5 } end,
	nowHeal = function(g) return { metric = "healing", perspective = "performed", scope = "self", groupBy = "source", period = "run", window = 5 } end,
}

-- Атлас классов окна создания персонажа (4 x 4 клетки по 64 пикселя). [НЕ ПРОВЕРЕНО в игре] раскладка клеток.
Mo.CLASS_ATLAS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
Mo.CLASS_COORDS = {
	warrior = { 0, 0.25, 0, 0.25 }, mage = { 0.25, 0.5, 0, 0.25 }, rogue = { 0.5, 0.75, 0, 0.25 }, druid = { 0.75, 1, 0, 0.25 },
	hunter = { 0, 0.25, 0.25, 0.5 }, shaman = { 0.25, 0.5, 0.25, 0.5 }, priest = { 0.5, 0.75, 0.25, 0.5 },
	warlock = { 0.75, 1, 0.25, 0.5 }, paladin = { 0, 0.25, 0.5, 0.75 },
}

----------------------------------------------------------------------------------------
-- Вид и запросы
----------------------------------------------------------------------------------------

function Mo.NewView(slot)
	return { slot = slot, qos = {}, items = {}, spare = {}, n = 0, total = 0, rate = nil, top = 0, code = nil,
		pageId = nil, page = nil, result = nil, dirty = true, pending = false, forcedAt = 0, state = "none", owner = nil }
end

local function GroupBy()
	return MU.opt.pets and "actor_source" or "source"
end

local function MakeQuery(view, qkey)
	local spec = SPECS[qkey](GroupBy())
	spec.key = "meter:"..tostring(view.slot)..":"..qkey
	if qkey == "owner" then
		spec.ownerId = view.owner
	end
	local qo = D.NewQuery(spec)
	view.qos[qkey] = qo
	return qo
end

-- Группировка питомцев поменялась: запросы остаются (с чекпойнтами), меняется только groupBy.
function Mo.RegroupViews(views)
	for i = 1, getn(views) do
		local v = views[i]
		for qkey, qo in pairs(v.qos) do
			if qkey ~= "party" and qkey ~= "owner" then
				qo.q.groupBy = GroupBy()
				qo.result, qo.rev, qo.at, qo.retryAt, qo.err = nil, nil, nil, nil, nil
			end
		end
		v.dirty = true
	end
end

-- Группа или соло по контексту счетчика (partyState), запасное: список героев группы.
function Mo.InGroup()
	local c = D.Context()
	if c and c.partyState ~= nil then
		return c.partyState ~= "solo"
	end
	return H.Party.InParty()
end

-- Настройка места (slotN) -> id страницы или nil, если место выключено. "auto" разворачивается.
function Mo.Resolve(view)
	if view.owner ~= nil or view.slot == 0 then
		return "owner"
	end
	local id = H.DB.Get("meter", MU.SLOT_KEYS[view.slot])
	if id == "off" then
		return nil
	end
	if id == "auto" or id == nil then
		return Mo.InGroup() and "party" or "boss"
	end
	if not Mo.PAGES[id] then
		return "damage"
	end
	return id
end

function Mo.PageOf(id)
	if id == "owner" then
		return Mo.PAGE_OWNER
	end
	return Mo.PAGES[id]
end

----------------------------------------------------------------------------------------
-- Построение строк
----------------------------------------------------------------------------------------

local function Cmp(a, b)
	if a.sortKey ~= b.sortKey then
		return a.sortKey > b.sortKey
	end
	return a.tie < b.tie
end

local function Item(view, n)
	local it = view.items[n]
	if not it then
		it = table.remove(view.spare) or {}
		table.insert(view.items, it)
	end
	return it
end

-- Сумма и ключ порядка строки по способу показа страницы.
local function Measure(row, measure)
	if measure == "window" then
		local w = row.windowAmount or 0
		return w, w
	end
	local amount = D.RowAmount(row)
	if measure == "rate" then
		return amount, D.RowRate(row) or 0
	end
	return amount, amount
end

local function FillSource(it, result, row, page)
	local name = D.SourceName(result, row.sourceKey) or "?"
	local color = row.sourceKey
	if row.actorId then
		local a = result.actors and result.actors[row.actorId]
		if a and a.kind ~= "hero" and a.name then
			name = a.name..": "..name
			color = row.actorId
		end
	end
	it.name = name
	it.r, it.g, it.b = H.SourceColor(color or "?")
	local icon, status = D.SourceIcon(result, row.sourceKey)
	-- Путь из движка не для всех способностей грузится как текстура (в игре 2026-11-09 пустые Экзорцизм, Освящение,
	-- Правосудие, Гнев небес), поэтому у способностей героя берем текстуру кнопки действия, она точно существует.
	do
		local _, _, ak = string.find(row.sourceKey or "", "^ability:([^:]+)")
		local si = ak and H.Spells.Find(ak)
		local act = si and H.Spells.ActionIcon(si)
		if type(act) == "string" and act ~= "" then
			icon = act
		end
	end
	if not icon then
		-- Движок отдает иконку не для всех строк (status не ready): у способностей героя она известна из слота,
		-- ключ берем из sourceKey вида ability:<key>:r<ранг> (в игре 2026-11-09 у Освящения и Экзорцизма иконки не было).
		local _, _, akey = string.find(row.sourceKey or "", "^ability:([^:]+)")
		if akey then
			local si = H.Spells.Find(akey)
			if si then
				icon = H.Spells.Icon(si)
			end
		end
	end
	it.icon = icon
	it.classKey = nil
	return status == "pending"
end

local function FillOwner(it, result, row)
	local name, class = D.OwnerName(result, row.ownerId)
	it.name = name or "?"
	it.classKey = class and string.lower(class) or nil
	it.r, it.g, it.b = H.Hero.ColorOf(it.classKey)
	it.icon = nil
	return false
end

local function Fold(view, items, n, key)
	local pct = MU.opt.fold
	if not pct or pct <= 0 or n < 3 then
		return n
	end
	local sum = 0
	for i = 1, n do
		sum = sum + items[i].sortKey
	end
	if sum <= 0 then
		return n
	end
	local first = n + 1
	for i = 1, n do
		if items[i].sortKey / sum * 100 < pct then
			first = i
			break
		end
	end
	if n - first + 1 < 2 then
		return n
	end
	local o = items[first]
	local amount, rate, key2, share = 0, 0, 0, 0
	local hasRate = false
	for i = first, n do
		local it = items[i]
		amount = amount + it.amount
		key2 = key2 + it.sortKey
		share = share + (it.share or 0)
		if it.rate then
			rate = rate + it.rate
			hasRate = true
		end
	end
	o.name, o.icon, o.classKey, o.kind = MU.S("others"), nil, nil, "others"
	o.r, o.g, o.b = 0.5, 0.5, 0.5
	o.amount, o.rate, o.sortKey, o.share = amount, hasRate and rate or nil, key2, share
	o.pct = floor(share * 100)
	o.proc, o.ownerId, o.sourceKey, o.actorId, o.row, o.count = false, nil, nil, nil, nil, n - first + 1
	return first
end

local function Build(view, result, page)
	local rows = result and result.rows or EMPTY
	local measure = page.measure
	local items = view.items
	local n = 0
	local pending = false
	local winTotal = 0
	if measure == "window" and result and result.totals then
		winTotal = result.totals.windowAmount or 0
	end
	for i = 1, getn(rows) do
		local row = rows[i]
		local amount, key = Measure(row, measure)
		local dup = nil
		if key > 0 or (measure == "rate" and amount > 0) then
			-- Ранги одной способности (ability:consecration:r1, :r4...) после повышения уровня приходят отдельными строками:
			-- сводим в одну строку по ключу без ранга, отдельно обычные и проковые.
			local base = not page.party and row.sourceKey and string.gsub(row.sourceKey, ":r%d+$", "") or nil
			if base and base ~= row.sourceKey then
				local isProc = row.procClassification == "proc" or (row.nativeProc == true and row.procClassification ~= "mixed")
				for j = 1, n do
					local o = items[j]
					if o.baseKey == base and o.proc == isProc and o.ownerId == row.ownerId and o.actorId == row.actorId then
						dup = o
						break
					end
				end
			end
			if dup then
				dup.amount = dup.amount + amount
				dup.sortKey = dup.sortKey + key
				local r2 = D.RowRate(row)
				if r2 then
					dup.rate = (dup.rate or 0) + r2
				end
				if measure ~= "window" then
					dup.share = dup.share + (row.share or 0)
					dup.pct = floor(dup.share * 100)
				end
			else
			n = n + 1
			local it = Item(view, n)
			it.baseKey = base
			it.row, it.tie, it.sortKey, it.amount = row, row.tieOrder or i, key, amount
			it.rate = D.RowRate(row)
			if measure == "window" then
				it.share = winTotal > 0 and amount / winTotal or 0
			else
				it.share = row.share or 0
			end
			it.pct = floor(it.share * 100)
			it.ownerId, it.sourceKey, it.actorId, it.count = row.ownerId, row.sourceKey, row.actorId, nil
			it.proc = row.procClassification == "proc" or (row.nativeProc == true and row.procClassification ~= "mixed")
			if page.party then
				it.kind = "owner"
				FillOwner(it, result, row)
			else
				it.kind = "src"
				if FillSource(it, result, row, page) then
					pending = true
				end
			end
			end
		end
	end
	for j = getn(items), n + 1, -1 do
		table.insert(view.spare, table.remove(items, j))
	end
	if n > 1 then
		table.sort(items, Cmp)
	end
	n = Fold(view, items, n)
	for j = getn(items), n + 1, -1 do
		table.insert(view.spare, table.remove(items, j))
	end
	view.n = n
	view.pending = pending
	view.top = n > 0 and items[1].sortKey or 0
	if measure == "window" then
		view.total = winTotal
	else
		view.total = D.Total(result)
	end
	view.rate = result and result.totals and D.RowRate(result.totals) or nil
	view.state = (result == nil) and "none" or (n == 0 and "empty" or "ok")
end

-- Обновить вид. force обходит кэш по ревизии. Возвращает true, если строки, итог или код ошибки поменялись.
function Mo.Update(view, force)
	local id = Mo.Resolve(view)
	if not id then
		local was = view.pageId
		view.pageId, view.page, view.n, view.state = nil, nil, 0, "off"
		return was ~= nil
	end
	local page = Mo.PageOf(id)
	local qo = view.qos[page.qkey] or MakeQuery(view, page.qkey)
	if qo.q.ownerId ~= view.owner and view.owner ~= nil then
		D.SetOwner(qo, view.owner)
	end
	local now = H.Now()
	if view.pending and now - view.forcedAt >= 1 then
		view.forcedAt = now
		force = true
	end
	local result, err = D.Fetch(qo, force)
	local code = err and err.code or nil
	if result == view.result and id == view.pageId and not view.dirty then
		if code ~= view.code then
			view.code = code
			return true
		end
		return false
	end
	view.dirty = false
	view.result, view.pageId, view.page, view.code = result, id, page, code
	Build(view, result, page)
	if view.pending then
		view.forcedAt = now
	end
	return true
end

-- Пометить вид устаревшим (смена забега, настройки): следующий Update перестроит строки.
function Mo.Dirty(view)
	view.dirty = true
	view.result = nil
end

-- Текст пустого состояния или nil, если строки есть. Ключ для MU.S.
function Mo.EmptyKey(view)
	if view.n > 0 then
		return nil
	end
	local code = view.code
	if code == "NO_PARTY" then
		return "no_party"
	elseif code == "NO_ENCOUNTER" then
		return "no_boss"
	elseif code == "NOT_READY" or code == "NO_RUN" or code == "NO_WORLD" or code == "NO_PLAYER" then
		return "no_data"
	elseif view.result == nil then
		return code and "no_data" or "loading"
	end
	local page = view.page
	return page and page.empty or "no_data"
end

-- Reset места: новый чекпойнт запроса текущей страницы. true или nil, причина.
function Mo.Reset(view)
	local id = Mo.Resolve(view)
	local page = id and Mo.PageOf(id)
	if not page or not page.reset then
		return nil, "none"
	end
	local qo = view.qos[page.qkey] or MakeQuery(view, page.qkey)
	local cp, why = D.Checkpoint(qo)
	view.dirty = true
	if cp then
		return true
	end
	return nil, why
end

-- NOW (inv meter #12): скорость за последние 5 с (windowSeconds = 5, recentRate), для подсказки шапки. Запрос создается при
-- первом наведении, дальше обновляется Fetch по правилам MeterData. nil, если для страницы NOW не имеет смысла или еще нет данных.
function Mo.NowRate(view, force)
	local id = view.pageId
	local page = id and Mo.PAGES[id]
	if not page or page.party or id == "boss" then
		return nil
	end
	local qkey = page.heal and "nowHeal" or "now"
	local qo = view.qos[qkey] or MakeQuery(view, qkey)
	local r = D.Fetch(qo, force)
	if r and r.totals then
		return D.RowRate(r.totals)
	end
	return nil
end

-- Освободить запросы вида и чекпойнты (выключение модуля).
function Mo.Dispose(view)
	for qkey, qo in pairs(view.qos) do
		D.ClearCheckpoint(qo)
		D.DropQuery(qo)
	end
	H.Wipe(view.qos)
	Mo.Dirty(view)
	view.n, view.state = 0, "none"
end

----------------------------------------------------------------------------------------
-- Вид владельца (окно разбивки, карточка героя)
----------------------------------------------------------------------------------------

function Mo.NewOwnerView(tag)
	local v = Mo.NewView(tag == "card" and -1 or 0)
	v.owner = false
	v.tag = tag
	return v
end

-- Сменить владельца. ownerId = nil снимает запрос.
function Mo.SetOwner(view, ownerId)
	if view.owner == ownerId then
		return
	end
	view.owner = ownerId
	local qo = view.qos.owner
	if qo then
		D.SetOwner(qo, ownerId)
	end
	Mo.Dirty(view)
end

-- Владелец задан: Update берет страницу "owner". Без владельца вид пуст.
function Mo.UpdateOwner(view, force)
	if not view.owner then
		return false
	end
	return Mo.Update(view, force)
end

----------------------------------------------------------------------------------------
-- Бижутерия и таланты владельца (из H.Loadout.Get): для карточки и окна разбивки
----------------------------------------------------------------------------------------

-- Имена бижутерии забега через запятую или nil.
function Mo.JewelryNames(data)
	local list = data and data.runJewelry
	local text = nil
	for i = 1, list and getn(list) or 0 do
		local src = data.sources and data.sources[list[i].sourceKey]
		local name = src and src.name or list[i].sourceKey
		text = text and (text..", "..name) or name
	end
	return text
end

-- Сумма рангов талантов.
function Mo.TalentPoints(data)
	local list = data and data.talents
	local sum = 0
	for i = 1, list and getn(list) or 0 do
		sum = sum + (list[i].rank or 0)
	end
	return sum
end
