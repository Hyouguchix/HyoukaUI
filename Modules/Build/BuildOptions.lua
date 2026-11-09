-- HyoukaUI: модуль Build, страница настроек "Сборка" (plan 5).
--
-- Страница добавляется в окно /hui через H.Options.AddPage при загрузке файла (кадры окна создаются при первом
-- открытии). Все переключатели пишут в настройки модуля (mod = "build"), модуль слушает событие SETTING и
-- перестраивает куски. Режим модуля (Выкл, Рядом, Вместо) переключается тут же и на странице "Модули".
-- Положение куска и размер задает раскладка (/hui move), здесь их нет.

local H = HyoukaUI
local B = H.Build
local K = H.Kit
local O = H.Options

local function ModeOptions()
	local out = {}
	for i = 1, table.getn(H.MODES) do
		table.insert(out, { value = H.MODES[i], label = K.L("mode_"..H.MODES[i], H.MODE_LABELS[H.MODES[i]]) })
	end
	return out
end

local function BuildPage(page, f)
	f:Header(B.T("o_module"))
	f:Segment({ label = B.T("o_mode"), options = ModeOptions(), bw = 50,
		hint = K.L("mode_hint", ""),
		get = function()
			return H.GetMode("build")
		end,
		set = function(v)
			H.SetMode("build", v)
		end })
	f:Gap(4)
	f:Header(B.T("o_list_head"))
	f:Toggle({ label = B.T("o_show_list"), mod = "build", key = "showList" })
	f:Toggle({ label = B.T("o_col_cd"), hint = B.T("o_col_cd_hint"), mod = "build", key = "showCd" })
	f:Toggle({ label = B.T("o_col_info"), hint = B.T("o_col_info_hint"), mod = "build", key = "showInfo" })
	f:Toggle({ label = B.T("o_col_rank"), mod = "build", key = "showRank" })
	f:Toggle({ label = B.T("o_roman"), mod = "build", key = "roman" })
	f:Gap(4)
	f:Header(B.T("o_jewelry_head"))
	f:Toggle({ label = B.T("o_jewelry_rows"), mod = "build", key = "jewelryRows" })
	f:Toggle({ label = B.T("o_jewelry_icons"), mod = "build", key = "jewelryIcons" })
	f:Toggle({ label = B.T("o_jewelry_names"), hint = B.T("o_jewelry_names_hint"), mod = "build", key = "jewelryNames" })
	f:Toggle({ label = B.T("o_jewelry_empty"), mod = "build", key = "jewelryEmpty" })
	f:Gap(4)
	f:Header(B.T("o_char_head"))
	f:Toggle({ label = B.T("o_char_window"), hint = B.T("o_char_window_hint"), mod = "build", key = "charWindow" })
	f:Toggle({ label = B.T("o_hide_zero"), mod = "build", key = "hideZero" })
	f:Button({ label = B.T("o_char_toggle"), onClick = function()
		B.ToggleCharacter()
	end })
	f:Refresh()
end

if O and O.AddPage then
	O.AddPage("build", function()
		return K.L("page_build", B.T("title"))
	end, BuildPage, 40)
end
