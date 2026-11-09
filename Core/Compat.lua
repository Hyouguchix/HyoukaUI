-- HyoukaUI: совместимость с Lua 5.0 и мелкие помощники без аллокаций.
-- В 5.0 нет оператора #, оператора % (есть math.mod), string.match, select, ...

local H = HyoukaUI

H.Getn = table.getn
H.Mod = math.mod

-- Глобальное окружение: вместо getglobal, который есть не везде.
H.Env = getfenv(0)

function H.Global(name)
	return H.Env[name]
end

-- Очистить таблицу на месте. Присваивание nil существующему полю при обходе разрешено в 5.0.
-- Для массивов дополнительно table.setn(t, 0): в 5.0 getn не следит за присваиванием nil.
function H.Wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	if table.setn then
		table.setn(t, 0)
	end
	return t
end

-- Округление к ближайшему целому, половина вверх.
function H.Round(v)
	return math.floor(v + 0.5)
end

function H.Clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

function H.Num(v, default)
	local n = tonumber(v)
	if n == nil then
		return default
	end
	return n
end

-- Глубокая копия с ограничением глубины. skip = набор ключей верхнего уровня, которые не копируются.
function H.Copy(t, depth, skip)
	if type(t) ~= "table" then
		return t
	end
	depth = depth or 8
	local out = {}
	for k, v in pairs(t) do
		if not (skip and skip[k]) then
			if type(v) == "table" then
				if depth > 0 then
					out[k] = H.Copy(v, depth - 1)
				end
			else
				out[k] = v
			end
		end
	end
	return out
end

-- Разбить строку по разделителю (обычная подстрока, не шаблон). Пустые куски сохраняются.
function H.Split(s, sep)
	local out = {}
	local pos = 1
	local step = string.len(sep)
	while true do
		local i = string.find(s, sep, pos, true)
		if not i then
			table.insert(out, string.sub(s, pos))
			return out
		end
		table.insert(out, string.sub(s, pos, i - 1))
		pos = i + step
	end
end

function H.Trim(s)
	local _, _, body = string.find(s, "^%s*(.-)%s*$")
	return body or s
end

function H.StartsWith(s, prefix)
	return string.sub(s, 1, string.len(prefix)) == prefix
end

-- Ключи таблицы по порядку: числа, затем строки по алфавиту.
function H.SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta == tb and (ta == "number" or ta == "string") then
			return a < b
		end
		if ta ~= tb then
			return ta == "number"
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Пул объектов: Get отдает свободный или создает новый, Put возвращает.
function H.Pool(create, reset)
	local pool = { free = {}, made = 0 }
	function pool.Get()
		local n = table.getn(pool.free)
		if n > 0 then
			return table.remove(pool.free, n)
		end
		pool.made = pool.made + 1
		return create()
	end
	function pool.Put(obj)
		if reset then
			reset(obj)
		end
		table.insert(pool.free, obj)
	end
	return pool
end

-- Есть ли в окружении имя вида "string.match" или "hooksecurefunc".
function H.Has(path)
	local cur = H.Env
	local pos = 1
	while true do
		local dot = string.find(path, ".", pos, true)
		local part = string.sub(path, pos, (dot or string.len(path) + 1) - 1)
		if type(cur) ~= "table" then
			return false
		end
		cur = cur[part]
		if cur == nil then
			return false
		end
		if not dot then
			return true
		end
		pos = dot + 1
	end
end
