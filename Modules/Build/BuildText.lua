-- HyoukaUI: модуль Build, строки и текстовые помощники.
-- Первый файл модуля: создает таблицу H.Build, которую дополняют остальные файлы.
--
-- B.T(key)          строка модуля на языке интерфейса (H.Locale.code); нет ключа - английская; нет и ее - H.L
-- B.Lower(s)        строчные буквы для ASCII и кириллицы (string.lower в 1.12 кириллицу не трогает)
-- B.RomanValue(s)   "VII" -> 7, не римская строка -> nil
-- B.HasWord(s, list) есть ли в строке (уже в нижнем регистре) любая из подстрок списка (plain find)
-- Только простые дефисы, прямые кавычки, буква е без двух точек.

local H = HyoukaUI

H.Build = H.Build or {}
local B = H.Build

B.SLOT_IDS = { 2, 11, 12, 13, 14 }          -- шея, два кольца, два аксессуара (индексы слотов инвентаря 1.12)
B.SLOT_KEYS = { "slot_neck", "slot_ring", "slot_ring", "slot_trinket", "slot_trinket" }

-- Части модуля (список, значки, бижутерия, персонаж): каждая файл регистрирует себя B.AddPart(имя, enable, disable).
-- Build.lua зовет enable(M) на OnEnable и disable(M) на OnDisable; подписки на события идут через M:On.
B.parts = {}
function B.AddPart(name, enable, disable)
	table.insert(B.parts, { name = name, enable = enable, disable = disable })
end

-- Подписки частей: шина дает одну подписку на пару (событие, владелец), поэтому части подписываются через
-- B.Listen(event, fn), а Build.lua вешает на каждое событие один общий обработчик (B.Wire).
B.listeners = {}
function B.Listen(event, fn)
	local list = B.listeners[event]
	if not list then
		list = {}
		B.listeners[event] = list
	end
	for i = 1, table.getn(list) do
		if list[i] == fn then
			return
		end
	end
	table.insert(list, fn)
end

local STR = {
	enUS = {
		title = "Build", jewelry = "Jewelry", racial = "(racial)", empty_slot = "empty slot", slot_empty = "empty",
		slot_neck = "Neck", slot_ring = "Ring", slot_trinket = "Trinket", no_tags = "-",
		char_hero = "Hero", char_run = "This run", char_time = "Time", char_kills = "Kills", char_gold = "Gold",
		char_level = "Level", char_gear = "Equipment", char_build = "Build", char_talents = "Talents",
		char_no_talents = "no talents yet", char_headline = "Damage", char_health = "Health", char_close = "Close",
		char_worn = "Worn gear", char_drag = "Drag the title to move",
		sec_attack = "Offense", sec_defense = "Defense", sec_reach = "Reach", sec_utility = "Utility",
		sec_dot = "Damage over time", sec_bonus = "Bonus damage", sec_talents = "Talents",
		side_hint = "Side by side: Shift+C opens this window, C opens the game one.",
		o_module = "Module", o_mode = "Mode", o_list_head = "Build list", o_show_list = "Show the build list",
		o_col_cd = "Cooldown column", o_col_cd_hint = "Time left on the cooldown, floored at 0.25 s.",
		o_col_info = "Info column", o_col_info_hint = "Range or radius taken from the ability tooltip.",
		o_col_rank = "Rank column", o_roman = "Rank in Roman numerals",
		o_jewelry_head = "Jewelry", o_jewelry_rows = "Section in the build list", o_jewelry_icons = "Icons above the player frame",
		o_jewelry_names = "Item name in the row", o_jewelry_names_hint = "Off: slot, rank and bonus tags.",
		o_jewelry_empty = "Show empty slots",
		o_char_head = "Character window", o_char_window = "Own character window",
		o_char_window_hint = "Key C in Replace mode, Shift+C in Side by side mode.",
		o_hide_zero = "Hide zero stats", o_char_toggle = "Open or close the window",
		fallback = "Build stayed in Side by side mode: SurvivorUI has its build list or jewelry on. Turn them off in the SurvivorUI settings and pick Replace again.",
	},
	ruRU = {
		title = "Сборка", jewelry = "Бижутерия", racial = "(раса)", empty_slot = "пустой слот", slot_empty = "пусто",
		slot_neck = "Шея", slot_ring = "Кольцо", slot_trinket = "Аксессуар", no_tags = "-",
		char_hero = "Герой", char_run = "Этот забег", char_time = "Время", char_kills = "Убийства", char_gold = "Золото",
		char_level = "Уровень", char_gear = "Экипировка", char_build = "Сборка", char_talents = "Таланты",
		char_no_talents = "талантов пока нет", char_headline = "Урон", char_health = "Здоровье", char_close = "Закрыть",
		char_worn = "Надетая экипировка", char_drag = "Тяните за заголовок, чтобы переместить",
		sec_attack = "Атака", sec_defense = "Защита", sec_reach = "Охват", sec_utility = "Прочее",
		sec_dot = "Урон со временем", sec_bonus = "Бонус к урону", sec_talents = "Таланты",
		side_hint = "Рядом: Shift+C открывает это окно, C открывает окно игры.",
		o_module = "Модуль", o_mode = "Режим", o_list_head = "Список сборки", o_show_list = "Показывать список сборки",
		o_col_cd = "Колонка Откат", o_col_cd_hint = "Оставшееся время отката с полом 0.25 с.",
		o_col_info = "Колонка Info", o_col_info_hint = "Дальность или радиус из подсказки способности.",
		o_col_rank = "Колонка Ранг", o_roman = "Ранг римскими цифрами",
		o_jewelry_head = "Бижутерия", o_jewelry_rows = "Раздел в списке сборки", o_jewelry_icons = "Значки над рамкой игрока",
		o_jewelry_names = "В строке имя предмета", o_jewelry_names_hint = "Выключено: слот, ранг и теги бонусов.",
		o_jewelry_empty = "Показывать пустые слоты",
		o_char_head = "Окно персонажа", o_char_window = "Свое окно персонажа",
		o_char_window_hint = "Клавиша C в режиме Вместо, Shift+C в режиме Рядом.",
		o_hide_zero = "Скрывать нулевые статы", o_char_toggle = "Открыть или закрыть окно",
		fallback = "Сборка осталась в режиме Рядом: в SurvivorUI включены список сборки или бижутерия. Выключите их в настройках SurvivorUI и снова выберите режим Вместо.",
	},
}
B.STR = STR

function B.T(key)
	local loc = H.Locale and H.Locale.code or "enUS"
	local t = STR[loc]
	local v = t and t[key]
	if v == nil then
		v = STR.enUS[key]
	end
	if v == nil then
		v = H.L and H.L[key] or key
	end
	return v
end

-- Строчные буквы. ASCII через string.lower, кириллица (UTF-8, лидирующие байты 208 и 209) по таблице байтов.
-- Создает таблицу и строки: звать по событиям (разбор подсказок), не из покадрового кода.
function B.Lower(s)
	s = string.lower(s)
	local len = string.len(s)
	local parts, n, changed = {}, 0, false
	local i = 1
	while i <= len do
		local b = string.byte(s, i)
		local c = (i < len) and string.byte(s, i + 1) or nil
		local nb, nc
		if b == 208 and c then
			if c >= 144 and c <= 159 then
				nb, nc = 208, c + 32
			elseif c >= 160 and c <= 175 then
				nb, nc = 209, c - 32
			elseif c == 129 then
				nb, nc = 209, 145
			end
		end
		n = n + 1
		if nb then
			parts[n] = string.char(nb, nc)
			changed = true
			i = i + 2
		else
			parts[n] = string.sub(s, i, i)
			i = i + 1
		end
	end
	if not changed then
		return s
	end
	return table.concat(parts)
end

local ROMAN = { I = 1, V = 5, X = 10 }

function B.RomanValue(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local total, prev = 0, 0
	for i = string.len(s), 1, -1 do
		local v = ROMAN[string.sub(s, i, i)]
		if not v then
			return nil
		end
		if v < prev then
			total = total - v
		else
			total = total + v
			prev = v
		end
	end
	return total
end

function B.HasWord(s, list)
	for i = 1, table.getn(list) do
		if string.find(s, list[i], 1, true) then
			return true
		end
	end
	return false
end
