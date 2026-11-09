-- HyoukaUI: Frames\Party, рамки соратников (кусок uf.party) (plan 3.1, spec 2.3 / 3.4, inv frames#30).
--
-- До 4 полос 199x43 ретейл-px (106.1x22.9 AS), шаг 44 вниз от левого верха контейнера 199x175; все числа берутся из
-- LayoutDefaults (pieces["uf.party"]: w, step, max), позиция куска из Layout. Своей рамки героя нет. Стиль как у рамок
-- игрока и цели (UnitFrame.Style): остаток #111111 0.9 на потерянном #4F4F4F, рамка 1 физический px, барStyle "class"
-- красит заливку цветом класса. Чисел HP нет. Имя цветом класса (класс из AZS_PARTY через H.Party, запасной UnitClass),
-- 8 символов, слева сверху (1,-2). Вне дальности альфа 0.35, у вашей цели белая рамка, у лидера корона (+1,+2).
-- Лежит (H.Party.Downed): заливка #AA3131 на всю полосу, под именем "ЛЕЖИТ 23 м"; если героя поднимает этот соратник
-- (H.Party.Revive: reviving, rshare), доля подъема - акцентная заливка поверх.
--
-- Источник здоровья и имен: стоковые юниты party1..party4 под pcall (F.Unit): жив ли юнит, UnitName, UnitHealth,
-- UnitHealthMax [НЕ ПРОВЕРЕНО: у героев AS эти юниты есть]. Если юнитов party нет совсем, а H.Party.InParty() говорит,
-- что группа есть, рамки берутся из строк AZS_PARTY (без героя) и показывают только имя, класс и "лежит".
-- Дальность: UnitIsVisible(unit) [НЕ ПРОВЕРЕНО]; лидер: UnitIsPartyLeader(unit); цель: UnitIsUnit(unit, "target").
-- Клик: выбор цели TargetUnit(unit). Меню по правому клику не делается (стоковый PartyMemberFrameNDropDown не проверен).
-- Режим Вместо: Park стоковых PartyMemberFrame1-4 (владелец "frames.party"; Reassert держит StockBar). Рядом: стоковые
-- остаются. Настройка showParty. События: UNIT_HEALTH/UNIT_MAXHEALTH, PLAYER_TARGET_CHANGED, PARTY_MEMBERS_CHANGED,
-- PARTY, DOWNED, REVIVE, опрос 0.1 с (кэши: без смены чисел ничего не пишется).

local H = HyoukaUI
local F = H.Frames
local T = H.Theme
local U = F.UnitFrame
local Bar = H.Bar
local Fm = H.Format

local S = { box = nil, m = {}, max = 4, step = 44, w = 199, parked = false }
F.Party = S

F.M.defaults.showParty = true

local part = F.Part("party", {})

local OWNER = "frames.party"
S.STOCK = { "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }
S.FAR_ALPHA = 0.35
S.NAME_CHARS = 8
S.CROWN = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local TOK = { "party1", "party2", "party3", "party4" }
local WHITE = { 1, 1, 1, 1 }

----------------------------------------------------------------------------------------
-- Кадры
----------------------------------------------------------------------------------------

local function Click(m)
	local pick = H.Env.TargetUnit
	if type(pick) == "function" and m.live then
		pcall(pick, TOK[m.i])
	end
end

local function NewMember(i, box)
	local m = { i = i, live = false, shown = false, alpha = 1 }
	local bar = Bar.New(box, { w = S.w, h = S.step - 1, bg = T.C.darkLost })
	bar:SetFrameStrata("LOW")
	bar:Hide()
	m.bar = bar
	-- доля подъема: акцентная заливка поверх полосы здоровья, под текстами
	local rev = bar:CreateTexture(nil, "ARTWORK")
	rev:SetTexture(T.TEX.flat)
	rev:Hide()
	m.rev = rev
	local fs = H.Text.New(bar, "small", { justify = "LEFT" })
	fs:SetPoint("TOPLEFT", bar, "TOPLEFT", H.R(1), -H.R(2))
	m.nameFs = fs
	local sub = H.Text.New(bar, "small", { justify = "LEFT" })
	sub:SetPoint("TOPLEFT", bar, "TOPLEFT", H.R(1), -H.R(16))
	m.sub = sub
	local crown = bar:CreateTexture(nil, "OVERLAY")
	crown:SetTexture(S.CROWN)
	crown:SetWidth(H.R(10))
	crown:SetHeight(H.R(10))
	crown:SetPoint("TOPRIGHT", bar, "TOPRIGHT", H.R(1), H.R(2))
	crown:Hide()
	m.crown = crown
	local btn = CreateFrame("Button", nil, bar)
	btn:SetAllPoints(bar)
	btn:RegisterForClicks("LeftButtonUp")
	F.M:Script(btn, "OnClick", function(self, button)
		Click(m)
	end)
	m.btn = btn
	U.Style(m)
	return m
end

function part.Build()
	local def = H.LayoutDefaults and H.LayoutDefaults.pieces and H.LayoutDefaults.pieces["uf.party"]
	if def then
		S.w, S.step, S.max = def.w or S.w, def.step or S.step, def.max or S.max
	end
	if S.max > 4 then
		S.max = 4
	end
	local box = CreateFrame("Frame", nil, UIParent)
	box:SetFrameStrata("LOW")
	box:Hide()
	S.box = box
	for i = 1, S.max do
		S.m[i] = NewMember(i, box)
	end
	S.Place()
end

-- Места полос: шаг в ретейл-px, пересчет при смене PX.
function S.Place()
	for i = 1, S.max do
		local m = S.m[i]
		if m then
			m.bar:ClearAllPoints()
			m.bar:SetPoint("TOPLEFT", S.box, "TOPLEFT", 0, -H.R(S.step * (i - 1)))
		end
	end
end

----------------------------------------------------------------------------------------
-- Данные
----------------------------------------------------------------------------------------

-- Кто в слотах: юниты party1..4, иначе строки AZS_PARTY без героя. Заполняет m.shown, m.live, m.name.
local function Resolve()
	local anyUnit = false
	for i = 1, S.max do
		local m = S.m[i]
		m.shown, m.live, m.name = false, false, nil
		if F.Unit("UnitExists", TOK[i]) then
			anyUnit = true
			m.shown, m.live = true, true
			m.name = F.Unit("UnitName", TOK[i]) or ""
		end
	end
	if anyUnit or not (H.Party.InParty() and H.Party.IsFresh()) then
		return
	end
	local me = H.Hero.Name()
	local slot = 0
	for k = 1, H.Party.Count() do
		local row = H.Party.Member(k)
		if row and row.name ~= me and slot < S.max then
			slot = slot + 1
			S.m[slot].shown, S.m[slot].name = true, row.name
		end
	end
end

-- Ключ класса участника ("warrior"): строка AZS_PARTY по имени, иначе токен клиента.
local function ClassOf(m)
	local name = m.name
	for k = 1, H.Party.Count() do
		local row = H.Party.Member(k)
		if row and row.name == name then
			return row.class
		end
	end
	if m.live then
		return F.UnitClassToken(TOK[m.i])
	end
	return nil
end

-- Лежит ли соратник и сколько до него ярдов (nil, если позиция недоступна).
local function DownInfo(name)
	local list = H.Party.Downed()
	for k = 1, H.Party.DownedCount() do
		if list[k].name == name then
			return true, list[k].dist
		end
	end
	return false, nil
end

----------------------------------------------------------------------------------------
-- Отрисовка (кэши по значению: без смены ничего не пишется)
----------------------------------------------------------------------------------------

local function SetLabel(m, down, dist)
	local key = -2
	if down then
		key = dist and math.floor(dist + 0.5) or -1
	end
	if m.lblKey == key then
		return
	end
	m.lblKey = key
	if not down then
		m.sub:SetText("")
	elseif key < 0 then
		m.sub:SetText(F.T("down", "ЛЕЖИТ"))
	else
		m.sub:SetText(F.T("down", "ЛЕЖИТ").." "..key.." "..F.T("unit_yd", "м"))
	end
	m.sub.huiText = nil
end

local function SetName(m, r, g, b)
	if m.shownName ~= m.name then
		m.shownName = m.name
		m.nameFs:SetText(Fm.Utf8Cut(m.name, S.NAME_CHARS))
		m.nameFs.huiText = nil
	end
	local key = r * 1000000 + g * 1000 + b
	if m.nameKey ~= key then
		m.nameKey = key
		m.nameFs:SetTextColor(r, g, b, 1)
	end
end

local function SetDown(m, down, r, g, b)
	if down then
		if not m.downFill then
			m.downFill = true
			local c = T.C.deadBar
			Bar.SetColor(m.bar, c[1], c[2], c[3])
		end
	else
		if m.downFill then
			m.downFill = false
			U.Style(m)
		end
		U.SetFill(m, r, g, b)
	end
end

local function SetRev(m, share)
	local w = 0
	if share > 0 then
		w = Bar.FillWidth(m.bar.huiInner or 0, share > 1 and 1 or share)
	end
	if m.revW == w then
		return
	end
	m.revW = w
	if w <= 0 then
		m.rev:Hide()
		return
	end
	local b = T.Border()
	local fr, fg, fb = T.Tint(T.AccentRGB())
	m.rev:ClearAllPoints()
	m.rev:SetPoint("TOPLEFT", m.bar, "TOPLEFT", b, -b)
	m.rev:SetPoint("BOTTOMLEFT", m.bar, "BOTTOMLEFT", b, b)
	m.rev:SetWidth(w)
	m.rev:SetVertexColor(fr, fg, fb, 1)
	m.rev:Show()
end

local function SetFlags(m, tok)
	local far = m.live and F.Env("UnitIsVisible") and not F.Unit("UnitIsVisible", tok)
	local alpha = far and S.FAR_ALPHA or 1
	if m.alpha ~= alpha then
		m.alpha = alpha
		m.bar:SetAlpha(alpha)
	end
	local tgt = m.live and F.Unit("UnitIsUnit", tok, "target") ~= nil
	if m.tgt ~= tgt then
		m.tgt = tgt
		local c = tgt and WHITE or T.C.border
		T.SetBorderColor(m.bar, c[1], c[2], c[3], c[4])
	end
	local lead = m.live and F.Unit("UnitIsPartyLeader", tok) ~= nil
	if m.lead ~= lead then
		m.lead = lead
		if lead then
			m.crown:Show()
		else
			m.crown:Hide()
		end
	end
end

--@frame
local function Paint(m, reviving, rshare)
	local tok = TOK[m.i]
	local r, g, b = H.Hero.ColorOf(ClassOf(m))
	local down, dist = DownInfo(m.name)
	SetName(m, r, g, b)
	SetDown(m, down, r, g, b)
	if down then
		Bar.Set(m.bar, 1, 1)
	elseif m.live then
		Bar.Set(m.bar, F.Unit("UnitHealth", tok) or 0, F.Unit("UnitHealthMax", tok) or 0)
	else
		Bar.Set(m.bar, 0, 0)
	end
	SetLabel(m, down, dist)
	SetRev(m, (down and reviving == m.name) and rshare or 0)
	SetFlags(m, tok)
end

function S.Update()
	if not S.box then
		return
	end
	Resolve()
	local _, _, _, reviving, rshare = H.Party.Revive()
	local count = 0
	for i = 1, S.max do
		local m = S.m[i]
		if m.shown and F.Opt("showParty") then
			count = count + 1
			if not m.bar:IsShown() then
				m.bar:Show()
			end
			Paint(m, reviving, rshare)
		elseif m.bar:IsShown() then
			m.bar:Hide()
		end
	end
	F.Show("uf.party", count > 0)
end

-- Полный пересчет: стиль, места, сброс кэшей.
function S.Apply()
	if not S.box then
		return
	end
	S.Place()
	for i = 1, S.max do
		local m = S.m[i]
		m.downFill, m.shownName, m.nameKey, m.lblKey, m.revW, m.tgt, m.lead, m.alpha = false, nil, nil, nil, nil, nil, nil, nil
		m.bar.huiVal = nil
		U.Style(m)
	end
	S.Update()
end

----------------------------------------------------------------------------------------
-- Парковка стоковых рамок группы (только Вместо)
----------------------------------------------------------------------------------------

function S.SyncPark(mode)
	local want = (mode == "replace") and F.Opt("parkStock") and true or false
	if want and not S.parked then
		S.parked = true
		for i = 1, table.getn(S.STOCK) do
			local fr = H.Env[S.STOCK[i]]
			if type(fr) == "table" and fr.SetParent then
				H.Park(fr, OWNER)
			end
		end
	elseif not want and S.parked then
		S.parked = false
		H.Unpark(OWNER)
	end
end

function part.Enable(mode)
	F.Piece("uf.party", S.box)
	F.M:Every(0.1, S.Update)
	S.SyncPark(mode)
	S.Apply()
end

function part.Disable()
	S.SyncPark("off")
	F.Unpiece("uf.party")
end

function part.Mode(mode)
	S.SyncPark(mode)
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "barStyle" then
		S.Apply()
	elseif key == "parkStock" then
		S.SyncPark(F.mode)
	end
end

F.On("THEME", S.Apply)
F.On("LAYOUT", S.Place)
F.On("PLAYER_TARGET_CHANGED", S.Update)
F.On("PARTY_MEMBERS_CHANGED", S.Update)
F.On("PARTY_CHANGED", S.Update)
F.On("PARTY", S.Update)
F.On("DOWNED", S.Update)
F.On("DOWNED_CHANGED", S.Update)
F.On("REVIVE", S.Update)
F.On("HERO_CHANGED", S.Update)
F.On("UNIT_HEALTH", function(ev, unit)
	if unit and string.sub(unit, 1, 5) == "party" then
		S.Update()
	end
end)
F.On("UNIT_MAXHEALTH", function(ev, unit)
	if unit and string.sub(unit, 1, 5) == "party" then
		S.Update()
	end
end)
F.On("LOGOUT", function()
	S.parked = false
end)
