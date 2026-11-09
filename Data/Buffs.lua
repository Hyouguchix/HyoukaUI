-- HyoukaUI: Data\Buffs, баффы, таймеры талантов, призывы и тотемы (plan 2.2).
--
-- AZS_BUFFS: { spell, left }: полной длительности нет. Длительность Buffs.Duration(spell)
-- выводится по росту left: когда бафф появляется или обновляется (left вырос против прошлой строки),
-- значение left принимается за кандидата, длительность - максимум кандидатов. Хранится в
-- HyoukaUIDB.global.buffDur[spell] (переживает /reload, audit build-25).
-- Остаток Buffs.Left(spell) считается от опорной точки забега (часы Run.Time в момент строки),
-- поэтому на паузе и выборе карты он стоит (audit meter-35).
-- Таймеры (AZS_TIMERS), призывы (AZS_PETS), тотемы (AZS_TOTEMS) читаются обходом с колбэком,
-- без таблиц на вызов; остаток считается от часов забега.
-- Событие: BUFFS_CHANGED(n) на каждую строку баффов.

local H = HyoukaUI

local B = {}
H.Buffs = B

local S = { left = {}, seen = {}, gen = 0, refT = nil, dur = {} }

function B.Count()
	return table.getn(AZS_BUFFS)
end

function B.Row(i)
	return AZS_BUFFS[i]
end

function B.Active(spell)
	return S.left[spell] ~= nil
end

-- Остаток баффа в секундах от часов забега или nil, если баффа нет.
function B.Left(spell)
	local base = S.left[spell]
	if base == nil then
		return nil
	end
	local t = H.Run.Time()
	if t and S.refT then
		base = base - (t - S.refT)
	end
	-- Строки раз в ~2 с с дрожью: конец отсчета устойчивый (Run.SteadyEnd), иначе цифры гуляют на границе секунды.
	-- На паузе и выборе карты остаток стоит, там конец уезжает вместе с часами GetTime и сглаживать нечего.
	if base > 0 and H.Run.Phase() == "playing" then
		local now = GetTime()
		base = H.Run.SteadyEnd(-spell, now + base) - now
	end
	if base < 0 then
		base = 0
	end
	return base
end

-- Известная длительность баффа (секунды) или nil, пока не видели его появления.
function B.Duration(spell)
	return S.dur[spell]
end

-- Таймеры талантов и бижутерии: fn(name, icon, kind, duration, remaining, ready) для каждого.
-- kind: "summon" или "cooldown". Возвращает число таймеров.
function B.Timers(fn)
	local list = AZS_TIMERS
	local now = H.Run.Time() or 0
	local n = table.getn(list)
	for i = 1, n do
		local t = list[i]
		local rem = (t.ready or 0) - now
		if rem < 0 then
			rem = 0
		end
		fn(t.name, t.icon, t.kind, t.wait, rem, rem == 0)
	end
	return n
end

-- Призывы: fn(id, key, kind, name, icon, permanent, duration, remaining). Постоянные: ends < 0.
function B.Summons(fn)
	local list = AZS_PETS
	local now = H.Run.Time() or 0
	local n = table.getn(list)
	for i = 1, n do
		local p = list[i]
		local permanent = type(p.ends) ~= "number" or p.ends < 0
		local rem
		if not permanent then
			rem = p.ends - now
			if rem < 0 then
				rem = 0
			end
		end
		fn(p.id, p.key, p.kind, p.name, p.icon ~= "" and p.icon or nil, permanent, (not permanent) and p.dur or nil, rem)
	end
	return n
end

-- Тотемы: fn(key, spell, name, icon, count, cap, duration, remaining).
function B.Totems(fn)
	local list = AZS_TOTEMS
	local now = H.Run.Time() or 0
	local n = table.getn(list)
	for i = 1, n do
		local t = list[i]
		local rem = (t.ends or 0) - now
		if rem < 0 then
			rem = 0
		end
		fn(t.key, t.spell, t.name, t.icon, t.count, t.cap, t.dur, rem)
	end
	return n
end

-- Призывы по видам существ (движок): groups, total. Создает таблицы, звать по событию PETS.
function B.SummonGroups()
	if AZS_GetSummonGroups then
		return AZS_GetSummonGroups()
	end
	return {}, 0
end

local function Persist()
	local g = H.DB and H.DB.ready and H.DB.Global()
	if g then
		g.buffDur = g.buffDur or {}
		return g.buffDur
	end
	return nil
end

local function OnBuffs()
	local list = AZS_BUFFS
	S.gen = S.gen + 1
	S.refT = H.Run.Time()
	local store = Persist()
	for i = 1, table.getn(list) do
		local b = list[i]
		local spell, left = b.spell, b.left
		if spell ~= nil and type(left) == "number" then
			local prev = S.left[spell]
			if prev == nil or left > prev + 0.05 then
				local known = S.dur[spell] or (store and store[spell])
				if known == nil or left > known then
					known = left
				end
				S.dur[spell] = known
				if store then
					store[spell] = known
				end
			end
			S.left[spell] = left
			S.seen[spell] = S.gen
		end
	end
	for spell in pairs(S.left) do
		if S.seen[spell] ~= S.gen then
			S.left[spell] = nil
		end
	end
	H.Fire("BUFFS_CHANGED", table.getn(list))
end

function B.Reset()
	H.Wipe(S.left)
	H.Wipe(S.seen)
	H.Wipe(S.dur)
	S.gen = 0
	S.refT = nil
end

H.Poll.AddLayer("buffs", B.Reset)
H.On("BUFFS", "buffs", OnBuffs)
