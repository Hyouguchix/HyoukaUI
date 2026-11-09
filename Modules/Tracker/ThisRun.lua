-- HyoukaUI: Modules\Tracker\ThisRun, панель "Этот забег" tr.thisRun (plan 3.2, tracker#27, #28).
--
-- Заголовок акцентом (клик сворачивает панель, настройка thisRunFolded) и строки "метка серым слева, значение
-- белым справа": время, уровень, убийства, убийств в минуту, элиты, стражи, боссы, урон нанесен, урон в секунду,
-- урон получен, золото за забег, сундуки, перебросы, жизни. Под ними три лучших крита по способностям.
-- Урон берется из H.Run.Damage().meter (урон счетчика, без оверкилла; с экраном итогов сравнивается только
-- endScreen, audit meter-44). Криты: событие COMBAT_EVENT(kind, amount, critical, source) слоя CombatText, имя
-- способности из H.CombatText.Last().ability, иначе ключ источника; поля событий в игре не сняты (проба 0.9), поэтому
-- доступ защитный: нет полей - раздел показывает "Критов пока нет".
-- Строки меняются, только если изменилось число (кэш в строке), по событиям RUN и METER; время и скорость раз в секунду.

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local getn = table.getn
local floor = math.floor

local PW, TITLE_H, ROW_H, MAXC, PAD = 230, 16, 14, 3, 3

-- Строки: ключ метки Tr.T, тип значения.
local ROWS = {
	{ "survived", "time" }, { "level", "int" }, { "kills", "short" }, { "kpm", "rate" }, { "elites", "int" },
	{ "guardians", "int" }, { "bosses", "int" }, { "dmg_done", "short" }, { "dmg_ps", "short" }, { "dmg_taken", "short" },
	{ "gold_earned", "short" }, { "chests", "int" }, { "rerolls", "int" }, { "lives", "int" },
}

local TR = { rows = {}, crow = {}, names = {}, amts = {}, nCrit = 0, h = 0 }
Tr.ThisRun = TR

local function R(px)
	return H.R(px)
end

----------------------------------------------------------------------------------------
-- Значения
----------------------------------------------------------------------------------------

local function Get(key)
	return H.Run.Get(key) or 0
end

-- Число для строки i (nil - строки нет). time и rate считаются от часов забега.
local function Value(key, t)
	local run = H.Run
	if key == "survived" then
		return floor(t or 0)
	elseif key == "level" then
		return run.Level() or 0
	elseif key == "kills" then
		return Get("kills")
	elseif key == "kpm" then
		if t and t >= 5 then
			return floor(Get("kills") / (t / 60) * 10)
		end
		return 0
	elseif key == "elites" then
		return Get("ek")
	elseif key == "guardians" then
		return Get("gk")
	elseif key == "bosses" then
		return Get("bk")
	elseif key == "dmg_done" then
		local meter = run.Damage()
		return floor(meter or 0)
	elseif key == "dmg_ps" then
		local meter = run.Damage()
		if meter and t and t >= 1 then
			return floor(meter / t)
		end
		return 0
	elseif key == "dmg_taken" then
		return Get("taken")
	elseif key == "gold_earned" then
		return Get("ge")
	elseif key == "chests" then
		return Get("ck")
	elseif key == "rerolls" then
		return Get("rr")
	end
	return Get("lives")
end

local RATES = {}

-- Десятые из целого v (в десятых): "118.4"; строки в кэше, значение меняется каждую секунду.
local function RateStr(v)
	local s = RATES[v]
	if not s then
		s = Fm.Int(floor(v / 10)).."."..Fm.Int(v - floor(v / 10) * 10)
		RATES[v] = s
	end
	return s
end

local function Text(kind, v)
	if kind == "time" then
		return Tr.TimeStr(v)
	elseif kind == "short" then
		return Fm.Short(v)
	elseif kind == "rate" then
		return RateStr(v)
	end
	return Fm.Int(v)
end

local function Update(slowOnly)
	if not TR.panel then
		return
	end
	local t = H.Run.Time()
	for i = 1, getn(ROWS) do
		local def = ROWS[i]
		local row = TR.rows[i]
		local v = Value(def[1], t)
		if v ~= row.v then
			row.v = v
			row.valFs:SetText(Text(def[2], v))
		end
	end
end

----------------------------------------------------------------------------------------
-- Криты
----------------------------------------------------------------------------------------

local Relayout

local function PaintCrits()
	local n = TR.nCrit
	for i = 1, MAXC do
		local row = TR.crow[i]
		if i <= n then
			row.nameFs:SetText(TR.names[i])
			row.valFs:SetText(Fm.Short(TR.amts[i]))
		end
	end
	TR.emptyFs:SetText(n == 0 and Tr.T("no_crits") or "")
end

local function OnCombat(ev, kind, amount, critical, source)
	if not critical or type(amount) ~= "number" or amount <= 0 or not Tr.Opt("crits") then
		return
	end
	local name = source
	local ok, rec = pcall(H.CombatText.Last)
	if ok and rec and rec.ability and rec.ability ~= "" then
		name = rec.ability
	end
	name = tostring(name or "?")
	local at
	for i = 1, TR.nCrit do
		if TR.names[i] == name then
			at = i
		end
	end
	if at then
		if amount <= TR.amts[at] then
			return
		end
		TR.amts[at] = amount
	else
		if TR.nCrit < MAXC then
			TR.nCrit = TR.nCrit + 1
			TR.names[TR.nCrit], TR.amts[TR.nCrit] = name, amount
		elseif amount > TR.amts[MAXC] then
			TR.names[MAXC], TR.amts[MAXC] = name, amount
		else
			return
		end
	end
	-- Сортировка вставками по убыванию (три записи).
	for i = 2, TR.nCrit do
		local j = i
		while j > 1 and TR.amts[j] > TR.amts[j - 1] do
			TR.amts[j], TR.amts[j - 1] = TR.amts[j - 1], TR.amts[j]
			TR.names[j], TR.names[j - 1] = TR.names[j - 1], TR.names[j]
			j = j - 1
		end
	end
	PaintCrits()
	Relayout()
end

----------------------------------------------------------------------------------------
-- Раскладка панели
----------------------------------------------------------------------------------------

function Relayout()
	if not TR.panel then
		return
	end
	local folded = Tr.Opt("thisRunFolded")
	local crits = Tr.Opt("crits")
	local y = PAD + TITLE_H
	TR.title:SetWidth(R(PW))
	TR.title:SetHeight(R(TITLE_H))
	for i = 1, getn(ROWS) do
		local row = TR.rows[i]
		row.frame:SetWidth(R(PW))
		row.frame:SetHeight(R(ROW_H))
		if folded then
			row.frame:Hide()
		else
			row.frame:ClearAllPoints()
			row.frame:SetPoint("TOPLEFT", TR.panel, "TOPLEFT", 0, -R(y))
			row.frame:Show()
			y = y + ROW_H
		end
	end
	if folded or not crits then
		TR.critHead:Hide()
		TR.emptyFs:Hide()
		for i = 1, MAXC do
			TR.crow[i].frame:Hide()
		end
	else
		TR.critHead:ClearAllPoints()
		TR.critHead:SetPoint("TOPLEFT", TR.panel, "TOPLEFT", R(4), -R(y + 2))
		TR.critHead:Show()
		y = y + TITLE_H
		TR.emptyFs:ClearAllPoints()
		TR.emptyFs:SetPoint("TOPLEFT", TR.panel, "TOPLEFT", R(4), -R(y))
		TR.emptyFs:Show()
		for i = 1, MAXC do
			local row = TR.crow[i]
			row.frame:SetWidth(R(PW))
			row.frame:SetHeight(R(ROW_H))
			row.frame:ClearAllPoints()
			row.frame:SetPoint("TOPLEFT", TR.panel, "TOPLEFT", 0, -R(y))
			if i <= TR.nCrit then
				row.frame:Show()
			else
				row.frame:Hide()
			end
			y = y + ROW_H
		end
	end
	TR.titleFs:SetText(Tr.T("this_run")..(folded and " +" or " -"))
	y = y + PAD
	if y ~= TR.h then
		TR.h = y
		if H.Layout.Has("tr.thisRun") then
			H.Layout.SetSize("tr.thisRun", nil, y)
		end
	end
end

local function Place()
	if not TR.panel then
		return
	end
	Tr.Set(TR.panel, Tr.Opt("thisRun") and Tr.InRun())
end

local function Refresh()
	if not TR.panel then
		return
	end
	local r, g, b = Tr.Accent()
	TR.titleFs:SetTextColor(r, g, b, 1)
	TR.critHead:SetTextColor(r, g, b, 1)
	TR.critHead:SetText(Tr.T("crits"))
	for i = 1, getn(ROWS) do
		TR.rows[i].labelFs:SetText(Tr.T(ROWS[i][1]))
	end
	Update()
	PaintCrits()
	Relayout()
end

----------------------------------------------------------------------------------------
-- Кадры
----------------------------------------------------------------------------------------

local function MakeRow(parent, labelText, valueColor)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(R(PW))
	f:SetHeight(R(ROW_H))
	local labelFs = K.Text(f, "body", nil, "LEFT")
	labelFs:SetPoint("LEFT", f, "LEFT", R(4), 0)
	Tr.Color(labelFs, Tr.C.gray)
	labelFs:SetText(labelText or "")
	local valFs = K.Text(f, "body", nil, "RIGHT")
	valFs:SetPoint("RIGHT", f, "RIGHT", -R(4), 0)
	Tr.Color(valFs, valueColor or Tr.C.white)
	return { frame = f, nameFs = labelFs, labelFs = labelFs, valFs = valFs }
end

local function Build()
	PW = Tr.Def("tr.thisRun", "w", PW)
	local panel = CreateFrame("Frame", nil, UIParent)
	TR.panel = panel
	K.Fill(panel, "bg", "BACKGROUND")
	K.Border(panel, "edge")
	local title = CreateFrame("Button", nil, panel)
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -R(PAD))
	title:SetWidth(R(PW))
	title:SetHeight(R(TITLE_H))
	TR.title = title
	TR.titleFs = K.Text(title, "body", nil, "LEFT")
	TR.titleFs:SetPoint("LEFT", title, "LEFT", R(4), 0)
	H.Script("tracker", title, "OnClick", function()
		Tr.Put("thisRunFolded", not Tr.Opt("thisRunFolded"))
	end)
	for i = 1, getn(ROWS) do
		TR.rows[i] = MakeRow(panel, Tr.T(ROWS[i][1]))
		TR.rows[i].v = nil
	end
	TR.critHead = K.Text(panel, "body", nil, "LEFT")
	TR.critHead:SetText(Tr.T("crits"))
	TR.emptyFs = K.Text(panel, "small", nil, "LEFT")
	Tr.Color(TR.emptyFs, Tr.C.gray)
	for i = 1, MAXC do
		TR.crow[i] = MakeRow(panel, "")
		TR.crow[i].frame:Hide()
	end
end

local function ResetCrits()
	TR.nCrit = 0
	H.Wipe(TR.names)
	H.Wipe(TR.amts)
end

Tr.Part("thisrun", {
	build = Build,
	show = function()
		Tr.Register("tr.thisRun", TR.panel)
		TR.h = 0
		if Tr.Opt("crits") and H.CombatText then
			H.CombatText.Watch("tracker", true)
		end
	end,
	hide = function()
		if H.CombatText then
			H.CombatText.Watch("tracker", false)
		end
	end,
	refresh = Refresh,
	place = Place,
	theme = function()
		TR.h = 0
		Relayout()
	end,
	slow = function(now)
		Update(true)
	end,
	reset = function()
		ResetCrits()
		for i = 1, getn(ROWS) do
			TR.rows[i].v = nil
		end
	end,
	settings = function(key)
		if key == "crits" then
			if H.CombatText then
				H.CombatText.Watch("tracker", Tr.Opt("crits") and true or false)
			end
		end
		Relayout()
	end,
	on = { RUN = Update, METER = Update, COMBAT_EVENT = OnCombat, LEVEL_CHANGED = Update },
	dump = function(out)
		table.insert(out, "этот забег: высота "..TR.h.."  свернуто "..tostring(Tr.Opt("thisRunFolded")).."  критов "..TR.nCrit)
		for i = 1, getn(ROWS) do
			table.insert(out, "  "..ROWS[i][1].." = "..tostring(TR.rows[i].valFs:GetText()))
		end
		for i = 1, TR.nCrit do
			table.insert(out, "  крит "..TR.names[i].." "..TR.amts[i])
		end
	end,
})
