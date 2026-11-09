-- HyoukaUI: модуль Build (сборка и бижутерия, plan 3.3), ядро модуля: настройки, режимы, показ, покрытие HUD.
--
-- Части модуля лежат в отдельных файлах и регистрируются через B.AddPart (BuildText.lua):
--   BuildList.lua      список сборки (build.list, кадр HyoukaUI_BuildList)
--   Jewelry.lua        данные слотов бижутерии, теги, строки раздела списка
--   JewelryIcons.lua   ряд значков uf.jewelry (кадр HyoukaUI_JewelryList)
--   Character.lua      свое окно персонажа (кадр HyoukaUI_Character), CharacterStats.lua его статы
--   AbilityInfo.lua    колонка Info (дальность, радиус)    BuildOptions.lua   страница настроек
--
-- РЕЖИМЫ. off: кадров нет. side ("Рядом"): куски рисуются рядом с играми без Claim и без парковки, окно
-- персонажа открывается по Shift+C, стоковое по C. replace ("Вместо"): часть HUD игры "build" скрывается
-- через H.Hud.Cover и только когда покрыты ВСЕ обязательные куски (build.list и uf.jewelry от этого модуля,
-- col.utility от модуля Frames): кто из них включен, этот модуль знать не может, правило в ядре (GameRules.cover).
-- Покрытие объявляется только для кусков, которые реально включены в настройках. Если рядом активны список
-- сборки или бижутерия SurvivorUI, режим "Вместо" не включается (остается "Рядом") и в чат идет одна строка.
-- ПОКАЗ. Куски видны вне фазы "ready" (в городе скрыты): список, если есть способности или бижутерия;
-- значки, если надета бижутерия (или включены пустые слоты). На карточках выбора (фаза choosing) списки
-- остаются и кликабельны: H.Vis.Register(кадр, { overCards = true }), имена кадров из H.FRAME_NAMES.
-- Публичное: H.Build (B): Mode(), Place(), Rebuild(), ToggleCharacter(), OpenCharacter(), CloseCharacter(),
-- SurvivorActive(); B.List, B.Jewelry, B.JewelryIcons, B.Info, B.Character.
-- События: подписки на SPELLS_CHANGED, LOADOUT_CHANGED, SCAN_READY, PHASE_CHANGED, RUN_STARTED, SETTING, LOCALE,
-- THEME, FONTS, UNIT_INVENTORY_CHANGED, LOGOUT. Своих событий в шину модуль не шлет.

local H = HyoukaUI
local B = H.Build

local M = H.NewModule("build", {
	label = "Сборка", schema = 1, migrations = {},
	defaults = {
		mode = "off",
		showList = true,        -- список сборки
		showCd = true,          -- колонка Откат (на новой установке включена, inv build critic wrong)
		showInfo = true,        -- колонка Info
		showRank = true,        -- колонка Ранг
		roman = false,          -- ранг римскими
		jewelryRows = true,     -- раздел "Бижутерия" в списке
		jewelryIcons = true,    -- ряд значков uf.jewelry
		jewelryNames = true,    -- в строке имя по качеству (false: слот и ранг)
		jewelryEmpty = true,    -- пустые слоты бледными
		charWindow = true,      -- свое окно персонажа
		hideZero = true,        -- в статах не показывать нули
		charPlaced = false, charX = 0, charY = 0,   -- где окно персонажа, если его двигали (ретейл-px от центра)
	},
	hud = { "build" },
	pieces = { "build.list", "uf.jewelry" },
	survivor = { key = "build", frames = { "SurvivorUIBuild", "SurvivorUIWorn" }, slash = "build" },
})
B.M = M

local S = { effective = "off", fallbackShown = false }
B.state = S

----------------------------------------------------------------------------------------
-- SurvivorUI рядом
----------------------------------------------------------------------------------------

local function ShownFrame(name)
	local f = H.Global(name)
	return type(f) == "table" and f.IsShown ~= nil and f:IsShown() and true or false
end

-- Включены ли список сборки или бижутерия в SurvivorUI (чтение, чужие данные не пишем).
function B.SurvivorActive()
	if not H.IsCoexist() then
		return false
	end
	if ShownFrame("SurvivorUIBuild") or ShownFrame("SurvivorUIWorn") then
		return true
	end
	local db = H.Global("SurvivorUIDB")
	if type(db) == "table" and (db.buildList ~= false or db.jewelryWorn ~= false) then
		return true
	end
	return false
end

-- Режим, в котором модуль работает на деле: "replace" превращается в "side", пока активен SurvivorUI.
function B.Mode()
	local mode = M.db.mode
	if mode == "replace" and B.SurvivorActive() then
		return "side"
	end
	return mode
end

----------------------------------------------------------------------------------------
-- Покрытие части HUD "build"
----------------------------------------------------------------------------------------

local function Cover(on, id)
	if on then
		H.Hud.Cover("build", id)
	else
		H.Hud.Uncover("build", id)
	end
end

function B.ApplyMode()
	if not M.enabled then
		return
	end
	local mode = B.Mode()
	if M.db.mode == "replace" and mode ~= "replace" and not S.fallbackShown then
		S.fallbackShown = true
		H.Print(B.T("fallback"))
	end
	if M.db.mode ~= "replace" then
		S.fallbackShown = false
	end
	S.effective = mode
	local db = M.db
	local replace = mode == "replace"
	Cover(replace and db.showList, "build.list")
	Cover(replace and db.jewelryIcons, "uf.jewelry")
end

----------------------------------------------------------------------------------------
-- Показ
----------------------------------------------------------------------------------------

function B.PhaseOk()
	local ph = H.Run.Phase()
	return ph ~= nil and ph ~= "ready"
end

function B.Place()
	if not M.enabled then
		return
	end
	local db = M.db
	local ok = B.PhaseOk()
	B.List.SetShown(db.showList and ok and (H.Spells.Count() > 0 or B.Jewelry.Count() > 0))
	local jf = B.JewelryIcons.Frame()
	if jf then
		if db.jewelryIcons and ok and (B.Jewelry.Count() > 0 or db.jewelryEmpty) then
			if not jf:IsShown() then
				jf:Show()
			end
		elseif jf:IsShown() then
			jf:Hide()
		end
	end
end

function B.Rebuild()
	if not M.enabled then
		return
	end
	B.List.Rebuild()
	B.JewelryIcons.Update(M.db.jewelryEmpty)
	B.Place()
end

local function OnJewelry()
	if M.enabled then
		B.JewelryIcons.Update(M.db.jewelryEmpty)
		B.List.Rebuild()
		B.Place()
	end
end

local function OnPhase()
	B.Place()
	B.ApplyMode()
end

local function OnSetting(ev, mod, key)
	if mod ~= "build" or key == "mode" then
		return
	end
	if key == "charPlaced" or key == "charX" or key == "charY" then
		return
	end
	B.ApplyMode()
	B.Rebuild()
end

local function OnInventory(ev, unit)
	if unit == nil or unit == "player" then
		B.Jewelry.Refresh()
	end
end

local function OnLoadout()
	B.Jewelry.Refresh()
end

local function OnScan(ev, kind)
	if kind == "item" then
		B.Jewelry.Refresh()
	end
end

local function OnLocale()
	B.Info.Invalidate()
	B.Jewelry.Reparse()
	B.Rebuild()
end

local function OnRunStart()
	B.Jewelry.Reset()
	B.Jewelry.Refresh()
	B.Rebuild()
end

local function OnSecond()
	B.Jewelry.Refresh()
	B.Place()
end

local function OnLogout()
	M:OnDisable()
end

-- Один общий обработчик на событие: вызывает все B.Listen этого события, ошибки идут в счетчик модуля.
-- Замыкание создается отдельной функцией: в Lua 5.0 переменные цикла pairs общие для всех итераций.
local function Dispatcher(list)
	return function(ev, a1, a2, a3)
		for i = 1, table.getn(list) do
			H.Safe("build", list[i], ev, a1, a2, a3)
		end
	end
end

function B.Wire(mod)
	for event, list in pairs(B.listeners) do
		mod:On(event, Dispatcher(list))
	end
end

----------------------------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------------------------

function M:OnEnable()
	B.List.Ensure()
	B.JewelryIcons.Ensure()
	H.Vis.Register(B.List.Frame(), { overCards = true, id = "build.list" })
	H.Vis.Register(B.JewelryIcons.Frame(), { overCards = true, id = "uf.jewelry" })
	for i = 1, table.getn(B.parts) do
		if B.parts[i].enable then
			B.parts[i].enable(self)
		end
	end
	B.Listen("PHASE_CHANGED", OnPhase)
	B.Listen("SETTING", OnSetting)
	B.Listen("UNIT_INVENTORY_CHANGED", OnInventory)
	B.Listen("LOADOUT_CHANGED", OnLoadout)
	B.Listen("SCAN_READY", OnScan)
	B.Listen("LOCALE", OnLocale)
	B.Listen("RUN_STARTED", OnRunStart)
	B.Listen("LOGOUT", OnLogout)
	B.Listen("SPELLS_CHANGED", B.Place)
	B.Wire(self)
	self:Every(1, OnSecond)
	self:Every(0.1, B.JewelryIcons.Tick)
	B.Jewelry.Subscribe(OnJewelry)
	B.Jewelry.Refresh()
	B.ApplyMode()
	B.Rebuild()
end

function M:OnDisable()
	H.Wipe(B.listeners)
	Cover(false, "build.list")
	Cover(false, "uf.jewelry")
	if B.List.Frame() then
		H.Vis.Unregister(B.List.Frame())
	end
	if B.JewelryIcons.Frame() then
		H.Vis.Unregister(B.JewelryIcons.Frame())
	end
	B.Jewelry.Unsubscribe(OnJewelry)
	for i = table.getn(B.parts), 1, -1 do
		if B.parts[i].disable then
			B.parts[i].disable(self)
		end
	end
	S.effective = "off"
	S.fallbackShown = false
end

function M:OnMode(mode)
	B.ApplyMode()
end

function M:OnWorld()
	B.Jewelry.Refresh()
	B.Rebuild()
end
