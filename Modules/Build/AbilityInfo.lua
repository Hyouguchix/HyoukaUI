-- HyoukaUI: модуль Build, колонка Info списка сборки: дальность и радиус способности.
--
-- Текст берется из подсказки кнопки действия через Data\TooltipScan (один скрытый тултип, очередь с
-- лимитом, кэш сбрасывает сам TooltipScan). Здесь только разбор записи { n, left, right }:
--  * ищется число, за которым (после пробелов) идет слово-единица: yd, yds, yard..., ярд..., м;
--  * строка с "когда/once/as soon" (условие запуска, не дальность) пропускается;
--  * строка со словами радиуса (radius, within, area, радиус, област) дает kind = "area";
--    остальные строки с ярдами дают kind = "range"; дальность сильнее радиуса.
-- Шаблоны string.find только ASCII; слова ищутся plain-поиском в строке, приведенной к нижнему регистру.
-- Ключ способности берется из AZS_SPELLS через H.Spells.Key (английский ключ, имен не сравниваем).
-- Колонка выключается сама (A.Dead), если из 4 и более прочитанных подсказок не разобрана ни одна:
-- значит, формулировки клиента на этом языке не распознаны. Сброс при смене языка и состава способностей.
-- [НЕ ПРОВЕРЕНО] реальные формулировки дальности и радиуса в подсказках игры (см. handoff_build.md).

local H = HyoukaUI
local B = H.Build

local A = {}
B.Info = A

local TRIGGER = { "once", "as soon", "когда", "как только" }
local AREA = { "radius", "within", "area", "радиус", "област" }
local RANGE_FIRST = { "радиус действия" }       -- русская "дальность": слово radius здесь не площадь
local UNITS = { { "yd", true }, { "yard", false }, { "ярд", false }, { "м", true } }

local cache = {}       -- ключ способности -> { rank, kind, value }
A.stats = { scanned = 0, hits = 0, pending = 0 }

local function IsBreak(line, q)
	local c = string.byte(line, q)
	return c == nil or (c < 128 and not string.find(string.char(c), "%w"))
end

-- Единица ярдов сразу после позиции e (конец числа)?
local function UnitAfter(line, e)
	local p = e + 1
	while string.sub(line, p, p) == " " do
		p = p + 1
	end
	for i = 1, table.getn(UNITS) do
		local u, strict = UNITS[i][1], UNITS[i][2]
		local n = string.len(u)
		if string.sub(line, p, p + n - 1) == u then
			if not strict or IsBreak(line, p + n) or string.sub(line, p + n, p + n) == "s" then
				return true
			end
		end
	end
	return false
end

-- Разбор одной строки: kind, value или nil.
local function ParseLine(text)
	local line = B.Lower(text)
	if B.HasWord(line, TRIGGER) then
		return nil
	end
	local kind = "range"
	if B.HasWord(line, AREA) and not B.HasWord(line, RANGE_FIRST) then
		kind = "area"
	end
	local pos = 1
	while true do
		local s, e, num = string.find(line, "(%d+%.?%d*)", pos)
		if not s then
			return nil
		end
		if UnitAfter(line, e) then
			return kind, tonumber(num)
		end
		pos = e + 1
	end
end

-- Разбор записи подсказки: дальность важнее радиуса. kind или nil.
function A.Parse(rec)
	local areaVal
	for i = 1, rec.n do
		for side = 1, 2 do
			local text = (side == 1) and rec.left[i] or rec.right[i]
			if text and text ~= "" then
				local kind, val = ParseLine(text)
				if kind == "range" then
					return "range", val
				end
				if kind == "area" and not areaVal then
					areaVal = val
				end
			end
		end
	end
	if areaVal then
		return "area", areaVal
	end
	return nil, nil
end

-- Info способности i из AZS_SPELLS: kind ("range" | "area" | nil), value, ready (false, пока подсказка не готова).
function A.Get(i)
	local key = H.Spells.Key(i)
	if not key then
		return nil, nil, true
	end
	local rank = H.Spells.Rank(i)
	local c = cache[key]
	if c and c.rank == rank then
		return c.kind, c.value, true
	end
	local slot = H.Spells.SlotOf(i)
	if not slot then
		return nil, nil, true
	end
	local rec = H.TooltipScan.Spell(slot)
	if rec == "pending" then
		A.stats.pending = A.stats.pending + 1
		return nil, nil, false
	end
	local kind, value = A.Parse(rec)
	A.stats.scanned = A.stats.scanned + 1
	if kind then
		A.stats.hits = A.stats.hits + 1
	end
	cache[key] = { rank = rank, kind = kind, value = value }
	return kind, value, true
end

-- Разбор не удался на языке клиента: колонку Info лучше убрать.
function A.Dead()
	return A.stats.scanned >= 4 and A.stats.hits == 0
end

function A.Invalidate()
	H.Wipe(cache)
	A.stats.scanned, A.stats.hits = 0, 0
end

-- Текст числа: целое без дроби, иначе одна цифра после точки.
function A.NumText(v)
	local r = math.floor(v + 0.5)
	if math.abs(v - r) < 0.05 then
		return H.Format.Int(r)
	end
	return string.format("%.1f", v)
end
