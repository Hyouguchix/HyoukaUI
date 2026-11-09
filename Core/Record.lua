-- HyoukaUI: запись сырых строк сервера (CHAT_MSG_ADDON с префиксом AZS*) для фикстур тестов.
--
-- /hui record            включить или выключить запись
-- /hui record mark <текст>  поставить метку в записи (старт, босс, левелап, смерть, конец)
-- /hui record clear      стереть записанное
--
-- Записи лежат в HyoukaUIDB.fixtures.entries как { t, p, m } (время GetTime, префикс, строка)
-- и попадают в файл SavedVariables при выходе или /reload. Запись ограничена по числу и
-- по длине строки; повтор той же строки с тем же префиксом подряд не пишется.

local H = HyoukaUI

local R = {}
H.Record = R

R.MAX_ENTRIES = 2000
R.MAX_LEN = 1500
R.on = false
R.last = {}        -- префикс -> последняя записанная строка
R.skipped = 0      -- сколько строк не записано из-за лимита
R.cut = 0          -- сколько строк обрезано по длине

function R.IsOn()
	return R.on
end

local function Store()
	if type(HyoukaUIDB) ~= "table" then
		return nil
	end
	local f = HyoukaUIDB.fixtures
	if not f then
		f = { entries = {} }
		HyoukaUIDB.fixtures = f
	end
	return f
end

function R.Count()
	local f = type(HyoukaUIDB) == "table" and HyoukaUIDB.fixtures
	return f and f.entries and table.getn(f.entries) or 0
end

function R.Add(prefix, msg)
	local f = Store()
	if not f then
		return false
	end
	if table.getn(f.entries) >= R.MAX_ENTRIES then
		R.skipped = R.skipped + 1
		return false
	end
	msg = tostring(msg or "")
	local entry = { t = H.Now(), p = prefix, m = msg }
	if string.len(msg) > R.MAX_LEN then
		entry.m = string.sub(msg, 1, R.MAX_LEN)
		entry.cut = 1
		R.cut = R.cut + 1
	end
	table.insert(f.entries, entry)
	return true
end

local function OnMessage(ev, prefix, msg)
	if not R.on or type(prefix) ~= "string" then
		return
	end
	if string.sub(prefix, 1, 3) ~= "AZS" then
		return
	end
	if R.last[prefix] == msg then
		return
	end
	R.last[prefix] = msg
	R.Add(prefix, msg)
end

function R.Start()
	local f = Store()
	if not f then
		return false
	end
	f.entries = {}
	f.started = date and date("%Y-%m-%d %H:%M:%S") or "?"
	f.note = "сырые строки CHAT_MSG_ADDON, префикс AZS*; t = GetTime()"
	f.version = H.version
	H.Wipe(R.last)
	R.skipped = 0
	R.cut = 0
	R.on = true
	H.On("CHAT_MSG_ADDON", "record", OnMessage)
	return true
end

function R.Stop()
	R.on = false
	H.Off("CHAT_MSG_ADDON", "record")
	local f = Store()
	if f then
		f.stopped = date and date("%Y-%m-%d %H:%M:%S") or "?"
	end
end

function R.Mark(text)
	if not R.on then
		return false
	end
	return R.Add("MARK", text)
end

function R.Clear()
	R.on = false
	H.Off("CHAT_MSG_ADDON", "record")
	if type(HyoukaUIDB) == "table" then
		HyoukaUIDB.fixtures = nil
	end
	H.Wipe(R.last)
end

function R.Status()
	return "запись "..(R.on and "ИДЕТ" or "выключена")..", записей "..R.Count().." из "..R.MAX_ENTRIES..", пропущено по лимиту "..R.skipped..", обрезано по длине "..R.cut
end

H.Slash.Register("record", function(rest)
	local _, _, cmd, arg = string.find(rest or "", "^(%S*)%s*(.-)$")
	cmd = string.lower(cmd or "")
	if cmd == "mark" then
		if R.Mark(arg ~= "" and arg or "mark") then
			H.Print("метка записана: "..arg)
		else
			H.Print("запись не идет, метка не поставлена")
		end
	elseif cmd == "clear" then
		R.Clear()
		H.Print("записанное стерто")
	elseif cmd == "status" then
		H.Print(R.Status())
	elseif R.on then
		R.Stop()
		H.Print("запись остановлена. "..R.Status().." Данные попадут в SavedVariables при выходе или /reload.")
	else
		if R.Start() then
			H.Print("запись включена (до "..R.MAX_ENTRIES.." строк AZS*). Играй забег, метки: /hui record mark <текст>. Остановить: /hui record")
		else
			H.Print("запись не началась: сохранения еще не готовы")
		end
	end
end, "record [mark <текст>|clear|status] - запись сырых строк AZS* в HyoukaUIDB.fixtures")
