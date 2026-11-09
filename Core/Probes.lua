-- HyoukaUI: каркас проб этапа 0 (plan 6.4, пробы 0.1-0.16) и команда /hui probe.
--
-- Каждая проба печатает сырые значения простым текстом в окно отладки (читается со
-- скриншота) и сохраняет те же строки в HyoukaUIDB.probes[N] (читается из файла
-- SavedVariables после выхода). Сами пробы лежат в ProbesData.lua (только чтение данных)
-- и ProbesUI.lua (создают временные кадры, интерактивные и с риском).
--
-- /hui probe            список проб
-- /hui probe N          одна проба (N = 1..16)
-- /hui probe all        все, что идут без участия человека
-- /hui probe N <арг>    у некоторых проб есть подкоманды (2 park/unpark/status, 6 stop,
--                       10 off, 11 off, 14 snap/compare)

local H = HyoukaUI

local P = {}
H.Probes = P

P.defs = {}        -- [n] = { n, title, question, auto, run }
P.results = {}     -- [n] = { lines, done }
P.shown = {}       -- номера проб, показанных в окне сейчас
P.MAX = 16

local R = {}
local R_META = { __index = R }

function R:Add(text)
	table.insert(self.lines, tostring(text))
end

-- Проба закончится позже (таймер, клик): вызвать Finish.
function R:Async()
	self.done = false
end

function R:Finish()
	if not self.done then
		self.done = true
	end
	P.Save(self)
	P.Redraw()
end

-- n: номер; def.title, def.question; def.auto: идет в "probe all"; def.run(r, arg).
function P.Define(n, def)
	def.n = n
	P.defs[n] = def
end

function P.Save(r)
	if type(HyoukaUIDB) ~= "table" then
		return
	end
	HyoukaUIDB.probes = HyoukaUIDB.probes or {}
	local keep = {}
	for i = 1, table.getn(r.lines) do
		keep[i] = r.lines[i]
	end
	HyoukaUIDB.probes[r.n] = { when = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = keep }
end

-- Окно показывает результаты проб из P.shown подряд.
function P.Redraw()
	local list = {}
	local pending = 0
	for i = 1, table.getn(P.shown) do
		local n = P.shown[i]
		local r = P.results[n]
		if r then
			for j = 1, table.getn(r.lines) do
				table.insert(list, r.lines[j])
			end
			if not r.done then
				pending = pending + 1
				table.insert(list, "... проба 0."..n.." еще идет")
			end
			table.insert(list, "")
		end
	end
	if P.footer then
		for i = 1, table.getn(P.footer) do
			table.insert(list, P.footer[i])
		end
	end
	H.Debug.Update(list, "probe "..table.concat(P.ShownNames(), ","))
end

function P.ShownNames()
	local names = {}
	for i = 1, table.getn(P.shown) do
		table.insert(names, tostring(P.shown[i]))
	end
	return names
end

-- Запустить пробу: вернуть результат (не показывая окно).
function P.Exec(n, arg)
	local def = P.defs[n]
	local r = setmetatable({ n = n, lines = {}, done = true }, R_META)
	P.results[n] = r
	if not def then
		r:Add("Нет пробы "..tostring(n))
		return r
	end
	r:Add("Проба 0."..n..": "..def.title)
	r:Add("Вопрос: "..def.question)
	local ok, err = pcall(def.run, r, arg)
	if not ok then
		r:Add("ОШИБКА пробы: "..tostring(err))
		H.ModuleError("debug", "проба 0."..n..": "..tostring(err))
		r.done = true
	end
	P.Save(r)
	return r
end

function P.Run(n, arg)
	P.shown = { n }
	P.footer = nil
	local r = P.Exec(n, arg)
	r.arg = arg
	P.Redraw()
	return r
end

function P.RunAll()
	P.shown = {}
	local manual = {}
	for n = 1, P.MAX do
		local def = P.defs[n]
		if def then
			if def.auto then
				table.insert(P.shown, n)
				P.Exec(n)
			else
				table.insert(manual, n)
			end
		end
	end
	P.footer = { "Не запускались (интерактивные или с риском для стоковых кадров): "..table.concat(manual, ", ")..". Запускать по одной: /hui probe N" }
	P.Redraw()
end

function P.ListLines()
	local list = { "Пробы этапа 0 (plan 6.4). /hui probe N, /hui probe all (только помеченные auto):" }
	for n = 1, P.MAX do
		local def = P.defs[n]
		if def then
			table.insert(list, string.format("  %2d  %s%s", n, def.title, def.auto and "" or "   [вручную]"))
		end
	end
	return list
end

H.Slash.Register("probe", function(rest)
	local _, _, a, b = string.find(rest or "", "^(%S*)%s*(.-)$")
	a = string.lower(a or "")
	if a == "" then
		H.Debug.Show(P.ListLines(), "probe")
		return
	end
	if a == "all" then
		P.RunAll()
		return
	end
	local n = tonumber(a)
	if not n or n < 1 or n > P.MAX or n ~= math.floor(n) then
		H.Debug.Show({ "Номер пробы 1..16 или all, получено: "..tostring(a) }, "probe")
		return
	end
	P.Run(n, b ~= "" and b or nil)
end, "probe [N|all] [арг] - пробы движка 0.1-0.16 (без аргумента: список)")
