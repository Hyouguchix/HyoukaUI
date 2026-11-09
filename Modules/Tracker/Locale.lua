-- HyoukaUI: Modules\Tracker\Locale, строки модуля Трекер (русский и английский).
-- Ядро Locale не правится: у модуля свои таблицы. Tr.T(key) берет язык из H.Locale.code, нет строки - английская,
-- нет и ее - сам ключ. Только простые дефисы и прямые кавычки.

local H = HyoukaUI

local Tr = H.Tr or {}
H.Tr = Tr

local STR = {}
Tr.STR = STR

STR.ruRU = {
	label = "Трекер", this_run = "Этот забег", survived = "Выжил", level = "Уровень", kills = "Убийства",
	kpm = "Убийств/мин", elites = "Элиты", guardians = "Стражи", bosses = "Боссы", dmg_done = "Урон нанесен",
	dmg_ps = "Урон/сек", dmg_taken = "Урон получен", gold = "Золото", gold_earned = "Золото за забег", chests = "Сундуки",
	rerolls = "Перебросы", lives = "Жизни", crits = "Лучшие криты", no_crits = "Критов пока нет",
	victory = "Победа", fallen = "Пал", down = "Лежит", paused = "Пауза", choosing = "Выбор",
	boss_in = "через", next_boss_in = "Следующий босс через", endless_bosses = "Боссов в бесконечном",
	boss_arrived = "Пришел босс", boss_generic = "Босс", goal = "к 8:00", goal_done = "готово", rage = "ЯРОСТЬ",
	tag_heroic = "Г", tag_normal = "Н", tag_endless = "inf", fps = "кадр/с", tip_final = "До финального босса",
	tip_endless = "Бесконечный режим: боссы возвращаются по таймеру.", tip_bosses = "Боссы", tip_lairs = "Логова",
	tip_diff = "Сложность зоны", tip_hide = "Скрыть: /hui module tracker off",
	lair_empty = "пусто", lair_awake = "бой",
	msg_part_off = "трекер: часть %s выключена из-за ошибок, /hui errors",
	msg_stay_side = "трекер остается в режиме Рядом: трекер SurvivorUI активен, выключите его командой /sui tracker",
	o_title = "Трекер", o_mode_hint = "Рядом рисует трекер поверх игрового для сравнения, Вместо прячет части игры.",
	o_panel = "Панель забега", o_bg = "Фон панели", o_timeline = "Полоса времени с засечками", o_schedule = "Расписание боссов",
	o_guardians = "Полоса стражей", o_tally = "Панель итогов (убийства, золото, сундуки)", o_goal = "Цель четырех стражей к 8:00",
	o_bars = "Полосы боссов", o_horizon = "Горизонт полос, с", o_relocate = "Переезд в выделенные, с",
	o_messages = "Сообщения", o_countdown = "Отсчет 5..1", o_hide_banners = "Прятать баннеры игры",
	o_boss_frames = "Рамки боссов", o_this_run = "Панель Этот забег", o_crits = "Лучшие криты",
	o_skin = "Плоская миникарта", o_clock = "Часы и FPS на миникарте", o_pins = "Пины сундуков и логов",
	o_pin_range = "Радиус пинов, ярды", o_pin_bosses = "Пины боссов", o_flag = "Прятать флажок игры",
	h_panel = "Панель", h_bars = "Полосы и сообщения", h_frames = "Рамки и панели", h_map = "Миникарта",
	n_pin_range = "Масштаб миникарты в ярдах не отдается игрой: радиус задается вручную, направление и расстояние точные.",
}

STR.enUS = {
	label = "Tracker", this_run = "This run", survived = "Survived", level = "Level", kills = "Kills",
	kpm = "Kills/min", elites = "Elites", guardians = "Guardians", bosses = "Bosses", dmg_done = "Damage dealt",
	dmg_ps = "Damage/sec", dmg_taken = "Damage taken", gold = "Gold", gold_earned = "Gold earned", chests = "Chests",
	rerolls = "Rerolls", lives = "Lives", crits = "Biggest crits", no_crits = "No crits yet",
	victory = "Victory", fallen = "Fallen", down = "Down", paused = "Paused", choosing = "Choosing",
	boss_in = "in", next_boss_in = "Next boss in", endless_bosses = "Endless bosses slain",
	boss_arrived = "Boss arrived", boss_generic = "Boss", goal = "by 8:00", goal_done = "done", rage = "ENRAGED",
	tag_heroic = "H", tag_normal = "N", tag_endless = "inf", fps = "fps", tip_final = "Final boss in",
	tip_endless = "Endless mode: bosses return on a timer.", tip_bosses = "Bosses", tip_lairs = "Lairs",
	tip_diff = "Zone difficulty", tip_hide = "Hide: /hui module tracker off",
	lair_empty = "empty", lair_awake = "fight",
	msg_part_off = "tracker: part %s was turned off after errors, /hui errors",
	msg_stay_side = "tracker stays in Side by side mode: the SurvivorUI tracker is active, turn it off with /sui tracker",
	o_title = "Tracker", o_mode_hint = "Side by side draws the tracker over the game one for comparison, Replace hides game parts.",
	o_panel = "Run panel", o_bg = "Panel background", o_timeline = "Time bar with boss ticks", o_schedule = "Boss schedule",
	o_guardians = "Guardians bar", o_tally = "Run totals panel (kills, gold, chests)", o_goal = "Four guardians by 8:00 goal",
	o_bars = "Boss bars", o_horizon = "Bar horizon, s", o_relocate = "Move to emphasized, s",
	o_messages = "Messages", o_countdown = "Countdown 5..1", o_hide_banners = "Hide game banners",
	o_boss_frames = "Boss frames", o_this_run = "This run panel", o_crits = "Biggest crits",
	o_skin = "Flat minimap", o_clock = "Clock and FPS on the minimap", o_pins = "Chest and lair pins",
	o_pin_range = "Pin radius, yards", o_pin_bosses = "Boss pins", o_flag = "Hide the game flag",
	h_panel = "Panel", h_bars = "Bars and messages", h_frames = "Frames and panels", h_map = "Minimap",
	n_pin_range = "The game does not give the minimap scale in yards: the radius is set by hand, direction and distance are exact.",
}

function Tr.T(key)
	local code = H.Locale and H.Locale.code or "enUS"
	local t = STR[code]
	local v = t and t[key]
	if v == nil then
		v = STR.enUS[key]
	end
	return v or key
end
