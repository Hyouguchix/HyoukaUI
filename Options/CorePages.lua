-- HyoukaUI: страницы настроек ядра (plan 5): Общее, Раскладка, Модули, Отладка.
-- Страницы модулей (Рамки, Трекер, Сборка, Урон) добавляют сами модули через H.Options.AddPage.
--
-- Ключи general, которые пишет эта страница (их читают Theme, Fonts и Locale слоя 1b-A):
--   accent    ключ палитры Theme.ACCENTS ("default", "teal", ..., "class") или "RRGGBB"
--   font      "expressway" | "game"        gameFont  true | false (Expressway во всей игре)
--   language  "auto" | "ruRU" | "enUS"     moveKey   "none" | "alt" | "ctrl" | "shift"
-- Умолчания этих ключей добавляются, только если другой слой не задал их раньше. Толщина рамки не
-- настраивается: решение проекта, 1 физический пиксель.
-- Эти слои сами слушают SETTING, поэтому страница только пишет значение.

local H = HyoukaUI
local K = H.Kit
local C = H.Controls
local O = H.Options

local getn = table.getn

local GENERAL_DEFAULTS = {
	accent = "default", font = "expressway", gameFont = true, language = "auto", moveKey = "none",
}

-- Не затирает умолчания, которые уже задал другой слой (D.Defaults заменяет таблицу целиком).
function O.EnsureGeneralDefaults()
	local d = H.DB.defaults.general or {}
	for k, v in pairs(GENERAL_DEFAULTS) do
		if d[k] == nil then
			d[k] = v
		end
	end
	H.DB.Defaults("general", d)
end

O.EnsureGeneralDefaults()

local function ClassRGB()
	local r, g, b
	if H.Hero and H.Hero.ClassColor then
		local ok, cr, cg, cb = pcall(H.Hero.ClassColor)
		if ok then
			r, g, b = cr, cg, cb
		end
	end
	return r or 0.78, g or 0.61, b or 0.43
end

-- Резервный набор, если слой Theme не загружен (ключи те же, что в Theme.ACCENTS).
local ACCENTS = {
	{ value = "default", color = { 0.451, 0.506, 1 } },
	{ value = "teal", color = { 0.047, 0.824, 0.616 } },
	{ value = "blue", color = { 0.25, 0.56, 1 } },
	{ value = "violet", color = { 0.64, 0.42, 1 } },
	{ value = "red", color = { 0.95, 0.30, 0.30 } },
	{ value = "orange", color = { 1, 0.56, 0.16 } },
	{ value = "gold", color = { 1, 0.82, 0 } },
	{ value = "green", color = { 0.36, 0.86, 0.36 } },
	{ value = "white", color = { 0.9, 0.9, 0.9 } },
	{ value = "class", color = ClassRGB },
}
O.ACCENTS = ACCENTS

local function AccentOptions()
	local src = H.Theme and H.Theme.ACCENTS
	if not src then
		return ACCENTS
	end
	local out = {}
	for i = 1, getn(src) do
		table.insert(out, { value = src[i].key, color = src[i].color or ClassRGB })
	end
	return out
end

local function SetAccent(v)
	if H.Theme and H.Theme.SetAccent then
		H.Theme.SetAccent(v)
	else
		H.DB.Set("general", "accent", v)
	end
end

----------------------------------------------------------------------------------------
-- Общее
----------------------------------------------------------------------------------------

local function BuildGeneral(page, f)
	f:Header(H.L.hdr_look)
	f:Swatches({ label = H.L.opt_accent, mod = "general", key = "accent", options = AccentOptions(),
		set = SetAccent })
	f:Dropdown({ label = H.L.opt_font, mod = "general", key = "font",
		options = { { value = "expressway", label = "Expressway" }, { value = "game", label = H.L.opt_font_game } } })
	f:Toggle({ label = H.L.opt_game_font, hint = H.L.hint_game_font,
		mod = "general", key = "gameFont" })
	f:Dropdown({ label = H.L.opt_language, mod = "general", key = "language",
		options = { { value = "auto", label = H.L.opt_language_auto }, { value = "ruRU", label = "Русский" },
			{ value = "enUS", label = "English" } } })
	f:Gap(4)
	f:Header(H.L.hdr_borders)
	f:Note(H.L.note_border)
end

----------------------------------------------------------------------------------------
-- Раскладка
----------------------------------------------------------------------------------------

local function MoveKeys()
	return {
		{ value = "none", label = H.L.opt_none }, { value = "alt", label = "Alt" },
		{ value = "ctrl", label = "Ctrl" }, { value = "shift", label = "Shift" },
	}
end

local function BuildLayout(page, f)
	local L = H.Layout
	f:Header(H.L.hdr_layout)
	f:Toggle({ label = H.L.mv_title, hint = H.L.hint_move,
		get = function()
			return H.Mover and H.Mover.IsOn()
		end,
		set = function(v)
			if v then
				O.Close()
				H.Mover.On()
			else
				H.Mover.Off()
			end
		end })
	f:Dropdown({ label = H.L.opt_move_key, mod = "general", key = "moveKey", options = MoveKeys() })
	f:Button({ label = H.L.btn_undo, onClick = function()
		if H.Mover then
			H.Mover.Undo()
		end
	end })
	local confirm = f:Button({ label = H.L.btn_reset_all, onClick = function(btn)
		if btn.armed then
			btn.armed = false
			btn:SetLabel(H.L.btn_reset_all)
			if H.Mover then
				H.Mover.ClearUndo()
			end
			L.ResetAll()
			return
		end
		btn.armed = true
		btn:SetLabel(H.L.btn_confirm_again)
		H.Clock.After("options", 4, function()
			btn.armed = false
			btn:SetLabel(H.L.btn_reset_all)
		end)
	end })
	f:Gap(4)
	local note = f:Note("")
	table.insert(f.items, function()
		note:SetText(H.Lf("layout_saved", L.SavedCount()))
	end)
	f:Refresh()
	return confirm
end

----------------------------------------------------------------------------------------
-- Модули
----------------------------------------------------------------------------------------

local function ModuleCount()
	local n = 0
	local list = H.Modules()
	for i = 1, getn(list) do
		if not list[i].internal then
			n = n + 1
		end
	end
	return n
end

local function ModuleOptions()
	local out = {}
	for i = 1, getn(H.MODES) do
		table.insert(out, { value = H.MODES[i], label = H.MODE_LABELS[H.MODES[i]] })
	end
	return out
end

local function BuildModules(page, f)
	f:Header(H.L.page_modules)
	local list = H.Modules()
	local shown = 0
	for i = 1, getn(list) do
		local M = list[i]
		if not M.internal then
			shown = shown + 1
			local name = M.name
			f:Segment({ label = H.ModuleLabel(M), options = ModuleOptions(), bw = 50,
				hint = M.suspended and H.L.mod_suspended_hint or nil,
				get = function()
					return H.GetMode(name)
				end,
				set = function(v)
					H.SetMode(name, v)
				end })
		end
	end
	if shown == 0 then
		f:Note(H.L.mod_none)
	end
	f:Gap(4)
	if H.IsCoexist() then
		f:Note(H.L.mod_note_coexist)
	else
		f:Note(H.L.mod_note)
	end
	page.moduleCount = shown
end

----------------------------------------------------------------------------------------
-- Отладка
----------------------------------------------------------------------------------------

local function ErrorTotal()
	local n = 0
	local list = H.Modules()
	for i = 1, getn(list) do
		n = n + H.Errors.Count(list[i].name)
	end
	return n + H.Errors.Count("debug") + H.Errors.Count("options") + H.Errors.Count("mover")
end

local function BuildDebug(page, f)
	f:Header(H.L.page_debug)
	local info = f:Note("")
	table.insert(f.items, function()
		info:SetText(H.Lf("dbg_errors", ErrorTotal()))
	end)
	f:Button({ label = H.L.dbg_selftest, onClick = function()
		H.Debug.Selftest()
	end })
	f:Button({ label = H.L.dbg_error_log, onClick = function()
		H.Debug.ShowErrors()
	end })
	f:Gap(4)
	f:Header(H.L.hdr_preview)
	f:Toggle({ label = H.L.dbg_stub_solo, hint = H.L.hint_stubs,
		get = function()
			return H.Demo and H.Demo.Scene() == "solo"
		end,
		set = function(v)
			if v then
				H.Demo.Show("solo")
			else
				H.Demo.Hide()
			end
		end })
	f:Toggle({ label = H.L.dbg_stub_party,
		get = function()
			return H.Demo and H.Demo.Scene() == "party"
		end,
		set = function(v)
			if v then
				H.Demo.Show("party")
			else
				H.Demo.Hide()
			end
		end })
	f:Button({ label = H.L.dbg_geometry, onClick = function()
		H.Slash.Run("geometry")
	end })
	f:Refresh()
end

local function Label(key)
	return function()
		return H.L[key]
	end
end

O.AddPage("general", Label("page_general"), BuildGeneral, 10)
O.AddPage("modules", Label("page_modules"), BuildModules, 20, function()
	local p = O.pages.modules
	return p.frame ~= nil and p.frame.moduleCount ~= ModuleCount()
end)
O.AddPage("layout", Label("page_layout"), BuildLayout, 80)
O.AddPage("debug", Label("page_debug"), BuildDebug, 90)
