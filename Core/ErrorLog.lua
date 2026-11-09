-- HyoukaUI: сборщик ошибок Lua (перенос из SurvivorUITweaks\ErrorLog.lua).
--
-- У игры нет файла с ошибками. Ошибки любых аддонов собираются здесь по корзинам
-- (аддон или модуль HyoukaUI) и при выходе попадают в HyoukaUIDB.report.
-- Обработчик ставится поверх прежнего и всегда передает ошибку дальше, как раньше.
-- Загружается вторым и ловит ошибки всех следующих файлов.

local H = HyoukaUI

local E = {}
H.Errors = E

E.MOST = 60          -- разных записей в одной корзине
E.buckets = {}       -- имя -> { list = {}, seen = {}, count = 0, overflow = 0 }
E.order = {}         -- имена корзин в порядке появления
E.total = 0          -- все ошибки подряд, с повторами
E.installed = false
E.available = false  -- есть ли seterrorhandler вообще
E.previous = nil
E.quiet = nil        -- подстрока: такие ошибки не уходят в прежний обработчик (пробы)

-- Имя корзины по тексту ошибки 1.12: "Interface\AddOns\<Аддон>\<путь>.lua:<строка>: ...".
-- Для HyoukaUI корзина уточняется папкой или модулем.
function E.Bucket(msg)
	msg = tostring(msg or "")
	local _, _, addon, rest = string.find(msg, "AddOns[\\/]([^\\/:]+)[\\/](.*)")
	if not addon then
		return "other"
	end
	if addon ~= "HyoukaUI" then
		return addon
	end
	local _, _, dir = string.find(rest, "^([^\\/:]+)[\\/]")
	if dir == "Modules" then
		local _, _, mod = string.find(rest, "^Modules[\\/]([^\\/:]+)[\\/]")
		if mod then
			return "HyoukaUI/"..mod
		end
	end
	if dir then
		return "HyoukaUI/"..dir
	end
	return "HyoukaUI"
end

local function GetBucket(name)
	local b = E.buckets[name]
	if not b then
		b = { list = {}, seen = {}, count = 0, overflow = 0 }
		E.buckets[name] = b
		table.insert(E.order, name)
	end
	return b
end

-- Запомнить ошибку. owner = явная корзина (модуль), иначе по тексту. Дубли по тексту
-- не плодят записи, а увеличивают count.
function E.Add(owner, msg)
	msg = tostring(msg or "?")
	local name = owner or E.Bucket(msg)
	local b = GetBucket(name)
	b.count = b.count + 1
	E.total = E.total + 1
	local entry = b.seen[msg]
	if entry then
		entry.count = entry.count + 1
		return entry
	end
	if table.getn(b.list) >= E.MOST then
		b.overflow = b.overflow + 1
		return nil
	end
	entry = { text = msg, count = 1, at = math.floor(H.Now()) }
	b.seen[msg] = entry
	table.insert(b.list, entry)
	return entry
end

-- Список записей корзины (пустой, если ошибок не было).
function E.List(owner)
	local b = E.buckets[owner]
	if not b then
		return {}
	end
	return b.list
end

-- Сколько ошибок случилось (с повторами). Без аргумента: во всех корзинах.
function E.Count(owner)
	if not owner then
		return E.total
	end
	local b = E.buckets[owner]
	return b and b.count or 0
end

-- Сколько разных записей хранится.
function E.Distinct(owner)
	local b = E.buckets[owner]
	return b and table.getn(b.list) or 0
end

function E.Clear(owner)
	if owner then
		local b = E.buckets[owner]
		if b then
			E.total = E.total - b.count
			b.list = {}
			b.seen = {}
			b.count = 0
			b.overflow = 0
		end
		return
	end
	E.buckets = {}
	E.order = {}
	E.total = 0
end

-- Убрать записи, содержащие метку (пробы стирают за собой свои тестовые ошибки).
function E.Forget(marker)
	for i = 1, table.getn(E.order) do
		local b = E.buckets[E.order[i]]
		local keep = {}
		for j = 1, table.getn(b.list) do
			local entry = b.list[j]
			if string.find(entry.text, marker, 1, true) then
				b.seen[entry.text] = nil
				b.count = b.count - entry.count
				E.total = E.total - entry.count
			else
				table.insert(keep, entry)
			end
		end
		b.list = keep
	end
end

-- Обработчик ошибок 1.12: запомнить и передать прежнему обработчику.
function E.Handler(message)
	pcall(E.Add, nil, message)
	local previous = E.previous
	if previous and not (E.quiet and string.find(tostring(message), E.quiet, 1, true)) then
		return previous(message)
	end
end

-- Ставит обработчик поверх прежнего. Без seterrorhandler (проба 0.1) не падает.
function E.Install()
	if E.installed then
		return true
	end
	if type(seterrorhandler) ~= "function" then
		E.available = false
		return false
	end
	E.available = true
	if type(geterrorhandler) == "function" then
		E.previous = geterrorhandler()
	end
	seterrorhandler(E.Handler)
	E.installed = true
	return true
end

-- Отчет для HyoukaUIDB.report (пишет Boot на PLAYER_LOGOUT).
function E.Report()
	local report = { version = H.version, total = E.total, buckets = {} }
	if date then
		report.when = date("%Y-%m-%d %H:%M:%S")
	end
	for i = 1, table.getn(E.order) do
		local name = E.order[i]
		local b = E.buckets[name]
		local out = { count = b.count, overflow = b.overflow, list = {} }
		for j = 1, table.getn(b.list) do
			local entry = b.list[j]
			out.list[j] = { text = entry.text, count = entry.count, at = entry.at }
		end
		report.buckets[name] = out
	end
	return report
end

E.Install()
