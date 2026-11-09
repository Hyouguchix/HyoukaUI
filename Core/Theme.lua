-- HyoukaUI: тема. Палитра-токены, физический пиксель (PX), перевод ретейл-пикселей в AS, рамка.
--
-- Единицы. Раскладка хранится в ретейл-пикселях (spec 2.2): 1 ретейл-пиксель = 1 физический пиксель.
-- Размер физического пикселя в единицах AS считается в рантайме (проба 0.3, README dev):
--   PX = 768 / (высота экрана в пикселях x эффективный масштаб UIParent)
--   2560x1440 при масштабе 0.9 -> 0.5926; 2560x1440 при масштабе 1.0 -> 0.5333.
-- Высота берется из CVar gxResolution (разбор через string.find с захватами), масштаб из
-- UIParent:GetEffectiveScale(). Пересчет на UI_SCALE_CHANGED, VARIABLES_LOADED, PLAYER_ENTERING_WORLD.
--
-- H.R(px)        ретейл-пиксели -> AS с привязкой к сетке физических пикселей
-- T.Px(n)        n физических пикселей в AS (без привязки)
-- T.Border()     толщина рамки в AS: ровно borderPx физических пикселей (по умолчанию 1)
-- T.AddBorder(frame, r, g, b, a)  четыре полоски по краю кадра; T.SetBorderColor(frame, r, g, b, a)
-- T.Accent() / T.AccentRGB()      цвет акцента (#7381FF, цвет класса или выбор пользователя)
-- T.Tint(r, g, b) -> r*0.76, g*0.76, b*0.76 (текстура atrocity, spec 1.5)
-- H.SourceColor(key) цвет источника по хэшу строки (стабильный между сессиями)
-- Событие THEME (без аргументов) при смене PX, акцента или толщины рамки.

local H = HyoukaUI

local T = {}
H.Theme = T

T.REF_HEIGHT = 768
T.TINT = 0.76
T.PX = 0.5333333
T.pxSource = "fallback"   -- "gx": посчитан из gxResolution и масштаба; "fallback": константа
T.screenW, T.screenH, T.scale = 0, 0, 1

local ADDON_TEX = "Interface\\AddOns\\HyoukaUI\\Media\\Textures\\"
T.TEX = {
	solid = "Interface\\ChatFrame\\ChatFrameBackground",   -- стоковая белая заливка, проверена игрой
	flat = ADDON_TEX.."flat",
	stripes = ADDON_TEX.."stripes",
	pip = ADDON_TEX.."pip",
	ring = ADDON_TEX.."ring",
	pinChest = ADDON_TEX.."pin_chest",
	pinSkull = ADDON_TEX.."pin_skull",
}

-- Палитра (spec 1.2). Цвета - массивы { r, g, b, a }.
T.C = {
	accent = { 0.451, 0.506, 1.0, 1 },
	panel = { 0.0314, 0.0314, 0.0314, 0.85 },     -- окна, панели, подсказки
	dock = { 0.0314, 0.0314, 0.0314, 0.80 },      -- полосы, док урона, пустые слоты
	inner = { 0.055, 0.055, 0.055, 0.90 },        -- кнопки, выпадающие списки
	tone = { 0.06, 0.06, 0.06, 0.80 },
	iconBg = { 0.08, 0.08, 0.08, 0.60 },          -- подложка иконок
	border = { 0, 0, 0, 1 },
	text = { 1, 1, 1, 1 },
	muted = { 0.5, 0.5, 0.5, 1 },                 -- пояснения, неактивное
	dim = { 0.486, 0.486, 0.486, 1 },             -- приглушенный текст (#7C7C7C)
	error = { 0.90, 0.30, 0.30, 1 },
	ok = { 0.30, 0.80, 0.40, 1 },
	warn = { 0.90, 0.75, 0.30, 1 },
	hover = { 0.851, 0.851, 0.851, 0.15 },       -- наведение без затухания
	select = { 0.451, 0.506, 1.0, 0.35 },        -- выбранный пункт меню
	fill = { 0.451, 0.506, 1.0, 0.40 },          -- заполнение прогресса
	darkRest = { 0.067, 0.067, 0.067, 0.90 },    -- остаток HP (dark mode)
	darkLost = { 0.31, 0.31, 0.31, 1 },
	absorbHeal = { 0.7098, 0.2078, 0.2078, 1 },  -- поглощение лечения #B53535
	castKick = { 0.6235, 0.749, 1.0, 1 },        -- прерываемый каст, кик готов
	castKickCd = { 0.7804, 0.7804, 0.7804, 1 },
	castNoKick = { 0.3137, 0.3137, 0.3137, 1 },
	deadBar = { 0.667, 0.192, 0.192, 1 },        -- #AA3131
	offlineBar = { 0.522, 0.392, 0.263, 1 },     -- #856443
	glow = { 1.0, 0.788, 0.137, 1 },             -- #FFC923
	pandemic = { 1.0, 0.2, 0.2, 1 },
	green = { 0, 1, 0, 1 },                      -- стаки статичных баффов
	zone = { 0.902, 0.851, 0.051, 1 },           -- зона на миникарте #E6D90D
}

-- Цвета вида цели (spec 5, неймплейты): трэш, элита, босс. Босс берет акцент.
T.KIND = {
	trash = { 0.635, 0.220, 0.220 },    -- #A23838
	elite = { 0.455, 0.443, 0.765 },    -- #7471C3
	boss = { 0.451, 0.506, 1.0 },
	emph = { 0.906, 0.165, 0.220 },     -- выделенная полоса босса #E72A38
}

-- Реакция NPC для имен: враг, нейтрал, друг.
T.REACTION = {
	hostile = { 0.90, 0.30, 0.30 },
	neutral = { 0.90, 0.75, 0.30 },
	friendly = { 0.30, 0.80, 0.40 },
	tapped = { 0.6, 0.6, 0.6 },
}

-- Цвета классов 1.12 (spec 1.2: значения по умолчанию, затемнения нет).
T.CLASS = {
	WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
	ROGUE = { 1.0, 0.96, 0.41 }, PRIEST = { 1.0, 1.0, 1.0 }, SHAMAN = { 0.0, 0.44, 0.87 },
	MAGE = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 }, DRUID = { 1.0, 0.49, 0.04 },
}

-- Ресурсы (spec 1.2).
T.RESOURCE = {
	rage = { 0.90, 0.15, 0.15 }, mana = { 0.0, 0.55, 1.0 }, energy = { 1.0, 0.96, 0.41 },
	focus = { 0.867, 0.573, 0.216 }, runic = { 0.769, 0.122, 0.231 },
}

-- Типы снимаемых эффектов (spec 1.2).
T.DISPEL = {
	Magic = { 0.2, 0.6, 1.0 }, Curse = { 0.6, 0.0, 1.0 }, Disease = { 0.6, 0.4, 0.0 },
	Poison = { 0.0, 0.6, 0.0 }, Bleed = { 0.75, 0.15, 0.15 },
}

-- Акценты на выбор (страница "Общее"); "default" - цвет проекта, "class" - цвет героя.
T.ACCENTS = {
	{ key = "default", color = { 0.451, 0.506, 1.0 } },
	{ key = "teal", color = { 0.047, 0.824, 0.616 } },
	{ key = "blue", color = { 0.25, 0.56, 1.0 } },
	{ key = "violet", color = { 0.64, 0.42, 1.0 } },
	{ key = "red", color = { 0.95, 0.3, 0.3 } },
	{ key = "orange", color = { 1.0, 0.56, 0.16 } },
	{ key = "gold", color = { 1.0, 0.82, 0.0 } },
	{ key = "green", color = { 0.36, 0.86, 0.36 } },
	{ key = "white", color = { 0.9, 0.9, 0.9 } },
	{ key = "class" },
}

local accent = { 0.451, 0.506, 1.0 }   -- текущий акцент (меняется на месте)

----------------------------------------------------------------------------------------
-- PX и перевод единиц
----------------------------------------------------------------------------------------

-- "2560x1440" -> 2560, 1440. Не строка или не тот вид -> nil.
function T.ParseResolution(s)
	if type(s) ~= "string" then
		return nil
	end
	local _, _, w, h = string.find(s, "^(%d+)[xX](%d+)")
	if not w then
		return nil
	end
	return tonumber(w), tonumber(h)
end

local function ReadResolution()
	local ok, v = pcall(GetCVar, "gxResolution")
	if ok then
		return T.ParseResolution(v)
	end
	return nil
end

local function ReadScale()
	if UIParent and UIParent.GetEffectiveScale then
		local ok, s = pcall(UIParent.GetEffectiveScale, UIParent)
		if ok and type(s) == "number" and s > 0 then
			return s
		end
	end
	return nil
end

-- Пересчитать PX. Возвращает true, если значение изменилось (и тогда шлет THEME).
function T.Compute()
	local w, h = ReadResolution()
	local s = ReadScale()
	local old = T.PX
	if w and h and h > 0 and s then
		T.screenW, T.screenH, T.scale = w, h, s
		T.PX = T.REF_HEIGHT / (h * s)
		T.pxSource = "gx"
	else
		T.PX = 0.5333333
		T.pxSource = "fallback"
	end
	if math.abs(T.PX - old) > 0.000001 then
		H.Fire("THEME")
		return true
	end
	return false
end

-- Привязка значения (AS) к сетке физических пикселей, симметрично для знака.
function T.Snap(v)
	local p = T.PX
	if v < 0 then
		return -math.floor(-v / p + 0.5) * p
	end
	return math.floor(v / p + 0.5) * p
end

-- Ретейл-пиксели -> AS.
function H.R(px)
	return T.Snap(px * T.PX)
end

function T.Px(n)
	return n * T.PX
end

-- Толщина рамки в физических пикселях: 1 (по умолчанию) .. 4.
function T.BorderPx()
	local n = H.DB and H.DB.Get("general", "borderPx")
	if type(n) ~= "number" then
		return 1
	end
	return H.Clamp(math.floor(n + 0.5), 1, 4)
end

function T.Border()
	return T.BorderPx() * T.PX
end

----------------------------------------------------------------------------------------
-- Цвет
----------------------------------------------------------------------------------------

function T.Tint(r, g, b)
	local k = T.TINT
	return r * k, g * k, b * k
end

function T.ClassColor(class)
	local c = class and T.CLASS[string.upper(class)]
	if not c and class and RAID_CLASS_COLORS then
		local rc = RAID_CLASS_COLORS[string.upper(class)]
		if rc then
			return rc.r, rc.g, rc.b
		end
	end
	if c then
		return c[1], c[2], c[3]
	end
	return 0.7, 0.7, 0.7
end

local function HeroClass()
	if H.Hero and H.Hero.Class then
		local ok, c = pcall(H.Hero.Class)
		if ok and c then
			return c
		end
	end
	if UnitClass then
		local ok, _, c = pcall(UnitClass, "player")
		if ok then
			return c
		end
	end
	return nil
end

function T.ResourceColor(kind)
	local c = kind and T.RESOURCE[kind]
	if c then
		return c[1], c[2], c[3]
	end
	return 0.7, 0.7, 0.7
end

-- Цвет вида цели: "trash", "elite", "boss" (босс = акцент), "emph".
function T.KindColor(kind)
	if kind == "boss" then
		return accent[1], accent[2], accent[3]
	end
	local c = T.KIND[kind] or T.KIND.trash
	return c[1], c[2], c[3]
end

local function HexByte(s)
	return tonumber(s, 16) / 255
end

-- Ключ акцента -> r, g, b. Ключ: палитра, "class" или "#RRGGBB" / "RRGGBB".
function T.ResolveAccent(key)
	if key == nil or key == "default" then
		return 0.451, 0.506, 1.0
	end
	if key == "class" then
		local c = HeroClass()
		if c then
			return T.ClassColor(c)
		end
		return 0.451, 0.506, 1.0
	end
	if type(key) == "string" then
		local _, _, r, g, b = string.find(key, "^#?(%x%x)(%x%x)(%x%x)$")
		if r then
			return HexByte(r), HexByte(g), HexByte(b)
		end
		for i = 1, table.getn(T.ACCENTS) do
			local a = T.ACCENTS[i]
			if a.key == key and a.color then
				return a.color[1], a.color[2], a.color[3]
			end
		end
	end
	return 0.451, 0.506, 1.0
end

local function PaintAccent()
	local c = T.C
	c.accent[1], c.accent[2], c.accent[3] = accent[1], accent[2], accent[3]
	c.select[1], c.select[2], c.select[3] = accent[1], accent[2], accent[3]
	c.fill[1], c.fill[2], c.fill[3] = accent[1], accent[2], accent[3]
	T.KIND.boss[1], T.KIND.boss[2], T.KIND.boss[3] = accent[1], accent[2], accent[3]
end

-- Перечитать акцент из настроек. Возвращает true, если цвет изменился.
function T.RefreshAccent()
	local key = H.DB and H.DB.Get("general", "accent")
	local r, g, b = T.ResolveAccent(key)
	if r == accent[1] and g == accent[2] and b == accent[3] then
		return false
	end
	accent[1], accent[2], accent[3] = r, g, b
	PaintAccent()
	return true
end

function T.AccentRGB()
	return accent[1], accent[2], accent[3]
end

function T.Accent()
	return accent[1], accent[2], accent[3], 1
end

-- Выбрать акцент: пишет в настройки (умолчание стирается) и шлет THEME.
function T.SetAccent(key)
	if H.DB then
		H.DB.Set("general", "accent", key)
	end
	if T.RefreshAccent() then
		H.Fire("THEME")
	end
end

-- Цвет источника по хэшу строки: тон из хэша, насыщенность и яркость фиксированы.
-- Один и тот же ключ всегда дает один цвет (meter#6). Результат кэшируется.
local sourceCache = {}

local function Hsv(h, s, v)
	local c = v * s
	local hp = h / 60
	local x = c * (1 - math.abs(math.mod(hp, 2) - 1))
	local r, g, b = 0, 0, 0
	if hp < 1 then
		r, g = c, x
	elseif hp < 2 then
		r, g = x, c
	elseif hp < 3 then
		g, b = c, x
	elseif hp < 4 then
		g, b = x, c
	elseif hp < 5 then
		r, b = x, c
	else
		r, b = c, x
	end
	local m = v - c
	return r + m, g + m, b + m
end

function T.SourceColor(key)
	key = tostring(key or "")
	local c = sourceCache[key]
	if not c then
		local hash = 5381
		for i = 1, string.len(key) do
			hash = math.mod(hash * 33 + string.byte(key, i), 1000003)
		end
		local r, g, b = Hsv(math.mod(hash, 360), 0.55, 0.92)
		c = { r, g, b }
		sourceCache[key] = c
	end
	return c[1], c[2], c[3]
end
H.SourceColor = T.SourceColor

-- Слой для окон ядра (Kit): токен -> r, g, b, a. Неизвестный токен дает nil, Kit берет свой запас.
local TOKEN = {
	bg = "panel", bgBar = "dock", inner = "inner", iconBg = "iconBg", edge = "border",
	muted = "dim", note = "muted", text = "text", ok = "ok", err = "error", warn = "warn",
	gold = "glow", hover = "hover", accent = "accent", accentSel = "select",
}

function H.Color(token)
	local name = TOKEN[token]
	if token == "accentDim" then
		return accent[1], accent[2], accent[3], 0.6
	end
	local c = name and T.C[name]
	if c then
		return c[1], c[2], c[3], c[4]
	end
	return nil
end

----------------------------------------------------------------------------------------
-- Рамка: четыре полоски однотонной текстуры по краю кадра
----------------------------------------------------------------------------------------

local borders = setmetatable({}, { __mode = "k" })   -- кадр -> { top, bottom, left, right }

local function PlaceBorder(frame, set, size)
	set.top:ClearAllPoints()
	set.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	set.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	set.top:SetHeight(size)
	set.bottom:ClearAllPoints()
	set.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	set.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	set.bottom:SetHeight(size)
	set.left:ClearAllPoints()
	set.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -size)
	set.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, size)
	set.left:SetWidth(size)
	set.right:ClearAllPoints()
	set.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -size)
	set.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, size)
	set.right:SetWidth(size)
end

local function MakeStrip(frame, layer, r, g, b, a)
	local t = frame:CreateTexture(nil, layer or "BORDER")
	t:SetTexture(T.TEX.solid)
	t:SetVertexColor(r, g, b, a)
	return t
end

-- Рамка по краю кадра: внутрь кадра, толщиной T.Border(). Повторный вызов только красит.
function T.AddBorder(frame, r, g, b, a, layer)
	local c = T.C.border
	r, g, b, a = r or c[1], g or c[2], b or c[3], a or c[4]
	local set = borders[frame]
	if set then
		T.SetBorderColor(frame, r, g, b, a)
		return set
	end
	set = {
		top = MakeStrip(frame, layer, r, g, b, a), bottom = MakeStrip(frame, layer, r, g, b, a),
		left = MakeStrip(frame, layer, r, g, b, a), right = MakeStrip(frame, layer, r, g, b, a),
	}
	borders[frame] = set
	frame.huiBorder = set
	PlaceBorder(frame, set, T.Border())
	return set
end

function T.SetBorderColor(frame, r, g, b, a)
	local set = borders[frame]
	if not set then
		return
	end
	a = a or 1
	set.top:SetVertexColor(r, g, b, a)
	set.bottom:SetVertexColor(r, g, b, a)
	set.left:SetVertexColor(r, g, b, a)
	set.right:SetVertexColor(r, g, b, a)
end

function T.ShowBorder(frame, on)
	local set = borders[frame]
	if not set then
		return
	end
	for _, t in pairs(set) do
		if on then
			t:Show()
		else
			t:Hide()
		end
	end
end

-- Пересчитать толщину у всех рамок (смена PX или borderPx).
function T.ReflowBorders()
	local size = T.Border()
	for frame, set in pairs(borders) do
		PlaceBorder(frame, set, size)
	end
end

function T.BorderCount()
	local n = 0
	for _ in pairs(borders) do
		n = n + 1
	end
	return n
end

-- Залить кадр плоским фоном: одна текстура на весь кадр под рамкой.
function T.AddBackground(frame, color, layer)
	local c = color or T.C.panel
	local t = frame.huiBg
	if not t then
		t = frame:CreateTexture(nil, layer or "BACKGROUND")
		t:SetTexture(T.TEX.solid)
		t:SetAllPoints(frame)
		frame.huiBg = t
	end
	t:SetVertexColor(c[1], c[2], c[3], c[4])
	return t
end

----------------------------------------------------------------------------------------
-- События
----------------------------------------------------------------------------------------

-- Стоковые события, которые шина должна зарегистрировать на кадре ядра.
local STOCK = H.Events and H.Events.STOCK
if STOCK then
	STOCK.UI_SCALE_CHANGED = true
	STOCK.VARIABLES_LOADED = true
end

local function Rescale()
	T.Compute()
end

H.On("VARIABLES_LOADED", "theme", Rescale)
H.On("UI_SCALE_CHANGED", "theme", Rescale)
H.On("PLAYER_ENTERING_WORLD", "theme", Rescale)

H.On("LOADED", "theme", function()
	local changed = T.Compute()
	if T.RefreshAccent() and not changed then
		H.Fire("THEME")
	end
end)

H.On("HERO_CHANGED", "theme", function()
	if H.DB and H.DB.Get("general", "accent") == "class" and T.RefreshAccent() then
		H.Fire("THEME")
	end
end)

H.On("SETTING", "theme", function(ev, mod, key)
	if mod == "general" and (key == "accent" or key == "borderPx") then
		T.RefreshAccent()
		H.Fire("THEME")
	end
end)

H.On("THEME", "theme", function()
	T.ReflowBorders()
end)

T.Compute()
