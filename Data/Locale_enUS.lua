-- HyoukaUI: строки интерфейса, английский (запасной язык) и подбор языка.
--
-- H.L.<ключ>          строка на текущем языке; нет в нем - английская; нет и в ней - сам ключ
-- H.Lf(ключ, a, b, c, d)   string.format над строкой (до 4 аргументов, без ...)
-- H.Locale.code       "enUS" или "ruRU"; H.Locale.Set(code), H.Locale.Detect()
-- Язык: настройка general.language ("enUS" / "ruRU"), иначе CVar azsLanguage ("ru" - русский).
-- Событие LOCALE (code) при смене языка.
--
-- Теги бижутерии (plan 3.3): tags - короткие надписи, tagFind - подстроки для поиска в тексте подсказки
-- (ТОЛЬКО string.find с plain = true: шаблоны с не-ASCII вешают движок, audit build-21), tagFmt - вид числовых тегов.
-- [НЕ ПРОВЕРЕНО] реальные формулировки бонусов бижутерии в игре: подстроки подобраны по смыслу.

local H = HyoukaUI

H.Locales = H.Locales or {}

H.Locales.enUS = {
	-- страницы настроек
	page_general = "General", page_modules = "Modules", page_frames = "Frames", page_tracker = "Tracker",
	page_build = "Build", page_meter = "Damage", page_layout = "Layout", page_hud = "Game HUD", page_debug = "Debug",
	-- модули и режимы
	mod_frames = "Frames", mod_tracker = "Tracker", mod_build = "Build", mod_meter = "Damage meter",
	mode_off = "Off", mode_side = "Side by side", mode_replace = "Replace",
	mode_hint = "Side by side shows both for comparison; Replace takes over the game part.",
	-- кнопки
	btn_close = "Close", btn_reset = "Reset", btn_apply = "Apply", btn_cancel = "Cancel", btn_yes = "Yes", btn_no = "No",
	btn_move = "Move", btn_demo = "Preview", btn_reset_all = "Reset all", btn_restore = "Restore all",
	-- общие настройки
	opt_accent = "Accent color", opt_font = "Font", opt_game_font = "Font in the whole game", opt_border = "Border",
	opt_border_1 = "1 pixel", opt_border_2 = "2 pixels", opt_scale = "Scale", opt_language = "Language",
	opt_tooltip = "Flat tooltips", opt_font_expressway = "Expressway", opt_font_game = "Game font",
	opt_language_auto = "Auto",
	acc_default = "Default blue", acc_teal = "Teal", acc_blue = "Blue", acc_violet = "Violet", acc_red = "Red",
	acc_orange = "Orange", acc_gold = "Gold", acc_green = "Green", acc_white = "White", acc_class = "Hero class",
	-- раскладка и перемещение
	mv_title = "Move mode", mv_hint = "Drag a piece. Arrows move by 1 pixel, Shift by 10. Esc leaves.",
	mv_reset_confirm = "Put every piece back to its default place?", mv_hidden = "hidden", mv_grid = "Grid",
	-- состояния
	dead = "DEAD", offline = "Offline", down = "DOWN", none = "none", loading = "Loading...", unit_yd = "yd", unit_sec = "s",
	-- счетчик урона
	meter_damage = "Damage", meter_party = "PARTY", meter_healing = "Healing", meter_boss = "Boss", meter_taken = "Taken",
	meter_dps = "DPS", meter_total = "Total", meter_now = "NOW", meter_30s = "30s", meter_reset = "Reset",
	meter_empty = "No data yet", meter_breakdown = "%s: damage by ability",
	-- трекер
	tr_this_run = "This run", tr_kills = "Kills", tr_gold = "Gold", tr_time = "Time", tr_level = "Level",
	tr_boss_next = "Boss in %s", tr_boss_up = "Boss: %s", tr_boss_dead = "%s defeated", tr_go = "GO", tr_wave = "Wave %d",
	-- сборка
	build_title = "Build", build_count = "%d/%d", build_jewelry = "Jewelry", build_racial = "(racial)",
	build_rank = "Rank", build_info = "Info", build_cd = "CD",
	-- окно персонажа
	char_title = "Character", char_empty = "Start a run to see stats", char_attack = "Attack", char_defense = "Defense",
	char_other = "Other",
	-- демо
	demo_solo = "Solo run", demo_coop = "Co-op run", demo_off = "Preview off",
	-- сообщения
	msg_module_off = "module %s is off because of errors, /hui errors",

	-- ядро: окна настроек, перемещение, команды /hui
	hdr_look = "Look",
	hdr_borders = "Borders",
	note_border = "Border thickness is always 1 physical pixel, this is a project decision. The pixel size is recalculated when resolution or scale changes.",
	hint_game_font = "Applies at once; some game windows update after /reload.",
	hdr_layout = "Piece placement",
	hint_move = "Drag with the mouse, arrows move by 1 px, with Shift by 10 px, Ctrl+Z undoes.",
	opt_move_key = "Hold key",
	opt_none = "None",
	btn_undo = "Undo last",
	btn_confirm_again = "Sure? Click again",
	layout_saved = "Saved changes: %s. Pieces without changes stay at their default places.",
	mod_suspended_hint = "Off because of an error: /hui errors",
	mod_none = "No modules yet.",
	mod_note_coexist = "SurvivorUI is loaded. Side by side shows both interfaces for comparison; Replace hides the matching parts of the game and SurvivorUI.",
	mod_note = "Side by side: for comparison, no game parts taken over. Replace: the module hides the stock part and puts its own.",
	dbg_errors = "Errors in log: %s",
	dbg_selftest = "Self-test",
	dbg_error_log = "Error log",
	hdr_preview = "Piece preview",
	dbg_stub_solo = "Stubs: solo",
	dbg_stub_party = "Stubs: party",
	hint_stubs = "Colored rectangles at layout positions.",
	dbg_geometry = "Piece geometry",
	btn_done = "Done",
	btn_show = "Show",
	btn_put_back = "Put back",
	mv_detached = "detached from the chain, screen corner ",
	mv_attached = "attached to ",
	mv_attached_screen = "attached to the screen",
	sl_help_head = "HyoukaUI %s (stage %s), /hui commands:",
	sl_unknown = "unknown command: %s. /hui lists them",
	sl_demo_missing = "demo unavailable: Core/Demo is not loaded",
	sl_demo_off = "demo off",
	sl_demo_on = "demo %s: %s stubs. /hui geometry prints coordinates, /hui move moves them",
	sl_demo_usage = "/hui demo solo | party | off (now: %s)",
	sl_demo_none = "off",
	sl_move_missing = "move mode unavailable: Core/Mover is not loaded",
	sl_move_state = "move mode: %s",
	sl_on = "on",
	sl_off = "off",
	sl_opts_missing = "options window unavailable: Options is not loaded",
	sl_layout_missing = "layout unavailable: Core/Layout is not loaded",
	sl_geo_none = "no registered pieces (/hui demo solo)",
	sl_geo_title = "geometry (AS top-left, then retail px)",
	sl_piece_reset = "piece %s put back in place",
	sl_layout_reset = "whole layout put back in place",
	sl_layout_info = "layout: detached or changed pieces %s. /hui layout reset [id]",
	sh_demo = "demo solo|party|off - stubs of all layout pieces in their places",
	sh_move = "move [on|off] - piece move mode",
	sh_options = "options - options window",
	sh_open = "open - same as options",
	sh_geometry = "geometry - rectangles of all pieces in AS and retail px",
	sh_layout = "layout [reset [id]] - saved piece positions",
	mod_chat = "Chat", mod_plates = "Nameplates",
	-- названия кусков раскладки (режим перемещения, карточка куска)
	["pc.col.main"] = "Abilities",
	["pc.col.class"] = "Class resource",
	["pc.col.buffs"] = "Run buffs",
	["pc.col.statics"] = "Lives and rerolls",
	["pc.col.utility"] = "Timers and summons",
	["pc.col.revive"] = "Revive",
	["pc.col.xp"] = "Run XP",
	["pc.uf.player"] = "Player",
	["pc.uf.jewelry"] = "Jewelry",
	["pc.uf.target"] = "Target",
	["pc.uf.targetAuras"] = "Target auras",
	["pc.uf.party"] = "Party",
	["pc.uf.levelup"] = "Level up",
	["pc.uf.buffs"] = "Player buffs",
	["pc.uf.debuffs"] = "Player debuffs",
	["pc.build.list"] = "Build",
	["pc.tr.minimap"] = "Minimap",
	["pc.tr.bars"] = "Boss bars",
	["pc.tr.tracker"] = "Run timer",
	["pc.tr.tally"] = "Run summary",
	["pc.tr.thisRun"] = "This run",
	["pc.tr.barsEmph"] = "Boss bar",
	["pc.tr.bossFrames"] = "Boss frames",
	["pc.tr.msg"] = "Messages",
	["pc.tr.msgEmph"] = "Important message",
	["pc.tr.count"] = "Countdown",
	["pc.mt.dock"] = "Damage meter",
	["pc.mt.breakdown"] = "Damage breakdown",
	["pc.ui.micro"] = "Side buttons",
	["pc.tr.loot"] = "Loot",
	["pc.ui.chat"] = "Chat spot",
	["pc.ui.tooltip"] = "Tooltip",

	-- теги бижутерии
	tags = {
		crit = "CRIT", area = "AREA", dmg = "DMG", speed = "SPD", life = "HP", cdr = "CDR", proj = "PROJ", armor = "ARM",
	},
	tagFind = {
		crit = { "critical" }, area = { "area", "radius" }, dmg = { "damage" }, speed = { "speed", "haste" },
		life = { "health", "life" }, cdr = { "cooldown" }, proj = { "projectile" }, armor = { "armor" },
	},
	tagFmt = { pct = "+%d%% %s", flat = "+%d %s", plain = "%s" },
	tagMore = "...+",
}

----------------------------------------------------------------------------------------
-- Подбор языка и доступ к строкам
----------------------------------------------------------------------------------------

local Loc = { code = "enUS" }
H.Locale = Loc

local CODES = { enUS = true, ruRU = true }

-- Язык по настройке, затем по CVar azsLanguage. Не меняет текущий, только возвращает.
function Loc.Pick()
	local pref = H.DB and H.DB.Get("general", "language")
	if pref and CODES[pref] then
		return pref
	end
	local ok, v = pcall(GetCVar, "azsLanguage")
	if ok and type(v) == "string" and string.lower(string.sub(v, 1, 2)) == "ru" then
		return "ruRU"
	end
	return "enUS"
end

function Loc.Set(code)
	if not CODES[code] or Loc.code == code then
		return false
	end
	Loc.code = code
	H.Fire("LOCALE", code)
	return true
end

function Loc.Detect()
	return Loc.Set(Loc.Pick())
end

H.L = setmetatable({}, {
	__index = function(t, key)
		local cur = H.Locales[Loc.code]
		local v = cur and cur[key]
		if v == nil then
			v = H.Locales.enUS[key]
		end
		if v == nil then
			return key
		end
		return v
	end,
})

function H.Lf(key, a, b, c, d)
	return string.format(H.L[key], a, b, c, d)
end

H.On("LOADED", "locale", function()
	Loc.Detect()
end)

H.On("SETTING", "locale", function(ev, mod, key)
	if mod == "general" and key == "language" then
		Loc.Detect()
	end
end)
