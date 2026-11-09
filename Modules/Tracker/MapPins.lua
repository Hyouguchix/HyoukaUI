-- HyoukaUI: Modules\Tracker\MapPins, пины сундуков, логов и боссов на миникарте (plan 3.2, tracker#34, #35).
--
-- ДАННЫЕ. Модули глобалов AZS_* не читают, поэтому пины берут мир у слоя данных H.World (ЗАПРОС К ДАННЫМ: файл
-- Data\World.lua, готовый текст лежит в записке передачи и в mock\ext_tracker.lua):
--   H.World.Player()  -> x, y, z, facing   положение героя в ярдах мира и направление, nil если не известно
--   H.World.Chests()  -> массив { id, x, y }   сундуки забега (пусто, если данные устарели)
--   H.World.Bosses()  -> массив { kind, name, x, y }   боссы и финальный босс (необязательно)
-- Логова берутся из H.Schedule.Lairs() (поля x, y, state, flag). Если H.World нет, пины молчат, остальной трекер работает.
--
-- ГЕОМЕТРИЯ. Мир: x растет на север, y на запад (так читает SurvivorUI MapPins.lua:228). От героя до цели:
-- на восток east = py - y, на север north = x - px, ярды dist = sqrt(east^2 + north^2). Курс по часовой от севера
-- bearing = atan2(east, north); направление героя heading = -facing (facing игры держит камеру, SurvivorUI берет
-- минус, api 2.8); относительный курс rel = bearing - heading, отрицательный влево, положительный вправо.
-- Карта без вращения: пин стоит в (east, north) * масштаб; если включено вращение карты (CVar rotateMinimap = 1,
-- [НЕ ПРОВЕРЕНО] как именно benilla крутит карту), пин считается по rel. Масштаб карты в ярдах игра не отдает:
-- радиус квадрата задается настройкой pinRange (по умолчанию 120 ярдов), направление и расстояние точные.
-- Пин дальше радиуса садится на край квадрата в ту же сторону (размер 11/16, альфа 0.7), ближе радиуса внутри.
-- Расстояния и курсы последнего шага лежат в /hui dump pins (расстояние до сундука при ходьбе к нему убывает).
-- Позиции считаются раз в 0.1 с, не в каждом кадре. Режим Вместо прячет флажок игры (Claim "flag" из Hub).

local H = HyoukaUI

local Tr = H.Tr

local getn = table.getn
local sqrt, atan2, sin, cos, abs, floor = math.sqrt, math.atan2, math.sin, math.cos, math.abs, math.floor

local PI = 3.14159265358979
local MAXP, PIN, PIN_EDGE, STEP = 24, 16, 11, 0.1

local PN = { pool = {}, count = 0, kinds = {}, yd = {}, br = {}, rel = {}, edge = {}, lastAt = 0, rotate = false, last = nil }
Tr.Pins = PN

local function R(px)
	return H.R(px)
end

----------------------------------------------------------------------------------------
-- Геометрия (чистые функции: тесты проверяют их без кадров)
----------------------------------------------------------------------------------------

-- Ярды, курс по часовой от севера (градусы, 0..360) и относительный курс (градусы, -180..180) от героя
-- (px, py, facing) до точки (x, y).
function PN.Bearing(px, py, facing, x, y)
	local east, north = py - y, x - px
	local yards = sqrt(east * east + north * north)
	local b = atan2(east, north)
	if b < 0 then
		b = b + 2 * PI
	end
	local heading = -(facing or 0)
	local rel = b - heading
	while rel > PI do
		rel = rel - 2 * PI
	end
	while rel <= -PI do
		rel = rel + 2 * PI
	end
	return yards, b * 180 / PI, rel * 180 / PI
end

-- Положение пина относительно центра карты в единицах полуширины (-1..1) и признак "на краю".
-- range: радиус квадрата в ярдах. rotateBy: угол вращения карты в радианах или nil (карта без вращения).
function PN.Offset(east, north, range, rotateBy)
	if rotateBy then
		local c, s = cos(rotateBy), sin(rotateBy)
		east, north = east * c - north * s, east * s + north * c
	end
	local m = abs(east)
	if abs(north) > m then
		m = abs(north)
	end
	if m <= range then
		return east / range, north / range, false
	end
	return east / m, north / m, true
end

----------------------------------------------------------------------------------------
-- Пины
----------------------------------------------------------------------------------------

local function NewPin()
	local f = CreateFrame("Frame", nil, PN.over)
	f:SetWidth(R(PIN))
	f:SetHeight(R(PIN))
	local t = f:CreateTexture(nil, "OVERLAY")
	t:SetAllPoints(f)
	f:Hide()
	return { frame = f, tex = t, kind = nil, edge = false }
end

local function Style(pin, kind, state, flagged)
	local T = H.Theme
	local C = Tr.C
	if kind == "chest" then
		pin.tex:SetTexture(T.TEX.pinChest)
		pin.tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
		pin.size = PIN
	elseif kind == "lair" then
		pin.tex:SetTexture(T.TEX.pinSkull)
		if flagged then
			pin.tex:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
		elseif state == "empty" then
			pin.tex:SetVertexColor(0.5, 0.5, 0.5, 0.7)
		elseif state == "awake" then
			pin.tex:SetVertexColor(C.orange[1], C.orange[2], C.orange[3], 1)
		else
			pin.tex:SetVertexColor(1, 1, 1, 1)
		end
		pin.size = PIN
	else
		pin.tex:SetTexture(T.TEX.pinSkull)
		if kind == "final" then
			pin.tex:SetVertexColor(C.orange[1], C.orange[2], C.orange[3], 1)
		else
			pin.tex:SetVertexColor(C.bossKind[1], C.bossKind[2], C.bossKind[3], 1)
		end
		pin.size = PIN + 4
	end
	pin.kind = kind
end

-- Поставить пин цели; возвращает расстояние в ярдах.
local function PutPin(kind, x, y, px, py, facing, half, range, state, flagged)
	if type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	local i = PN.count + 1
	if i > MAXP then
		return
	end
	PN.count = i
	local pin = PN.pool[i]
	if not pin then
		pin = NewPin()
		PN.pool[i] = pin
	end
	if pin.kind ~= kind or pin.state ~= state or pin.flagged ~= flagged then
		Style(pin, kind, state, flagged)
		pin.state, pin.flagged = state, flagged
	end
	local yards, bearing, rel = PN.Bearing(px, py, facing, x, y)
	local east, north = py - y, x - px
	local rot = nil
	if PN.rotate then
		rot = -(facing or 0)
	end
	local ux, uy, edge = PN.Offset(east, north, range, rot)
	local size = edge and R(PIN_EDGE) or R(pin.size or PIN)
	if edge ~= pin.edge or size ~= pin.sz then
		pin.edge, pin.sz = edge, size
		pin.frame:SetWidth(size)
		pin.frame:SetHeight(size)
		pin.frame:SetAlpha(edge and 0.7 or 1)
	end
	local lim = half - size / 2
	local ax, ay = ux * lim, uy * lim
	if ax ~= pin.ax or ay ~= pin.ay then
		pin.ax, pin.ay = ax, ay
		pin.frame:ClearAllPoints()
		pin.frame:SetPoint("CENTER", PN.holder, "CENTER", ax, ay)
	end
	if not pin.shown then
		pin.shown = true
		pin.frame:Show()
	end
	PN.kinds[i], PN.yd[i], PN.br[i], PN.rel[i], PN.edge[i] = kind, yards, bearing, rel, edge
end

local function HideFrom(i)
	for j = i, getn(PN.pool) do
		local pin = PN.pool[j]
		if pin.shown then
			pin.shown = false
			pin.frame:Hide()
		end
	end
end

local function Step(now)
	local W = H.World
	if not W or not W.Player then
		PN.count = 0
		HideFrom(1)
		return
	end
	local px, py, pz, facing = W.Player()
	if not px or not py then
		PN.count = 0
		HideFrom(1)
		return
	end
	local range = Tr.Opt("pinRange")
	if not range or range < 10 then
		range = 10
	end
	local half = ((PN.holder:GetWidth() or R(230)) - 2 * H.Theme.Border()) / 2
	PN.count = 0
	PN.px, PN.py, PN.facing = px, py, facing
	local chests = W.Chests and W.Chests()
	if chests then
		for i = 1, getn(chests) do
			PutPin("chest", chests[i].x, chests[i].y, px, py, facing, half, range)
		end
	end
	local lairs = H.Schedule.Lairs()
	for i = 1, getn(lairs) do
		local l = lairs[i]
		PutPin("lair", l.x, l.y, px, py, facing, half, range, l.state, l.flag == 1)
	end
	if Tr.Opt("pinBosses") and W.Bosses then
		local list = W.Bosses()
		if list then
			for i = 1, getn(list) do
				PutPin(list[i].kind == "finalBoss" and "final" or "boss", list[i].x, list[i].y, px, py, facing, half, range)
			end
		end
	end
	HideFrom(PN.count + 1)
end

local function Active()
	return Tr.Opt("pins") and Tr.InRun() and PN.holder ~= nil and PN.holder:IsShown()
end

--@frame
local function Tick(now)
	if now - PN.lastAt < STEP then
		return
	end
	PN.lastAt = now
	if PN.on then
		Step(now)
	end
end

local function Rotation()
	local ok, v = pcall(GetCVar, "rotateMinimap")
	PN.rotate = (ok and v == "1")
end

local function Place()
	if not PN.over then
		return
	end
	local on = Active() and true or false
	PN.on = on
	Tr.Set(PN.over, on)
	if not on then
		PN.count = 0
		HideFrom(1)
	else
		Rotation()
		Step(H.Now())
	end
end

local function Build()
	PN.holder = Tr.Minimap and Tr.Minimap.holder
	PN.over = CreateFrame("Frame", nil, PN.holder or UIParent)
	if PN.holder then
		PN.over:SetAllPoints(PN.holder)
		PN.over:SetFrameLevel(PN.holder:GetFrameLevel() + 10)
	end
end

Tr.Part("pins", {
	build = Build,
	place = Place,
	tick = Tick,
	refresh = Place,
	slow = function(now)
		if PN.on then
			Rotation()
		end
	end,
	settings = function(key)
		Place()
	end,
	hide = function()
		PN.on = false
		PN.count = 0
		if PN.over then
			HideFrom(1)
		end
	end,
	on = { CHESTS = Place, LAIRS_CHANGED = Place },
	dump = function(out)
		table.insert(out, "== Пины ==")
		table.insert(out, "H.World "..(H.World and "есть" or "НЕТ (запрос к слою данных)").."  пинов "..PN.count
			.."  радиус "..tostring(Tr.Opt("pinRange")).." ярдов  вращение карты "..tostring(PN.rotate))
		if PN.px then
			table.insert(out, string.format("герой x %.1f y %.1f facing %.2f (heading %.2f)", PN.px, PN.py, PN.facing or 0, -(PN.facing or 0)))
		end
		for i = 1, PN.count do
			local rel = PN.rel[i]
			table.insert(out, string.format("%2d %-6s %7.1f ярдов  курс %6.1f  относительно %6.1f (%s)%s", i, PN.kinds[i], PN.yd[i],
				PN.br[i], rel, rel < 0 and "влево" or "вправо", PN.edge[i] and "  на краю" or "  внутри"))
		end
	end,
})
