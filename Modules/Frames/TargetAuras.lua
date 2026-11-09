-- HyoukaUI: Frames\TargetAuras, дебафы цели над рамкой цели (кусок uf.targetAuras) (plan 3.1, spec 3.1).
--
-- Иконки 33 ретейл-px, шаг 1, 8 в ряд, рост влево и вверх от правого верхнего угла рамки цели. Рядов по
-- умолчанию 1 (опция auraRows до 3). Отступление от ретейла (там баффы цели): в игре полезны ваши DoT, поэтому
-- дебафы. Источник H.Units.Debuffs("target"): для боссов и стражей AZS_GetDebuffs (длительность, остаток,
-- стаки, тип снятия), для остальных UnitDebuff (иконка, стаки). Свои дебафы (H.Units.Owns по id заклинания)
-- с акцентной рамкой, остальные по типу снятия или черные. Цифры отката (роль body) по центру, стаки справа
-- снизу, шторки нет у откатов короче порога. Список читается только по событиям (вызов создает таблицы):
-- PLAYER_TARGET_CHANGED, UNIT_AURA (target), DEBUFFS, TARGET, UNITS_CHANGED.
-- Число рядов отдается Layout (SetRows, SetSize): при 2 и более рядах кусок поднимается над выделенными
-- полосами Трекера по правилу above из LayoutDefaults.

local H = HyoukaUI
local F = H.Frames
local B = F.Buttons
local I = H.Icon
local T = H.Theme
local L = H.Layout

local S = { frame = nil, pool = nil, rows = 0 }
F.TargetAuras = S

local part = F.Part("targetauras", {})

local SIZE, GAP, PER_ROW = 33, 1, 8

function part.Build()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("LOW")
	f:Hide()
	S.frame = f
	S.pool = B.Pool(f, { size = SIZE, digitsRole = "body", stackRole = "small" })
end

local function Place(n)
	local step = H.R(SIZE) + H.R(GAP)
	if not B.NeedPlace(S.pool, n, step) then
		return
	end
	for k = 1, n do
		local ic = S.pool.list[k]
		local col = math.mod(k - 1, PER_ROW)
		local row = math.floor((k - 1) / PER_ROW)
		ic:ClearAllPoints()
		ic:SetPoint("BOTTOMRIGHT", S.frame, "BOTTOMRIGHT", -col * step, row * step)
	end
end

-- Высота куска по числу рядов (ретейл-px) и число рядов для правила above.
local function SetRows(rows)
	if rows == S.rows then
		return
	end
	S.rows = rows
	if L.Has("uf.targetAuras") then
		local r = rows
		if r < 1 then
			r = 1
		end
		L.SetSize("uf.targetAuras", nil, r * SIZE + (r - 1) * GAP)
		L.SetRows("uf.targetAuras", rows)
	end
end

local function Border(ic, rec)
	if rec.spell ~= nil and H.Units.Owns(rec.spell) then
		local r, g, b = T.AccentRGB()
		I.SetBorderColor(ic, r, g, b, 1)
		return
	end
	local c = rec.dispelType and T.DISPEL[rec.dispelType]
	if c then
		I.SetBorderColor(ic, c[1], c[2], c[3], 1)
	else
		I.SetBorderColor(ic, 0, 0, 0, 1)
	end
end

function S.Update()
	local f = S.frame
	if not f then
		return
	end
	local n = 0
	local exists = F.Unit("UnitExists", "target")
	if exists and F.Opt("showTargetAuras") then
		local list = H.Units.Debuffs("target")
		local cap = PER_ROW * F.Opt("auraRows")
		local total = table.getn(list)
		for i = 1, total do
			if n < cap then
				local rec = list[i]
				n = n + 1
				local ic = B.Get(S.pool, n)
				I.SetTexture(ic, rec.icon or B.UNKNOWN)
				I.SetStack(ic, rec.stacks or 0)
				if rec.duration and rec.remaining and not rec.permanent then
					B.SetEnds(ic, rec.duration, rec.remaining)
				else
					I.Clear(ic)
				end
				Border(ic, rec)
			end
		end
	end
	B.Finish(S.pool, n)
	if n > 0 then
		Place(n)
	end
	SetRows(math.ceil(n / PER_ROW))
	F.Show("uf.targetAuras", n > 0)
end

function part.Enable(mode)
	S.rows = -1
	F.Piece("uf.targetAuras", S.frame)
	S.Update()
end

function part.Disable()
	B.Finish(S.pool, 0)
	F.Unpiece("uf.targetAuras")
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showTargetAuras" or key == "auraRows" then
		S.Update()
	end
end

F.On("PLAYER_TARGET_CHANGED", S.Update)
F.On("UNIT_AURA", function(ev, unit)
	if unit == "target" then
		S.Update()
	end
end)
F.On("DEBUFFS", S.Update)
F.On("TARGET", S.Update)
F.On("UNITS_CHANGED", S.Update)
F.On("THEME", S.Update)
