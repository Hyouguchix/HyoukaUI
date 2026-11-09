-- HyoukaUI: Modules\Meter\Module.lua, модуль "счетчик урона": объявление, режимы, жизненный цикл, команда /hui meter.
--
-- Модуль читает только API ядра (H.MeterData, H.CombatText, H.Loadout, H.Spells, H.Buffs, H.Run, H.Party, H.Hud, H.Layout,
-- H.Vis, H.Tooltip) и свои настройки. Глобалов AZS_* здесь нет (lint azs-in-module).
--
-- Режимы (plan 4): Выкл, Рядом, Вместо.
--   Выкл    ничего не создается и не показывается.
--   Рядом   док рисуется на свободном месте слева от штатного (его ширина + зазор), без Claim "meter" (штатный счетчик игры
--           остается на экране для сравнения).
--   Вместо  Claim "meter" через H.Hud (часть HUD "meter": одно покрытие, правило Cover для нее не нужно), док на ретейл-месте.
--           Если SurvivorUI показывает свой счетчик, модуль остается в режиме Рядом и пишет одну строку.
--
-- Файлы папки (порядок загрузки см. handoff_meter.md): Module, Strings, Model, Crits, Rows, Menu, Card, Dock, Breakdown,
-- MeterOptions. Общая таблица H.MeterUI (MU); функции других файлов вызываются в момент работы, поэтому порядок
-- загрузки после Module не важен.

local H = HyoukaUI

local MU = H.MeterUI or {}
H.MeterUI = MU

MU.OWNER = "meter"
MU.SLOTS = 3
MU.SLOT_KEYS = { "slot1", "slot2", "slot3" }
MU.locGen = 0      -- растет на смену языка: подписи пересобираются

-- Умолчания. slot2 = "auto": в группе страница "Группа", соло страница "Босс" (critic meter, plan 3.4).
-- slot3 = "off" скрывает нижнее место второй колонки, и верхнее занимает всю высоту.
local M = H.NewModule("meter", {
	label = "Счетчик урона", schema = 1, migrations = {},
	defaults = {
		mode = "off", slot1 = "damage", slot2 = "auto", slot3 = "healing", rightText = "dps",
		foldPct = 0, pets = false, always = false, crits = true, collapsed = false,
	},
})
MU.M = M

-- Режим, который действует на самом деле: "Вместо" при активном счетчике SurvivorUI остается "Рядом".
function MU.SurvivorMeterActive()
	if not H.IsCoexist() then
		return false
	end
	local f = H.Env.SurvivorUIMeter
	return type(f) == "table" and f.IsShown ~= nil and f:IsShown() and true or false
end

function MU.EffectiveMode()
	local mode = H.GetMode("meter")
	if mode == "replace" and MU.SurvivorMeterActive() then
		return "side", "survivor"
	end
	return mode, nil
end

-- Настройки, прочитанные один раз (обновляются на SETTING): строки и колонки не читают DB в кадре.
MU.opt = { right = "dps", fold = 0, pets = false, always = false, crits = true, collapsed = false }

function MU.LoadOptions()
	local o = MU.opt
	o.right = H.DB.Get("meter", "rightText") or "dps"
	o.fold = H.DB.Get("meter", "foldPct") or 0
	o.pets = H.DB.Get("meter", "pets") and true or false
	o.always = H.DB.Get("meter", "always") and true or false
	o.crits = H.DB.Get("meter", "crits") ~= false
	o.collapsed = H.DB.Get("meter", "collapsed") and true or false
end

function M:OnInit()
	MU.LoadOptions()
	if H.Slash then
		H.Slash.Register("meter", MU.Command, "meter [status|reset N|page N id|collapse|open] - счетчик урона")
	end
end

function M:OnEnable()
	MU.LoadOptions()
	MU.Dock.Enable()
end

function M:OnDisable()
	MU.Dock.Disable()
end

-- PLAYER_ENTERING_WORLD: только обновление состояния (после /reload посреди забега).
function M:OnWorld()
	MU.Dock.UpdateShown()
end

-- Вызывается ядром при смене режима, пока модуль включен (side <-> replace) и перед включением.
function M:OnMode(mode)
	if M.enabled and mode ~= "off" then
		MU.Dock.ApplyMode()
	end
end

----------------------------------------------------------------------------------------
-- Команда /hui meter
----------------------------------------------------------------------------------------

local function Say(text)
	H.Print("meter: "..text)
end

function MU.Command(rest)
	rest = rest or ""
	local _, _, sub, arg1, arg2 = string.find(rest, "^%s*(%S*)%s*(%S*)%s*(%S*)")
	sub = string.lower(sub or "")
	if sub == "" or sub == "status" then
		local eff, why = MU.EffectiveMode()
		Say("режим "..H.GetMode("meter").." (действует "..eff..(why and ", счетчик SurvivorUI виден" or "")..")"
			..", колонки "..tostring(H.DB.Get("meter", "slot1"))..", "..tostring(H.DB.Get("meter", "slot2"))..", "
			..tostring(H.DB.Get("meter", "slot3"))..", разбивка "..(MU.Breakdown and MU.Breakdown.IsOpen() and "открыта" or "закрыта"))
		-- Для сверки в игре: итоги колонок против суммы строк счетчика игры (без оверкилла; экран итогов считает с ним).
		local game = H.Run.Damage()
		local line = "итоги колонок:"
		for i = 1, MU.SLOTS do
			local sec = MU.Dock and MU.Dock.Section(i)
			if sec and sec.active then
				line = line.." "..i.."="..tostring(sec.view.total).." ("..tostring(sec.view.pageId)..")"
			end
		end
		Say(line..", счетчик игры (сумма строк) "..tostring(game))
	elseif sub == "reset" then
		local n = tonumber(arg1)
		if n and n >= 1 and n <= MU.SLOTS and M.enabled then
			MU.Dock.Reset(n)
		else
			Say("/hui meter reset 1|2|3")
		end
	elseif sub == "page" then
		local n = tonumber(arg1)
		if n and n >= 1 and n <= MU.SLOTS and arg2 ~= "" then
			H.DB.Set("meter", MU.SLOT_KEYS[n], arg2)
		else
			Say("/hui meter page 1|2|3 damage|dps|healing|party|boss|last30|auto|off")
		end
	elseif sub == "collapse" then
		H.DB.Set("meter", "collapsed", not H.DB.Get("meter", "collapsed"))
	elseif sub == "open" then
		if M.enabled then
			MU.Breakdown.OpenSelf()
		else
			Say("модуль выключен: включите его на странице Модули (/hui options)")
		end
	else
		Say("неизвестная подкоманда: "..sub)
	end
end
