-- HyoukaUI: Modules\Plates\Plates, модуль "plates" (неймплейты): настройки, режимы, покадровый драйвер, события, API.
--
-- Плашки врагов и друзей рисует клиент 1.12: это безымянные дети WorldFrame, которые он выдает юнитам из своего пула.
-- Модуль берет их по очереди (Skin), каждый кадр читает у плашки имя, цвет и здоровье стоковой полосы (Update),
-- определяет вид врага (Kinds: якоря мира, AZS_UnitKind цели, имена), красит по виду (Style) и ведет цель, наведение и
-- сквозные клики (Targeting). Читает AZS_* только Data\Plates.
--
-- РЕЖИМЫ. Выкл: плашки как в игре, наших кадров на экране нет. Рядом: стоковая графика не трогается, поверх плашек
-- элит, стражей и боссов рисуется только метка вида (череп). Вместо: стоковая графика гасится и рисуется плоская полоса
-- 1 px с именем, долей здоровья, цветом и размером по виду, меткой, подсветкой цели и наведения, сквозные клики, по
-- желанию дебаффы на плашке цели. Режим Вместо превращается в Рядом, пока работает SurvivorPlates (две раскраски одной
-- плашки не нужны); его плашки (plate.survivorOverlay) модуль не трогает никогда.
-- Все обратимо: Выкл, выход и приостановка модуля возвращают стоковую графику плашек и CVar раскладки.
--
-- Публичное: H.Plates (Pl): Mode() настроенный режим, Effective() режим на деле, Count() плашек в пуле и видимых и
-- нарисованных, Shows(unitId) нарисована ли плашка юнита (как SurvivorPlates_PlateShows), Restyle(), Selftest().
-- События, которые шлет модуль: PLATES_CHANGED(нарисовано) на смене числа нарисованных плашек (не чаще раза в 0.25 с).
-- Подписки: SETTING, THEME, FONTS, PLAYER_TARGET_CHANGED, PARTY_MEMBERS_CHANGED, UNITS_CHANGED, CARDS, LOGOUT.
-- Размеры хранятся в ретейл-пикселях (физический пиксель при 1440p), без раскладки: плашки плавают над юнитами.

local H = HyoukaUI

local getn = table.getn

local Pl = {}
H.Plates = Pl

Pl.ENEMY = { "normal", "elite", "guardian", "boss", "final" }
Pl.FRIEND = { "party", "pet", "totem" }
Pl.ORDER = { "normal", "elite", "guardian", "boss", "final", "party", "pet", "totem" }

-- Что известно о виде: размеры в ретейл-пикселях (ширина, высота полосы, имя, доля), цвет, метка (текстура и размер),
-- подъем кадра над остальными, switch: чьим переключателем показа управляется.
Pl.KINDS = {
	normal = { w = 150, h = 14, name = 12, share = 11, color = { 0.635, 0.220, 0.220 }, switch = "normal" },
	elite = { w = 176, h = 17, name = 13, share = 12, color = { 0.200, 0.660, 0.300 }, switch = "elite",
		skull = "plate_skull", mark = 14, rise = 10 },
	guardian = { w = 196, h = 20, name = 13, share = 12, color = { 0.200, 0.450, 0.850 }, switch = "guardian",
		skull = "plate_horns", mark = 18, rise = 20 },
	boss = { w = 220, h = 27, name = 14, share = 13, color = { 0.640, 0.300, 0.880 }, switch = "boss",
		skull = "plate_boss", mark = 22, rise = 30 },
	final = { w = 240, h = 27, name = 14, share = 13, color = { 1.000, 0.550, 0.100 }, switch = "boss",
		skull = "plate_boss", mark = 22, rise = 30 },
	party = { w = 110, h = 9, name = 11, share = 9, color = { 0.450, 0.780, 1.000 }, switch = "party", rim = true },
	pet = { w = 110, h = 9, name = 11, share = 9, color = { 0.300, 0.880, 0.620 }, switch = "pet", rim = true },
	totem = { w = 90, h = 8, name = 10, share = 8, color = { 0.300, 0.880, 0.620 }, switch = "totem", rim = true },
}

local defaults = {
	mode = "off",
	show_normal = true, show_elite = true, show_guardian = true, show_boss = true,
	show_party = true, show_pet = true, show_totem = true,
	targetAlways = true,        -- плашка цели видна, даже если ее вид выключен
	names = "all",              -- имена: all, special (кроме обычных врагов), none
	shareText = true, marks = true, targetDebuffs = true,
	dimOthers = true, dimPct = 70, normalPct = 80,
	clickThrough = true, overlap = true, lockKeys = true,
	scale = 1, editKind = "normal",
}
for i = 1, getn(Pl.ORDER) do
	local kind = Pl.ORDER[i]
	local k = Pl.KINDS[kind]
	k.kw, k.kh, k.kn, k.ks, k.km = "w_"..kind, "h_"..kind, "n_"..kind, "s_"..kind, "m_"..kind
	defaults[k.kw], defaults[k.kh], defaults[k.kn], defaults[k.ks] = k.w, k.h, k.name, k.share
	if k.skull then
		defaults[k.km] = k.mark
	end
end

-- Английские строки лежат в PlatesOptions.lua (Pl.STR.enUS); русские - запасной текст в вызовах Pl.T.
Pl.STR = { enUS = {} }

function Pl.T(key, ru)
	local loc = H.Locale
	if loc and loc.code == "enUS" then
		local v = Pl.STR.enUS[key]
		if v then
			return v
		end
	end
	return H.Kit.L(key, ru)
end

local M = H.NewModule("plates", { label = "Nameplates", schema = 1, migrations = {}, defaults = defaults })
Pl.M = M

local S = {
	list = {}, vis = {}, visN = 0, hasTarget = false, targetName = nil, targetKind = nil, tOverlay = nil,
	kindsVer = 1, anchorVer = 0, scanned = 0, round = 0, choosing = false, eff = "off", hovered = nil,
	drawn = 0, drawnNow = 0, lastDrawn = -1, foreignSkipped = 0, warned = false,
	prevLayout = nil, prevEnemies = nil, prevFriends = nil, partyCount = 0, wantEnemies = true, wantFriends = true,
}
Pl.S = S

-- Настройки одним куском: читаются при смене настроек, а не каждый кадр.
Pl.cfg = { show = {}, st = {} }
for i = 1, getn(Pl.ORDER) do
	Pl.cfg.st[Pl.ORDER[i]] = { r = 1, g = 1, b = 1 }
end

-- Строки долей без конкатенации в кадре: PCT[0..100].
Pl.PCT = {}
for i = 0, 100 do
	Pl.PCT[i] = i.."%"
end

----------------------------------------------------------------------------------------
-- Настройки и режим
----------------------------------------------------------------------------------------

function Pl.Mode()
	return M.db.mode
end

-- Режим на деле: Вместо превращается в Рядом, пока SurvivorPlates красит те же плашки.
function Pl.Effective()
	local mode = M.db.mode
	if mode == "replace" and H.PlatesData.ForeignActive() then
		return "side"
	end
	return mode
end

function Pl.Reload()
	local db, cfg = M.db, Pl.cfg
	local scale = H.Clamp(tonumber(db.scale) or 1, 0.5, 2)
	cfg.scale = scale
	cfg.names = db.names
	cfg.shareText = db.shareText and true or false
	cfg.marks = db.marks and true or false
	cfg.debuffs = db.targetDebuffs and true or false
	cfg.targetAlways = db.targetAlways and true or false
	cfg.clickThrough = db.clickThrough and true or false
	cfg.overlap = db.overlap and true or false
	cfg.lockKeys = db.lockKeys and true or false
	cfg.dimAlpha = db.dimOthers and H.Clamp(db.dimPct, 10, 100) / 100 or 1
	cfg.normalAlpha = H.Clamp(db.normalPct, 10, 100) / 100
	local enemies, friends = false, false
	for i = 1, getn(Pl.ORDER) do
		local kind = Pl.ORDER[i]
		local k = Pl.KINDS[kind]
		local st = cfg.st[kind]
		st.w, st.h = db[k.kw] * scale, db[k.kh] * scale
		st.name, st.share = db[k.kn] * scale, db[k.ks] * scale
		st.r, st.g, st.b = k.color[1], k.color[2], k.color[3]
		st.rim, st.rise, st.skull = k.rim, k.rise or 0, k.skull
		st.mark = k.skull and db[k.km] * scale or 0
		st.friend = k.rim and true or false
		local on = db["show_"..k.switch] and true or false
		cfg.show[kind] = on
		if on then
			if st.friend then
				friends = true
			else
				enemies = true
			end
		end
	end
	S.wantEnemies, S.wantFriends = enemies, friends
end

-- Стоковые плашки нужны клиенту включенными: враги, пока включен хоть один вид (или есть цель-враг при "цель всегда"),
-- друзья, пока включен хоть один их вид.
local function EnemiesWanted()
	if S.wantEnemies then
		return true
	end
	return Pl.cfg.targetAlways and H.PlatesData.TargetHostile()
end

local function ApplyShown()
	H.PlatesData.ApplyShown(EnemiesWanted(), S.wantFriends, true)
end

local function Engage(eff)
	local PD = H.PlatesData
	if eff == "replace" then
		if S.prevEnemies == nil then
			S.prevEnemies = H.Global("NAMEPLATES_ON") and 1 or 0
			S.prevFriends = H.Global("FRIENDNAMEPLATES_ON") and 1 or 0
		end
		if Pl.cfg.overlap and S.prevLayout == nil then
			local was = PD.Overlap()
			if was ~= nil then
				S.prevLayout = was and 1 or 0
				PD.SetOverlap(true)
			end
		end
		ApplyShown()
	else
		Pl.Release()
	end
end

-- Вернуть CVar раскладки и включение плашек, как было до режима Вместо. Включение возвращается, только если оно было
-- известно (у игры нет вопроса "включены ли плашки": глобалы NAMEPLATES_ON и FRIENDNAMEPLATES_ON могли быть пусты).
function Pl.Release()
	local PD = H.PlatesData
	if S.prevLayout ~= nil then
		PD.SetOverlap(S.prevLayout == 1)
		S.prevLayout = nil
	end
	if S.prevEnemies ~= nil then
		if S.prevEnemies == 1 then
			PD.ApplyShown(true, S.prevFriends == 1, false)
		end
		S.prevEnemies, S.prevFriends = nil, nil
	end
end

-- Привести все плашки к режиму и настройкам. Зовется при включении, смене режима и настроек.
function Pl.Apply()
	if not M.enabled then
		return
	end
	Pl.Reload()
	local eff = Pl.Effective()
	if M.db.mode == "replace" and eff ~= "replace" and not S.warned then
		S.warned = true
		H.Print(Pl.T("pl_foreign_print", "неймплейты остались в режиме Рядом: загружен SurvivorPlates. Отключите его в списке аддонов и перезайдите."))
	end
	if M.db.mode ~= "replace" then
		S.warned = false
	end
	S.eff = eff
	for i = 1, getn(S.list) do
		Pl.Skin.Engage(S.list[i], eff)
		if eff == "replace" and not Pl.cfg.clickThrough then
			S.list[i].plate:EnableMouse(true)
		end
	end
	Engage(eff)
	S.kindsVer = S.kindsVer + 1
end

function Pl.Restyle()
	for i = 1, getn(S.list) do
		local o = S.list[i]
		o.kind = nil
		o.escale = nil
	end
	S.kindsVer = S.kindsVer + 1
end

function Pl.Count()
	return getn(S.list), S.visN, S.drawn
end

-- Нарисована ли плашка юнита с таким id якоря (для частей, которые не должны дублировать ее: метки мира).
function Pl.Shows(unit)
	if unit == nil or S.eff ~= "replace" then
		return false
	end
	local want = tostring(unit)
	for i = 1, S.visN do
		local o = S.vis[i]
		if o.shown and o.unit ~= nil and tostring(o.unit) == want then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------
-- Плашка за кадр
----------------------------------------------------------------------------------------

-- Нужна ли полоса: вид включен, либо это цель при "цель всегда". Друзья без включенного вида полосы не имеют.
local function Wanted(cfg, kind, isTarget, friend)
	if cfg.show[kind] then
		return true
	end
	return isTarget and cfg.targetAlways and not friend
end

--@frame
function Pl.Update(o, now)
	if o.plate.survivorOverlay then
		-- SurvivorPlates оформил эту плашку (после нас или раньше): свои кадры на ней гасим, стоковое не трогаем.
		if o.eff ~= "foreign" then
			Pl.Skin.Yield(o)
		end
		return
	end
	local stock = o.stock
	local Kn, St = Pl.Kinds, Pl.Style
	local name = stock.name:GetText()
	local lo, hi = stock.health:GetMinMaxValues()
	local r, g, b = stock.health:GetStatusBarColor()
	local friendly = (r and g and b and r < 0.2 and (g > 0.8 or b > 0.8)) and true or false
	if name ~= o.lastName or friendly ~= o.lastFriend or hi ~= o.lastHigh or o.kindsVer ~= S.kindsVer then
		Kn.Reclassify(o, name, lo, hi, friendly)
	end
	local es = o.plate:GetEffectiveScale()
	if es ~= o.escale then
		St.Rescale(o, es)
	end
	local isTarget = S.hasTarget and name == S.targetName and o.plate:GetAlpha() == 1
	local kind = Kn.Resolve(o, name, isTarget, now)
	if isTarget then
		S.tOverlay = o
	end
	if kind ~= o.kind or not o.st then
		St.Dress(o, kind or "normal")
	end
	local cfg = Pl.cfg
	if S.eff ~= "replace" then
		St.Marker(o, kind, cfg)
		return
	end
	local shown = Wanted(cfg, kind, isTarget, o.st.friend) and not S.choosing and true or false
	if shown ~= o.shown then
		o.shown = shown
		if shown then
			o.bar:Show()
		else
			o.bar:Hide()
		end
		if stock.raid then
			stock.raid:SetAlpha(shown and 1 or 0)
		end
	end
	if not shown then
		return
	end
	S.drawnNow = S.drawnNow + 1
	if cfg.clickThrough and o ~= S.hovered and o.plate:IsMouseEnabled() then
		o.plate:EnableMouse(false)
	end
	local share = 0
	if lo and hi and hi > lo then
		share = (stock.health:GetValue() - lo) / (hi - lo)
		if share < 0 then
			share = 0
		elseif share > 1 then
			share = 1
		end
	end
	St.SetShare(o, share)
	local edge = isTarget and 1 or 0
	local alpha = 1
	if S.hasTarget and not isTarget then
		alpha = cfg.dimAlpha
	end
	if kind == "normal" and not isTarget then
		alpha = alpha * cfg.normalAlpha
	end
	if edge ~= o.pEdge or alpha ~= o.pAlpha or not o.painted then
		o.pEdge, o.pAlpha = edge, alpha
		St.Paint(o)
	end
	local marked = stock.raid and stock.raid:IsShown() and true or false
	if marked and not o.marked then
		St.PlaceRaid(o)
	end
	o.marked = marked
end

--@frame
function Pl.Frame(dt)
	local Sk = Pl.Skin
	Sk.Scan()
	local n, bright = Sk.Collect()
	S.hasTarget = bright == 1 and UnitExists("target") and true or false
	S.tOverlay = nil
	S.drawnNow = 0
	local now = GetTime()
	local vis = S.vis
	for i = 1, n do
		Pl.Update(vis[i], now)
	end
	S.drawn = S.drawnNow
end

----------------------------------------------------------------------------------------
-- Таймеры
----------------------------------------------------------------------------------------

-- Раз в 0.25 с: каталог якорей, цель, состав группы, число нарисованных.
function Pl.Slow()
	local PD = H.PlatesData
	-- Каталог якорей нужен, только пока на экране есть плашки (каждое чтение это ответ движка, мусор для сборщика).
	if S.visN > 0 and PD.Available() then
		PD.ReadAnchors()
	end
	if PD.version ~= S.anchorVer then
		S.anchorVer = PD.version
		S.kindsVer = S.kindsVer + 1
	end
	Pl.Target.Refresh()
	local members = PD.PartyCount()
	if members ~= S.partyCount then
		S.partyCount = members
		S.kindsVer = S.kindsVer + 1
	end
	if S.drawn ~= S.lastDrawn then
		S.lastDrawn = S.drawn
		H.Fire("PLATES_CHANGED", S.drawn)
	end
end

-- Раз в 0.1 с: проекция якорей и захват плашек.
function Pl.Claim()
	if S.visN > 0 and H.PlatesData.Project() then
		Pl.Kinds.Claim()
	end
end

-- Раз в 0.5 с: плашки включены, как выбрано (клавиши V и Shift+V игра принимает сама, поэтому говорится заново).
function Pl.Guard()
	if S.eff == "replace" and Pl.cfg.lockKeys then
		ApplyShown()
	end
end

----------------------------------------------------------------------------------------
-- Жизненный цикл и события
----------------------------------------------------------------------------------------

local function OnSetting(ev, mod, key)
	if mod ~= "plates" or not M.enabled then
		return
	end
	if key == "editKind" then
		return
	end
	Pl.Apply()
	Pl.Restyle()
end

local function OnTheme()
	Pl.Restyle()
end

local function OnTarget()
	Pl.Target.Refresh()
end

local function OnParty()
	S.kindsVer = S.kindsVer + 1
end

local function OnUnits()
	Pl.Kinds.Rebuild()
end

local function OnCards()
	S.choosing = H.Vis and H.Vis.IsChoosing() and true or false
end

local function OnLogout()
	if M.enabled then
		M:OnDisable()
	end
end

function M:OnInit()
	local D = H.Debug
	if D and D.SelftestParts and not Pl.selftestAdded then
		Pl.selftestAdded = true
		table.insert(D.SelftestParts, function(L)
			local lines = Pl.Selftest()
			for i = 1, getn(lines) do
				table.insert(L, lines[i])
			end
		end)
	end
	if D and D.Extra then
		D.Extra.plates = Pl.Dump
	end
end

function M:OnEnable()
	Pl.Reload()
	S.eff = Pl.Effective()
	S.choosing = H.Vis and H.Vis.IsChoosing() and true or false
	self:On("SETTING", OnSetting)
	self:On("THEME", OnTheme)
	self:On("FONTS", OnTheme)
	self:On("PLAYER_TARGET_CHANGED", OnTarget)
	self:On("PARTY_MEMBERS_CHANGED", OnParty)
	self:On("UNITS_CHANGED", OnUnits)
	self:On("CARDS", OnCards)
	self:On("LOGOUT", OnLogout)
	self:OnFrame(Pl.Frame)
	self:Every(0.25, Pl.Slow)
	self:Every(0.1, Pl.Claim)
	self:Every(0.5, Pl.Guard)
	self:Every(0.05, Pl.Target.HoverTick)
	self:Every(0.2, Pl.Target.DebuffTick)
	Pl.Kinds.Rebuild()
	Pl.Apply()
end

function M:OnDisable()
	for i = 1, getn(S.list) do
		Pl.Skin.Engage(S.list[i], "off")
	end
	Pl.Target.Reset()
	Pl.Release()
	S.eff = "off"
	S.visN = 0
	S.drawn, S.lastDrawn = 0, -1
end

----------------------------------------------------------------------------------------
-- Отладка: selftest и dump
----------------------------------------------------------------------------------------

function Pl.Selftest()
	local PD = H.PlatesData
	local lines = {}
	local total, vis, drawn = Pl.Count()
	table.insert(lines, "plates: режим "..tostring(M.db.mode)..", на деле "..tostring(S.eff)..", плашек в пуле "..total..", видимых "..vis
		..", нарисовано "..drawn..", чужих пропущено "..S.foreignSkipped)
	if PD.Foreign() then
		local state = PD.ForeignActive() and "красит плашки: Вместо работает как Рядом, отключите его" or "в режиме ожидания"
		table.insert(lines, "plates: ПРЕДУПРЕЖДЕНИЕ SurvivorPlates загружен и "..state)
	end
	return lines
end

function Pl.Dump(out)
	local PD = H.PlatesData
	local total, vis, drawn = Pl.Count()
	table.insert(out, "== Plates ==")
	table.insert(out, "режим "..tostring(M.db.mode).." на деле "..tostring(S.eff).."  плашек "..total.." видимых "..vis.." нарисовано "..drawn)
	table.insert(out, "якорей "..PD.Count().."  версия якорей "..PD.version.."  версия видов "..S.kindsVer.."  цель "..tostring(S.targetName).." "..tostring(S.targetKind))
	local by = {}
	for i = 1, S.visN do
		local k = S.vis[i].kind or "?"
		by[k] = (by[k] or 0) + 1
	end
	for i = 1, getn(Pl.ORDER) do
		local k = Pl.ORDER[i]
		if by[k] then
			table.insert(out, "  "..k..": "..by[k])
		end
	end
	table.insert(out, "SurvivorPlates загружен "..tostring(PD.Foreign()).." активен "..tostring(PD.ForeignActive()))
end
