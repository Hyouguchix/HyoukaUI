-- HyoukaUI: Frames\ClassBar, класс-ресурс над рядом способностей (кусок col.class) (plan 3.1).
--
-- Сегменты по классовому счетчику забега: ключ proc, текущее pv (дробное), максимум pm. Рамка одна на всю
-- полосу, зазор 1 px, пустые сегменты #080808 0.85. Дробная часть pv рисуется частичной яркостью следующего
-- сегмента. Без proc кусок скрыт и схлопывается (Layout), цепочка выше опускается.
-- Цвет: bloodrage #E62626, seal_fate #FFF569, soul_fire цвет класса героя, lightwell #008CFF.
-- Сегменты: bloodrage 5 (шкала 0-100), lightwell 3 (одно значение 0-1 на три колодца) [НЕ ПРОВЕРЕНО],
-- остальные pm.
-- Данные: H.Run.Get("proc"|"pv"|"pm"), событие RUN.

local H = HyoukaUI
local F = H.Frames
local T = H.Theme

local S = { bar = nil, text = nil, proc = nil, partial = 0, whole = -1, segs = -1 }
F.ClassBar = S

local part = F.Part("classbar", {})

local PROC = {
	bloodrage = { 0.902, 0.149, 0.149 },
	seal_fate = { 1.0, 0.961, 0.412 },
	lightwell = { 0.0, 0.549, 1.0 },
}

function part.Build()
	local bar = H.Bar.NewSeg(UIParent, { w = 321, h = 13, bg = "dock", gap = 1 })
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	S.bar = bar
	local fs = H.Text.New(bar, "small", { justify = "RIGHT" })
	fs:SetPoint("RIGHT", bar, "RIGHT", -H.R(2), 0)
	S.text = fs
end

local function Color(proc)
	local c = PROC[proc]
	if c then
		return c[1], c[2], c[3]
	end
	return H.Hero.ClassColor()
end

-- Сброс дробного сегмента на цвет пустого.
local function ClearPartial()
	local idx = S.partial
	if idx > 0 then
		local t = S.bar.huiSegs[idx]
		if t then
			local d = T.C.darkRest
			t:SetVertexColor(d[1], d[2], d[3], d[4])
		end
		S.partial = 0
	end
end

function S.Update()
	local bar = S.bar
	if not bar then
		return
	end
	local proc = H.Run.Get("proc")
	if type(proc) ~= "string" or proc == "" or not F.Opt("showClass") then
		F.Show("col.class", false)
		return
	end
	local pv, pm = H.Run.Get("pv") or 0, H.Run.Get("pm") or 0
	local segs, val
	if proc == "bloodrage" then
		segs = 5
		val = pm > 0 and pv / pm * 5 or 0
	elseif proc == "lightwell" then
		segs = 3
		val = pm > 0 and pv / pm * 3 or 0
	else
		segs = pm
		val = pv
	end
	if segs < 1 then
		F.Show("col.class", false)
		return
	end
	if proc ~= S.proc then
		S.proc = proc
		H.Bar.SegColor(bar, Color(proc))
	end
	local whole = math.floor(val + 0.0001)
	if whole > segs then
		whole = segs
	end
	local frac = val - whole
	if S.segs ~= segs or S.whole ~= whole then
		ClearPartial()
	end
	H.Bar.SegSet(bar, whole, segs)
	S.segs, S.whole = segs, whole
	if frac > 0.01 and whole < segs then
		local t = bar.huiSegs[whole + 1]
		if t then
			local r, g, b = T.Tint(bar.huiLit[1], bar.huiLit[2], bar.huiLit[3])
			t:SetVertexColor(r, g, b, frac)
			S.partial = whole + 1
		end
	else
		ClearPartial()
	end
	H.Text.SetInt(S.text, whole)
	F.Show("col.class", true)
end

function part.Enable(mode)
	F.Piece("col.class", S.bar)
	S.proc, S.segs, S.whole = nil, -1, -1
end

function part.Disable()
	F.Unpiece("col.class")
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showClass" then
		S.Update()
	end
end

F.On("RUN", S.Update)
F.On("HERO_CHANGED", function()
	S.proc = nil
	S.Update()
end)
F.On("THEME", function()
	S.segs = -1
	S.Update()
end)
