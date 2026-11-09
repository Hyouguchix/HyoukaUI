-- HyoukaUI: окно отладки, selftest, список ошибок, дампы данных, inspect и frames
-- (перенос из SurvivorUITweaks\Debug.lua). Окно создается при первом показе: пока им не
-- пользуются, аддон ничего не рисует.
--
-- /hui selftest, /hui errors, /hui dump <имя>, /hui inspect, /hui frames

local H = HyoukaUI

local D = {}
H.Debug = D

H.NewModule("debug", { label = "Отладка", internal = true })

local LINES = 38      -- строк на экране
local MAXC = 104      -- символов в строке до переноса
local ROW_H = 13

D.all = {}            -- все строки (после переносов)
D.top = 1
D.title = ""
D.shows = 0
D.Extra = {}          -- имя дампа -> function(out): добавляет строки слоя (Core\DebugData.lua)
D.SelftestParts = {}  -- function(L, bad): добавляют строки в selftest (Core\DebugData.lua)

----------------------------------------------------------------------------------------
-- Форматирование
----------------------------------------------------------------------------------------

-- Печатный вид значения: строки в кавычках и короткие, таблицы счетом ключей.
function D.Val(v)
	local t = type(v)
	if t == "string" then
		local s = string.gsub(v, "[%c]", " ")
		if string.len(s) > 80 then
			s = string.sub(s, 1, 77).."..."
		end
		return "\""..s.."\""
	elseif t == "table" then
		local n = 0
		for _ in pairs(v) do
			n = n + 1
		end
		return "{table, ключей "..n.."}"
	end
	return tostring(v)
end

-- Одна строка со всеми полями записи: k=v k=v.
function D.Row(row)
	local keys = H.SortedKeys(row)
	local parts = {}
	for i = 1, table.getn(keys) do
		table.insert(parts, tostring(keys[i]).."="..D.Val(row[keys[i]]))
	end
	return table.concat(parts, " ")
end

-- Дамп таблицы в список строк: ключи по порядку, вложенные таблицы до depth уровней.
function D.DumpTable(t, out, indent, depth, maxKeys)
	indent = indent or ""
	maxKeys = maxKeys or 60
	local keys = H.SortedKeys(t)
	for i = 1, table.getn(keys) do
		if i > maxKeys then
			table.insert(out, indent.."... еще "..(table.getn(keys) - maxKeys).." ключей")
			break
		end
		local k = keys[i]
		local v = t[k]
		table.insert(out, indent..tostring(k)..": "..D.Val(v))
		if type(v) == "table" and (depth or 0) > 0 then
			D.DumpTable(v, out, indent.."    ", depth - 1, maxKeys)
		end
	end
	return out
end

-- Разрезать строку по числу символов UTF-8, не ломая многобайтовые.
local function CutChars(s, maxc)
	local len = string.len(s)
	local chars, i = 0, 1
	while i <= len do
		local b = string.byte(s, i)
		if b < 128 or b >= 192 then
			if chars >= maxc then
				break
			end
			chars = chars + 1
		end
		i = i + 1
	end
	if i > len then
		return s, nil
	end
	return string.sub(s, 1, i - 1), string.sub(s, i)
end
D.CutChars = CutChars

-- Перенос длинных строк, чтобы окно читалось на скриншоте.
function D.Wrap(list)
	local out = {}
	for i = 1, table.getn(list) do
		local s = string.gsub(tostring(list[i]), "[\r\n]+", " ")
		local head, tail = CutChars(s, MAXC)
		table.insert(out, head)
		while tail do
			head, tail = CutChars("    "..tail, MAXC)
			table.insert(out, head)
		end
	end
	return out
end

----------------------------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------------------------

local box, rows, footer

local function Render()
	if not box then
		return
	end
	for i = 1, LINES do
		rows[i]:SetText(D.all[D.top + i - 1] or "")
	end
	local total = table.getn(D.all)
	local last = D.top + LINES - 1
	if last > total then
		last = total
	end
	footer:SetText(string.format("строки %d-%d из %d, колесо мыши листает", total > 0 and D.top or 0, last, total))
end

function D.Scroll(delta)
	local maxTop = table.getn(D.all) - LINES + 1
	if maxTop < 1 then
		maxTop = 1
	end
	D.top = H.Clamp(D.top + delta, 1, maxTop)
	Render()
end

local function Build()
	box = CreateFrame("Frame", "HyoukaUI_Debug", UIParent)
	box:SetWidth(640)
	box:SetHeight((LINES + 2) * ROW_H + 24)
	box:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -40)
	box:SetFrameStrata("TOOLTIP")
	box:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	box:SetBackdropColor(0, 0, 0, 0.92)
	box:SetBackdropBorderColor(0.45, 0.5, 1, 1)
	box:EnableMouse(true)
	box:EnableMouseWheel(true)
	box:Hide()
	rows = {}
	for i = 1, LINES + 1 do
		local fs = box:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\ARIALN.TTF", 11, "")
		fs:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6 - (i - 1) * ROW_H)
		fs:SetWidth(620)
		fs:SetHeight(ROW_H)
		fs:SetJustifyH("LEFT")
		rows[i] = fs
	end
	footer = box:CreateFontString(nil, "OVERLAY")
	footer:SetFont("Fonts\\ARIALN.TTF", 10, "")
	footer:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 8, 6)
	footer:SetWidth(520)
	footer:SetJustifyH("LEFT")
	footer:SetTextColor(0.6, 0.6, 0.6)
	H.Script("debug", box, "OnMouseWheel", function(self, delta)
		D.Scroll(-3 * (delta or 0))
	end)
	local function Button(label, x, handler)
		local b = CreateFrame("Button", nil, box)
		b:SetWidth(18)
		b:SetHeight(16)
		b:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", x, 4)
		local fs = b:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\ARIALN.TTF", 13, "")
		fs:SetPoint("CENTER", b, "CENTER", 0, 0)
		fs:SetText(label)
		H.Script("debug", b, "OnClick", handler)
	end
	Button("x", -4, function() box:Hide() end)
	Button("v", -24, function() D.Scroll(LINES - 2) end)
	Button("^", -44, function() D.Scroll(-(LINES - 2)) end)
	if UISpecialFrames then
		table.insert(UISpecialFrames, "HyoukaUI_Debug")
	end
end

-- Показать список строк в окне. Первая строка (title) выделена как заголовок.
function D.Show(list, title)
	local all = { title and ("== "..title.." ==") or "== HyoukaUI ==" }
	local wrapped = D.Wrap(list)
	for i = 1, table.getn(wrapped) do
		table.insert(all, wrapped[i])
	end
	D.all = all
	D.title = title or ""
	D.top = 1
	D.shows = D.shows + 1
	if not box then
		Build()
	end
	box:Show()
	Render()
end

function D.Hide()
	if box then
		box:Hide()
	end
end

function D.IsShown()
	return box ~= nil and box:IsShown()
end

-- Перерисовать с сохранением позиции прокрутки (асинхронные пробы).
function D.Update(list, title)
	local top = D.top
	D.Show(list, title)
	D.top = top
	Render()
end

----------------------------------------------------------------------------------------
-- selftest
----------------------------------------------------------------------------------------

local function YN(v)
	return v and "да" or "нет"
end

local function CountKeys(t)
	local n = 0
	if type(t) == "table" then
		for _ in pairs(t) do
			n = n + 1
		end
	end
	return n
end

-- Строки самопроверки и вердикт приемки этапа 0: на экране ничего не меняется, счетчики нулевые.
function D.SelftestLines()
	local E = H.Errors
	local L = {}
	local bad = {}
	local db = HyoukaUIDB
	table.insert(L, "HyoukaUI "..H.version..", этап "..H.stage..", схема сохранений "..tostring(db and db.schema)..", загружен через "..string.format("%.1f", H.Now()).." с")
	table.insert(L, "SurvivorUI загружен: "..YN(H.IsCoexist())..".  SurvivorUITweaks: "..YN(IsAddOnLoaded and IsAddOnLoaded("SurvivorUITweaks") and true))
	table.insert(L, "Перехват ошибок: seterrorhandler есть "..YN(E.available)..", установлен "..YN(E.installed)..", прежний обработчик "..YN(E.previous ~= nil))

	table.insert(L, "Модули ("..table.getn(H.moduleList).."):")
	local moduleErrors = 0
	for i = 1, table.getn(H.moduleList) do
		local m = H.moduleList[i]
		moduleErrors = moduleErrors + m.errors
		table.insert(L, "  "..m.name.."  режим="..(H.MODE_LABELS[H.GetMode(m.name)] or "?")..(m.internal and " (ядро)" or "").."  включен="..YN(m.enabled).."  приостановлен="..YN(m.suspended).."  ошибок="..m.errors)
	end
	if moduleErrors > 0 then
		table.insert(bad, "ошибки модулей: "..moduleErrors)
	end

	local claims, parks = H.counters.claims, H.counters.parks
	local owned = db and db.global and db.global.hud and db.global.hud.owned
	local ownedList = {}
	if owned then
		local keys = H.SortedKeys(owned)
		for i = 1, table.getn(keys) do
			table.insert(ownedList, tostring(keys[i]))
		end
	end
	table.insert(L, "claims = "..claims.."   parks = "..parks.."   hudOwned = "..(table.getn(ownedList) == 0 and "(пусто)" or table.concat(ownedList, ",")))
	if claims ~= 0 then table.insert(bad, "claims ~= 0") end
	if parks ~= 0 then table.insert(bad, "parks ~= 0") end
	if table.getn(ownedList) > 0 then table.insert(bad, "hudOwned не пуст") end

	table.insert(L, "Ошибок Lua всего: "..E.total.." (корзин: "..table.getn(E.order)..")")
	for i = 1, table.getn(E.order) do
		local name = E.order[i]
		table.insert(L, "  "..name..": "..E.buckets[name].count)
	end
	if E.total > 0 then
		table.insert(bad, "ошибок Lua: "..E.total)
	end

	local marks = H.SortedKeys(H.hooks)
	local markText = {}
	for i = 1, table.getn(marks) do
		table.insert(markText, marks[i].."="..tostring(H.hooks[marks[i]]))
	end
	table.insert(L, "Метки владельцев хуков: "..table.getn(marks)..(table.getn(marks) > 0 and (" ("..table.concat(markText, ", ")..")") or ""))
	table.insert(L, "Шторка кулдаунов (за 60 с): нет данных, появятся на этапе 2")
	for i = 1, table.getn(D.SelftestParts) do
		D.SelftestParts[i](L, bad)
	end

	local events, subs = H.Events.Stats()
	local nf, nt, running = H.Clock.Count()
	table.insert(L, "Шина: событий "..events..", подписок "..subs..".  Часы: покадровых "..nf..", таймеров "..nt..", драйвер "..(running and "идет" or "выключен"))
	table.insert(L, "DB: готова "..YN(H.DB.ready)..", миграций "..H.DB.stats.migrated..", сбоев "..H.DB.stats.failed..", копия prev "..YN(db and db.prev ~= nil)..", сохранения новее аддона "..YN(H.DB.newer))
	local fixtures = db and db.fixtures
	table.insert(L, "Запись фикстур: "..(H.Record and H.Record.IsOn() and "идет" or "выключена")..", записей в сохранении "..CountKeys(fixtures and fixtures.entries))
	local ran = {}
	if db and db.probes then
		for k in pairs(db.probes) do
			if type(k) == "number" then
				table.insert(ran, k)
			end
		end
		table.sort(ran)
	end
	table.insert(L, "Пробы с сохраненным результатом: "..(table.getn(ran) == 0 and "нет" or table.concat(ran, ",")))
	if table.getn(bad) == 0 then
		table.insert(L, "ПРИЕМКА ЭТАПА 0 (ничего не менять, нули в счетчиках): ДА")
	else
		table.insert(L, "ПРИЕМКА ЭТАПА 0: НЕТ. "..table.concat(bad, "; "))
	end
	return L, table.getn(bad) == 0
end

function D.Selftest()
	local lines, passed = D.SelftestLines()
	D.Show(lines, "selftest")
	H.Print("selftest: "..(passed and "в норме" or "есть замечания").." (окно отладки)")
	return lines, passed
end

----------------------------------------------------------------------------------------
-- errors
----------------------------------------------------------------------------------------

function D.ErrorLines()
	local E = H.Errors
	local L = { "Ошибок Lua: "..E.total.." в "..table.getn(E.order).." корзинах (аддон или модуль)" }
	for i = 1, table.getn(E.order) do
		local name = E.order[i]
		local b = E.buckets[name]
		table.insert(L, "["..name.."] ошибок "..b.count..", разных "..table.getn(b.list)..(b.overflow > 0 and (", не уместилось "..b.overflow) or ""))
		for j = 1, table.getn(b.list) do
			local entry = b.list[j]
			table.insert(L, "  x"..entry.count.." (t="..entry.at..") "..entry.text)
		end
	end
	return L
end

function D.ShowErrors()
	D.Show(D.ErrorLines(), "errors")
end

----------------------------------------------------------------------------------------
-- dump
----------------------------------------------------------------------------------------

local STAMPS = { "RUN", "ZONE", "SCHEDULE", "UNITS", "DEBUFFS", "TARGET", "SPELLS", "TIMERS", "BUFFS", "PETS",
	"TOTEMS", "METER", "HEALING", "BOSSMETER", "REVIVE", "PARTY", "DOWNED", "CHESTS", "LAIRS", "TAKEN", "END", "BANNER" }
D.STAMPS = STAMPS

local DUMPS = { run = "AZS_RUN", zone = "AZS_ZONE", target = "AZS_TARGET", revive = "AZS_REVIVE",
	["end"] = "AZS_END", units = "AZS_UNITS", spells = "AZS_SPELLS", hudcvars = "AZS_HUD_CVARS",
	party = "AZS_PARTY" }

function D.DumpNames()
	local all = {}
	for k in pairs(DUMPS) do
		all[k] = true
	end
	for k in pairs(D.Extra) do
		all[k] = true
	end
	local names = H.SortedKeys(all)
	table.insert(names, "stamps")
	return names
end

local function IsList(t)
	return type(t[1]) == "table"
end

-- Сырой дамп по имени (глобал движка). Возвращает список или nil и причину.
function D.RawDumpLines(name)
	name = string.lower(name or "")
	local L = {}
	if name == "stamps" then
		local now = H.Now()
		table.insert(L, "GetTime = "..string.format("%.3f", now))
		for i = 1, table.getn(STAMPS) do
			local g = "AZS_"..STAMPS[i].."_UPDATED"
			local v = H.Global(g)
			table.insert(L, g.." = "..(v and (string.format("%.3f", v).." (назад "..string.format("%.2f", now - v).." с)") or "nil"))
		end
		return L
	end
	local global = DUMPS[name]
	if not global and string.find(name, "^azs_") then
		global = string.upper(name)
	end
	if not global then
		return nil, "неизвестное имя. Доступно: "..table.concat(D.DumpNames(), ", ")
	end
	local value = H.Global(global)
	if value == nil then
		return nil, "глобала "..global.." нет"
	end
	table.insert(L, global.." ("..type(value)..")")
	if type(value) ~= "table" then
		table.insert(L, D.Val(value))
		return L
	end
	if name == "hudcvars" then
		local keys = H.SortedKeys(value)
		table.insert(L, "частей: "..table.getn(keys))
		for i = 1, table.getn(keys) do
			local part = keys[i]
			local shown = AZS_IsHudShown and AZS_IsHudShown(part)
			table.insert(L, "  "..tostring(part).." = "..tostring(value[part]).."   GetCVar = "..tostring(GetCVar and GetCVar(tostring(value[part]))).."   AZS_IsHudShown = "..tostring(shown))
		end
		return L
	end
	if IsList(value) then
		table.insert(L, "записей: "..table.getn(value))
		local stamp = H.Global(global.."_UPDATED")
		if stamp then
			table.insert(L, "метка "..global.."_UPDATED = "..string.format("%.3f", stamp))
		end
		for i = 1, table.getn(value) do
			if i > 25 then
				table.insert(L, "... еще "..(table.getn(value) - 25))
				break
			end
			table.insert(L, i..": "..D.Row(value[i]))
		end
		return L
	end
	local keys = H.SortedKeys(value)
	table.insert(L, "ключей: "..table.getn(keys))
	local stamp = H.Global(global.."_UPDATED")
	if stamp then
		table.insert(L, "метка "..global.."_UPDATED = "..string.format("%.3f", stamp))
	end
	D.DumpTable(value, L, "  ", 1, 80)
	return L
end

-- Строки дампа: сначала вид слоя данных HyoukaUI (D.Extra), затем сырой глобал, если он есть.
function D.DumpLines(name)
	name = string.lower(name or "")
	local extra = D.Extra[name]
	local lines, why = D.RawDumpLines(name)
	if not extra then
		return lines, why
	end
	local out = {}
	extra(out)
	if lines then
		table.insert(out, "-- сырой глобал движка --")
		for i = 1, table.getn(lines) do
			table.insert(out, lines[i])
		end
	end
	return out
end

function D.Dump(name)
	local lines, why = D.DumpLines(name)
	if not lines then
		D.Show({ why }, "dump")
		return
	end
	D.Show(lines, "dump "..tostring(name))
end

----------------------------------------------------------------------------------------
-- inspect и frames (из прототипа)
----------------------------------------------------------------------------------------

local function NameOf(f)
	if not f then
		return "nil"
	end
	local name = f.GetName and f:GetName()
	return (name or "<без имени>").." ["..(f.GetObjectType and f:GetObjectType() or "?").."]"
end

local function Size(f)
	local w, h = f:GetWidth(), f:GetHeight()
	return math.floor((w or 0) + 0.5).."x"..math.floor((h or 0) + 0.5)
end

local function AddRegions(list, f, indent)
	local regions = { f:GetRegions() }
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local kind = region:GetObjectType()
		if kind == "Texture" then
			table.insert(list, indent.."tex "..tostring(region:GetName()).." "..tostring(region:GetTexture())..(region:IsShown() and "" or " (скрыта)"))
		elseif kind == "FontString" then
			local path, size = region:GetFont()
			table.insert(list, indent.."txt \""..tostring(region:GetText()).."\" "..tostring(path).." "..tostring(size))
		end
	end
end

function D.InspectLines()
	local list = {}
	local focus = GetMouseFocus and GetMouseFocus()
	table.insert(list, "Под курсором: "..NameOf(focus))
	if not focus then
		return list
	end
	local chain, at, level = "", focus:GetParent(), 0
	while at and level < 8 do
		chain = chain.." < "..NameOf(at).." "..Size(at)
		at = at:GetParent()
		level = level + 1
	end
	table.insert(list, "Размер "..Size(focus).."  Родители:"..chain)
	pcall(function()
		if focus.GetNormalTexture then
			local n = focus:GetNormalTexture()
			table.insert(list, "Normal: "..tostring(n and n:GetTexture()))
		end
	end)
	AddRegions(list, focus, "  ")
	local parent = focus:GetParent()
	if parent then
		table.insert(list, "Регионы родителя "..NameOf(parent)..":")
		AddRegions(list, parent, "  ")
	end
	return list
end

-- Через 2 секунды смотрит элемент под курсором (успеть навести мышь).
function D.Inspect()
	H.Print("inspect: наведи курсор на элемент, результат через 2 с")
	H.Clock.After("debug", 2, function()
		D.Show(D.InspectLines(), "inspect")
	end)
end

function D.FramesLines()
	local list = { "Видимые окна под UIParent:" }
	local children = { UIParent:GetChildren() }
	for i = 1, table.getn(children) do
		local f = children[i]
		if f:IsVisible() and f:GetName() ~= "HyoukaUI_Debug" then
			local name = f:GetName()
			local w, h = f:GetWidth() or 0, f:GetHeight() or 0
			if name or (w > 40 and h > 40) then
				table.insert(list, NameOf(f).." "..Size(f).." strata "..tostring(f:GetFrameStrata()))
			end
		end
	end
	table.insert(list, "WorldFrame детей: "..table.getn({ WorldFrame:GetChildren() }))
	return list
end

function D.Frames()
	D.Show(D.FramesLines(), "frames")
end

----------------------------------------------------------------------------------------
-- Команды
----------------------------------------------------------------------------------------

H.Slash.Register("selftest", function() D.Selftest() end, "selftest - версия, модули, claims/parks/hudOwned, ошибки, метки хуков")
H.Slash.Register("errors", function(rest)
	if rest == "clear" then
		H.Errors.Clear()
		H.Print("журнал ошибок очищен")
		return
	end
	D.ShowErrors()
end, "errors [clear] - ошибки Lua всех аддонов по корзинам")
H.Slash.Register("dump", function(rest)
	D.Dump(rest)
end, "dump <run|zone|target|revive|end|units|spells|party|schedule|loadout|meter|hud|park|poll|hudcvars|stamps> - слои данных и сырые AZS_*")
H.Slash.Register("inspect", function() D.Inspect() end, "inspect - элемент под курсором (через 2 с)")
H.Slash.Register("frames", function() D.Frames() end, "frames - видимые окна верхнего уровня")
