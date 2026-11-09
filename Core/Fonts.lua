-- HyoukaUI: шрифты. Роли (spec 1.4), Expressway из папки аддона, шрифт во всей игре.
--
-- Размер роли задан в ретейл-пикселях и переводится так: целых пикселей x PX (Theme). Движок рисует
-- размер с шагом в физический пиксель (проба 0.15: 6.9 рисуется как 7), поэтому дробные размеры не нужны.
--
-- F.Role(role)            -> путь, размер, флаги
-- F.Apply(fs, role)       ставит шрифт роли и запоминает связь (перекраска на THEME и FONTS)
-- F.SetGameFont(on)       шрифт Expressway во всей игре: ОДИН хук SetFont на общей метатаблице
-- F.Reassert()            довести шрифты, созданные позже (видимые тексты)
-- F.Owner()               кто владеет хуком SetFont: "HyoukaUI", "SurvivorUITweaks" или nil
--
-- Хук SetFont ставится один раз. Метка владельца лежит на таблице методов: huiFontOwner (наша) и
-- suitFontHooked (SurvivorUITweaks). Если метка Tweaks уже есть, второй хук не ставится: шрифт во
-- всей игре остается за Tweaks, мы только пользуемся своим путем для своих текстов.

local H = HyoukaUI

local F = {}
H.Fonts = F

F.PATH = "Interface\\AddOns\\HyoukaUI\\Media\\Fonts\\Expressway.ttf"
F.OWN_MARK = "huiFontOwner"
F.FOREIGN_MARK = "suitFontHooked"

-- Символы без литералов не-ASCII в коде. В Expressway есть U+00BB и U+00B7, бесконечности нет.
F.SYM = { arrow = "\194\187", dot = "\194\183", inf = "inf", sep = " | " }

-- Роли: размер в ретейл-пикселях (spec 1.4, 3.2, 3.6), флаги.
F.ROLES = {
	body = { 13, "OUTLINE" },      -- основной текст рамок
	small = { 12, "OUTLINE" },     -- мелкий: бинды, ранги, подсказка small
	title = { 14, "OUTLINE" },     -- заголовки, чат, миникарта
	num = { 15, "OUTLINE" },       -- цифры кулдаунов вспомогательного ряда, таймер босса
	numL = { 17, "OUTLINE" },      -- цифры главного ряда
	stat = { 18, "OUTLINE" },      -- стаки статичных баффов
	msg = { 23, "OUTLINE" },       -- сообщения
	msgEmph = { 40, "OUTLINE" },   -- выделенное сообщение
	count = { 55, "OUTLINE" },     -- обратный отсчет
}

-- Имена ролей слоя Kit (окна ядра): normal, chat, cd, big, msg.
F.ALIAS = { normal = "body", chat = "title", cd = "num", big = "numL" }

local S = {
	face = F.PATH,        -- путь, который ставят роли
	faceOk = false,       -- Expressway загрузился (проба через строку)
	gameOn = false,       -- хук подменяет чужие шрифты
	seen = {},            -- путь -> уже Expressway
	hooked = {},          -- таблица методов -> { orig, wrapper }
	hookCount = 0,
	saved = nil,          -- исходные глобальные шрифты
	foreign = false,      -- есть хук Tweaks
}
F.S = S

local bound = setmetatable({}, { __mode = "k" })   -- строка -> роль

local origStd = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

----------------------------------------------------------------------------------------
-- Проба и путь
----------------------------------------------------------------------------------------

local function IsExpress(path)
	return type(path) == "string" and string.find(string.lower(path), "expressway", 1, true) ~= nil
end

-- Шрифт принимается движком: строка в него ставится и GetFont возвращает путь Expressway.
function F.Probe()
	local ok, res = pcall(function()
		local probe = UIParent:CreateFontString(nil, "OVERLAY")
		probe:SetFont(F.PATH, 12)
		local got = probe:GetFont()
		probe:Hide()
		return IsExpress(got)
	end)
	S.faceOk = ok and res and true or false
	return S.faceOk
end

local function Choice()
	return H.DB and H.DB.Get("general", "font")
end

-- Путь шрифта для наших текстов: Expressway, если загрузился и не выбран шрифт игры.
function F.Path()
	if S.faceOk and Choice() ~= "game" then
		return F.PATH
	end
	return origStd
end

-- "ruRU" или "enUS": язык интерфейса (Locale). Кириллица в Expressway есть (проба 0.11).
function F.Lang()
	return (H.Locale and H.Locale.code) or "enUS"
end

----------------------------------------------------------------------------------------
-- Роли
----------------------------------------------------------------------------------------

-- Размер роли в AS: целое число физических пикселей x PX.
function F.Size(retailPx)
	local px = math.floor(retailPx + 0.5)
	if px < 1 then
		px = 1
	end
	return px * H.Theme.PX
end

-- delta: поправка к размеру роли в ретейл-пикселях (необязательно).
function F.Role(role, delta)
	local r = F.ROLES[role] or F.ROLES[F.ALIAS[role]] or F.ROLES.body
	return F.Path(), F.Size(r[1] + (delta or 0)), r[2]
end

function F.Apply(fs, role, delta)
	local path, size, flags = F.Role(role, delta)
	fs:SetFont(path, size, flags)
	fs.huiFontDelta = delta
	bound[fs] = role
	return fs
end

-- Перекрасить все связанные строки (смена PX, шрифта или режима).
function F.Refresh()
	for fs, role in pairs(bound) do
		local path, size, flags = F.Role(role, fs.huiFontDelta)
		fs:SetFont(path, size, flags)
	end
end

function F.BoundCount()
	local n = 0
	for _ in pairs(bound) do
		n = n + 1
	end
	return n
end

----------------------------------------------------------------------------------------
-- Шрифт во всей игре: один хук SetFont
----------------------------------------------------------------------------------------

local function MethodsOf(sample)
	if not sample then
		return nil
	end
	local meta = getmetatable(sample)
	local methods = meta and meta.__index
	if type(methods) == "table" and type(methods.SetFont) == "function" then
		return methods
	end
	return nil
end

-- Обертка SetFont: чужой путь заменяется на свой, размер и обводка те же.
local function MakeWrapper(orig)
	return function(self, path, size, flags)
		if S.gameOn and type(path) == "string" and path ~= S.face then
			local own = S.seen[path]
			if own == nil then
				own = IsExpress(path)
				S.seen[path] = own
			end
			if not own then
				path = S.face
			end
		end
		return orig(self, path, size, flags)
	end
end

local function Samples()
	if S.samples then
		return S.samples
	end
	local list = {}
	local function add(f)
		if f then
			table.insert(list, f)
		end
	end
	local ok = pcall(function()
		add(UIParent:CreateFontString(nil, "OVERLAY"))
		add(CreateFrame("EditBox", nil, UIParent))
		add(CreateFrame("ScrollingMessageFrame", nil, UIParent))
		add(CreateFrame("MessageFrame", nil, UIParent))
	end)
	if H.Env.GameFontNormal then
		add(H.Env.GameFontNormal)
	end
	for i = 1, table.getn(list) do
		if list[i].Hide then
			list[i]:Hide()
		end
	end
	S.samples = list
	return list, ok
end

-- Поставить хук. Возвращает "own", "foreign" (хук Tweaks уже стоит) или "none" (не получилось).
function F.InstallHook()
	local list = Samples()
	local result = "none"
	S.foreign = false
	for i = 1, table.getn(list) do
		local methods = MethodsOf(list[i])
		if methods then
			if methods[F.FOREIGN_MARK] then
				S.foreign = true
				result = "foreign"
			elseif methods[F.OWN_MARK] then
				if result == "none" then
					result = "own"
				end
			elseif not S.hooked[methods] then
				local orig = methods.SetFont
				local wrapper = MakeWrapper(orig)
				methods.SetFont = wrapper
				methods[F.OWN_MARK] = H.name
				S.hooked[methods] = { orig = orig, wrapper = wrapper }
				S.hookCount = S.hookCount + 1
				if result ~= "foreign" then
					result = "own"
				end
			end
		end
	end
	if S.foreign and S.hookCount == 0 then
		H.RegisterHook("SetFont", "SurvivorUITweaks")
	elseif S.hookCount > 0 then
		H.RegisterHook("SetFont", H.name)
	end
	return result
end

-- Снять хук. Если поверх нашей обертки кто-то обернул еще раз, обертка остается, но молчит.
function F.RemoveHook()
	S.gameOn = false
	for methods, rec in pairs(S.hooked) do
		if methods.SetFont == rec.wrapper then
			methods.SetFont = rec.orig
			methods[F.OWN_MARK] = nil
			S.hooked[methods] = nil
			S.hookCount = S.hookCount - 1
		end
	end
	if S.hookCount == 0 and H.hooks.SetFont == H.name then
		H.hooks.SetFont = nil
	end
end

-- Кто владеет хуком: по меткам на таблицах методов.
function F.Owner()
	local list = Samples()
	local own, foreign = false, false
	for i = 1, table.getn(list) do
		local methods = MethodsOf(list[i])
		if methods then
			own = own or methods[F.OWN_MARK] ~= nil
			foreign = foreign or methods[F.FOREIGN_MARK] ~= nil
		end
	end
	if own and not foreign then
		return H.name
	end
	if foreign and not own then
		return "SurvivorUITweaks"
	end
	if own and foreign then
		return "both"
	end
	return nil
end

-- Сколько таблиц методов несет нашу метку (должно быть не больше числа видов виджетов, не двоиться).
function F.OwnMarks()
	return S.hookCount
end

----------------------------------------------------------------------------------------
-- Глобальные шрифты и доводка уже созданных
----------------------------------------------------------------------------------------

local GLOBALS = { "STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "NAMEPLATE_FONT", "DAMAGE_TEXT_FONT" }
local TEXT_FRAMES = { EditBox = true, ScrollingMessageFrame = true, MessageFrame = true, SimpleHTML = true }

local function Refont(object)
	local path, size, flags = object:GetFont()
	if path and size and size > 0 and not IsExpress(path) then
		object:SetFont(S.face, size, flags)
	end
end

local function FontObject(value)
	if type(value) == "table" and type(value.GetObjectType) == "function" and value:GetObjectType() == "Font" then
		Refont(value)
	end
end

local function FrameTexts(frame)
	if TEXT_FRAMES[frame:GetObjectType()] and frame.GetFont then
		Refont(frame)
	end
	local regions = { frame:GetRegions() }
	for i = 1, table.getn(regions) do
		local r = regions[i]
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			Refont(r)
		end
	end
end

-- Пройти шрифтовые объекты и все тексты. visibleOnly: только видимые кадры (дешево).
function F.ApplyEverywhere(visibleOnly)
	if not S.gameOn then
		return 0
	end
	local n = 0
	if not visibleOnly then
		for _, value in pairs(H.Env) do
			pcall(FontObject, value)
		end
	end
	if not EnumerateFrames then
		return n
	end
	local frame = EnumerateFrames()
	while frame do
		if not visibleOnly or frame:IsVisible() then
			pcall(FrameTexts, frame)
			n = n + 1
		end
		frame = EnumerateFrames(frame)
	end
	return n
end

function F.Reassert()
	if S.gameOn then
		F.ApplyEverywhere(true)
	end
end

-- Подмена во всей игре нужна, если не выключена опцией и не выбран "шрифт игры" для наших текстов.
function F.GameFontWanted()
	return not H.DB or (H.DB.Get("general", "gameFont") ~= false and Choice() ~= "game")
end

-- Включить или выключить Expressway во всей игре. Возвращает итог: "own", "foreign", "none", "off".
function F.SetGameFont(on)
	if not on then
		F.RemoveHook()
		if S.saved then
			for i = 1, table.getn(GLOBALS) do
				H.Env[GLOBALS[i]] = S.saved[GLOBALS[i]]
			end
			S.saved = nil
		end
		H.Clock.Stop("fonts")
		return "off"
	end
	if not S.faceOk then
		return "none"
	end
	S.face = F.PATH
	if not S.saved then
		S.saved = {}
		for i = 1, table.getn(GLOBALS) do
			S.saved[GLOBALS[i]] = H.Env[GLOBALS[i]]
		end
	end
	for i = 1, table.getn(GLOBALS) do
		H.Env[GLOBALS[i]] = F.PATH
	end
	local result = F.InstallHook()
	S.gameOn = (result == "own")
	if result == "own" then
		F.ApplyEverywhere(false)
	elseif result == "none" and EnumerateFrames then
		-- хук не поставить: довод видимых текстов раз в 2 секунды (как в прототипе)
		S.gameOn = true
		H.Clock.Stop("fonts")
		H.Clock.Every("fonts", 2, F.Reassert)
	end
	return result
end

-- Одна строка для selftest и отладки.
function F.Describe()
	return "шрифт "..(S.faceOk and "загружен" or "НЕ загружен")..", хук SetFont: владелец "..tostring(F.Owner())
		..", наших меток "..S.hookCount..", подмена "..(S.gameOn and "вкл" or "выкл")
end

----------------------------------------------------------------------------------------
-- События
----------------------------------------------------------------------------------------

H.On("LOADED", "fonts", function()
	F.Probe()
	if F.GameFontWanted() then
		F.SetGameFont(true)
	end
	F.Refresh()
end)

H.On("PLAYER_ENTERING_WORLD", "fonts", function()
	F.Reassert()
end)

H.On("THEME", "fonts", function()
	F.Refresh()
end)

H.On("SETTING", "fonts", function(ev, mod, key)
	if mod == "general" and (key == "font" or key == "gameFont") then
		F.SetGameFont(F.GameFontWanted())
		H.Fire("FONTS")
	end
end)

H.On("FONTS", "fonts", function()
	F.Refresh()
end)

F.Probe()
