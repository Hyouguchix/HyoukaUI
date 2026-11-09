-- HyoukaUI: Modules\Tracker\LootLog, панель добычи забега tr.loot (часть "loot" модуля Трекер).
--
-- Маленький список того, что выпало в этом забеге: новое сверху, в строке иконка, имя цветом редкости, "x2" при повторе того
-- же предмета (одна строка, снова наверху) и минута:секунда забега. Панель видна, только когда что-то выпало, в фазе выбора
-- карт скрыта вместе с остальными кусками (Tr.Set, Visibility), новый runId (Hub: reset) очищает список. Строк показано не
-- больше настройки lootLines (по умолчанию 8): старые уходят вниз и за край списка. Данные: чат (Tr.LootParse), события
-- CHAT_MSG_LOOT и подстраховка через AddMessage окна чата (строка из двух дорожек считается один раз). Наведение на строку
-- показывает подсказку предмета: ссылка из строки или запомненная по имени у надетых предметов; без ссылки - имя и пояснение.
-- Режимы: Выкл - кадров нет; Рядом - рисуем; Вместо - часть игры loot закрывает запись Claims (запрос к ядру в записке).
-- Строки панели собраны заранее и переиспользуются; текст ставится, только когда запись изменилась (счетчик ver).

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format
local LP = Tr.LootParse

local getn = table.getn
local floor = math.floor

local PW, TITLE_H, ROW_H, PAD, ICON = 230, 16, 18, 3, 16
local KEEP, MAXROWS, TIME_W, COUNT_W = 40, 12, 30, 24
local WHITE = { 1, 1, 1 }
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Строки: свои ключи в таблицах Locale трекера (добавляются, чужие не трогаются).
Tr.STR.ruRU.loot = "Добыча"
Tr.STR.enUS.loot = "Loot"
Tr.STR.ruRU.loot_tip = "Подробности предмета появятся, когда герой наденет его в забеге."
Tr.STR.enUS.loot_tip = "Item details show here once the hero has worn it in a run."
Tr.STR.ruRU.o_loot = "Панель добычи"
Tr.STR.enUS.o_loot = "Loot panel"
Tr.STR.ruRU.o_loot_lines = "Строк в списке"
Tr.STR.enUS.o_loot_lines = "Lines in the list"
Tr.STR.ruRU.o_loot_hint = "Что выпало в этом забеге: новое сверху. Слева у игры свой список добычи: в режиме Вместо он скрыт."
Tr.STR.enUS.o_loot_hint = "What dropped this run, newest on top. In Replace mode the game's own loot notices are hidden."

-- Умолчания настроек (Hub их не знает): добавляются в таблицу умолчаний модуля.
local defaults = H.DB and H.DB.defaults and H.DB.defaults.tracker
if defaults then
	if defaults.lootLog == nil then
		defaults.lootLog = true
	end
	if defaults.lootLines == nil then
		defaults.lootLines = 8
	end
end

-- Событие чата не входит в список стоковых событий ядра: добавляем его в общую таблицу (ядро не правится).
if H.Events and H.Events.STOCK then
	H.Events.STOCK.CHAT_MSG_LOOT = true
end

-- Запасное место, пока в Data\LayoutDefaults нет записи tr.loot: под панелью "Этот забег", той же ширины.
local FALLBACK = {
	label = Tr.T("loot"), point = "TOPLEFT", rel = "tr.thisRun", relPoint = "BOTTOMLEFT", x = 0, y = -1, w = 230, h = 40,
	src = "plan 2.8 (левая колонка: под tr.thisRun, ширина 230 как у нее); нет в ретейле",
}

local LL = { rows = {}, entries = {}, free = {}, pool = {}, h = 0, known = {} }
Tr.LootLog = LL

local function R(px)
	return H.R(px)
end

local function Opt(key)
	local v = Tr.Opt(key)
	if key == "lootLines" then
		v = tonumber(v) or 8
		if v < 1 then
			v = 1
		elseif v > MAXROWS then
			v = MAXROWS
		end
		return floor(v)
	end
	return v ~= false
end

----------------------------------------------------------------------------------------
-- Запомненные ссылки надетых предметов (имя -> "item:id:...")
----------------------------------------------------------------------------------------

local function Known()
	local g = H.DB and H.DB.Global and H.DB.Global()
	if g then
		g.lootLinks = g.lootLinks or {}
		return g.lootLinks
	end
	return LL.known
end

local function Learn(link)
	if type(link) ~= "string" then
		return
	end
	local n = LP.Items(link, LL.pool, 1)
	if n > 0 and LL.pool[1].link then
		Known()[LL.pool[1].name] = LL.pool[1].link
	end
end

local function LearnSlots(from, to)
	if not GetInventoryItemLink then
		return
	end
	for slot = from, to do
		local ok, link = pcall(GetInventoryItemLink, "player", slot)
		if ok then
			Learn(link)
		end
	end
end

----------------------------------------------------------------------------------------
-- Иконка и цвет предмета: по ссылке из строки или запомненной; чего нет, дочитывается раз в секунду
----------------------------------------------------------------------------------------

local function Resolve(e)
	local link = e.link or Known()[e.name]
	if not link then
		return
	end
	e.link = link
	if GetItemInfo then
		local ok, _, _, quality, _, _, _, _, _, tex = pcall(GetItemInfo, link)
		if ok then
			if tex and not e.tex then
				e.tex = tex
				e.ver = e.ver + 1
			end
			if not e.colored and quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
				local c = ITEM_QUALITY_COLORS[quality]
				e.r, e.g, e.b, e.colored = c.r, c.g, c.b, true
				e.ver = e.ver + 1
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- Записи (новое сверху)
----------------------------------------------------------------------------------------

local Paint, Relayout, Place

local function Take()
	local n = getn(LL.free)
	if n > 0 then
		return table.remove(LL.free, n)
	end
	return {}
end

local function Release(e)
	e.link, e.tex, e.colored = nil, nil, nil
	table.insert(LL.free, e)
end

local function AddItem(name, color, link, count)
	local entries = LL.entries
	local now = H.Run.Time() or 0
	local e
	for i = 1, getn(entries) do
		if entries[i].name == name then
			e = table.remove(entries, i)
			break
		end
	end
	if e then
		e.count = e.count + count
		e.ver = e.ver + 1
	else
		e = Take()
		e.name, e.count, e.ver, e.tries = name, count, 1, 0
		local r, g, b = LP.Rgb(color)
		if r then
			e.r, e.g, e.b, e.colored = r, g, b, true
		else
			e.r, e.g, e.b, e.colored = 1, 1, 1, false
		end
	end
	e.link = link or e.link
	e.at = floor(now)
	table.insert(entries, 1, e)
	while getn(entries) > KEEP do
		Release(table.remove(entries))
	end
	Resolve(e)
	if link then
		Known()[name] = link
	end
end

local function Seen(text, way)
	if not LL.on or not Opt("lootLog") then
		return
	end
	local rest = LP.Received(text)
	if not rest or not LP.Fresh(rest, way, H.Now()) then
		return
	end
	local pool = LL.pool
	local n = LP.Items(rest, pool, 8)
	for i = 1, n do
		local rec = pool[i]
		AddItem(rec.name, rec.color, rec.link, rec.count)
	end
	if n > 0 then
		Paint()
		Relayout()
		Place()
	end
end

local function OnLoot(ev, message)
	Seen(message, "event")
end

----------------------------------------------------------------------------------------
-- Подстраховка: строка, которая дошла до окна чата, но не пришла событием
----------------------------------------------------------------------------------------

local function InstallWatch()
	local f = DEFAULT_CHAT_FRAME
	if not f then
		return
	end
	if LL.wrap then
		LL.watching = true
		return
	end
	local stock = f.AddMessage
	if type(stock) ~= "function" then
		return
	end
	LL.stock = stock
	LL.wrap = function(self, text, a, b, c, d, e)
		if LL.watching then
			H.Safe("tracker", Seen, text, "window")
		end
		return stock(self, text, a, b, c, d, e)
	end
	f.AddMessage = LL.wrap
	LL.watching = true
end

local function RemoveWatch()
	LL.watching = false
	local f = DEFAULT_CHAT_FRAME
	if f and LL.wrap and f.AddMessage == LL.wrap then
		f.AddMessage = LL.stock
		LL.wrap, LL.stock = nil, nil
	end
end

----------------------------------------------------------------------------------------
-- Строки панели
----------------------------------------------------------------------------------------

local function Tip(row)
	local e = row.entry
	if not e then
		return
	end
	local tip = GameTooltip
	tip:SetOwner(row.frame, "ANCHOR_RIGHT")
	local link = e.link or Known()[e.name]
	local ok = false
	if link then
		ok = pcall(tip.SetHyperlink, tip, link)
	end
	if not ok then
		tip:SetText(e.name, e.r or 1, e.g or 1, e.b or 1)
		tip:AddLine(Tr.T("loot_tip"), 0.62, 0.62, 0.68, 1)
	end
	tip:Show()
end

local function MakeRow(i)
	local f = CreateFrame("Button", nil, LL.panel)
	f:SetWidth(R(PW))
	f:SetHeight(R(ROW_H))
	local row = { frame = f, entry = nil, ver = nil }
	local icon = H.Icon.New(f, { size = ICON, digits = false })
	icon:SetPoint("LEFT", f, "LEFT", R(3), 0)
	row.icon = icon
	row.timeFs = K.Text(f, "body", nil, "RIGHT")
	row.timeFs:SetPoint("RIGHT", f, "RIGHT", -R(4), 0)
	Tr.Color(row.timeFs, Tr.C.gray)
	row.countFs = K.Text(f, "body", nil, "RIGHT")
	row.countFs:SetPoint("RIGHT", f, "RIGHT", -R(4 + TIME_W), 0)
	Tr.Color(row.countFs, Tr.C.count)
	row.nameFs = K.Text(f, "body", nil, "LEFT")
	row.nameFs:SetPoint("LEFT", f, "LEFT", R(ICON + 7), 0)
	row.nameFs:SetWidth(R(PW - ICON - 7 - 4 - TIME_W - COUNT_W))
	row.nameFs:SetHeight(R(ROW_H - 4))
	H.Script("tracker", f, "OnEnter", function()
		pcall(Tip, row)
	end)
	H.Script("tracker", f, "OnLeave", function()
		GameTooltip:Hide()
	end)
	LL.rows[i] = row
	return row
end

local function Shown()
	local n = getn(LL.entries)
	local cap = Opt("lootLines")
	if n > cap then
		n = cap
	end
	return n
end

-- Текст строк ставится, только когда запись или ее версия изменилась.
function Paint()
	if not LL.panel then
		return
	end
	local n = Shown()
	for i = 1, MAXROWS do
		local row = LL.rows[i]
		if i <= n then
			row = row or MakeRow(i)
			local e = LL.entries[i]
			if row.entry ~= e or row.ver ~= e.ver then
				row.entry, row.ver = e, e.ver
				row.nameFs:SetText(e.name)
				row.nameFs:SetTextColor(e.r or 1, e.g or 1, e.b or 1, 1)
				row.countFs:SetText(e.count > 1 and ("x"..Fm.Int(e.count)) or "")
				row.timeFs:SetText(Tr.TimeStr(e.at))
				H.Icon.SetTexture(row.icon, e.tex or QMARK)
				H.Icon.SetBorderColor(row.icon, 0, 0, 0, 1)
			end
			row.frame:Show()
		elseif row then
			row.entry, row.ver = nil, nil
			row.frame:Hide()
		end
	end
end

function Relayout()
	if not LL.panel then
		return
	end
	local n = Shown()
	local y = PAD + TITLE_H
	LL.titleFs:SetText(Tr.T("loot"))
	for i = 1, n do
		local row = LL.rows[i]
		if row then
			row.frame:SetWidth(R(PW))
			row.frame:SetHeight(R(ROW_H))
			row.frame:ClearAllPoints()
			row.frame:SetPoint("TOPLEFT", LL.panel, "TOPLEFT", 0, -R(y))
			y = y + ROW_H
		end
	end
	y = y + PAD
	if y ~= LL.h then
		LL.h = y
		if H.Layout.Has("tr.loot") then
			H.Layout.SetSize("tr.loot", nil, y)
		end
	end
end

function Place()
	if not LL.panel then
		return
	end
	Tr.Set(LL.panel, Opt("lootLog") and getn(LL.entries) > 0 and Tr.InRun())
end

local function Refresh()
	if not LL.panel then
		return
	end
	local r, g, b = Tr.Accent()
	LL.titleFs:SetTextColor(r, g, b, 1)
	for i = 1, getn(LL.rows) do
		LL.rows[i].ver = nil
	end
	Paint()
	Relayout()
end

local function Build()
	PW = Tr.Def("tr.thisRun", "w", PW)
	local panel = CreateFrame("Frame", nil, UIParent)
	LL.panel = panel
	K.Fill(panel, "bg", "BACKGROUND")
	K.Border(panel, "edge")
	LL.titleFs = K.Text(panel, "body", nil, "LEFT")
	LL.titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", R(4), -R(PAD + 1))
	panel:Hide()
end

local function Clear()
	local entries = LL.entries
	for i = getn(entries), 1, -1 do
		Release(table.remove(entries, i))
	end
	LP.Reset()
	Paint()
	Relayout()
end

----------------------------------------------------------------------------------------
-- Часть трекера
----------------------------------------------------------------------------------------

Tr.Part("loot", {
	build = Build,
	show = function()
		LL.on = true
		FALLBACK.label = Tr.T("loot")
		Tr.Register("tr.loot", LL.panel, H.Layout.Def("tr.loot") == nil and FALLBACK or nil)
		LL.h = 0
		InstallWatch()
		LearnSlots(1, 19)
	end,
	hide = function()
		LL.on = false
		RemoveWatch()
		GameTooltip:Hide()
	end,
	refresh = Refresh,
	place = Place,
	theme = function()
		LL.h = 0
		Relayout()
	end,
	slow = function(now)
		local n = Shown()
		local dirty = false
		for i = 1, n do
			local e = LL.entries[i]
			if (not e.tex or not e.colored) and e.tries < 10 then
				e.tries = e.tries + 1
				local ver = e.ver
				Resolve(e)
				dirty = dirty or e.ver ~= ver
			end
		end
		if dirty then
			Paint()
		end
	end,
	reset = Clear,
	settings = function(key)
		if key == "lootLines" or key == "lootLog" then
			Paint()
			Relayout()
		end
	end,
	on = {
		CHAT_MSG_LOOT = OnLoot,
		UNIT_INVENTORY_CHANGED = function(ev, unit)
			if unit == "player" then
				LearnSlots(2, 2)
				LearnSlots(11, 14)
			end
		end,
	},
	dump = function(out)
		table.insert(out, "добыча: записей "..getn(LL.entries).."  строк "..getn(LL.rows).."  высота "..LL.h.."  окно чата "..tostring(LL.watching == true))
		for i = 1, Shown() do
			local e = LL.entries[i]
			table.insert(out, "  "..e.name.." x"..e.count.." "..Tr.TimeStr(e.at).." "..tostring(e.link))
		end
	end,
})

----------------------------------------------------------------------------------------
-- Настройки: своя страница (страницу "Трекер" ведет TrackerOptions); цепочка поверх Tr.RegisterOptions
----------------------------------------------------------------------------------------

local function BuildPage(page, f)
	f:Header(Tr.T("loot"))
	f:Toggle({ label = Tr.T("o_loot"), hint = Tr.T("o_loot_hint"), mod = "tracker", key = "lootLog" })
	f:Slider({ label = Tr.T("o_loot_lines"), mod = "tracker", key = "lootLines", min = 3, max = MAXROWS, step = 1,
		fmt = function(v)
			return tostring(v)
		end })
	f:Refresh()
end

local prevOptions = Tr.RegisterOptions
function Tr.RegisterOptions()
	if prevOptions then
		prevOptions()
	end
	if H.Options and H.Options.AddPage then
		H.Options.AddPage("trackerLoot", function()
			return K.L("page_tracker_loot", Tr.T("loot"))
		end, BuildPage, 41)
	end
end
