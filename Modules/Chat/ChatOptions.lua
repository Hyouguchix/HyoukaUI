-- HyoukaUI: Chat\ChatOptions, страницы настроек модуля Чат (окно 400x300 без прокрутки, строка 16 AS).
--
-- "Чат" (порядок 40): режим Выкл / Рядом / Вместо (тот же переключатель, что на странице Модули), размер, текст, фон, метки
-- времени, уголок размера. "Чат: вкладки" (порядок 41): вкладки, фильтры крика и баннеров, затухание, колесо.
-- Значения пишутся в H.DB (модуль "chat"), модуль сам слушает SETTING. Положение и масштаб куска ui.chat - в режиме
-- перемещения (/hui move).

local H = HyoukaUI
local C = H.Chat
local K = H.Kit
local O = H.Options

local getn = table.getn

local function T(key)
	return C.T(key)
end

local function Toggle(f, key, label, hint)
	f:Toggle({ label = label, hint = hint, mod = "chat", key = key })
end

local function Int(v)
	return string.format("%d", v)
end

local function BuildMain(page, f)
	f:Header(T("o_mode"))
	local names = {}
	for i = 1, getn(H.MODES) do
		table.insert(names, { value = H.MODES[i], label = K.L("mode_"..H.MODES[i], H.MODE_LABELS[H.MODES[i]]) })
	end
	f:Segment({ label = T("label"), options = names, bw = 50,
		get = function()
			return H.GetMode("chat")
		end,
		set = function(v)
			H.SetMode("chat", v)
			f:Refresh()
		end })
	f:Note(T("o_mode_hint"))
	f:Gap(2)
	f:Header(T("o_look"))
	f:Slider({ label = T("o_width"), mod = "chat", key = "width", min = 200, max = 900, step = 5, fmt = Int })
	f:Slider({ label = T("o_height"), mod = "chat", key = "height", min = 80, max = 500, step = 5, fmt = Int })
	f:Slider({ label = T("o_text"), mod = "chat", key = "textSize", min = 10, max = 20, step = 1, fmt = Int })
	f:Slider({ label = T("o_bg"), mod = "chat", key = "bgAlpha", min = 0, max = 1, step = 0.05,
		fmt = function(v)
			return string.format("%.2f", v)
		end })
	Toggle(f, "timestamps", T("o_stamp"))
	Toggle(f, "lock", T("o_lock"))
	f:Refresh()
end

local function BuildTabs(page, f)
	f:Header(T("o_tabs"))
	Toggle(f, "showCombat", T("o_combat"))
	Toggle(f, "tabLoot", T("o_loot"))
	Toggle(f, "tabParty", T("o_party"))
	Toggle(f, "dedupe", T("o_dedupe"))
	Toggle(f, "hideYells", T("o_yells"))
	Toggle(f, "hideBanners", T("o_banners"))
	f:Slider({ label = T("o_wheel"), mod = "chat", key = "wheelLines", min = 1, max = 10, step = 1, fmt = Int })
	f:Gap(2)
	f:Header(T("o_fade"))
	Toggle(f, "fade", T("o_fade_on"))
	f:Slider({ label = T("o_fade_after"), mod = "chat", key = "fadeAfter", min = 3, max = 60, step = 1, fmt = Int })
	f:Refresh()
end

local function Label(key)
	return function()
		return T(key)
	end
end

O.AddPage("chat", Label("o_chat"), BuildMain, 40)
O.AddPage("chat_tabs", Label("o_page_tabs"), BuildTabs, 41)
