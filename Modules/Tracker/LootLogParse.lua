-- HyoukaUI: Modules\Tracker\LootLogParse, разбор строк добычи для панели tr.loot (Tr.LootParse). Рисования здесь нет.
--
-- Движок ничего не говорит о добыче через API аддонов: она приходит строками чата "Вы получаете добычу: [предмет]" (событие
-- CHAT_MSG_LOOT и та же строка в окне чата). Строка может нести ссылку "|cffRRGGBB|Hitem:id:...|h[Имя]|h|r" или одно
-- имя в скобках; за предметом может стоять "x2". Lua 5.0: ни string.match, ни string.gmatch, разбор через string.find.
--
-- LP.Received(message)             текст после слов "Вы получаете добычу:" (любой язык из списка) или nil
-- LP.Items(rest, pool, max)        предметы из rest в переиспользуемые записи pool[i] = { name, color, link, id, count }; число найденных
-- LP.Fresh(text, way, now)         одна и та же строка могла прийти и событием, и через окно чата: true, если эта дорожка
--                                  принесла строку больше раз, чем другая (две одинаковые строки подряд считаются обе)
-- LP.Rgb(hex)                      "ffa335ee" -> r, g, b (0..1) или nil
-- LP.Reset()                       забыть последние строки (тесты)
-- Только простые дефисы и прямые кавычки; не-ASCII (слова языков) стоит только в списке RECEIVE и ищется простым find.

local H = HyoukaUI

local Tr = H.Tr or {}
H.Tr = Tr

local LP = {}
Tr.LootParse = LP

local find, sub, tonumber = string.find, string.sub, tonumber

-- Слова строки "Вы получаете добычу:" на языках игры (как их пишет сервер); простой поиск без шаблонов.
local RECEIVE = {
	"You receive loot:", "You receive item:", "Вы получаете добычу:", "Вы получаете предмет:",
	"Otrzymujesz łup:", "Du erhältst Beute:", "Você recebe saque:", "Recibes botín:", "Vous recevez du butin :",
	"Ganimet aldın:", "你获得了战利品：", "전리품을 받았습니다:", "Primești pradă:", "Ви отримуєте здобич:",
	"戦利品を入手：", "Získáváš kořist:",
}

function LP.Received(message)
	if type(message) ~= "string" then
		return nil
	end
	for i = 1, table.getn(RECEIVE) do
		local _, last = find(message, RECEIVE[i], 1, true)
		if last then
			return sub(message, last + 1)
		end
	end
	local _, _, rest = find(message, "You receive [%a ]+: (.+)")
	return rest
end

function LP.Rgb(hex)
	if type(hex) ~= "string" or string.len(hex) ~= 8 then
		return nil
	end
	local r, g, b = tonumber(sub(hex, 3, 4), 16), tonumber(sub(hex, 5, 6), 16), tonumber(sub(hex, 7, 8), 16)
	if not (r and g and b) then
		return nil
	end
	return r / 255, g / 255, b / 255
end

local HEAD = 90

-- Предметы строки: ссылка дает цвет, link ("item:id:...") и id; без ссылки остается имя в скобках.
function LP.Items(rest, pool, max)
	local n, pos = 0, 1
	max = max or 8
	while n < max do
		local a, b, name = find(rest, "%[(.-)%]", pos)
		if not a then
			break
		end
		local head = sub(rest, math.max(1, a - HEAD), a - 1)
		local color, link
		local _, _, c, l = find(head, "|c(%x%x%x%x%x%x%x%x)|H(item:[%d:%-]+)|h$")
		if c then
			color, link = c, l
		else
			_, _, color = find(head, "|c(%x%x%x%x%x%x%x%x)$")
			_, _, link = find(head, "|H(item:[%d:%-]+)|h$")
		end
		pos = b + 1
		local _, tail = find(rest, "^|h|r", pos)
		if tail then
			pos = tail + 1
		end
		local count = 1
		local _, cEnd, cnt = find(rest, "^ ?x(%d+)", pos)
		if cnt then
			count = tonumber(cnt) or 1
			pos = cEnd + 1
		end
		if name ~= "" then
			n = n + 1
			local rec = pool[n]
			if not rec then
				rec = {}
				pool[n] = rec
			end
			rec.name, rec.color, rec.link, rec.count = name, color, link, count
			rec.id = nil
			if link then
				local _, _, id = find(link, "^item:(%d+)")
				rec.id = tonumber(id)
			end
		end
	end
	return n
end

local recent = {}

function LP.Reset()
	for k in pairs(recent) do
		recent[k] = nil
	end
end

function LP.Fresh(text, way, now)
	for line, seen in pairs(recent) do
		if now - seen.at >= 1 then
			recent[line] = nil
		end
	end
	local seen = recent[text]
	if not seen then
		seen = { at = now, event = 0, window = 0 }
		recent[text] = seen
	end
	seen[way] = seen[way] + 1
	return seen[way] > seen[way == "event" and "window" or "event"]
end
