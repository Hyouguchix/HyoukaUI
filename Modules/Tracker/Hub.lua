-- HyoukaUI: Modules\Tracker\Hub, модуль "tracker": реестр частей, рассылка событий, покадровый драйвер, захват
-- частей HUD игры, куски раскладки, кэши строк. Здесь нет рисования: части лежат в соседних файлах.
--
-- Модуль один (H.NewModule("tracker")), частей несколько: panel, timeline, schedule, guardians, bosstimers,
-- bossframes, thisrun, minimap, pins. Часть регистрируется Tr.Part(name, def), поля def (все необязательные):
--   build()            создать кадры (один раз, при первом включении модуля, не при загрузке файла)
--   show() / hide()    включить / выключить часть (куски регистрируются в Layout, подписки живут в Hub)
--   on = { EVENT = fn(event, a1, a2, a3, a4) }   события шины; Hub подписан один раз на событие (владелец у
--                      шины один на пару событие-владелец, поэтому части делят одну подписку)
--   tick(now)          раз в TICK (0.05 с), без аллокаций
--   slow(now)          раз в секунду
--   place()            решить, показан ли главный кадр (Tr.Set), зовется на смене фазы, карточек, настроек
--   settings(key)      ключ настройки изменился
--   replace(on)        включился или выключился режим "Вместо" (Hud и Park только там)
--   reset()            начался новый забег
--   dump(out)          строки для /hui dump tracker
-- Ошибка части не выключает модуль: считается у части, после 5 ошибок часть гасится, остальные работают.
--
-- Режимы (plan раздел 4): Выкл - кадров нет; Рядом - рисуем, части игры не трогаем; Вместо - Claim частей HUD
-- (с правилом Cover, если оно описано в GameRules) и Park стоковых кадров. Если трекер SurvivorUI жив, модуль
-- остается в Рядом и пишет одну строку.

local H = HyoukaUI

local getn = table.getn

local Tr = H.Tr or {}
H.Tr = Tr

local M = H.NewModule("tracker", {
	label = Tr.T("label"), schema = 1, migrations = {},
	defaults = {
		mode = "off",
		panel = true, panelBg = true, timeline = true, schedule = true, guardians = true, tally = true, goal = true,
		bars = true, horizon = 120, relocate = 15,
		messages = true, countdown = true, hideBanners = true,
		bossFrames = true, thisRun = true, thisRunFolded = false, crits = true,
		skin = true, clock = true, pins = true, pinRange = 120, pinBosses = false, flagHide = true,
	},
})
Tr.M = M

Tr.TICK = 0.05
Tr.STEADY = 0.35      -- допуск устойчивости отсчетов, секунды (то же, что Run.STEADY_TOL)

-- Палитра модуля (spec 1.2, plan 3.2). Массивы { r, g, b, a }.
Tr.C = {
	gray = { 0.486, 0.486, 0.486, 1 }, white = { 1, 1, 1, 1 }, orange = { 1, 0.655, 0.2, 1 },
	green = { 0.302, 0.8, 0.4, 1 }, red = { 0.906, 0.165, 0.22, 1 }, warnRed = { 0.9, 0.3, 0.3, 1 },
	zone = { 0.902, 0.851, 0.051, 0.9 }, gold = { 1, 0.788, 0.137, 1 }, pink = { 1, 0.55, 0.75, 1 },
	purple = { 0.69, 0.48, 1, 1 }, bossKind = { 0.455, 0.443, 0.765, 1 }, count = { 0.882, 0.882, 0.882, 1 },
	barBg = { 0.0314, 0.0314, 0.0314, 0.406 }, barFill = { 0.486, 0.486, 0.486, 0.9 }, barEmph = { 0.906, 0.165, 0.22, 0.9 },
	rest = { 0.067, 0.067, 0.067, 0.9 }, lost = { 0.31, 0.31, 0.31, 1 }, empty = { 0.0314, 0.0314, 0.0314, 0.8 },
	dead = { 0.667, 0.192, 0.192, 1 },
}

local S = {
	built = false, enabled = false, replace = false, acc = 0, lastSlow = 0, subscribed = {},
	pieces = {}, claims = {}, warned = false,
}
Tr.S = S

Tr.parts, Tr.plist = {}, {}

----------------------------------------------------------------------------------------
-- Мелочь: настройки, цвет, строки с кэшем
----------------------------------------------------------------------------------------

function Tr.Opt(key)
	return M.db[key]
end

-- Размер или шаг куска из таблицы раскладки (Data\LayoutDefaults через Layout), запасное значение - spec.
-- Геометрия кусков живет в данных раскладки: модуль берет оттуда ширины и шаги, позиций в коде нет.
function Tr.Def(id, key, default)
	local d = H.Layout and H.Layout.Def and H.Layout.Def(id)
	local v = d and d[key]
	if v == nil then
		return default
	end
	return v
end

-- Падение якоря для куска, которому нужен чужой кусок (модуль Frames может быть выключен): берется от центра экрана
-- из таблицы раскладки родителя parentId (CENTER от CENTER), смещение и угол берутся из def самого куска id.
-- Возвращает таблицу fallback для Layout или nil, если родитель задан не от центра.
function Tr.FallbackFrom(id, parentId)
	local d, p = H.Layout.Def(id), H.Layout.Def(parentId)
	if not d or not p or p.point ~= "CENTER" or p.relPoint ~= "CENTER" or p.rel ~= "UIParent" then
		return nil
	end
	local w, h = p.w or 0, p.h or 0
	local ax = (p.x or 0) - w / 2
	local ay = (p.y or 0) + h / 2
	if d.relPoint == "TOPRIGHT" or d.relPoint == "BOTTOMRIGHT" then
		ax = ax + w
	end
	if d.relPoint == "BOTTOMLEFT" or d.relPoint == "BOTTOMRIGHT" then
		ay = ay - h
	end
	return { point = d.point, relPoint = "CENTER", x = ax + (d.x or 0), y = ay + (d.y or 0) }
end

function Tr.Put(key, value)
	H.DB.Set("tracker", key, value)
end

function Tr.Paint(tex, c)
	tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

function Tr.Color(fs, c)
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

function Tr.Accent()
	local T = H.Theme
	if T and T.AccentRGB then
		return T.AccentRGB()
	end
	return 0.451, 0.506, 1
end

-- Плоская заливка кадра цветом c; возвращает текстуру.
function Tr.Fill(frame, c, layer)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(H.Kit.FLAT)
	Tr.Paint(t, c)
	return t
end

local TIMES, INS = {}, {}

-- "m:ss" из кэша: покадровый код не создает строк после прогрева.
function Tr.TimeStr(sec)
	local s = TIMES[sec]
	if not s then
		s = H.Format.Time(sec)
		TIMES[sec] = s
	end
	return s
end

-- "через m:ss".
function Tr.InStr(sec)
	local s = INS[sec]
	if not s then
		s = Tr.T("boss_in").." "..Tr.TimeStr(sec)
		INS[sec] = s
	end
	return s
end

function Tr.ClearStrings()
	H.Wipe(TIMES)
	H.Wipe(INS)
end

-- Идет ли забег: фаза есть и это не лобби.
function Tr.InRun()
	local ph = H.Run.Phase()
	return ph ~= nil and ph ~= "ready"
end

-- Кадр показан или скрыт без вмешательства в экран выбора карт (его ведет Visibility).
function Tr.Set(frame, on)
	if H.Vis and H.Vis.IsChoosing() then
		if not on and frame:IsShown() then
			frame:Hide()
		end
		return
	end
	if on then
		if not frame:IsShown() then
			frame:Show()
		end
	elseif frame:IsShown() then
		frame:Hide()
	end
end

function Tr.IsReplace()
	return S.replace
end

function Tr.IsEnabled()
	return S.enabled
end

-- Трекер SurvivorUI жив: его кадр существует и показан (plan раздел 4, проверка перед режимом Вместо).
function Tr.SurvivorActive()
	local f = H.Global("SurvivorUITracker")
	return type(f) == "table" and f.IsShown ~= nil and f:IsShown() and true or false
end

----------------------------------------------------------------------------------------
-- Части
----------------------------------------------------------------------------------------

function Tr.Part(name, def)
	def.name = name
	def.active = false
	def.fails = 0
	Tr.parts[name] = def
	table.insert(Tr.plist, def)
	return def
end

function Tr.Fail(p, err)
	H.Errors.Add("tracker", tostring(p.name)..": "..tostring(err))
	p.fails = p.fails + 1
	if p.fails >= 5 and p.active then
		p.active = false
		if p.hide then
			pcall(p.hide)
		end
		H.Print(string.format(Tr.T("msg_part_off"), tostring(p.name)))
	end
end

local function Safe(p, fn, a1, a2, a3, a4, a5)
	local ok, err = pcall(fn, a1, a2, a3, a4, a5)
	if not ok then
		Tr.Fail(p, err)
	end
end

local function Dispatch(ev, a1, a2, a3, a4)
	local list = Tr.plist
	for i = 1, getn(list) do
		local p = list[i]
		if p.active then
			local fn = p.on and p.on[ev]
			if fn then
				Safe(p, fn, ev, a1, a2, a3, a4)
			end
		end
	end
end

local function PlaceAll()
	local list = Tr.plist
	for i = 1, getn(list) do
		local p = list[i]
		if p.active and p.place then
			Safe(p, p.place)
		end
	end
end
Tr.PlaceAll = PlaceAll

local function Each(method, a1)
	local list = Tr.plist
	for i = 1, getn(list) do
		local p = list[i]
		if p.active and p[method] then
			Safe(p, p[method], a1)
		end
	end
end
Tr.Each = Each

-- Повторное чтение данных всеми частями: после включения, смены режима, смены забега.
function Tr.RefreshAll()
	Each("refresh")
	PlaceAll()
end

----------------------------------------------------------------------------------------
-- Куски раскладки
----------------------------------------------------------------------------------------

function Tr.Register(id, frame, def)
	H.Layout.Piece(id, frame, def)
	H.Vis.Register(frame, { id = id })
	S.pieces[id] = frame
end

function Tr.UnregisterAll()
	for id, frame in pairs(S.pieces) do
		H.Vis.Unregister(frame)
		frame:Hide()
		H.Layout.Unpiece(id)
		S.pieces[id] = nil
	end
end

local function SetReplace(on)
	if on == S.replace then
		return
	end
	S.replace = on
	Each("replace", on)
	Tr.SyncHud()
end

-- Режим модуля -> внутреннее состояние. Вместо при живом трекере SurvivorUI остается Рядом.
function Tr.ApplyMode(mode)
	local replace = (mode == "replace")
	if replace and Tr.SurvivorActive() then
		replace = false
		if not S.warned then
			S.warned = true
			H.Print(Tr.T("msg_stay_side"))
		end
	end
	SetReplace(replace)
end

----------------------------------------------------------------------------------------
-- Покадровый драйвер: один колбэк модуля
----------------------------------------------------------------------------------------

--@frame
function Tr.Frame(dt)
	S.acc = S.acc + dt
	if S.acc < Tr.TICK then
		return
	end
	S.acc = 0
	local now = H.Now()
	local slow = false
	if now - S.lastSlow >= 1 then
		S.lastSlow = now
		slow = true
	end
	local list = Tr.plist
	for i = 1, getn(list) do
		local p = list[i]
		if p.active then
			if p.tick then
				local ok, err = pcall(p.tick, now)
				if not ok then
					Tr.Fail(p, err)
				end
			end
			if slow and p.slow then
				local ok, err = pcall(p.slow, now)
				if not ok then
					Tr.Fail(p, err)
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- События
----------------------------------------------------------------------------------------

local function OnPlace(ev)
	PlaceAll()
end

local function OnPhase(ev, a1, a2)
	Dispatch(ev, a1, a2)
	PlaceAll()
end

local function OnRunStarted(ev, a1, a2)
	Each("reset")
	Dispatch(ev, a1, a2)
	Tr.RefreshAll()
end

local function OnSetting(ev, mod, key)
	if mod ~= "tracker" or not S.enabled or key == "mode" then
		return
	end
	Tr.SyncHud()
	Each("settings", key)
	Tr.RefreshAll()
end

local function OnTheme(ev)
	Tr.ClearStrings()
	Each("theme")
	Each("refresh")
end

local HUB_EVENTS = {
	PHASE_CHANGED = OnPhase, RUN_STARTED = OnRunStarted, RUN_LEFT = OnPhase, RUN_ENDED = OnPhase,
	CARDS = OnPlace, SETTING = OnSetting, THEME = OnTheme,
}

local function Subscribe()
	for ev, fn in pairs(HUB_EVENTS) do
		S.subscribed[ev] = true
		M:On(ev, fn)
	end
	local list = Tr.plist
	for i = 1, getn(list) do
		local on = list[i].on
		if on then
			for ev in pairs(on) do
				if not S.subscribed[ev] then
					S.subscribed[ev] = true
					M:On(ev, Dispatch)
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------------------------

function Tr.Build()
	if S.built then
		return
	end
	S.built = true
	local list = Tr.plist
	for i = 1, getn(list) do
		if list[i].build then
			Safe(list[i], list[i].build)
		end
	end
end

-- Только то, что не создает кадров: отладка. Кадры и подписки появляются в OnEnable.
function M:OnInit()
	M.label = Tr.T("label")
	H.On("LOCALE", "tracker.label", function()
		M.label = Tr.T("label")
	end)
	if Tr.RegisterOptions then
		Tr.RegisterOptions()
	end
	local D = H.Debug
	if D and D.Extra then
		D.Extra.tracker = function(out)
			Tr.DumpLines(out)
		end
		D.Extra.pins = function(out)
			local p = Tr.parts.pins
			if p and p.dump then
				p.dump(out)
			end
		end
	end
end

function M:OnEnable()
	S.enabled = true
	S.acc, S.lastSlow = 0, 0
	Tr.Build()
	local list = Tr.plist
	for i = 1, getn(list) do
		local p = list[i]
		p.active = true
		p.fails = 0
		if p.show then
			Safe(p, p.show)
		end
	end
	Subscribe()
	M:OnFrame(Tr.Frame)
	Tr.ApplyMode(H.GetMode("tracker"))
	Tr.SyncHud()
	Tr.RefreshAll()
end

function M:OnDisable()
	S.enabled = false
	SetReplace(false)
	local list = Tr.plist
	for i = getn(list), 1, -1 do
		local p = list[i]
		p.active = false
		if p.hide then
			pcall(p.hide)
		end
	end
	Tr.UnregisterAll()
	for ev in pairs(S.subscribed) do
		S.subscribed[ev] = nil
	end
	S.warned = false
end

-- Смена режима на включенном модуле: Рядом <-> Вместо.
function M:OnMode(mode)
	if S.enabled and mode ~= "off" then
		Tr.ApplyMode(mode)
		Tr.RefreshAll()
	end
end

----------------------------------------------------------------------------------------
-- Отладка: /hui dump tracker
----------------------------------------------------------------------------------------

function Tr.DumpLines(out)
	table.insert(out, "== Трекер ==")
	table.insert(out, "режим "..H.GetMode("tracker").."  включен "..tostring(S.enabled).."  вместо "..tostring(S.replace)
		.."  кадры собраны "..tostring(S.built))
	local claimed = Tr.ClaimedParts()
	table.insert(out, "захвачено частей игры "..getn(claimed)..": "..table.concat(claimed, " "))
	local line = ""
	for i = 1, getn(Tr.plist) do
		local p = Tr.plist[i]
		line = line..p.name.."="..(p.active and "on" or "off")..(p.fails > 0 and ("(ошибок "..p.fails..")") or "").." "
	end
	table.insert(out, "части: "..line)
	for i = 1, getn(Tr.plist) do
		local p = Tr.plist[i]
		if p.dump and p.name ~= "pins" then
			p.dump(out)
		end
	end
end
