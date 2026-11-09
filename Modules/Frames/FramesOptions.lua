-- HyoukaUI: Frames\FramesOptions, страницы настроек модуля Рамки (plan 5, страница 3).
--
-- Три страницы (в окне 400x300 нет прокрутки, строка 16 AS): "Рамки" (режим, вид рамок игрока и цели, ауры),
-- "Колонка" (способности, XP, класс-ресурс), "Показ" (какие куски видны). Значения пишутся в H.DB (модуль
-- "frames"), части сами слушают SETTING. Положение и масштаб кусков - в режиме перемещения (/hui move).
-- Режим модуля Выкл / Рядом / Вместо: тот же переключатель, что на странице Модули. Если запрошено Вместо, но
-- на экране рамки SurvivorUI, действует Рядом (строка под переключателем).

local H = HyoukaUI
local F = H.Frames
local O = H.Options

local getn = table.getn

local function Opts(list)
	local out = {}
	for i = 1, getn(list) do
		table.insert(out, { value = list[i][1], label = F.T(list[i][2], list[i][3]) })
	end
	return out
end

local function T(key, ru)
	return F.T(key, ru)
end

-- Страницы строятся один раз: смена языка делает их устаревшими, и они пересобираются при открытии.
local builtCode = {}

local function Stale(key)
	return function()
		return builtCode[key] ~= (H.Locale and H.Locale.code)
	end
end

local function Mark(key, build)
	return function(page, f)
		builtCode[key] = H.Locale and H.Locale.code
		build(page, f)
	end
end

local function Toggle(f, key, label, hint)
	f:Toggle({ label = label, hint = hint, mod = "frames", key = key })
end

local function BuildUnits(page, f)
	f:Header(T("opt_frames_mode", "Режим"))
	local names = {}
	for i = 1, getn(H.MODES) do
		table.insert(names, { H.MODES[i], "mode_"..H.MODES[i], H.MODE_LABELS[H.MODES[i]] })
	end
	f:Segment({ label = T("mod_frames", "Рамки"), options = Opts(names), bw = 50,
		get = function()
			return H.GetMode("frames")
		end,
		set = function(v)
			H.SetMode("frames", v)
			f:Refresh()
		end })
	local note = f:Note("")
	table.insert(f.items, function()
		local want, now = H.GetMode("frames"), F.mode
		if want == "replace" and now == "side" then
			note:SetText(T("opt_frames_survivor", "Вместо не включено: на экране рамки SurvivorUI. Выключите их в SurvivorUI."))
		else
			note:SetText("")
		end
	end)
	f:Gap(2)
	f:Header(T("opt_frames_look", "Рамки игрока и цели"))
	f:Dropdown({ label = T("opt_bar_style", "Полоса"), mod = "frames", key = "barStyle",
		options = Opts({ { "dark", "opt_bar_dark", "Темная (ретейл)" }, { "class", "opt_bar_class", "Цвет класса" } }) })
	Toggle(f, "playerName", T("opt_player_name", "Имя героя"))
	Toggle(f, "targetName", T("opt_target_name", "Имя цели"))
	Toggle(f, "targetOfTarget", T("opt_tot", "Цель цели"))
	Toggle(f, "shield", T("opt_shield", "Щит"))
	Toggle(f, "power", T("opt_power", "Полоска ресурса"))
	Toggle(f, "portrait", T("opt_portrait", "Портрет"))
	f:Slider({ label = T("opt_aura_rows", "Рядов аур цели"), mod = "frames", key = "auraRows", min = 1, max = 3, step = 1,
		fmt = function(v)
			return string.format("%d", v)
		end })
	f:Refresh()
end

local function BuildColumn(page, f)
	f:Header(T("opt_frames_abilities", "Способности"))
	Toggle(f, "rank", T("opt_rank", "Ранг на иконках"))
	Toggle(f, "binds", T("opt_binds", "Клавиши на иконках"))
	Toggle(f, "greyCd", T("opt_grey_cd", "Серые иконки на откате"),
		T("opt_grey_cd_hint", "Как в ретейле. Шторка и цифры остаются в любом случае."))
	f:Slider({ label = T("opt_cd_min", "Откат от, с"), mod = "frames", key = "cdMin", min = 0.5, max = 3, step = 0.5,
		hint = T("opt_cd_min_hint", "Шторка и цифры только для отката не короче."),
		fmt = function(v)
			return string.format("%.1f", v)
		end })
	Toggle(f, "permanentPets", T("opt_pets", "Постоянные питомцы"))
	f:Gap(2)
	f:Header(T("opt_frames_xp", "Опыт забега"))
	f:Dropdown({ label = T("opt_xp_place", "Место"), mod = "frames", key = "xpPlace",
		options = Opts({ { "top", "opt_xp_top", "Сверху по центру" }, { "column", "opt_xp_column", "Над колонкой" } }) })
	f:Refresh()
end

local function BuildShow(page, f)
	f:Header(T("opt_frames_show", "Показывать"))
	Toggle(f, "showMain", T("piece_main", "Ряд способностей"))
	Toggle(f, "showClass", T("piece_class", "Класс-ресурс"))
	Toggle(f, "showBuffs", T("piece_buffs", "Баффы забега"))
	Toggle(f, "showStatics", T("piece_statics", "Жизни и перебросы"))
	Toggle(f, "showUtility", T("piece_utility", "Таймеры и призывы"))
	Toggle(f, "showXp", T("piece_xp", "Полоса опыта"))
	Toggle(f, "showPlayer", T("piece_player", "Рамка героя"))
	Toggle(f, "showTarget", T("piece_target", "Рамка цели"))
	Toggle(f, "showTargetAuras", T("piece_target_auras", "Дебафы цели"))
	Toggle(f, "showPlayerAuras", T("piece_player_auras", "Ауры героя"))
	Toggle(f, "showLevelUp", T("piece_levelup", "Новый уровень"))
	Toggle(f, "showMicro", T("piece_micro", "Кнопки сбоку"))
	Toggle(f, "showParty", T("piece_party", "Рамки группы и подъем"))
	Toggle(f, "parkStock", T("opt_park_stock", "Прятать стоковые рамки"),
		T("opt_park_stock_hint", "Только в режиме Вместо."))
	f:Refresh()
end

local function Label(key, ru)
	return function()
		return F.T(key, ru)
	end
end

O.AddPage("frames", Label("page_frames", "Рамки"), Mark("frames", BuildUnits), 30, Stale("frames"))
O.AddPage("frames_column", Label("page_frames_column", "Колонка"), Mark("frames_column", BuildColumn), 31, Stale("frames_column"))
O.AddPage("frames_show", Label("page_frames_show", "Показ"), Mark("frames_show", BuildShow), 32, Stale("frames_show"))
