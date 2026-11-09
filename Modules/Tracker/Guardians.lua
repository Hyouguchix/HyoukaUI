-- HyoukaUI: Modules\Tracker\Guardians, секция стражей логов панели tr.tracker (plan 3.2, tracker#17, #20).
--
-- Полоса из сегментов, по одному на логово (порядок H.Schedule.Lairs, до 8). Состояние сегмента:
--   asleep  страж на месте - акцент;
--   awake   проснулся - оранжевый с заливкой доли здоровья стража (H.Units.Get по id логова);
--   empty   логово пусто: темный сегмент с временем возрождения (H.Schedule.RespawnIn, только в фазе playing),
--           без известного времени - зеленый (страж убит).
-- Над полосой цель "N/4 к 8:00" с оставшимся временем (число 4 и секунда 480 - условие достижения игры, значения
-- взяты из SurvivorUI Guardians.lua:60 [НЕ ПРОВЕРЕНО в игре]); до 8:00 считается лучший счет gk, после 8:00 счет
-- замирает. Сегменты и тексты меняются по событиям LAIRS_CHANGED, UNITS_CHANGED, RUN; раз в 0.05 с идет только
-- таймер возрождения (строки из кэша) и оставшееся время цели.

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local getn = table.getn
local floor, ceil = math.floor, math.ceil

local MAXS, GOAL_N, GOAL_T = 8, 4, 480
local STRIP_H, GOAL_H = 10, 14


local GD = { segs = {}, before = 0, count = 0, goalStr = {}, goalSec = -1, shown = false, goalOn = false }
Tr.Guard = GD

local function R(px)
	return H.R(px)
end

local function GoalStr(n)
	local s = GD.goalStr[n]
	if not s then
		s = Fm.Int(n).."/"..Fm.Int(GOAL_N).." "..Tr.T("goal")
		GD.goalStr[n] = s
	end
	return s
end

local function Goal()
	local gk = H.Run.Get("gk") or 0
	local t = H.Run.Time() or 0
	if t < GOAL_T and gk > GD.before then
		GD.before = gk
	end
	local C = Tr.C
	GD.goalFs:SetText(GoalStr(GD.before))
	if GD.before >= GOAL_N then
		Tr.Color(GD.goalFs, C.green)
		GD.goalTime:SetText(Tr.T("goal_done"))
		Tr.Color(GD.goalTime, C.green)
		GD.goalSec = -3
	elseif t < GOAL_T then
		Tr.Color(GD.goalFs, C.white)
		Tr.Color(GD.goalTime, C.white)
		GD.goalSec = -1
	else
		Tr.Color(GD.goalFs, C.gray)
		GD.goalTime:SetText("")
		GD.goalSec = -3
	end
end

-- Раскладка сегментов под число логов.
local function LayoutSegs(n)
	local gap = H.Theme.Px(1)
	local w = (R(Tr.PanelWidth() - 8) - gap * (n - 1)) / n
	if w < 1 then
		w = 1
	end
	local top = GD.goalOn and R(GOAL_H) or 0
	for i = 1, MAXS do
		local s = GD.segs[i]
		if i <= n then
			s.frame:ClearAllPoints()
			s.frame:SetPoint("TOPLEFT", GD.frame, "TOPLEFT", R(4) + (i - 1) * (w + gap), -(top + R(1)))
			s.frame:SetWidth(w)
			s.frame:SetHeight(R(STRIP_H))
			s.w = w
			s.frame:Show()
		else
			s.frame:Hide()
		end
	end
	GD.count = n
end

local function Paint(seg, lair, i)
	local C = Tr.C
	local state = lair.state
	local prev = seg.state
	seg.state = state
	seg.fill:Hide()
	-- Текст не стираем при каждой перерисовке: пустое место между SetText("") и следующим тиком мерцало раз в секунду
	-- (отсчет возрождения писался заново на каждое событие расписания). Стираем только при смене состояния.
	if prev ~= state then
		seg.timeFs:SetText("")
		seg.pct = -1
		seg.sec = -1
	end
	Tr.Color(seg.timeFs, C.white)
	if state == "awake" then
		-- dark mode ретейла: потерянное здоровье серое, остаток темный (как у рамок игрока и цели)
		Tr.Paint(seg.bg, C.lost)
		local u = lair.id and H.Units.Get(lair.id)
		local frac = 0
		if u and u.hpm and u.hpm > 0 and u.hp then
			frac = u.hp / u.hpm
			if frac > 1 then
				frac = 1
			end
		end
		if frac > 0 then
			Tr.Paint(seg.fill, C.rest)
			seg.fill:SetWidth(H.Theme.Snap((seg.w or 1) * frac))
			seg.fill:Show()
			-- проснувшийся страж виден по оранжевой доле здоровья
			local pct = floor(frac * 100 + 0.5)
			if seg.pct ~= pct then
				seg.pct = pct
				seg.timeFs:SetText(pct.."%")
			end
			Tr.Color(seg.timeFs, C.orange)
		elseif seg.pct ~= -1 then
			seg.pct = -1
			seg.timeFs:SetText("")
		end
	elseif state == "empty" then
		if H.Schedule.RespawnIn(i) then
			Tr.Paint(seg.bg, C.rest)
		else
			Tr.Paint(seg.bg, C.green)
		end
	else
		local r, g, b = Tr.Accent()
		seg.bg:SetVertexColor(r, g, b, 0.9)
	end
end

local function Refresh()
	if not GD.frame then
		return
	end
	local lairs = H.Schedule.Lairs()
	local n = H.Schedule.LairCount()
	if n > MAXS then
		n = MAXS
	end
	if n ~= GD.count then
		LayoutSegs(n)
	end
	for i = 1, n do
		Paint(GD.segs[i], lairs[i], i)
	end
	Goal()
end

local function Place()
	if not GD.frame then
		return
	end
	local on = Tr.Opt("guardians") and Tr.InRun() and H.Schedule.LairCount() > 0
	local goal = Tr.Opt("goal") and true or false
	if goal ~= GD.goalOn then
		GD.goalOn = goal
		GD.count = -1
		Refresh()
	end
	if goal then
		GD.goalFs:Show()
		GD.goalTime:Show()
	else
		GD.goalFs:Hide()
		GD.goalTime:Hide()
	end
	GD.shown = on and true or false
	Tr.SetSection("guardians", on, (goal and GOAL_H or 0) + STRIP_H + 3)
end

local function OnChange()
	Refresh()
	Place()
end

-- Строка забега приходит часто: цели достаточно пересчитать счет стражей и число логов.
local function OnRun()
	if H.Schedule.LairCount() ~= GD.count then
		OnChange()
	elseif GD.frame then
		Goal()
	end
end

--@frame
local function Tick(now)
	if not GD.shown then
		return
	end
	for i = 1, GD.count do
		local seg = GD.segs[i]
		if seg.state == "empty" then
			local left = H.Schedule.RespawnIn(i)
			if left then
				local sec = ceil(left)
				if sec ~= seg.sec then
					seg.sec = sec
					seg.timeFs:SetText(Tr.TimeStr(sec))
				end
			elseif seg.sec ~= -2 then
				seg.sec = -2
				seg.timeFs:SetText("")
			end
		end
	end
	if GD.goalOn and GD.goalSec ~= -3 then
		local t = H.Run.Time() or 0
		if t < GOAL_T then
			local sec = ceil(GOAL_T - t)
			if sec ~= GD.goalSec then
				GD.goalSec = sec
				GD.goalTime:SetText(Tr.TimeStr(sec))
			end
		else
			Goal()
		end
	end
end

local function Build()
	local sec = CreateFrame("Frame", nil, UIParent)
	GD.frame = sec
	GD.goalFs = K.Text(sec, "small", nil, "LEFT")
	GD.goalFs:SetPoint("TOPLEFT", sec, "TOPLEFT", R(4), -R(1))
	GD.goalTime = K.Text(sec, "small", nil, "RIGHT")
	GD.goalTime:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -R(4), -R(1))
	for i = 1, MAXS do
		local f = CreateFrame("Frame", nil, sec)
		local bg = Tr.Fill(f, Tr.C.rest, "BACKGROUND")
		bg:SetAllPoints(f)
		local fill = Tr.Fill(f, Tr.C.orange, "ARTWORK")
		fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		fill:Hide()
		local timeFs = K.Text(f, "small", nil, "CENTER")
		timeFs:SetPoint("CENTER", f, "CENTER", 0, 0)
		f:Hide()
		GD.segs[i] = { frame = f, bg = bg, fill = fill, timeFs = timeFs, sec = -1, w = 1 }
	end
	Tr.AddSection("guardians", sec, GOAL_H + STRIP_H + 3, 40)
end

Tr.Part("guardians", {
	build = Build,
	theme = function()
		GD.count = -1
		GD.goalSec = -1
	end,
	refresh = Refresh,
	place = Place,
	tick = Tick,
	reset = function()
		GD.before = 0
		GD.count = -1
		GD.goalSec = -1
	end,
	settings = function(key)
		if key == "guardians" or key == "goal" then
			Place()
		end
	end,
	on = { LAIRS_CHANGED = OnChange, UNITS_CHANGED = Refresh, RUN = OnRun, ZONE = OnChange },
	dump = function(out)
		table.insert(out, "стражи: логов "..H.Schedule.LairCount().."  сегментов "..GD.count.."  цель "..GD.before.."/"..GOAL_N)
		local lairs = H.Schedule.Lairs()
		for i = 1, getn(lairs) do
			table.insert(out, "  "..i..". "..tostring(lairs[i].state).."  "..tostring(lairs[i].name).."  возрождение "
				..tostring(H.Schedule.RespawnIn(i)))
		end
	end,
})
