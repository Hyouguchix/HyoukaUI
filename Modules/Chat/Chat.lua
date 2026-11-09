-- HyoukaUI: модуль Chat (чат как в ретейле). Plan 2.8 (кусок ui.chat), spec 3.8.
--
-- Один модуль "chat" из нескольких файлов. Этот файл создает H.Chat (C): настройки, режимы, жизненный цикл,
-- одиночный таймер (Tick раз в 0.05 с), события, публичный API.
--
--   Выкл     ничего не создается и не трогается.
--   Рядом    свой плоский чат рядом с игровым для сравнения: своя панель (кусок ui.chat, сдвинут вправо), вкладки,
--            СВОИ окна сообщений (копия потока через обертку AddMessage), стоковый чат и поле ввода не тронуты.
--   Вместо   стоковое окно ChatFrame1 (и пристыкованные) переодето: ставится на кусок, стоковые вкладки, кнопки
--            прокрутки, арт спрятаны (Park), поле ввода плоское, колесо листает. Вкладки поверх стоковых окон
--            плюс две вкладки-ленты модуля (Добыча и система, Группа).
-- Все возвращается: Disable идет в обратном порядке частей, на LOGOUT то же самое.
--
-- Файлы: Strings (строки), Stock (стоковые кадры и переодевание), Panel (панель, кусок Layout, размер), Feeds (обертка
-- AddMessage, ленты, метки времени), Tabs (вкладки), EditBox (поле ввода), Fade (затухание), ChatOptions (настройки).
-- Публичное: C.Opt, C.EffectiveMode, C.Select(key), C.Selected(), C.SetSize(wpx, hpx), C.Selftest().
-- События, которые шлет модуль: CHAT_MODE(mode) после включения, смены режима и выключения ("off").

local H = HyoukaUI

local C = {}
H.Chat = C

C.ID = "ui.chat"

C.DEFAULTS = {
	width = 425,              -- ретейл-px, spec 3.8 (панель 425x214)
	height = 214,
	bgAlpha = 0.80,           -- фон #080808 0.80
	textSize = 14,            -- ретейл-px, spec 3.8 (текст 14 outline)
	timestamps = true,        -- "%I:%M %p " серым
	lock = false,             -- спрятать уголок размера
	showCombat = false,       -- вкладка стокового окна Combat Log (около 13 строк в секунду)
	tabLoot = true,           -- лента "Добыча и система"
	tabParty = true,          -- лента "Группа"
	dedupe = false,           -- строка, ушедшая в ленту, не показывается во вкладке General (только Вместо)
	hideYells = false,        -- не показывать крики боссов
	hideBanners = false,      -- не показывать эмоции рейда (баннеры забега)
	fade = false,             -- затухание по таймеру (в ретейле выключено)
	fadeAfter = 12,           -- секунд покоя до затухания
	wheelLines = 3,           -- строк на щелчок колеса (spec 3.8)
}

local M = H.NewModule("chat", { label = "Чат", schema = 1, migrations = {}, defaults = C.DEFAULTS })
C.M = M

-- Стоковое событие 1.12, которое шина зарегистрирует на кадре ядра.
local STOCK = H.Events and H.Events.STOCK
if STOCK then
	STOCK.UPDATE_CHAT_WINDOWS = true
end

C.mode = "off"
C.live = false
C.stats = { rebuilds = 0, verifies = 0 }

local VERIFY_STEP = 1

local verifyLeft = VERIFY_STEP

function C.Opt(key)
	return M.db[key]
end

function C.T(key)
	local S = C.Str
	return S and S.Get(key) or key
end

----------------------------------------------------------------------------------------
-- Режим
----------------------------------------------------------------------------------------

-- Панель чата SurvivorUI на экране? Тогда режим Вместо не включается (две панели и две обертки AddMessage).
function C.SurvivorChatActive()
	local f = H.Env.SurvivorUIChatPanel
	if type(f) == "table" and f.IsShown then
		local ok, shown = pcall(f.IsShown, f)
		return ok and shown and true or false
	end
	return false
end

function C.EffectiveMode()
	local m = H.GetMode(M.name)
	if m == "replace" and C.SurvivorChatActive() then
		if not C.warned then
			C.warned = true
			H.Print(C.T("survivor"))
		end
		return "side"
	end
	C.warned = nil
	return m
end

local PARTS = { "Panel", "Stock", "Feeds", "Tabs", "Edit", "Fade" }

local function Enable(mode)
	C.mode = mode
	for i = 1, table.getn(PARTS) do
		local p = C[PARTS[i]]
		if p and p.Enable then
			H.Safe(M.name, p.Enable, mode)
		end
	end
end

local function Disable()
	for i = table.getn(PARTS), 1, -1 do
		local p = C[PARTS[i]]
		if p and p.Disable then
			H.Safe(M.name, p.Disable)
		end
	end
	C.mode = "off"
end

----------------------------------------------------------------------------------------
-- Обновление и сверка
----------------------------------------------------------------------------------------

function C.Refresh()
	if not C.live then
		return
	end
	for i = 1, table.getn(PARTS) do
		local p = C[PARTS[i]]
		if p and p.Refresh then
			H.Safe(M.name, p.Refresh)
		end
	end
end

-- Раз в секунду: стоковый код мог переставить окно, поле ввода, показать спрятанное или переименовать окно.
local function Verify()
	C.stats.verifies = C.stats.verifies + 1
	for i = 1, table.getn(PARTS) do
		local p = C[PARTS[i]]
		if p and p.Verify then
			p.Verify()
		end
	end
end

--@frame
function C.Tick(dt)
	if not C.live then
		return
	end
	C.Fade.Tick(dt)
	C.Tabs.Tick()
	verifyLeft = verifyLeft - dt
	if verifyLeft <= 0 then
		verifyLeft = VERIFY_STEP
		Verify()
	end
end

-- Полная пересборка вкладок (смена списка окон).
function C.Rebuild()
	if C.live then
		C.stats.rebuilds = C.stats.rebuilds + 1
		C.Tabs.Rebuild()
	end
end

----------------------------------------------------------------------------------------
-- Жизненный цикл модуля
----------------------------------------------------------------------------------------

local function OnSetting(ev, mod, key)
	if mod ~= M.name or key == "mode" then
		return
	end
	C.Refresh()
end

-- Смена языка: подпись куска в режиме перемещения и подписи вкладок пересобираются.
local function OnLocale()
	if C.live and C.Panel and C.Panel.frame and C.mode and C.mode ~= "off" then
		C.Panel.Register(C.mode)
	end
	C.Rebuild()
end

local function Subscribe()
	M:On("LOCALE", OnLocale)
	M:On("SETTING", OnSetting)
	M:On("THEME", C.Refresh)
	M:On("FONTS", C.Refresh)
	M:On("UPDATE_CHAT_WINDOWS", C.Rebuild)
	M:On("LOGOUT", C.Teardown)
	M:Every(0.05, C.Tick)
end

function M:OnEnable()
	local mode = C.EffectiveMode()
	if mode == "off" then
		return
	end
	C.live = true
	verifyLeft = VERIFY_STEP
	Enable(mode)
	Subscribe()
	H.Fire("CHAT_MODE", mode)
end

function M:OnDisable()
	C.Teardown()
	H.Fire("CHAT_MODE", "off")
end

-- Все вернуть на место (выключение модуля и выход из игры). Повтор безвреден.
function C.Teardown()
	if not C.live then
		return
	end
	C.live = false
	Disable()
end

-- Смена режима Рядом <-> Вместо при включенном модуле: запись в DB уже сделана ядром.
function M:OnMode(mode)
	if mode == "off" or not M.enabled or not C.live then
		return
	end
	local want = C.EffectiveMode()
	if want == C.mode then
		return
	end
	Disable()
	Enable(want)
	H.Fire("CHAT_MODE", want)
end

-- После входа в мир стоковый код мог переставить окна: сверка сразу.
function M:OnWorld()
	if C.live then
		Verify()
	end
end

----------------------------------------------------------------------------------------
-- Публичный API
----------------------------------------------------------------------------------------

function C.Select(key)
	if C.live then
		return C.Tabs.SelectKey(key)
	end
	return false
end

function C.Selected()
	return C.live and C.Tabs.SelectedKey() or nil
end

-- Размер панели в ретейл-px (с границами и записью в настройки).
function C.SetSize(wpx, hpx)
	return C.Panel.SetSize(wpx, hpx)
end

function C.Selftest()
	local out = {}
	table.insert(out, "chat: режим "..tostring(C.mode).." (запрошен "..tostring(H.GetMode(M.name))..")"..
		", вкладок "..tostring(C.Tabs and C.Tabs.Count() or 0)..", ошибок "..H.Errors.Count(M.name))
	if C.Feeds then
		table.insert(out, "chat: обертки AddMessage "..C.Feeds.WrapCount()..", строк в лентах "..C.Feeds.stats.lines..
			", сбоев маршрута "..C.Feeds.stats.errors)
	end
	return out
end
