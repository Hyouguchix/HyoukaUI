-- HyoukaUI: Modules\Tracker\Tracker, панель забега tr.tracker (plan 3.2): зона и теги, часы забега с длиной,
-- состояние (победа, лежит, пал, пауза, выбор), жизни, подсказка-сводка. Убийства, золото и сундуки вынесены в Tally.lua (tr.tally).
-- Остальные секции панели (полоса времени, стражи, расписание) приходят из соседних файлов через
-- Tr.AddSection: панель складывает видимые секции столбиком и сообщает Layout свою высоту.
--
-- Данные: H.Run (фаза, часы, длина, Get, Zone, Ended, IsDowned, Affixes). Часы текста идут из tick раз в 0.05 с,
-- строка меняется только при смене целой секунды (кэш строк в Hub). Остальное по событиям RUN, ZONE, PHASE.
-- Режим Вместо: часть игры clock закрывает эта панель; tally закрывает отдельный кусок tr.tally (Claims).

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local getn = table.getn
local floor = math.floor

local PW, PAD = 230, 3          -- ширина панели (из раскладки при сборке) и отступ сверху и снизу, ретейл-px
local ROW_HEAD, ROW_CLOCK = 18, 28

local P = { secs = {}, h = 0, sec = -1, lastLen = nil }
Tr.Panel = P

-- Ширина панели (ретейл-px) для секций, которым нужна ширина полосы.
function Tr.PanelWidth()
	return PW
end

local function R(px)
	return H.R(px)
end

----------------------------------------------------------------------------------------
-- Секции: столбик внутри панели
----------------------------------------------------------------------------------------

-- Секция: frame, высота h в ретейл-px, order задает место. Скрытая секция места не занимает.
function Tr.AddSection(key, frame, h, order)
	local s = { key = key, frame = frame, h = h, order = order or 50, on = false }
	table.insert(P.secs, s)
	table.sort(P.secs, function(a, b)
		return a.order < b.order
	end)
	frame:SetParent(P.panel)
	return s
end

function Tr.FindSection(key)
	for i = 1, getn(P.secs) do
		if P.secs[i].key == key then
			return P.secs[i]
		end
	end
	return nil
end

function Tr.SetSection(key, on, h)
	local s = Tr.FindSection(key)
	if not s then
		return
	end
	s.on = on and true or false
	if h then
		s.h = h
	end
	Tr.Relayout()
end

function Tr.Relayout()
	local panel = P.panel
	if not panel then
		return
	end
	local y = PAD
	for i = 1, getn(P.secs) do
		local s = P.secs[i]
		if s.on then
			s.frame:ClearAllPoints()
			s.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -R(y))
			s.frame:SetWidth(R(PW))
			s.frame:SetHeight(R(s.h))
			if not s.frame:IsShown() then
				s.frame:Show()
			end
			y = y + s.h
		elseif s.frame:IsShown() then
			s.frame:Hide()
		end
	end
	y = y + PAD
	if y ~= P.h then
		P.h = y
		if H.Layout.Has("tr.tracker") then
			H.Layout.SetSize("tr.tracker", nil, y)
		end
	end
end

----------------------------------------------------------------------------------------
-- Содержимое: зона, теги, часы, состояние
----------------------------------------------------------------------------------------

local function Heroic()
	local h = tonumber(H.Run.Zone("heroic")) or 0
	return h
end

local AFFIX = { bolstering = "BOL", sanguine = "SAN", explosive = "EXP", raging = "RAG", necrotic = "NEC", volcanic = "VOL" }

-- Строка тегов с цветовыми кодами: сложность, бесконечный режим, аффиксы. Собирается по событию.
local function TagsText()
	local C = Tr.C
	local out = ""
	local heroic = Heroic()
	if heroic > 0 then
		out = Fm.ColorCode(C.orange[1], C.orange[2], C.orange[3])..Tr.T("tag_heroic")..Fm.Int(heroic).."|r"
	else
		out = Fm.ColorCode(C.gray[1], C.gray[2], C.gray[3])..Tr.T("tag_normal").."|r"
	end
	if H.Run.IsEndless() then
		out = out.." "..Fm.ColorCode(C.purple[1], C.purple[2], C.purple[3])..Tr.T("tag_endless").."|r"
	end
	local aff = H.Run.Affixes()
	if aff then
		local list = ""
		for key in string.gfind(aff, "[^,]+") do
			local short = AFFIX[key] or string.upper(string.sub(key, 1, 3))
			list = list..(list == "" and "" or " ")..short
		end
		out = out.." "..Fm.ColorCode(C.warnRed[1], C.warnRed[2], C.warnRed[3])..list.."|r"
	end
	return out
end

local function Header()
	local name = H.Run.Zone("zname") or ""
	if P.zoneName ~= name then
		P.zoneName = name
		H.Text.Fit(P.zone, name, R(120))
	end
	-- Строка тегов собирается, только если изменились сложность, бесконечный режим или аффиксы.
	local heroic, endless, aff = Heroic(), H.Run.IsEndless(), H.Run.Affixes()
	if heroic ~= P.tagH or endless ~= P.tagE or aff ~= P.tagA then
		P.tagH, P.tagE, P.tagA = heroic, endless, aff
		local tags = TagsText()
		if P.tags ~= tags then
			P.tags = tags
			P.tagsFs:SetText(tags)
		end
	end
end

-- Состояние забега: ключ строки и цвет, nil если все идет.
local function StateOf()
	local C = Tr.C
	local ended = H.Run.Ended()
	if ended == "victory" then
		return "victory", C.green
	end
	if ended then
		return "fallen", C.warnRed
	end
	if H.Run.IsDowned() then
		return "down", C.warnRed
	end
	local ph = H.Run.Phase()
	if ph == "dead" then
		return "fallen", C.warnRed
	elseif ph == "paused" then
		return "paused", C.gray
	elseif ph == "choosing" then
		return "choosing", C.gray
	end
	return nil, nil
end

local function State()
	local key, color = StateOf()
	if key ~= P.stateKey then
		P.stateKey = key
		P.stateFs:SetText(key and Tr.T(key) or "")
		if key then
			Tr.Color(P.stateFs, color)
		end
	end
	local gray = (key == "paused" or key == "choosing")
	if gray ~= P.gray then
		P.gray = gray
		Tr.Color(P.clock, gray and Tr.C.gray or Tr.C.white)
	end
	local lives = H.Run.Get("lives") or 0
	if lives ~= P.lives then
		P.lives = lives
		if lives > 0 then
			P.livesFs:SetText("x"..Fm.Int(lives))
			P.livesFs:Show()
		else
			P.livesFs:Hide()
		end
	end
end

-- Длина забега справа от часов; в бесконечном режиме и без длины ее нет.
local function Length()
	local len = H.Run.Length()
	if H.Run.IsEndless() then
		len = nil
	end
	if len ~= P.lastLen then
		P.lastLen = len
		if len then
			P.len:SetText("/ "..Tr.TimeStr(floor(len)))
			P.len:Show()
		else
			P.len:Hide()
		end
	end
end

local function Refresh()
	if not P.panel then
		return
	end
	Header()
	State()
	Length()
	P.sec = -1
end

--@frame
local function Tick(now)
	local t = H.Run.Time()
	local sec = 0
	if t then
		sec = floor(t)
	end
	if sec ~= P.sec then
		P.sec = sec
		P.clock:SetText(Tr.TimeStr(sec))
	end
end

----------------------------------------------------------------------------------------
-- Подсказка
----------------------------------------------------------------------------------------

local function ShowTip()
	local tip = GameTooltip
	if not tip or not P.panel then
		return
	end
	local C = Tr.C
	tip:SetOwner(P.panel, "ANCHOR_BOTTOMLEFT")
	tip:ClearLines()
	tip:AddLine(H.Run.Zone("zname") or "", C.zone[1], C.zone[2], C.zone[3])
	if H.Run.IsEndless() then
		tip:AddLine(Tr.T("tip_endless"), 1, 1, 1)
	else
		local left = H.Run.Left()
		if left then
			tip:AddLine(Tr.T("tip_final").." "..Tr.TimeStr(floor(left)), 1, 1, 1)
		end
	end
	local bs, bt = H.Run.Get("bs"), H.Run.Get("bt")
	if bs and bt then
		tip:AddLine(Tr.T("tip_bosses").." "..Fm.Int(bs).."/"..Fm.Int(bt), 0.8, 0.8, 0.8)
	end
	local lairs = H.Run.Get("lairs")
	if lairs then
		tip:AddLine(Tr.T("tip_lairs").." "..Fm.Int(lairs), 0.8, 0.8, 0.8)
	end
	local diff = tonumber(H.Run.Zone("diff"))
	if diff and diff ~= 1 then
		tip:AddLine(Tr.T("tip_diff").." x"..diff, 0.8, 0.8, 0.8)
	end
	tip:AddLine(Tr.T("tip_hide"), 0.5, 0.5, 0.5)
	tip:Show()
end

----------------------------------------------------------------------------------------
-- Кадры
----------------------------------------------------------------------------------------

local function ApplyBg()
	local on = Tr.Opt("panelBg")
	if on then
		P.bg:Show()
	else
		P.bg:Hide()
	end
	for i = 1, 4 do
		if on then
			P.border[i]:Show()
		else
			P.border[i]:Hide()
		end
	end
end

local function Row(h)
	local f = CreateFrame("Frame", nil, P.panel)
	f:SetHeight(R(h))
	f:SetWidth(R(PW))
	return f
end

local function Build()
	PW = Tr.Def("tr.tracker", "w", PW)
	local panel = CreateFrame("Frame", nil, UIParent)
	panel:SetFrameStrata("MEDIUM")
	P.panel = panel
	P.bg = K.Fill(panel, "bg", "BACKGROUND")
	P.border = K.Border(panel, "edge")
	panel:EnableMouse(true)
	H.Script("tracker", panel, "OnEnter", ShowTip)
	H.Script("tracker", panel, "OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	local head = Row(ROW_HEAD)
	P.zone = K.Text(head, "title", nil, "LEFT")
	P.zone:SetPoint("LEFT", head, "LEFT", R(4), 0)
	Tr.Color(P.zone, Tr.C.zone)
	P.tagsFs = K.Text(head, "small", nil, "RIGHT")
	P.tagsFs:SetPoint("RIGHT", head, "RIGHT", -R(4), 0)
	Tr.AddSection("head", head, ROW_HEAD, 10).on = true

	local clk = Row(ROW_CLOCK)
	P.clock = K.Text(clk, "msg", nil, "LEFT")
	P.clock:SetPoint("LEFT", clk, "LEFT", R(4), 0)
	P.len = K.Text(clk, "body", nil, "LEFT")
	P.len:SetPoint("LEFT", P.clock, "RIGHT", R(4), -R(2))
	Tr.Color(P.len, Tr.C.gray)
	P.stateFs = K.Text(clk, "body", nil, "RIGHT")
	P.stateFs:SetPoint("RIGHT", clk, "RIGHT", -R(4), 0)
	P.livesFs = K.Text(clk, "body", nil, "RIGHT")
	P.livesFs:SetPoint("RIGHT", P.stateFs, "LEFT", -R(6), 0)
	Tr.Color(P.livesFs, Tr.C.pink)
	P.livesFs:Hide()
	Tr.AddSection("clock", clk, ROW_CLOCK, 20).on = true

	ApplyBg()
end

----------------------------------------------------------------------------------------
-- Часть
----------------------------------------------------------------------------------------

local function Place()
	if not P.panel then
		return
	end
	Tr.Set(P.panel, Tr.Opt("panel") and Tr.InRun())
end

local part = Tr.Part("panel", {
	build = Build,
	show = function()
		Tr.Register("tr.tracker", P.panel)
		P.h = 0
		ApplyBg()
		Tr.Relayout()
	end,
	hide = function()
		if GameTooltip and P.panel then
			GameTooltip:Hide()
		end
	end,
	refresh = Refresh,
	place = Place,
	theme = function()
		P.zoneName = nil
		Tr.Relayout()
	end,
	settings = function(key)
		if key == "panelBg" then
			ApplyBg()
		end
	end,
	reset = function()
		-- false, не nil: пустое новое значение должно отличаться от сброшенного кэша и перерисоваться.
		P.stateKey, P.gray, P.lives, P.lastLen = false, nil, nil, false
		P.zoneName, P.tags, P.tagH, P.tagE, P.tagA = nil, nil, nil, nil, nil
	end,
	tick = Tick,
	on = {
		RUN = Refresh, ZONE = Refresh, REVIVE = Refresh, DOWN_CHANGED = Refresh, LEVEL_CHANGED = Refresh,
		PHASE_CHANGED = Refresh, RUN_ENDED = Refresh, LOCALE = Refresh,
	},
	dump = function(out)
		table.insert(out, "панель: показана "..tostring(P.panel and P.panel:IsShown()).."  высота "..tostring(P.h)
			.."  состояние "..tostring(P.stateKey).."  секунда "..tostring(P.sec))
	end,
})
