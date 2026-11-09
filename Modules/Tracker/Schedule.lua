-- HyoukaUI: Modules\Tracker\Schedule, секция расписания боссов панели tr.tracker (plan 3.2, tracker#8, #10).
--
-- Строка на босса: имя слева, справа состояние. Будущий босс серый со временем прихода; следующий белый с
-- "через m:ss" золотом; живой оранжевый с долей здоровья; убитый зеленый со временем, когда падение было
-- замечено (событие BOSS_DEAD), иначе со временем прихода. В бесконечном режиме расписание замерло на победе:
-- вместо строк две строки "Следующий босс через m:ss" и "Боссов в бесконечном: N" (N = убито боссов минус
-- боссов расписания [ОЦЕНКА]: счетчик bk берется за весь забег). Строки меняются по событиям; раз в 0.05 с
-- идет только обратный отсчет следующего босса (строки из кэша, секунда меняется раз в секунду).

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local getn = table.getn
local floor, ceil = math.floor, math.ceil

local MAXR, ROW_H = 8, 15

local SC = { rows = {}, fell = {}, nextRow = nil, nextSec = -1, endSec = -1, endCount = nil, endStr = {}, shown = 0 }
Tr.Sched = SC

local function R(px)
	return H.R(px)
end

local function BossPct(name)
	local list = H.Units.Bosses()
	for i = 1, getn(list) do
		local u = list[i]
		if u.name == name and u.hpm and u.hpm > 0 then
			return Fm.Pct(u.hp or 0, u.hpm)
		end
	end
	return nil
end

local function Bind(row, line, nextLine)
	local C = Tr.C
	if row.name ~= line.name then
		row.name = line.name
		H.Text.Fit(row.nameFs, line.name or "", R(135))
	end
	row.line = line
	local state = line.state
	if state == "up" then
		Tr.Color(row.nameFs, C.orange)
		local pct = BossPct(line.name)
		row.rightFs:SetText(pct and (Fm.Int(pct).."%") or Tr.TimeStr(floor(line.at)))
		Tr.Color(row.rightFs, C.orange)
	elseif state == "dead" then
		Tr.Color(row.nameFs, C.green)
		local at = SC.fell[line.index] or floor(line.at)
		row.rightFs:SetText(Tr.TimeStr(at))
		Tr.Color(row.rightFs, C.green)
	elseif line == nextLine then
		Tr.Color(row.nameFs, C.white)
		Tr.Color(row.rightFs, C.gold)
		row.sec = -1
		SC.nextRow = row
		local left = H.Schedule.Left(line)
		if left then
			row.sec = ceil(left)
			if row.sec < 0 then
				row.sec = 0
			end
			row.rightFs:SetText(Tr.InStr(row.sec))
		else
			row.rightFs:SetText("")
		end
	else
		Tr.Color(row.nameFs, C.gray)
		row.rightFs:SetText(Tr.TimeStr(floor(line.at)))
		Tr.Color(row.rightFs, C.gray)
	end
end

local function Refresh()
	if not SC.frame then
		return
	end
	local list = H.Schedule.Lines()
	local n = getn(list)
	if n > MAXR then
		n = MAXR
	end
	local nextLine = nil
	if not H.Run.IsEndless() then
		nextLine = H.Schedule.Next()
	end
	SC.nextRow = nil
	for i = 1, MAXR do
		local row = SC.rows[i]
		if i <= n then
			Bind(row, list[i], nextLine)
			row.frame:Show()
		else
			row.line, row.name = nil, nil
			row.frame:Hide()
		end
	end
	SC.shown = n
	-- Бесконечный режим: счет убитых боссов сверх расписания.
	if H.Run.IsEndless() then
		local bk = H.Run.Get("bk") or 0
		local count = bk - H.Schedule.Count()
		if count < 0 then
			count = 0
		end
		if count ~= SC.endCount then
			SC.endCount = count
			SC.endKilled:SetText(Tr.T("endless_bosses")..": "..Fm.Int(count))
		end
	end
end

local function Place()
	if not SC.frame then
		return
	end
	local on = Tr.Opt("schedule") and Tr.InRun()
	local endless = H.Run.IsEndless()
	Tr.SetSection("schedule", on and not endless and SC.shown > 0, SC.shown * ROW_H + 2)
	Tr.SetSection("endless", on and endless)
end

local function OnChange()
	Refresh()
	Place()
end

-- Строка забега приходит часто: расписание перерисовывается, только если сменился бесконечный режим или счет боссов.
local function OnRun()
	local endless = H.Run.IsEndless()
	local bk = H.Run.Get("bk")
	if endless ~= SC.wasEndless or (endless and bk ~= SC.lastBk) then
		SC.wasEndless, SC.lastBk = endless, bk
		OnChange()
	end
end

local function OnBossDead(ev, index, name)
	local t = H.Run.Time()
	if t and index then
		SC.fell[index] = floor(t)
	end
	OnChange()
end

local function EndStr(sec)
	local s = SC.endStr[sec]
	if not s then
		s = Tr.T("next_boss_in").." "..Tr.TimeStr(sec)
		SC.endStr[sec] = s
	end
	return s
end

--@frame
local function Tick(now)
	if H.Run.IsEndless() then
		local left = H.Schedule.NextEndless()
		if left then
			local sec = ceil(left)
			if sec ~= SC.endSec then
				SC.endSec = sec
				SC.endNext:SetText(EndStr(sec))
			end
		elseif SC.endSec ~= -2 then
			SC.endSec = -2
			SC.endNext:SetText("")
		end
		return
	end
	local row = SC.nextRow
	if row and row.line then
		local left = H.Schedule.Left(row.line)
		if left then
			local sec = ceil(left)
			if sec < 0 then
				sec = 0
			end
			if sec ~= row.sec then
				row.sec = sec
				row.rightFs:SetText(Tr.InStr(sec))
			end
		end
	end
end

local function Build()
	local sec = CreateFrame("Frame", nil, UIParent)
	SC.frame = sec
	for i = 1, MAXR do
		local f = CreateFrame("Frame", nil, sec)
		f:SetHeight(R(ROW_H))
		f:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -R((i - 1) * ROW_H + 1))
		f:SetPoint("TOPRIGHT", sec, "TOPRIGHT", 0, -R((i - 1) * ROW_H + 1))
		local nameFs = K.Text(f, "body", nil, "LEFT")
		nameFs:SetPoint("LEFT", f, "LEFT", R(4), 0)
		local rightFs = K.Text(f, "body", nil, "RIGHT")
		rightFs:SetPoint("RIGHT", f, "RIGHT", -R(4), 0)
		SC.rows[i] = { frame = f, nameFs = nameFs, rightFs = rightFs, sec = -1 }
		f:Hide()
	end
	Tr.AddSection("schedule", sec, ROW_H, 50)

	local e = CreateFrame("Frame", nil, UIParent)
	SC.endFrame = e
	SC.endNext = K.Text(e, "body", nil, "LEFT")
	SC.endNext:SetPoint("TOPLEFT", e, "TOPLEFT", R(4), -R(1))
	Tr.Color(SC.endNext, Tr.C.white)
	SC.endKilled = K.Text(e, "body", nil, "LEFT")
	SC.endKilled:SetPoint("TOPLEFT", e, "TOPLEFT", R(4), -R(ROW_H + 1))
	Tr.Color(SC.endKilled, Tr.C.purple)
	Tr.AddSection("endless", e, ROW_H * 2 + 2, 55)
end

-- THEME: высоты и места строк в ретейл-px пересчитываются под новый размер пикселя.
local function OnTheme()
	for i = 1, MAXR do
		local f = SC.rows[i].frame
		f:SetHeight(R(ROW_H))
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", SC.frame, "TOPLEFT", 0, -R((i - 1) * ROW_H + 1))
		f:SetPoint("TOPRIGHT", SC.frame, "TOPRIGHT", 0, -R((i - 1) * ROW_H + 1))
	end
	SC.endKilled:ClearAllPoints()
	SC.endKilled:SetPoint("TOPLEFT", SC.endFrame, "TOPLEFT", R(4), -R(ROW_H + 1))
	for i = 1, MAXR do
		SC.rows[i].name = nil
	end
end

Tr.Part("schedule", {
	build = Build,
	theme = OnTheme,
	refresh = function()
		Refresh()
	end,
	place = Place,
	tick = Tick,
	reset = function()
		H.Wipe(SC.fell)
		SC.endCount, SC.endSec, SC.nextRow = nil, -1, nil
		SC.wasEndless, SC.lastBk = nil, nil
	end,
	settings = function(key)
		if key == "schedule" then
			Place()
		end
	end,
	on = {
		SCHEDULE_CHANGED = OnChange, BOSS_UP = OnChange, BOSS_DEAD = OnBossDead, UNITS_CHANGED = Refresh, RUN = OnRun,
		ZONE = OnChange,
	},
	dump = function(out)
		table.insert(out, "расписание: строк "..SC.shown.."  следующая "..tostring(SC.nextRow and SC.nextRow.name)
			.."  бесконечный "..tostring(H.Run.IsEndless()))
		for i = 1, SC.shown do
			local r = SC.rows[i]
			table.insert(out, "  "..i..". "..tostring(r.nameFs:GetText()).."  "..tostring(r.rightFs:GetText()))
		end
	end,
})
