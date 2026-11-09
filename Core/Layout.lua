-- HyoukaUI: раскладка. Реестр кусков, анкор-цепочки в ретейл-пикселях, стеки со схлопыванием,
-- сохраненные смещения пользователя (plan 2.2 Layout, 2.8, 5).
--
-- ФОРМАТ Data\LayoutDefaults.lua (H.LayoutDefaults), все числа в РЕТЕЙЛ-пикселях (= 1 физический
-- пиксель при ppUIScale 0.5333). В AS их переводит H.R(px) (снап к физическому пикселю):
--
--   H.LayoutDefaults = {
--     pieces = {
--       ["col.main"] = {
--         label = "Способности",                 -- подпись в режиме перемещения
--         point = "CENTER", rel = "UIParent", relPoint = "CENTER", x = 0, y = -290,   -- y вверх, как SetPoint
--         w = 321, h = 45,                       -- размер (width/height тоже понимаются)
--         slots = 7, icon = 45, gap = 1,         -- необязательно: w = slots*icon + (slots-1)*gap
--         widthMatch = "col.main",               -- необязательно: ширина как у другого куска (правило 171.2 AS)
--         collapse = true,                       -- скрытый кусок не занимает места: дети берут его якорь
--         fallback = { point, relPoint, x, y },  -- от UIParent, если куска rel нет (модуль выключен)
--         movable = false, overCards = true,     -- movable по умолчанию true
--       },
--     },
--     order = { "col.main", ... },               -- необязательно: порядок для Mover и Demo
--     above = { ["uf.targetAuras"] = { over = "tr.barsEmph", point = "BOTTOMRIGHT",
--               relPoint = "TOPRIGHT", x = 0, y = 2, minRows = 2 } },
--   }
--
-- Таблица без поля pieces тоже принимается (кусок под своим id прямо в корне).
--
-- Сохранения: HyoukaUIDB.layout[id] = { p, rp, x, y, scale, hidden }. Только оторванные или
-- измененные куски; умолчания не пишутся. x, y в ретейл-пикселях от угла экрана p.
--
-- Rect(id) -> left, top, w, h в AS, начало в левом верхнем углу UIParent, y вниз. Размеры и смещения
-- снапятся по отдельности, как у движка. Смещения и размеры куска умножаются на его scale.

local H = HyoukaUI

local getn = table.getn

local L = {}
H.Layout = L

local FRAC = {
	TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 },
}
L.FRAC = FRAC

local FALLBACK_W, FALLBACK_H = 1365.333, 768
local MAX_HOPS = 8

local defs = {}       -- id -> описание из таблицы умолчаний
local defOrder = {}   -- id по порядку
local aboveRules = {}
local pieces = {}     -- id -> { id, frame, def }
local pieceOrder = {}
local emptyFlag = {}  -- id -> true: кусок пуст (для кусков без кадра)
local sizeOv = {}     -- id -> { w, h } в ретейл-px, выставляет модуль
local rowsOf = {}     -- id -> число рядов (правило above)
local ignoreId = nil
local applying = false

----------------------------------------------------------------------------------------
-- Единицы
----------------------------------------------------------------------------------------

local function PX()
	return H.Kit and H.Kit.PX() or 0.5333
end

local function R(px)
	if H.R then
		return H.R(px)
	end
	return px * PX()
end

-- Размер области рисования в единицах привязок кадров. Проверено в игре (2026-11-09): при uiScale 0.9
-- UIParent:GetWidth() = 1365.333, а экран в тех же единицах шире: GetScreenWidth() = 1517.037
-- (1365.333 / 0.9). Привязки от левого верхнего угла считаются по GetScreenWidth/Height.
function L.Screen()
	local w, h
	if GetScreenWidth and GetScreenHeight then
		w, h = GetScreenWidth(), GetScreenHeight()
	end
	if not w or not h or w <= 0 or h <= 0 then
		w, h = FALLBACK_W, FALLBACK_H
		if UIParent then
			w = UIParent:GetWidth() or w
			h = UIParent:GetHeight() or h
			if w <= 0 or h <= 0 then
				w, h = FALLBACK_W, FALLBACK_H
			end
		end
	end
	return w, h
end

----------------------------------------------------------------------------------------
-- Таблица умолчаний
----------------------------------------------------------------------------------------

local function Sorted(map)
	local keys = {}
	for k, v in pairs(map) do
		if type(v) == "table" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

-- Принять таблицу в формате из заголовка (используют Data\LayoutDefaults и тесты).
function L.SetDefaults(t)
	defs, defOrder, aboveRules = {}, {}, {}
	if type(t) ~= "table" then
		return
	end
	local src = t.pieces or t
	for k, v in pairs(src) do
		if type(k) == "string" and type(v) == "table" and (v.point or v.w or v.width or v.rel) then
			defs[k] = v
		end
	end
	if t.order then
		for i = 1, getn(t.order) do
			if defs[t.order[i]] then
				table.insert(defOrder, t.order[i])
			end
		end
	end
	local seen = {}
	for i = 1, getn(defOrder) do
		seen[defOrder[i]] = true
	end
	local rest = Sorted(defs)
	for i = 1, getn(rest) do
		if not seen[rest[i]] then
			table.insert(defOrder, rest[i])
		end
	end
	if type(t.above) == "table" then
		aboveRules = t.above
	end
end

local loaded = false

local function EnsureDefaults()
	if not loaded then
		loaded = true
		if H.LayoutDefaults then
			L.SetDefaults(H.LayoutDefaults)
		end
	end
end

function L.Defs()
	EnsureDefaults()
	return defs, defOrder
end

function L.Def(id)
	EnsureDefaults()
	local p = pieces[id]
	return p and p.def or defs[id]
end

-- Название куска для окон перемещения и карточки: строка pc.<id> текущего языка, иначе label из описания куска
-- (запасное, для кусков без своего ключа), иначе id.
function L.PieceLabel(id, def)
	local key = "pc."..id
	local v = H.L and H.L[key]
	if v ~= nil and v ~= key then
		return v
	end
	def = def or (H.LayoutDefaults and H.LayoutDefaults.pieces[id])
	return (def and def.label) or id
end

-- Только для тестов: подменить таблицу и снять все регистрации.
function L.Reset_()
	loaded = true
	L.SetDefaults(nil)
	pieces, pieceOrder, emptyFlag, sizeOv, rowsOf = {}, {}, {}, {}, {}
end

----------------------------------------------------------------------------------------
-- Сохранения
----------------------------------------------------------------------------------------

local function Store()
	local db = HyoukaUIDB
	return type(db) == "table" and db.layout or nil
end

function L.Saved(id)
	local s = Store()
	return s and s[id] or nil
end

local function SavedMake(id)
	local s = Store()
	if not s then
		return nil
	end
	if not s[id] then
		s[id] = {}
	end
	return s[id]
end

-- Запись без полезного содержимого удаляется: умолчания не пишутся.
local function SavedClean(id)
	local s = Store()
	local r = s and s[id]
	if r and r.p == nil and (r.scale == nil or r.scale == 1) and not r.hidden then
		s[id] = nil
	end
end

function L.IsDetached(id)
	local r = L.Saved(id)
	return r ~= nil and r.p ~= nil
end

function L.Scale(id)
	local r = L.Saved(id)
	local s = r and r.scale
	if not s then
		local d = L.Def(id)
		s = d and d.scale
	end
	return s or 1
end

function L.IsHiddenByUser(id)
	local r = L.Saved(id)
	return r ~= nil and r.hidden == true
end

----------------------------------------------------------------------------------------
-- Видимость и схлопывание
----------------------------------------------------------------------------------------

local function IsVisible(id)
	local p = pieces[id]
	if not p then
		return false
	end
	if p.frame then
		return p.frame:IsShown() and true or false
	end
	return not emptyFlag[id]
end
L.IsVisible = IsVisible

local function Collapsed(id)
	local p = pieces[id]
	return p ~= nil and p.def.collapse == true and not IsVisible(id)
end

function L.IsCollapsed(id)
	return Collapsed(id)
end

----------------------------------------------------------------------------------------
-- Якорь куска: сохраненное смещение, правило above, схлопнутые родители, запасной якорь
----------------------------------------------------------------------------------------

-- Возвращает point, relId, relPoint, x, y (px, y вверх). relId = "UIParent" или id присутствующего куска.
local function Anchor(id)
	local p = pieces[id]
	local d = p.def
	local point, rel, relPoint, x, y
	local r = (ignoreId ~= id) and L.Saved(id) or nil
	if r and r.p then
		return r.p, "UIParent", r.rp or r.p, r.x or 0, r.y or 0
	end
	local rule = aboveRules[id]
	if rule and (rowsOf[id] or 1) >= (rule.minRows or 2) and pieces[rule.over] and IsVisible(rule.over) then
		return rule.point, rule.over, rule.relPoint or rule.point, rule.x or 0, rule.y or 0
	end
	point, rel, relPoint, x, y = d.point or "CENTER", d.rel or "UIParent", d.relPoint or d.point or "CENTER", d.x or 0, d.y or 0
	local hops = 0
	while rel ~= "UIParent" and pieces[rel] and Collapsed(rel) and hops < MAX_HOPS do
		local pd = pieces[rel].def
		relPoint = pd.relPoint or pd.point or relPoint
		rel = pd.rel or "UIParent"
		hops = hops + 1
	end
	if rel ~= "UIParent" and not pieces[rel] then
		local fb = d.fallback
		if fb then
			return fb.point or point, "UIParent", fb.relPoint or fb.point or point, fb.x or 0, fb.y or 0
		end
		return "CENTER", "UIParent", "CENTER", 0, 0
	end
	return point, rel, relPoint, x, y
end

----------------------------------------------------------------------------------------
-- Размеры и прямоугольники
----------------------------------------------------------------------------------------

local function WidthPx(id, depth)
	local ov = sizeOv[id]
	if ov and ov.w then
		return ov.w
	end
	local p = pieces[id]
	local d = p and p.def or defs[id]
	if not d then
		return 0
	end
	if d.widthMatch and d.widthMatch ~= id and (depth or 0) < MAX_HOPS and (pieces[d.widthMatch] or defs[d.widthMatch]) then
		return WidthPx(d.widthMatch, (depth or 0) + 1)
	end
	if d.slots then
		return d.slots * (d.icon or 0) + (d.slots - 1) * (d.gap or 0)
	end
	return d.w or d.width or 0
end

local function HeightPx(id)
	local ov = sizeOv[id]
	if ov and ov.h then
		return ov.h
	end
	local p = pieces[id]
	local d = p and p.def or defs[id]
	return d and (d.h or d.height) or 0
end

function L.SizePx(id)
	return WidthPx(id), HeightPx(id)
end

local function RectOf(id, depth)
	local p = pieces[id]
	if not p or (depth or 0) > 16 then
		return nil
	end
	local scale = L.Scale(id)
	local w, h = R(WidthPx(id)) * scale, R(HeightPx(id)) * scale
	local point, rel, relPoint, x, y = Anchor(id)
	local rl, rt, rw, rh
	if rel == "UIParent" then
		rl, rt = 0, 0
		rw, rh = L.Screen()
	else
		rl, rt, rw, rh = RectOf(rel, (depth or 0) + 1)
		if not rl then
			rl, rt = 0, 0
			rw, rh = L.Screen()
		end
	end
	local fr = FRAC[relPoint] or FRAC.CENTER
	local fp = FRAC[point] or FRAC.CENTER
	local tx = rl + fr[1] * rw + R(x) * scale
	local ty = rt + fr[2] * rh - R(y) * scale
	return tx - fp[1] * w, ty - fp[2] * h, w, h
end

function L.Rect(id)
	return RectOf(id, 0)
end

-- То же в ретейл-px (деление на PX): для сравнения с tests\geometry_expected.lua.
function L.RectPx(id)
	local l, t, w, h = RectOf(id, 0)
	if not l then
		return nil
	end
	local px = PX()
	return l / px, t / px, w / px, h / px
end

-- Прямоугольник без сохраненного места самого куска (куда "на место").
function L.DefaultRect(id)
	ignoreId = id
	local l, t, w, h = RectOf(id, 0)
	ignoreId = nil
	return l, t, w, h
end

----------------------------------------------------------------------------------------
-- Применение к кадрам
----------------------------------------------------------------------------------------

function L.Apply(id)
	local p = pieces[id]
	if not p or not p.frame then
		return
	end
	local f, d = p.frame, p.def
	local scale = L.Scale(id)
	local point, rel, relPoint, x, y = Anchor(id)
	f:ClearAllPoints()
	local relFrame = UIParent
	if rel ~= "UIParent" then
		relFrame = pieces[rel].frame
		if not relFrame then
			local l, t = RectOf(id, 0)
			f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", l / scale, -t / scale)
			relFrame = nil
		end
	end
	if relFrame then
		f:SetPoint(point, relFrame, relPoint, R(x), R(y))
	end
	if not d.autosize then
		local w, h = WidthPx(id), HeightPx(id)
		if w > 0 then
			f:SetWidth(R(w))
		end
		if h > 0 then
			f:SetHeight(R(h))
		end
	end
	f:SetScale(scale)
	if L.IsHiddenByUser(id) and p.origHide then
		p.origHide(f)
	end
end

function L.Reflow()
	if applying then
		return
	end
	applying = true
	for i = 1, getn(pieceOrder) do
		L.Apply(pieceOrder[i])
	end
	applying = false
end

-- Кусок показали или скрыли: цепочки пересчитываются без опроса.
function L.Touch(id)
	if id == nil or pieces[id] then
		L.Reflow()
	end
end

local function Wrap(p)
	local f = p.frame
	if p.wrapped or not f or not f.Show then
		return
	end
	p.wrapped = true
	p.origShow, p.origHide = f.Show, f.Hide
	local id = p.id
	f.Show = function(self, a)
		if L.IsHiddenByUser(id) then
			return
		end
		p.origShow(self, a)
		L.Touch(id)
	end
	f.Hide = function(self, a)
		p.origHide(self, a)
		L.Touch(id)
	end
end

-- Зарегистрировать кусок. frame может быть nil (виртуальный кусок: демо, тесты, расчет геометрии).
-- def необязателен и поверх таблицы умолчаний. Возвращает запись куска.
function L.Piece(id, frame, def)
	EnsureDefaults()
	local merged = {}
	local base = defs[id]
	if base then
		for k, v in pairs(base) do
			merged[k] = v
		end
	end
	if def then
		for k, v in pairs(def) do
			merged[k] = v
		end
	end
	local p = pieces[id]
	if not p then
		p = { id = id }
		pieces[id] = p
		table.insert(pieceOrder, id)
	end
	p.frame, p.def = frame, merged
	if frame and (merged.collapse or L.IsHiddenByUser(id)) then
		Wrap(p)
	end
	L.Reflow()
	return p
end

function L.Unpiece(id)
	local p = pieces[id]
	if not p then
		return
	end
	if p.wrapped and p.frame then
		p.frame.Show, p.frame.Hide = nil, nil
	end
	pieces[id] = nil
	for i = getn(pieceOrder), 1, -1 do
		if pieceOrder[i] == id then
			table.remove(pieceOrder, i)
		end
	end
	emptyFlag[id], sizeOv[id], rowsOf[id] = nil, nil, nil
	L.Reflow()
end

function L.Has(id)
	return pieces[id] ~= nil
end

function L.Frame(id)
	return pieces[id] and pieces[id].frame
end

-- Зарегистрированные id: по порядку таблицы умолчаний, затем остальные в порядке регистрации.
function L.Ids()
	EnsureDefaults()
	local out, seen = {}, {}
	for i = 1, getn(defOrder) do
		if pieces[defOrder[i]] then
			table.insert(out, defOrder[i])
			seen[defOrder[i]] = true
		end
	end
	for i = 1, getn(pieceOrder) do
		if not seen[pieceOrder[i]] then
			table.insert(out, pieceOrder[i])
		end
	end
	return out
end

-- Кусок без кадра: пустой или нет (для схлопывания в расчете).
function L.SetEmpty(id, empty)
	emptyFlag[id] = empty and true or nil
	L.Touch(id)
end

-- Размер от модуля в ретейл-px (nil оставляет умолчание). Для рядов, чей размер зависит от содержимого.
function L.SetSize(id, wpx, hpx)
	local ov = sizeOv[id]
	if not ov then
		ov = {}
		sizeOv[id] = ov
	end
	ov.w, ov.h = wpx, hpx
	L.Touch(id)
end

function L.SetRows(id, n)
	rowsOf[id] = n
	L.Touch(id)
end

----------------------------------------------------------------------------------------
-- Общие помощники для LayoutEdit и LayoutStack
----------------------------------------------------------------------------------------

L.Store, L.SavedMake, L.SavedClean = Store, SavedMake, SavedClean
L.R, L.PX = R, PX

function L.Changed(id)
	L.Reflow()
	H.Fire("LAYOUT", id)
end

-- Спрятать кадр куска в обход обертки (Show при hidden пользователя заблокирован).
function L.HideRaw(id)
	local p = pieces[id]
	if p and p.frame then
		Wrap(p)
		p.origHide(p.frame)
	end
end

-- Смена PX, акцента или толщины рамки (THEME): размеры и якоря кусков пересчитываются здесь, модулям звать Reflow не нужно
-- (их вызовы остаются безвредными: повторный проход дает те же числа).
H.On("THEME", "layout", L.Reflow)
