-- HyoukaUI: раскладка по умолчанию (plan 2.8 с решениями пользователя 9.1). Только данные.
--
-- ФОРМАТ (его читает Core\Layout.lua, подробнее там). ВСЕ ЧИСЛА В РЕТЕЙЛ-ПИКСЕЛЯХ: 1 ретейл-пиксель =
-- 1 физический пиксель. В AS их переводит H.R(px). Проверка: ретейл x 0.5333 = AS при масштабе 1.0.
--   pieces[id] = {
--     label          подпись в режиме перемещения
--     point, rel, relPoint, x, y    якорь куска; rel = "UIParent" или id другого куска; y вверх, как SetPoint
--     w, h           размер; slots + icon + gap дают w = slots x icon + (slots - 1) x gap
--     widthMatch     ширина как у другого куска (колонка под ширину главного ряда)
--     collapse       пустой (скрытый) кусок не занимает места: дети цепляются к его якорю
--     fallback       { point, relPoint, x, y } от UIParent, если куска rel нет (модуль выключен)
--     movable = false, overCards = true     не двигается / виден поверх карточек выбора
--     step, max, dir        для стеков и рядов: шаг между элементами, их число, направление роста
--     rows, rowMax          для рядов иконок: рядов по умолчанию и допустимо
--     src            ссылка на строку spec (retail-ui-spec.md) или план
--     note           отступление от spec или неподтвержденное значение
--   }
--   order = { ... }   родители раньше детей (порядок для Mover и Demo)
--   above[id] = { over, point, relPoint, x, y, minRows }   правило "над другим куском" (считает Layout)
--   variants[id].<имя> = { ... }   альтернативные значения (опции), Layout их не читает
--
-- Решения пользователя (plan 9.1): рамки игрока и цели на ретейл-местах (-385.5 / +385.5 от центра),
-- XP забега сверху по центру, док урона справа с одним столбцом "в секунду", баннеры боссов свои.
-- Ретейл-позиции центральной колонки заданы от CENTER(0,-290) без полупиксельного снапа EllesmereUI.

local H = HyoukaUI

H.LayoutDefaults = {
	version = 1,

	pieces = {
		-- Центральная колонка: ряд способностей и все, что к нему склеено зазором 1 px.
		["col.main"] = {
			label = "Способности", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 0, y = -290,
			slots = 7, icon = 45, gap = 1, h = 45,
			src = "spec 2.3 стр.158 (CDM_cooldowns 45, шаг 1); plan 2.8: 7 слотов вместо 10 дают 321",
		},
		["col.class"] = {
			label = "Класс-ресурс", point = "BOTTOM", rel = "col.main", relPoint = "TOP", x = 0, y = 1,
			widthMatch = "col.main", h = 13, collapse = true,
			src = "spec 2.3 стр.160 (ERB_ClassResource 13); 3.2 unlockWidthMatch",
			note = "plan 2.8: сидит над col.main, потому что полоса XP ушла наверх экрана (решение 5)",
		},
		["col.buffs"] = {
			label = "Баффы забега", point = "BOTTOM", rel = "col.class", relPoint = "TOP", x = 0, y = 1,
			widthMatch = "col.main", h = 34, collapse = true,
			src = "spec 2.3 стр.161 (CDM_buffs 34, шаг 1 над класс-ресурсом после схлопывания)",
		},
		["col.statics"] = {
			label = "Жизни и перебросы", point = "BOTTOM", rel = "col.buffs", relPoint = "TOP", x = 0, y = 1,
			widthMatch = "col.main", h = 37, collapse = true,
			src = "spec 2.3 стр.163 (статичные баффы 37 у краев колонки)",
		},
		["col.utility"] = {
			label = "Таймеры и призывы", point = "TOP", rel = "col.main", relPoint = "BOTTOM", x = 0, y = -1,
			widthMatch = "col.main", h = 37, collapse = true,
			src = "spec 2.3 стр.164 (CDM_utility 37, 1 px под главным рядом)",
		},
		["col.revive"] = {
			label = "Подъем", point = "TOP", rel = "col.utility", relPoint = "BOTTOM", x = 0, y = -1,
			widthMatch = "col.main", h = 22, collapse = true,
			src = "spec 2.3 стр.165 (ERB_CastBar 22: иконка слева + полоса)",
		},
		["col.xp"] = {
			label = "Опыт забега", point = "TOP", rel = "UIParent", relPoint = "TOP", x = 0, y = -1.5,
			w = 400, h = 18, movable = true,
			src = "spec 2.3 стр.182 (полоса опыта 400x18, центр около 10.5 px ниже верха); 5 стр.439",
			note = "решение 5: сверху по центру, не в колонке; вариант в колонке см. variants",
		},

		-- Рамки игрока и цели на ретейл-местах (решение 7).
		["uf.player"] = {
			label = "Игрок", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = -385.5, y = -290,
			w = 272, h = 45,
			src = "spec 2.3 стр.166 (рамка игрока 272x45, центр -385.5,-290)",
		},
		["uf.jewelry"] = {
			label = "Бижутерия", point = "BOTTOMRIGHT", rel = "uf.player", relPoint = "TOPRIGHT", x = 0, y = 1,
			slots = 5, icon = 34, gap = 1, h = 34, overCards = true, dir = "LEFT",
			fallback = { point = "BOTTOMRIGHT", relPoint = "CENTER", x = -249.5, y = -266.5 },   -- правый верх uf.player + 1: -385.5 + 136, -290 + 22.5 + 1
			src = "spec 2.3 стр.168 (защитные кулдауны 34 над рамкой игрока, рост влево); 5 стр.437",
		},
		["uf.target"] = {
			label = "Цель", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 385.5, y = -290,
			w = 272, h = 45,
			src = "spec 2.3 стр.170 (рамка цели 272x45, центр +385.5,-290)",
		},
		["uf.targetAuras"] = {
			label = "Ауры цели", point = "BOTTOMRIGHT", rel = "uf.target", relPoint = "TOPRIGHT", x = 0, y = 1,
			slots = 8, icon = 33, gap = 1, h = 33, rows = 1, rowMax = 3, dir = "LEFT",
			src = "spec 2.3 стр.171 (баффы цели 33, 8 в ряд, до 3 рядов, рост влево и вверх)",
		},
		["uf.party"] = {
			label = "Группа", point = "TOPLEFT", rel = "UIParent", relPoint = "TOPLEFT", x = 512.5, y = -673.5,
			w = 199, h = 175, step = 44, max = 4, dir = "DOWN",
			src = "spec 2.3 стр.176 (группа 199x43, шаг 1, слева 512.5, сверху 673.5; своей рамки нет, до 4)",
		},
		["uf.levelup"] = {
			label = "Новый уровень", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 0, y = -483,
			w = 52, h = 52,
			src = "spec 2.3 стр.181 (кнопка особого действия CENTER(-0.5,-483)); размер 52 как у иконок напоминаний стр.175",
			note = "[НЕ ПРОВЕРЕНО] размер в ретейле не задан",
		},
		["uf.buffs"] = {
			label = "Ауры игрока", point = "TOPRIGHT", rel = "tr.minimap", relPoint = "TOPLEFT", x = -1, y = 0,
			slots = 12, icon = 32, gap = 1, h = 98, rows = 3, rowMax = 3, dir = "LEFT",
			fallback = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -232, y = -1 },   -- там, где стояла бы миникарта: 230 + 1 + 1 слева от края
			src = "spec 2.3 стр.186 (баффы игрока 395x98, иконки 32, 12x3, правый край x 2328)",
		},
		["uf.debuffs"] = {
			label = "Дебаффы игрока", point = "BOTTOMRIGHT", rel = "tr.minimap", relPoint = "BOTTOMLEFT", x = -1, y = 0,
			w = 607, h = 37, dir = "LEFT",
			fallback = { point = "BOTTOMRIGHT", relPoint = "TOPRIGHT", x = -232, y = -231 },   -- низом вровень с картой 230
			src = "spec 2.3 стр.187 (дебаффы 607x37, иконки 37, 16x1, y 194-231)",
		},

		-- Список сборки: геометрия KickTracker AES.
		["build.list"] = {
			label = "Сборка", point = "BOTTOMLEFT", rel = "UIParent", relPoint = "BOTTOMLEFT", x = 513, y = 768,
			w = 225, h = 24, step = 25, dir = "UP", overCards = true,
			src = "spec 2.3 стр.197 (KickTracker 199x24, расширено до 225 под длинные значения отката, шаг 1 вверх, BOTTOMLEFT 513 от левого края, низ y 672 от верха)",
		},

		-- Правая колонка: миникарта, полосы боссов, трекер.
		["tr.minimap"] = {
			label = "Миникарта", point = "TOPRIGHT", rel = "UIParent", relPoint = "TOPRIGHT", x = -1, y = -1,
			w = 230, h = 230,
			src = "spec 2.3 стр.185 (миникарта AES 230x230, TOPRIGHT(-1,-1))",
		},
		["tr.bars"] = {
			label = "Полосы боссов", point = "TOPRIGHT", rel = "tr.minimap", relPoint = "BOTTOMRIGHT", x = 0, y = -2,
			w = 228, h = 112, step = 23, max = 5, dir = "DOWN", reserve = 5,
			src = "spec 2.3 стр.188 (BigWigs 228x20, до 5, шаг 23, первая на 2 px ниже миникарты)",
			note = "h = место под 5 полос: 4 x 23 + 20; не схлопывается, чтобы трекер не прыгал (plan 2.8)",
		},
		["tr.tracker"] = {
			label = "Таймер забега", point = "TOPRIGHT", rel = "tr.bars", relPoint = "BOTTOMRIGHT", x = 0, y = -1,
			w = 230, h = 100,
			src = "spec 2.3 стр.202 (таймер M+ ширина 230); plan 2.8: стек миникарта - полосы - трекер",
			note = "deviation от spec 5 RIGHT(0,+300); [НЕ ПРОВЕРЕНО] высота 100 - заглушка до этапа 4",
		},
		["tr.tally"] = {
			label = "Итоги забега", point = "TOPRIGHT", rel = "tr.tracker", relPoint = "BOTTOMRIGHT", x = 0, y = -1,
			w = 230, h = 34,
			src = "plan 2.8: стек миникарта - полосы - трекер - итоги (нет в ретейле; плоская панель как таймер M+, ширина 230)",
			note = "решение пользователя 2026-11-09: убийства, золото и сундуки вынесены из панели трекера; высота 34: подпись сверху, значение снизу (решение пользователя 2026-11-09) [НЕ ПРОВЕРЕНО в игре]",
		},
		["tr.thisRun"] = {
			label = "Этот забег", point = "TOPLEFT", rel = "UIParent", relPoint = "TOPLEFT", x = 1, y = -1,
			w = 230, h = 100, collapse = true,
			src = "plan 2.8 (нет в ретейле, место рейд-рамок, ширина 230); spec 2.3 стр.177 (рейд, левый верхний угол x 1)",
			note = "[НЕ ПРОВЕРЕНО] высота 100 - заглушка до этапа 4",
		},
		["tr.barsEmph"] = {
			label = "Полосы босса", point = "BOTTOMLEFT", rel = "uf.target", relPoint = "TOPLEFT", x = 1, y = 36,
			w = 269, h = 22, step = 23, max = 3, dir = "UP",
			fallback = { point = "BOTTOMLEFT", relPoint = "CENTER", x = 250.5, y = -231.5 },   -- левый верх uf.target + 1, +36: 249.5 + 1, -290 + 22.5 + 36
			src = "spec 2.3 стр.189 (BigWigs выделенные 269x22, до 3, BOTTOMLEFT = TOPLEFT цели +1,+36)",
		},
		["tr.bossFrames"] = {
			label = "Рамки боссов", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 720, y = -99.5,
			w = 220, h = 43, step = 45, max = 5, dir = "UP",
			src = "spec 2.3 стр.174 (боссы 1-5 220x43, шаг 45 вверх, boss1 CENTER(720,-99.5))",
		},

		-- Сообщения (шрифт 23 / 40 / 55).
		["tr.msg"] = {
			label = "Сообщения", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 0, y = 248,
			w = 600, h = 28, dir = "UP",
			src = "spec 2.3 стр.190 (сообщения BigWigs шрифт 23, CENTER +248, рост вверх)",
		},
		["tr.msgEmph"] = {
			label = "Важное сообщение", point = "TOP", rel = "UIParent", relPoint = "TOP", x = 0, y = -300,
			w = 800, h = 48,
			src = "spec 2.3 стр.191 (выделенное сообщение шрифт 40, TOP -300)",
		},
		["tr.count"] = {
			label = "Отсчет", point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 0, y = 135,
			w = 160, h = 64,
			src = "spec 2.3 стр.192 (обратный отсчет шрифт 55, CENTER +135)",
		},

		-- Док урона и окна над ним.
		["mt.dock"] = {
			label = "Счетчик урона", point = "BOTTOMRIGHT", rel = "UIParent", relPoint = "BOTTOMRIGHT", x = -1, y = 1,
			w = 427, h = 214,
			src = "spec 2.3 стр.183 (счетчик урона AES 427x214, BOTTOMRIGHT(-1,1)); 3.7",
		},
		["mt.breakdown"] = {
			label = "Разбивка урона", point = "BOTTOMRIGHT", rel = "UIParent", relPoint = "BOTTOMRIGHT", x = -1, y = 216,
			w = 427, h = 45, step = 24, max = 10, dir = "UP",
			src = "spec 3.11 (сумки AES над доком); plan 2.8: 21 + n x 24, до 10 строк",
		},

		-- Прочее.
		["ui.micro"] = {
			label = "Кнопки сбоку", point = "BOTTOMLEFT", rel = "UIParent", relPoint = "BOTTOMLEFT", x = 427, y = 1,
			w = 85, h = 214,
			src = "spec 2.3 стр.179 (боковая панель 85x214 по наведению, справа от чата +1)",
		},
		["tr.loot"] = {
			label = "Добыча", point = "TOPLEFT", rel = "tr.thisRun", relPoint = "BOTTOMLEFT", x = 0, y = -1,
			widthMatch = "tr.thisRun", w = 230, h = 40,
			src = "plan 2.8 (нет в ретейле): левая колонка, под панелью Этот забег, ширина 230 как у нее; зазор 1 px как между панелями правой колонки",
			note = "высота задается кодом по числу строк (3 + 16 + 18 на строку + 3 ретейл-px) [НЕ ПРОВЕРЕНО в игре]",
		},
		["ui.chat"] = {
			label = "Место чата", point = "BOTTOMLEFT", rel = "UIParent", relPoint = "BOTTOMLEFT", x = 1, y = 1,
			w = 425, h = 214, movable = false,
			src = "spec 2.3 стр.178 (чат 425x214, BOTTOMLEFT(1,1)); чат в v1 не двигаем",
			note = "[НЕ ПРОВЕРЕНО] где чат стоит в benilla; кусок только резервирует место",
		},
		["ui.tooltip"] = {
			label = "Подсказка", point = "BOTTOMRIGHT", rel = "UIParent", relPoint = "BOTTOMRIGHT", x = -1, y = 216,
			w = 130, h = 20, movable = false,
			src = "spec 2.3 стр.184 (якорь подсказки 130x20, BOTTOMRIGHT(-1,216)); 3.10",
		},
	},

	-- Порядок: родители раньше детей.
	order = {
		"col.main", "col.class", "col.buffs", "col.statics", "col.utility", "col.revive", "col.xp",
		"uf.player", "uf.jewelry", "uf.target", "uf.targetAuras", "uf.party", "uf.levelup",
		"build.list",
		"tr.minimap", "uf.buffs", "uf.debuffs", "tr.bars", "tr.tracker", "tr.tally", "tr.thisRun", "tr.loot",
		"tr.barsEmph", "tr.bossFrames", "tr.msg", "tr.msgEmph", "tr.count",
		"mt.dock", "mt.breakdown", "ui.micro", "ui.chat", "ui.tooltip",
	},

	-- Ауры цели поднимаются над выделенными полосами, когда рядов аур 2 и больше (plan 2.8).
	-- x = 2: правый край полос босса на 2 px левее правого края цели (269 + 1 против 272).
	above = {
		["uf.targetAuras"] = { over = "tr.barsEmph", point = "BOTTOMRIGHT", relPoint = "TOPRIGHT", x = 2, y = 2, minRows = 2 },
	},

	variants = {
		["col.xp"] = {
			-- Полоса над рядом способностей шириной колонки (вариант вопроса 5, не по умолчанию).
			column = {
				point = "BOTTOM", rel = "col.main", relPoint = "TOP", x = 0, y = 1, widthMatch = "col.main", h = 14,
				src = "spec 2.3 стр.159 (ERB_Power 459x14)",
			},
		},
		["uf.player"] = {
			-- Прижать к ряду способностей с зазором (вариант вопроса 7, не по умолчанию).
			pinned = { point = "RIGHT", rel = "col.main", relPoint = "LEFT", x = -20, y = 0 },
		},
		["uf.target"] = {
			pinned = { point = "LEFT", rel = "col.main", relPoint = "RIGHT", x = 20, y = 0 },
		},
	},
}
