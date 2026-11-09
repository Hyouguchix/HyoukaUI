-- HyoukaUI: Modules\Meter\Strings.lua, строки счетчика урона на русском и английском.
-- MU.S(key) -> строка языка интерфейса (H.Locale.code), нет в языке - английская, нет и в ней - сам ключ.
-- MU.Sf(key, a, b, c) -> string.format над строкой. Простые дефисы, прямые кавычки, без буквы "е с двумя точками".

local H = HyoukaUI
local MU = H.MeterUI

local EN = {
	page_damage = "Damage", page_dps = "Damage per second", page_healing = "Healing", page_party = "Party",
	page_boss = "Boss", page_last30 = "Last 30 s", page_auto = "Auto (party or boss)", page_off = "Hidden",
	boss_active = "Boss (fight)",
	m_breakdown = "Breakdown by ability", m_collapse = "Collapse", m_expand = "Expand",
	reset = "Reset", reset_glyph = "R", reset_tip = "Reset this column", menu_tip = "Choose the page",
	reset_limit = "Reset is not available: too many checkpoints", reset_unsupported = "Reset is not supported by this game version",
	reset_none = "Reset is not available now",
	others = "Others", proc = "(proc)",
	empty_damage = "No damage yet", empty_healing = "No healing yet", empty_party = "No party damage yet",
	empty_boss = "No boss damage yet", no_party = "Not in a party", no_boss = "No boss fight yet", no_data = "No data yet",
	loading = "Loading...",
	c_rank = "Rank", c_cd = "Cooldown", c_ready = "Ready in", c_buff = "Buff lasts", c_buff_for = "Buff active",
	c_damage = "Damage done", c_healing = "Healing done", c_share = "Share", c_rate = "Per second", c_proc = "Proc",
	c_crits = "Critical strikes", c_count = "Count", c_best = "Biggest", c_avg = "Average", c_min = "Smallest", c_last = "Last",
	c_hits = "Normal hits", c_top = "Top spell", c_spells = "Damage by spell", c_jewelry = "Jewelry", c_talents = "Talents",
	c_points = "points", c_none = "none", c_you = "You",
	bd_title = "%s: damage by ability", bd_total = "Total", bd_footer = "Jewelry: %s", bd_close = "Close", bd_empty = "No damage yet",
	bd_hero = "Hero", bd_col_dps = "per sec", bd_col_amount = "damage", bd_col_pct = "%",
	sec = "s", per_sec = "/s", t_avg = "Per second (average)", t_now = "Now (5 s)", t_total = "Total",
	o_slot1 = "Left column", o_slot2 = "Right column, top", o_slot3 = "Right column, bottom", o_right = "Number on the right",
	o_right_dps = "Per second", o_right_total = "Total", o_right_full = "Total (per second, share)",
	o_fold = "Fold small lines into Others", o_fold_off = "Off", o_pets = "Pets as separate lines",
	o_always = "Show outside a run", o_crits = "Crits and hits in the card", o_reset_all = "Reset all columns",
	o_open = "Open the breakdown of your hero", o_hint = "Click the header for the page menu, right-click it for your own breakdown. Click a party row to see that hero's damage by ability.",
	o_cols = "Columns", o_view = "Look", o_actions = "Actions",
	sui_meter_visible = "SurvivorUI meter is visible: staying in Side by side mode. Turn it off (/sui meter) and pick Replace again.",
}

local RU = {
	page_damage = "Урон", page_dps = "Урон в секунду", page_healing = "Лечение", page_party = "Группа",
	page_boss = "Босс", page_last30 = "Последние 30 с", page_auto = "Авто (группа или босс)", page_off = "Скрыть",
	boss_active = "Босс (бой)",
	m_breakdown = "Разбивка по способностям", m_collapse = "Свернуть", m_expand = "Развернуть",
	reset = "Сброс", reset_glyph = "С", reset_tip = "Сбросить эту колонку", menu_tip = "Выбрать страницу",
	reset_limit = "Сброс недоступен: слишком много чекпойнтов", reset_unsupported = "Сброс не поддерживается этой версией игры",
	reset_none = "Сейчас сброс недоступен",
	others = "Прочее", proc = "(proc)",
	empty_damage = "Урона пока нет", empty_healing = "Лечения пока нет", empty_party = "Урона группы пока нет",
	empty_boss = "Урона по боссу пока нет", no_party = "Вы не в группе", no_boss = "Боя с боссом еще не было", no_data = "Данных пока нет",
	loading = "Загрузка...",
	c_rank = "Ранг", c_cd = "Перезарядка", c_ready = "Готово через", c_buff = "Бафф длится", c_buff_for = "Бафф активен",
	c_damage = "Нанесено урона", c_healing = "Нанесено лечения", c_share = "Доля", c_rate = "В секунду", c_proc = "Прок",
	c_crits = "Критические удары", c_count = "Количество", c_best = "Наибольший", c_avg = "Средний", c_min = "Наименьший", c_last = "Последний",
	c_hits = "Обычные удары", c_top = "Лучшая способность", c_spells = "Урон по способностям", c_jewelry = "Бижутерия", c_talents = "Таланты",
	c_points = "очков", c_none = "нет", c_you = "Вы",
	bd_title = "%s: урон по способностям", bd_total = "Всего", bd_footer = "Бижутерия: %s", bd_close = "Закрыть", bd_empty = "Урона пока нет",
	bd_hero = "Герой", bd_col_dps = "в сек", bd_col_amount = "урон", bd_col_pct = "%",
	sec = "с", per_sec = "/с", t_avg = "В секунду (в среднем)", t_now = "Сейчас (5 с)", t_total = "Всего",
	o_slot1 = "Левая колонка", o_slot2 = "Правая колонка, верх", o_slot3 = "Правая колонка, низ", o_right = "Число справа",
	o_right_dps = "В секунду", o_right_total = "Сумма", o_right_full = "Сумма (в секунду, доля)",
	o_fold = "Мелкие строки в Прочее", o_fold_off = "Выкл", o_pets = "Питомцы отдельными строками",
	o_always = "Показывать вне забега", o_crits = "Криты и удары в карточке", o_reset_all = "Сбросить все колонки",
	o_open = "Разбивка вашего героя", o_hint = "Клик по шапке открывает меню страниц, правый клик по шапке показывает разбивку вашего героя. Клик по строке героя на странице Группа показывает его урон по способностям.",
	o_cols = "Колонки", o_view = "Вид", o_actions = "Действия",
	sui_meter_visible = "счетчик SurvivorUI виден: остаюсь в режиме Рядом. Выключите его (/sui meter) и выберите Вместо снова.",
}

function MU.S(key)
	local code = H.Locale and H.Locale.code
	if code == "ruRU" then
		return RU[key] or EN[key] or key
	end
	return EN[key] or key
end

function MU.Sf(key, a, b, c)
	return string.format(MU.S(key), a, b, c)
end

-- Тесты: обе таблицы должны иметь одни и те же ключи.
function MU.StringTables()
	return EN, RU
end
