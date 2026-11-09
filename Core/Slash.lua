-- HyoukaUI: команда /hui. Подкоманды регистрируют остальные файлы через H.Slash.Register.

local H = HyoukaUI

local S = {}
H.Slash = S

S.cmds = {}
S.order = {}

-- name: подкоманда в нижнем регистре; fn(rest); help: строка вида "имя - описание" или функция, ее возвращающая (язык).
function S.Register(name, fn, help)
	if not S.cmds[name] then
		table.insert(S.order, name)
	end
	S.cmds[name] = { fn = fn, help = help }
end

function S.HelpLines()
	local list = { H.Lf("sl_help_head", H.version, H.stage) }
	for i = 1, table.getn(S.order) do
		local c = S.cmds[S.order[i]]
		local help = c.help
		if type(help) == "function" then
			help = help()
		end
		table.insert(list, "  /hui "..(help or S.order[i]))
	end
	return list
end

function S.Help()
	local list = S.HelpLines()
	if H.Debug and H.Debug.Show then
		H.Debug.Show(list, "/hui")
	else
		for i = 1, table.getn(list) do
			H.Print(list[i])
		end
	end
end

-- Разобрать строку после /hui и выполнить. Ошибка команды идет в корзину модуля debug.
function S.Run(msg)
	local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
	cmd = string.lower(cmd or "")
	if cmd == "" or cmd == "help" or cmd == "?" then
		S.Help()
		return true
	end
	local c = S.cmds[cmd]
	if not c then
		H.Print(H.Lf("sl_unknown", cmd))
		return false
	end
	H.Safe("debug", c.fn, rest)
	return true
end

SLASH_HYOUKAUI1 = "/hui"
SlashCmdList["HYOUKAUI"] = function(msg)
	S.Run(msg)
end

----------------------------------------------------------------------------------------
-- Команды раскладки и окон (этап 1b). Модули берутся при вызове, а не при загрузке файла,
-- поэтому порядок загрузки относительно Layout, Mover, Demo и Options не важен.
----------------------------------------------------------------------------------------

local function Say(list, title)
	if H.Debug and H.Debug.Show then
		H.Debug.Show(list, title)
	else
		for i = 1, table.getn(list) do
			H.Print(list[i])
		end
	end
end

S.Register("demo", function(rest)
	if not H.Demo then
		H.Print(H.L.sl_demo_missing)
		return
	end
	local scene = string.lower(rest or "")
	if scene == "off" then
		H.Demo.Hide()
		H.Print(H.L.sl_demo_off)
	elseif H.Demo.scenes[scene] then
		local n = H.Demo.Show(scene)
		H.Print(H.Lf("sl_demo_on", scene, n))
	else
		H.Print(H.Lf("sl_demo_usage", tostring(H.Demo.Scene() or H.L.sl_demo_none)))
	end
end, function()
	return H.L.sh_demo
end)

S.Register("move", function(rest)
	if not H.Mover then
		H.Print(H.L.sl_move_missing)
		return
	end
	local arg = string.lower(rest or "")
	if arg == "on" then
		H.Mover.On()
	elseif arg == "off" then
		H.Mover.Off()
	else
		H.Mover.Toggle()
	end
	H.Print(H.Lf("sl_move_state", H.Mover.IsOn() and H.L.sl_on or H.L.sl_off))
end, function()
	return H.L.sh_move
end)

local function OpenOptions()
	if H.Options then
		H.Options.Toggle()
	else
		H.Print(H.L.sl_opts_missing)
	end
end

S.Register("options", OpenOptions, function()
	return H.L.sh_options
end)
S.Register("open", OpenOptions, function()
	return H.L.sh_open
end)

S.Register("geometry", function()
	if not H.Layout then
		H.Print(H.L.sl_layout_missing)
		return
	end
	local list = H.Layout.GeometryLines()
	if table.getn(list) == 0 then
		list = { H.L.sl_geo_none }
	end
	Say(list, H.L.sl_geo_title)
end, function()
	return H.L.sh_geometry
end)

S.Register("layout", function(rest)
	if not H.Layout then
		return
	end
	local _, _, sub, id = string.find(rest or "", "^(%S*)%s*(.-)$")
	if sub == "reset" then
		if id and id ~= "" then
			H.Layout.Reset(id)
			H.Print(H.Lf("sl_piece_reset", id))
		else
			H.Layout.ResetAll()
			H.Print(H.L.sl_layout_reset)
		end
	else
		H.Print(H.Lf("sl_layout_info", H.Layout.SavedCount()))
	end
end, function()
	return H.L.sh_layout
end)
