-- HyoukaUI: глобальная таблица, версия, реестр модулей и их режимы.
-- Загружается первым: ErrorLog и все остальные файлы пишут в таблицу HyoukaUI.
-- Здесь только определения; ничего не рисуется и не регистрируется.

HyoukaUI = HyoukaUI or {}
local H = HyoukaUI

H.name = "HyoukaUI"
H.version = "0.1.0"
H.stage = "1"
H.SCHEMA = 1

-- Режимы модуля (plan 1, принцип 6): Выкл, Рядом, Вместо.
H.MODES = { "off", "side", "replace" }
-- Названия режимов на текущем языке: читаются при обращении (H.L), поэтому смена языка их не устаревает.
local MODE_KEYS = { off = "mode_off", side = "mode_side", replace = "mode_replace" }
H.MODE_LABELS = setmetatable({}, {
	__index = function(t, mode)
		local key = MODE_KEYS[mode]
		return key and H.L[key] or nil
	end,
})

-- Единственный список именованных кадров аддона (plan 2.7). check_globals.py сверяет
-- с ним каждый CreateFrame с именем. Имя нужно только там, где его требует движок или 1.12.
H.FRAME_NAMES = {
	HyoukaUI_Debug = true,
	HyoukaUI_ProbeBtn = true,
	HyoukaUI_ProbeBox = true,
	HyoukaUI_ProbeCD = true,
	HyoukaUI_ScanTip = true,       -- скрытый тултип Data\TooltipScan (нужен шаблон со строками TextLeft<n>)
	HyoukaUI_Options = true,       -- окно настроек OptionsPanel (Esc через UISpecialFrames)
	HyoukaUI_PlayerClick = true,   -- Frames: кнопка клика по рамке героя (ToggleDropDownMenu читает GetName источника)
	HyoukaUI_TargetClick = true,   -- Frames: то же для рамки цели
	HyoukaUI_Breakdown = true,     -- Meter: окно разбивки (Esc через UISpecialFrames)
	HyoukaUI_BuildList = true,     -- Build: список сборки
	HyoukaUI_JewelryList = true,   -- Build: ряд значков бижутерии
	HyoukaUI_Character = true,     -- Build: окно персонажа (Esc через UISpecialFrames)
}

-- Настоящие счетчики для приемки: claims и covers ведет Hud, parks ведет Park.
H.counters = { claims = 0, parks = 0, covers = 0 }

-- Реестр меток владельцев хуков (plan 2.2, SetFont и GameTooltip_SetDefaultAnchor).
H.hooks = {}

H.modules = {}
H.moduleList = {}
H.booted = false

local P = {}
H.ModuleProto = P
local PROTO_META = { __index = P }

function H.Now()
	if GetTime then
		return GetTime()
	end
	return 0
end

function H.Print(text)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cff7381FFHyoukaUI:|r "..tostring(text))
	end
end

-- Загружен ли рядом SurvivorUI.
function H.IsCoexist()
	if not IsAddOnLoaded then
		return false
	end
	local ok, loaded = pcall(IsAddOnLoaded, "SurvivorUI")
	return ok and loaded and true or false
end

function H.RegisterHook(name, owner)
	H.hooks[name] = owner or H.name
end

-- H.NewModule(name, spec): spec = { label, defaults, schema, migrations, internal }.
-- internal = true: модуль ядра, всегда включен, режимов у него нет.
function H.NewModule(name, spec)
	if H.modules[name] then
		return H.modules[name]
	end
	spec = spec or {}
	local defaults = {}
	if spec.defaults then
		for k, v in pairs(spec.defaults) do
			defaults[k] = v
		end
	end
	if not spec.internal and defaults.mode == nil then
		defaults.mode = "off"
	end
	local M = { name = name, label = spec.label or name, spec = spec, defaults = defaults,
		internal = spec.internal and true or false, errors = 0, errTimes = {},
		suspended = false, inited = false, enabled = false }
	setmetatable(M, PROTO_META)
	if H.DB then
		M.db = H.DB.Module(name, defaults, spec)
	end
	table.insert(H.moduleList, M)
	H.modules[name] = M
	return M
end

function H.Module(name)
	return H.modules[name]
end

function H.Modules()
	return H.moduleList
end

function H.IsSuspended(owner)
	local M = H.modules[owner]
	return M ~= nil and M.suspended
end

-- Текущий режим модуля: "off", "side" или "replace".
function H.GetMode(name)
	local M = H.modules[name]
	if not M then
		return "off"
	end
	if M.internal then
		return "replace"
	end
	if M.db then
		return M.db.mode or "off"
	end
	return M.defaults.mode or "off"
end

local function WantsEnabled(M)
	return (M.internal or H.GetMode(M.name) ~= "off") and not M.suspended
end

-- Вызов метода модуля под защитой: ошибка уходит в счетчик модуля.
function H.CallModule(M, method, a1, a2)
	local fn = M[method]
	if type(fn) ~= "function" then
		return true
	end
	return H.Safe(M.name, fn, M, a1, a2)
end

function H.EnableModule(M)
	if M.enabled or M.suspended then
		return
	end
	if not M.inited then
		M.inited = true
		H.CallModule(M, "OnInit")
	end
	M.enabled = true
	H.CallModule(M, "OnEnable")
	H.Fire("MODULE", M.name, "on")
end

function H.DisableModule(M)
	if not M.enabled then
		return
	end
	M.enabled = false
	H.CallModule(M, "OnDisable")
	H.Off(nil, M.name)
	if H.Clock then
		H.Clock.Stop(M.name)
	end
	H.Fire("MODULE", M.name, "off")
end

-- Смена режима: пишется в DB (равное умолчанию стирается), модуль включается или гасится.
function H.SetMode(name, mode)
	local M = H.modules[name]
	if not M or M.internal then
		return false
	end
	if not H.MODE_LABELS[mode] then
		return false
	end
	H.DB.Set(name, "mode", mode)
	H.CallModule(M, "OnMode", mode)
	if H.booted then
		if mode == "off" then
			H.DisableModule(M)
		elseif not M.enabled then
			H.EnableModule(M)
		end
	end
	H.Fire("MODULE", name, mode)
	return true
end

-- Название модуля для окон: строка mod_<имя> текущего языка, иначе label модуля (строка или функция), иначе имя.
function H.ModuleLabel(M)
	local key = "mod_"..M.name
	local v = H.L[key]
	if v ~= key then
		return v
	end
	local label = M.label
	if type(label) == "function" then
		label = label()
	end
	return label or M.name
end

-- Аварийное выключение модуля (порог ошибок). Остальные модули не затрагиваются.
function H.Suspend(name, reason)
	local M = H.modules[name]
	if not M or M.suspended or M.internal then
		return false
	end
	M.suspended = true
	M.suspendReason = reason
	H.DisableModule(M)
	H.Print(H.Lf("msg_module_off", name))
	H.Fire("MODULE", name, "suspended")
	return true
end

function H.Resume(name)
	local M = H.modules[name]
	if not M or not M.suspended then
		return false
	end
	M.suspended = false
	M.suspendReason = nil
	H.Wipe(M.errTimes)
	if H.booted and WantsEnabled(M) then
		H.EnableModule(M)
	end
	return true
end

-- Жизненный цикл, вызывается из Boot: OnInit один раз, затем OnEnable включенных.
function H.StartModules()
	for i = 1, table.getn(H.moduleList) do
		local M = H.moduleList[i]
		if not M.inited then
			M.inited = true
			H.CallModule(M, "OnInit")
		end
	end
	for i = 1, table.getn(H.moduleList) do
		local M = H.moduleList[i]
		if WantsEnabled(M) and not M.enabled then
			M.enabled = true
			H.CallModule(M, "OnEnable")
		end
	end
end

-- Методы модуля: все подписки и таймеры идут через ядро с владельцем = имя модуля.
function P:On(event, fn)
	H.On(event, self.name, fn)
end

function P:Every(period, fn)
	H.Clock.Every(self.name, period, fn)
end

function P:OnFrame(fn)
	H.Clock.OnFrame(self.name, fn)
end

function P:Script(frame, script, fn)
	H.Script(self.name, frame, script, fn)
end

function P:Mode()
	return H.GetMode(self.name)
end

function P:SetMode(mode)
	return H.SetMode(self.name, mode)
end
