-- HyoukaUI: Modules\Plates\PlatesOptions, страницы настроек неймплейтов: режим и показ по видам, вид и поведение, размеры.
--
-- Три страницы (окно настроек не прокручивается, строк на странице не больше 17):
--   plates       режим модуля, предупреждение о SurvivorPlates, какие виды показывать
--   plates_look  имена, доля, метки, дебаффы цели, затемнение остальных, сквозные клики, раскладка, клавиши V
--   plates_size  вид из списка и его ширина, высота, размеры имени, доли и метки; общий масштаб
-- Размеры в ретейл-пикселях (физический пиксель при 1440p). Настройки пишутся в раздел модуля plates, модуль слушает
-- SETTING и перерисовывает плашки сам.

local H = HyoukaUI
local Pl = H.Plates
local O = H.Options

local M = Pl.M

-- Английские строки (русские - запасной текст в вызовах Pl.T, Pl.T лежит в Plates.lua).
Pl.STR.enUS = {
	mod_plates = "Nameplates",
	plates_kind_normal = "Normal enemies", plates_kind_elite = "Elites", plates_kind_guardian = "Lair guardians",
	plates_kind_boss = "Bosses", plates_kind_final = "Final boss", plates_kind_party = "Party allies",
	plates_kind_pet = "Pets and summons", plates_kind_totem = "Totems",
	page_plates = "Nameplates", page_plates_look = "Plates: look", page_plates_size = "Plates: sizes",
	pl_foreign_print = "nameplates stayed in Side by side mode: SurvivorPlates is loaded. Disable it in the addon list and reload.",
	pl_mode = "Mode", pl_mode_hint = "Side by side draws only the kind markers; Replace swaps the stock plates for its own.",
	pl_title = "Nameplates",
	pl_foreign = "SurvivorPlates is loaded: it paints the same plates. Replace works as Side by side while it is on.",
	pl_show = "Show plates", pl_boss_final = "Bosses and final boss", pl_target_always = "Always show target plate",
	pl_target_always_hint = "Show the target even if its kind is turned off.",
	pl_look = "Look", pl_names = "Names", pl_names_all = "On all", pl_names_special = "Except normal", pl_names_none = "None",
	pl_share = "Health share in the bar", pl_marks = "Kind marker (skull)", pl_target_debuffs = "Debuffs on the target plate",
	pl_dim = "Dim others when targeting", pl_dim_pct = "Their brightness, %", pl_normal_pct = "Normal enemies brightness, %",
	pl_behavior = "Behavior", pl_click = "Click through plates",
	pl_click_hint = "A click targets whatever is under it; only the plate under the cursor is caught.",
	pl_overlap = "Plates over enemies", pl_overlap_hint = "Do not spread plates in a crowd (CVar nameplateLayout).",
	pl_lock = "Keep plates on", pl_lock_hint = "The V and Shift+V keys do not turn plates off.",
	pl_sizes = "Plate sizes, retail pixels", pl_kind = "Kind", pl_w = "Bar width", pl_h = "Bar height",
	pl_name_size = "Name size", pl_share_size = "Share size", pl_mark_size = "Mark size", pl_reset_kind = "Reset this kind",
	pl_general = "General", pl_scale = "Scale of all plates",
	pl_sizes_note = "Elites, guardians and bosses have a marker. Sizes apply immediately.",
}

-- Подпись модуля следует за языком.
M.label = Pl.T("mod_plates", "Неймплейты")
H.On("LOCALE", "plates_label", function()
	M.label = Pl.T("mod_plates", "Неймплейты")
end)

-- Страницы строятся один раз: смена языка делает их устаревшими и они пересобираются при открытии.
local builtCode = {}

local function LocaleStale(key)
	return builtCode[key] ~= (H.Locale and H.Locale.code)
end

local function Mark(key, build)
	return function(page, f)
		builtCode[key] = H.Locale and H.Locale.code
		build(page, f)
	end
end

local LABELS = {
	normal = "Обычные враги", elite = "Элиты", guardian = "Стражи логов", boss = "Боссы", final = "Финальный босс",
	party = "Союзники из группы", pet = "Питомцы и призванные", totem = "Тотемы",
}

local function Label(kind)
	return Pl.T("plates_kind_"..kind, LABELS[kind])
end

local function ModeOptions()
	local out = {}
	for i = 1, table.getn(H.MODES) do
		table.insert(out, { value = H.MODES[i], label = Pl.T("mode_"..H.MODES[i], H.MODE_LABELS[H.MODES[i]]) })
	end
	return out
end

local function ModeRow(f)
	f:Segment({ label = Pl.T("pl_mode", "Режим"), options = ModeOptions(), bw = 50,
		hint = Pl.T("pl_mode_hint", "Рядом рисует только метки вида; Вместо заменяет стоковые плашки своими."),
		get = function()
			return H.GetMode("plates")
		end,
		set = function(v)
			H.SetMode("plates", v)
		end })
end

local builtForeign = false

local function BuildMain(page, f)
	local PD = H.PlatesData
	builtForeign = PD.Foreign()
	f:Header(Pl.T("pl_title", "Неймплейты"))
	ModeRow(f)
	if builtForeign then
		f:Note(Pl.T("pl_foreign", "Загружен SurvivorPlates: он красит те же плашки. Вместо работает как Рядом, пока он включен."), "warn")
	end
	f:Gap(4)
	f:Header(Pl.T("pl_show", "Показывать плашки"))
	f:Toggle({ label = Label("normal"), mod = "plates", key = "show_normal" })
	f:Toggle({ label = Label("elite"), mod = "plates", key = "show_elite" })
	f:Toggle({ label = Label("guardian"), mod = "plates", key = "show_guardian" })
	f:Toggle({ label = Pl.T("pl_boss_final", "Боссы и финальный"), mod = "plates", key = "show_boss" })
	f:Toggle({ label = Label("party"), mod = "plates", key = "show_party" })
	f:Toggle({ label = Label("pet"), mod = "plates", key = "show_pet" })
	f:Toggle({ label = Label("totem"), mod = "plates", key = "show_totem" })
	f:Toggle({ label = Pl.T("pl_target_always", "Плашка цели всегда"), hint = Pl.T("pl_target_always_hint", "Показывать цель, даже если ее вид выключен."),
		mod = "plates", key = "targetAlways" })
	f:Refresh()
end

local function BuildLook(page, f)
	f:Header(Pl.T("pl_look", "Вид"))
	f:Dropdown({ label = Pl.T("pl_names", "Имена"), mod = "plates", key = "names", options = {
		{ value = "all", label = Pl.T("pl_names_all", "На всех") }, { value = "special", label = Pl.T("pl_names_special", "Кроме обычных") },
		{ value = "none", label = Pl.T("pl_names_none", "Нет") } } })
	f:Toggle({ label = Pl.T("pl_share", "Доля здоровья в полосе"), mod = "plates", key = "shareText" })
	f:Toggle({ label = Pl.T("pl_marks", "Метка вида (череп)"), mod = "plates", key = "marks" })
	f:Toggle({ label = Pl.T("pl_target_debuffs", "Дебаффы на плашке цели"), mod = "plates", key = "targetDebuffs" })
	f:Toggle({ label = Pl.T("pl_dim", "Затемнять остальные при цели"), mod = "plates", key = "dimOthers" })
	f:Slider({ label = Pl.T("pl_dim_pct", "Их яркость, %"), mod = "plates", key = "dimPct", min = 20, max = 100, step = 5,
		fmt = function(v)
			return tostring(v)
		end })
	f:Slider({ label = Pl.T("pl_normal_pct", "Яркость обычных, %"), mod = "plates", key = "normalPct", min = 20, max = 100, step = 5,
		fmt = function(v)
			return tostring(v)
		end })
	f:Gap(4)
	f:Header(Pl.T("pl_behavior", "Поведение"))
	f:Toggle({ label = Pl.T("pl_click", "Клики сквозь плашки"), hint = Pl.T("pl_click_hint", "Клик берет в цель то, на что попал; ловит только плашка под курсором."),
		mod = "plates", key = "clickThrough" })
	f:Toggle({ label = Pl.T("pl_overlap", "Плашки над врагами"), hint = Pl.T("pl_overlap_hint", "Не раздвигать плашки в толпе (CVar nameplateLayout)."),
		mod = "plates", key = "overlap" })
	f:Toggle({ label = Pl.T("pl_lock", "Держать плашки включенными"), hint = Pl.T("pl_lock_hint", "Клавиши V и Shift+V не выключают плашки."),
		mod = "plates", key = "lockKeys" })
	f:Refresh()
end

local function Current()
	return M.db.editKind
end

local function KeyOf(field)
	local k = Pl.KINDS[Current()]
	return k and k[field]
end

local function SizeSlider(f, label, field, min, max, step)
	f:Slider({ label = label, min = min, max = max, step = step,
		fmt = function(v)
			return tostring(v)
		end,
		get = function()
			local key = KeyOf(field)
			return key and M.db[key] or min
		end,
		set = function(v)
			local key = KeyOf(field)
			if key then
				H.DB.Set("plates", key, v)
			end
		end })
end

local function KindOptions()
	local out = {}
	for i = 1, table.getn(Pl.ORDER) do
		table.insert(out, { value = Pl.ORDER[i], label = Label(Pl.ORDER[i]) })
	end
	return out
end

local function BuildSize(page, f)
	f:Header(Pl.T("pl_sizes", "Размеры плашки, ретейл-пиксели"))
	f:Dropdown({ label = Pl.T("pl_kind", "Вид"), mod = "plates", key = "editKind", options = KindOptions() })
	SizeSlider(f, Pl.T("pl_w", "Ширина полосы"), "kw", 40, 400, 2)
	SizeSlider(f, Pl.T("pl_h", "Высота полосы"), "kh", 4, 60, 1)
	SizeSlider(f, Pl.T("pl_name_size", "Размер имени"), "kn", 6, 30, 1)
	SizeSlider(f, Pl.T("pl_share_size", "Размер доли"), "ks", 6, 30, 1)
	SizeSlider(f, Pl.T("pl_mark_size", "Размер метки"), "km", 8, 48, 1)
	f:Button({ label = Pl.T("pl_reset_kind", "Сбросить этот вид"), onClick = function()
		local k = Pl.KINDS[Current()]
		if k then
			H.DB.Set("plates", k.kw, k.w)
			H.DB.Set("plates", k.kh, k.h)
			H.DB.Set("plates", k.kn, k.name)
			H.DB.Set("plates", k.ks, k.share)
			if k.skull then
				H.DB.Set("plates", k.km, k.mark)
			end
		end
		f:Refresh()
	end })
	f:Gap(4)
	f:Header(Pl.T("pl_general", "Общее"))
	f:Slider({ label = Pl.T("pl_scale", "Масштаб всех плашек"), mod = "plates", key = "scale", min = 0.5, max = 2, step = 0.05,
		fmt = function(v)
			return string.format("%.2f", v)
		end })
	f:Note(Pl.T("pl_sizes_note", "Метка есть у элит, стражей и боссов. Размеры применяются сразу."))
	f:Refresh()
end

if O and O.AddPage then
	O.AddPage("plates", function()
		return Pl.T("page_plates", "Неймплейты")
	end, Mark("plates", BuildMain), 41, function()
		return builtForeign ~= H.PlatesData.Foreign() or LocaleStale("plates")
	end)
	O.AddPage("plates_look", function()
		return Pl.T("page_plates_look", "Плашки: вид")
	end, Mark("plates_look", BuildLook), 42, function()
		return LocaleStale("plates_look")
	end)
	O.AddPage("plates_size", function()
		return Pl.T("page_plates_size", "Плашки: размеры")
	end, Mark("plates_size", BuildSize), 43, function()
		return LocaleStale("plates_size")
	end)
end
