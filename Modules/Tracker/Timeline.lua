-- HyoukaUI: Modules\Tracker\Timeline, полоса времени забега с засечками боссов (plan 3.2, tracker#7).
--
-- Полоса 222x10 (ретейл-px) заливается акцентом по доле часов забега от его длины. На секундах прихода боссов
-- стоят засечки шириной в один физический пиксель: будущий босс серый, следующий белый, живой оранжевый,
-- убитый зеленый; финальный выше остальных. Засечки красятся по событиям расписания (SCHEDULE_CHANGED, BOSS_UP,
-- BOSS_DEAD), а не по таймеру: "следующий" меняется только со сменой состояний. В бесконечном режиме и без
-- известной длины полоса скрыта (там работает секция расписания: "Следующий босс через").
-- Покадровая часть: только Bar.Set(часы, длина), строк и таблиц не создает.

local H = HyoukaUI

local Tr = H.Tr

local getn = table.getn

local MAXT = 16
local BAR_H, ROW_H = 10, 15

local TL = { ticks = {}, lastLen = nil, shown = false }
Tr.Timeline = TL

local function R(px)
	return H.R(px)
end

local function Want()
	if not Tr.Opt("timeline") or not Tr.InRun() or H.Run.IsEndless() then
		return false
	end
	local len = H.Run.Length()
	return len ~= nil and len > 0
end

local function TickColor(line, nextLine)
	local C = Tr.C
	if line.state == "up" then
		return C.orange
	elseif line.state == "dead" then
		return C.green
	elseif line == nextLine then
		return C.white
	end
	return C.gray
end

-- Расставить засечки по расписанию.
local function Ticks()
	if not TL.bar then
		return
	end
	local len = H.Run.Length()
	local list = H.Schedule.Lines()
	local nextLine = H.Schedule.Next()
	local px = H.Theme.Px(1)
	local border = H.Theme.Border()
	local inner = TL.bar:GetWidth() - 2 * border
	for i = 1, MAXT do
		local tick = TL.ticks[i]
		local line = list[i]
		if line and len and len > 0 and not H.Run.IsEndless() and line.at and line.at <= len then
			tick:ClearAllPoints()
			tick:SetPoint("CENTER", TL.over, "LEFT", border + inner * (line.at / len), 0)
			tick:SetWidth(px)
			tick:SetHeight(R(line.final == 1 and BAR_H + 8 or BAR_H + 4))
			Tr.Paint(tick, TickColor(line, nextLine))
			tick:Show()
		else
			tick:Hide()
		end
	end
end

local function Place()
	if not TL.frame then
		return
	end
	local want = Want()
	Tr.SetSection("timeline", want)
	if want and not TL.shown then
		TL.shown = true
		Ticks()
	elseif not want then
		TL.shown = false
	end
end

local function Fill()
	local r, g, b = Tr.Accent()
	H.Bar.SetColor(TL.bar, r, g, b)
end

local function Refresh()
	if not TL.frame then
		return
	end
	Fill()
	Ticks()
	TL.lastLen = H.Run.Length()
	H.Bar.Set(TL.bar, 0, 1)
end

--@frame
local function Tick(now)
	if not TL.shown then
		return
	end
	local len = H.Run.Length()
	local t = H.Run.Time()
	if len and len > 0 and t then
		H.Bar.Set(TL.bar, t, len)
	end
end

local function OnZone()
	if H.Run.Length() ~= TL.lastLen then
		TL.lastLen = H.Run.Length()
		Ticks()
	end
	Place()
end

local function Build()
	local sec = CreateFrame("Frame", nil, UIParent)
	TL.frame = sec
	TL.bar = H.Bar.New(sec, { w = Tr.PanelWidth() - 8, h = BAR_H, bg = "dock" })
	TL.bar:SetPoint("LEFT", sec, "LEFT", R(4), 0)
	TL.over = CreateFrame("Frame", nil, TL.bar)
	TL.over:SetAllPoints(TL.bar)
	TL.over:SetFrameLevel(TL.bar:GetFrameLevel() + 3)
	for i = 1, MAXT do
		local t = TL.over:CreateTexture(nil, "OVERLAY")
		t:SetTexture(H.Kit.FLAT)
		t:Hide()
		TL.ticks[i] = t
	end
	Tr.AddSection("timeline", sec, ROW_H, 30)
end

Tr.Part("timeline", {
	build = Build,
	refresh = Refresh,
	place = Place,
	tick = Tick,
	hide = function()
		TL.shown = false
	end,
	reset = function()
		TL.lastLen = nil
		TL.shown = false
	end,
	settings = function(key)
		if key == "timeline" then
			Place()
		end
	end,
	on = {
		SCHEDULE_CHANGED = function()
			Ticks()
			Place()
		end,
		BOSS_UP = Ticks, BOSS_DEAD = Ticks, ZONE = OnZone, RUN = OnZone,
	},
	dump = function(out)
		local n = 0
		for i = 1, MAXT do
			if TL.ticks[i] and TL.ticks[i]:IsShown() then
				n = n + 1
			end
		end
		table.insert(out, "полоса времени: показана "..tostring(TL.shown).."  засечек "..n.."  длина "..tostring(H.Run.Length()))
	end,
})
