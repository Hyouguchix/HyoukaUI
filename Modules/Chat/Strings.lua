-- HyoukaUI: Modules\Chat\Strings, строки модуля Чат (русский и английский).
-- Ядро Locale не правится: у модуля свои таблицы. Str.Get(key) берет язык из H.Locale.code, нет строки - английская,
-- нет и ее - сам ключ. Только простые дефисы и прямые кавычки.

local H = HyoukaUI
local C = H.Chat

local Str = {}
C.Str = Str

local STR = {}
Str.STR = STR

STR.ruRU = {
	label = "Чат", piece = "Чат", tab_general = "Общий", tab_loot = "Добыча и система", tab_party = "Группа",
	survivor = "Чат: SurvivorUI показывает свою панель чата, остаюсь в режиме Рядом. Выключите панель в SurvivorUI и снова выберите Вместо.",
	o_chat = "Чат", o_mode = "Режим", o_mode_hint = "Рядом рисует свой чат справа от игрового, Вместо переодевает игровой чат.",
	o_look = "Вид", o_width = "Ширина, px", o_height = "Высота, px", o_text = "Размер текста", o_bg = "Фон",
	o_stamp = "Время у строк", o_lock = "Без уголка размера",
	o_tabs = "Вкладки", o_combat = "Вкладка Combat Log", o_loot = "Вкладка Добыча и система", o_party = "Вкладка Группа",
	o_dedupe = "Не дублировать в Общем", o_yells = "Прятать крики боссов", o_banners = "Прятать баннеры забега",
	o_fade = "Затухание", o_fade_on = "Затухание по таймеру", o_fade_after = "Затухать через, с", o_wheel = "Строк на щелчок",
	o_page_tabs = "Чат: вкладки",
	tip_grip = "Размер чата",
}

STR.enUS = {
	label = "Chat", piece = "Chat", tab_general = "General", tab_loot = "Loot and system", tab_party = "Party",
	survivor = "Chat: SurvivorUI shows its own chat panel, staying in Side by side mode. Turn its panel off and pick Replace again.",
	o_chat = "Chat", o_mode = "Mode", o_mode_hint = "Side by side draws its own chat to the right of the game one, Replace restyles the game chat.",
	o_look = "Look", o_width = "Width, px", o_height = "Height, px", o_text = "Text size", o_bg = "Background",
	o_stamp = "Timestamps", o_lock = "No size grip",
	o_tabs = "Tabs", o_combat = "Combat Log tab", o_loot = "Loot and system tab", o_party = "Party tab",
	o_dedupe = "Do not repeat in General", o_yells = "Hide boss yells", o_banners = "Hide run banners",
	o_fade = "Fade", o_fade_on = "Fade by timer", o_fade_after = "Fade after, s", o_wheel = "Lines per wheel step",
	o_page_tabs = "Chat: tabs",
	tip_grip = "Size the chat",
}

function Str.Lang()
	local code = H.Locale and H.Locale.code
	if code == "ruRU" then
		return "ruRU"
	end
	return "enUS"
end

function Str.Get(key)
	local t = STR[Str.Lang()]
	local v = t and t[key]
	if v == nil then
		v = STR.enUS[key]
	end
	if v == nil then
		return key
	end
	return v
end
