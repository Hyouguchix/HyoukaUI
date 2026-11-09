-- HyoukaUI: модуль Build, надетая бижутерия: данные слотов, теги бонусов и строки раздела списка сборки.
--
-- Слоты 2, 11, 12, 13, 14 (шея, кольца, аксессуары). Состав берется стоковыми GetInventoryItemLink и
-- GetInventoryItemTexture (мгновенно, без ожидания ответа loadout), теги из текста подсказки предмета
-- через Data\TooltipScan (SetInventoryItem, очередь с лимитом, SCAN_READY). Ранг: из loadout
-- (H.Loadout.ItemRank), иначе римская цифра в конце имени, иначе nil.
-- Замена предмета видна сразу: UNIT_INVENTORY_CHANGED и опрос раз в секунду (улучшение карточкой события
-- не шлет, inv build#22). Запись слота сравнивается по ссылке: новая ссылка - новый разбор.
--
-- Теги: строка подсказки с числом и подстрокой из H.L.tagFind (plain find, нижний регистр, ASCII и кириллица),
-- самый специфичный тег первым (порядок ORDER), значение со знаком, формат из H.L.tagFmt. До 5 тегов,
-- подбор по ширине ступенями small 12 -> 11 -> 10 ретейл-px (6.4 -> 5.9 -> 5.3 AS), дальше первые теги и "...+".
-- [НЕ ПРОВЕРЕНО] формулировки бонусов бижутерии в игре: подстроки в Locale подобраны по смыслу.
--
-- J.Slot(i) -> запись { id, link, name, tex, r, g, b, quality, rank, tags, nTags, pending, ver }
-- J.Refresh() -> true, если что-то изменилось; J.Subscribe(fn) вызывает fn() после изменения.
-- J.NewRow(parent) / J.UpdateRow(row, i, mode): строка раздела "Бижутерия" списка сборки.

local H = HyoukaUI
local B = H.Build

local J = {}
B.Jewelry = J

local getn = table.getn
local ORDER = { "crit", "cdr", "area", "proj", "armor", "speed", "life", "dmg" }
local NEGATIVE = { "reduce", "decrease", "lower", "less", "меньш", "уменьш", "сниж", "сокращ" }
local QUALITY = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }
local MAX_TAGS = 5

local slots = {}
for i = 1, 5 do
	slots[i] = { id = B.SLOT_IDS[i], tags = {}, nTags = 0, r = 1, g = 1, b = 1, quality = 1, ver = 0 }
end
local subs = {}
J.stats = { refreshes = 0, changes = 0 }

function J.Slot(i)
	return slots[i]
end

function J.Count()
	local n = 0
	for i = 1, 5 do
		if slots[i].link then
			n = n + 1
		end
	end
	return n
end

function J.Subscribe(fn)
	for i = 1, getn(subs) do
		if subs[i] == fn then
			return
		end
	end
	table.insert(subs, fn)
end

function J.Unsubscribe(fn)
	for i = getn(subs), 1, -1 do
		if subs[i] == fn then
			table.remove(subs, i)
		end
	end
end

local function Notify()
	for i = 1, getn(subs) do
		subs[i]()
	end
end

----------------------------------------------------------------------------------------
-- Теги
----------------------------------------------------------------------------------------

local function TagKey(line)
	local codes = { H.Locale and H.Locale.code or "enUS", "enUS", "ruRU" }
	for c = 1, 3 do
		local loc = H.Locales[codes[c]]
		local tf = loc and loc.tagFind
		if tf then
			for i = 1, getn(ORDER) do
				local words = tf[ORDER[i]]
				if words and B.HasWord(line, words) then
					return ORDER[i]
				end
			end
		end
	end
	return nil
end

local function MakeTag(key, line)
	local s, e, num = string.find(line, "(%d+%.?%d*)")
	if not s then
		return nil
	end
	local value = math.floor(tonumber(num) + 0.5)
	local negative = (s > 1 and string.sub(line, s - 1, s - 1) == "-") or B.HasWord(line, NEGATIVE)
	local pct = string.sub(line, e + 1, e + 1) == "%"
	local fmts = H.L.tagFmt
	local word = H.L.tags[key] or key
	local text = string.format(pct and fmts.pct or fmts.flat, value, word)
	if negative then
		text = string.gsub(text, "^%+", "-")
	end
	return text
end

local function ClearTags(rec)
	H.Wipe(rec.tags)
	rec.nTags = 0
end

-- Теги из записи подсказки. Первая строка - имя предмета, ее пропускаем.
local function BuildTags(rec, scan)
	ClearTags(rec)
	local used = {}
	for i = 2, scan.n do
		local text = scan.left[i]
		if text and string.find(text, "%d") then
			local line = B.Lower(text)
			local key = TagKey(line)
			if key and not used[key] then
				local tag = MakeTag(key, line)
				if tag and rec.nTags < MAX_TAGS then
					used[key] = true
					rec.nTags = rec.nTags + 1
					table.insert(rec.tags, tag)     -- не tags[n] = ...: после H.Wipe (setn 0) getn не растет
				end
			end
		end
	end
end

local function ReadTags(rec)
	local scan = H.TooltipScan.Item(rec.id)
	if scan == "pending" then
		rec.pending = true
		return false
	end
	rec.pending = false
	BuildTags(rec, scan)
	return true
end

----------------------------------------------------------------------------------------
-- Запись слота
----------------------------------------------------------------------------------------

-- Цвет и качество из ссылки на предмет: r, g, b, quality (белый и качество 1, если цвета в ссылке нет).
function J.LinkColor(link)
	local _, _, hex = string.find(link, "|c%x%x(%x%x%x%x%x%x)|H")
	if not hex then
		return 1, 1, 1, 1
	end
	return tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255,
		tonumber(string.sub(hex, 5, 6), 16) / 255, QUALITY[string.lower(hex)] or 1
end

local function ParseLink(rec, link)
	rec.r, rec.g, rec.b, rec.quality = J.LinkColor(link)
	local _, _, name = string.find(link, "%[(.-)%]")
	rec.name = name or link
	local rank = H.Loadout.ItemRank(rec.id)
	if type(rank) ~= "number" then
		local _, _, roman = string.find(rec.name, "%s(%u+)$")
		rank = B.RomanValue(roman)
	end
	rec.rank = rank
end

local function ReadSlot(rec)
	local link = GetInventoryItemLink("player", rec.id)
	if link == nil then
		link = false
	end
	local tex = GetInventoryItemTexture("player", rec.id)
	local changed = false
	if (rec.link or false) ~= link then
		changed = true
		rec.ver = rec.ver + 1
		if link then
			rec.link = link
			ParseLink(rec, link)
			ReadTags(rec)
		else
			rec.link, rec.name, rec.rank, rec.pending = nil, nil, nil, false
			ClearTags(rec)
		end
	elseif link and rec.pending and ReadTags(rec) then
		changed = true
		rec.ver = rec.ver + 1
	end
	if rec.tex ~= tex then
		rec.tex = tex
		changed = true
	end
	return changed
end

-- Перечитать все слоты. true, если что-то изменилось.
function J.Refresh()
	J.stats.refreshes = J.stats.refreshes + 1
	local any = false
	for i = 1, 5 do
		if ReadSlot(slots[i]) then
			any = true
		end
	end
	if any then
		J.stats.changes = J.stats.changes + 1
		Notify()
	end
	return any
end

-- Принудительный повторный разбор тегов (смена языка).
function J.Reparse()
	for i = 1, 5 do
		local rec = slots[i]
		if rec.link then
			ReadTags(rec)
			rec.ver = rec.ver + 1
		end
	end
	Notify()
end

function J.Reset()
	for i = 1, 5 do
		local rec = slots[i]
		rec.link, rec.name, rec.tex, rec.rank, rec.pending = nil, nil, nil, nil, false
		ClearTags(rec)
		rec.ver = rec.ver + 1
	end
end

----------------------------------------------------------------------------------------
-- Подпись слота и строка раздела
----------------------------------------------------------------------------------------

function J.SlotLabel(i)
	return B.T(B.SLOT_KEYS[i])
end

local ROW_W, ROW_H = 199, 24

local function JoinTags(rec, n)
	local sep = " "..H.Fonts.SYM.dot.." "
	if n >= rec.nTags then
		return table.concat(rec.tags, sep)
	end
	local part = {}
	for k = 1, n do
		part[k] = rec.tags[k]
	end
	return table.concat(part, sep)..H.L.tagMore
end

-- Теги в ширину avail (AS): ступени шрифта, затем меньше тегов. Результат кэшируется по версии записи.
local function FitTags(row, rec, avail)
	if row.tagVer == rec.ver and row.tagAvail == avail and row.tagLoc == H.Locale.code then
		return
	end
	row.tagVer, row.tagAvail, row.tagLoc = rec.ver, avail, H.Locale.code
	local fs = row.tags
	if rec.nTags == 0 then
		H.Fonts.Apply(fs, "small", 0)
		fs:SetText(rec.pending and "..." or B.T("no_tags"))
		return
	end
	local full = JoinTags(rec, rec.nTags)
	for step = 0, 2 do
		H.Fonts.Apply(fs, "small", -step)
		fs:SetText(full)
		if fs:GetStringWidth() <= avail then
			return
		end
	end
	for n = rec.nTags - 1, 1, -1 do
		fs:SetText(JoinTags(rec, n))
		if fs:GetStringWidth() <= avail then
			return
		end
	end
	fs:SetText(JoinTags(rec, 1))
end

function J.NewRow(parent)
	local row = H.Panel.New(parent, { w = ROW_W, h = ROW_H, bg = "panel" })
	row.icon = H.Icon.New(row, { size = ROW_H - 2, border = false, digits = false })
	row.icon:SetPoint("LEFT", row, "LEFT", H.R(1), 0)
	row.name = H.Text.New(row, "body")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", H.R(3), 0)
	row.tags = H.Text.New(row, "small", { justify = "RIGHT" })
	row.tags:SetPoint("RIGHT", row, "RIGHT", -H.R(3), 0)
	row.slotIndex = 0
	row:EnableMouse(true)
	H.Script("build", row, "OnEnter", function(self)
		local rec = slots[row.slotIndex]
		if rec and rec.link then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetInventoryItem("player", rec.id)
			GameTooltip:Show()
		end
	end)
	H.Script("build", row, "OnLeave", function(self)
		GameTooltip:Hide()
	end)
	return row
end

-- Показать слот i в строке. mode "names": имя по качеству и теги; "slot": слот, ранг и теги.
function J.UpdateRow(row, i, mode)
	local rec = slots[i]
	row.slotIndex = i
	local fullW = H.R(ROW_W)
	if not rec.link then
		row.icon:Hide()
		row.tags:SetText("")
		row.tagVer = nil
		H.Text.SetColor(row.name, "dim")
		H.Text.Fit(row.name, J.SlotLabel(i).." "..B.T("slot_empty"), fullW - H.R(8))
		return
	end
	row.icon:Show()
	H.Icon.SetTexture(row.icon, rec.tex)
	H.Text.SetColor(row.name, mode == "slot" and "text" or { rec.r, rec.g, rec.b, 1 })
	FitTags(row, rec, math.floor(fullW * 0.55))
	local tagW = row.tags:GetStringWidth() or 0
	local label
	if mode == "slot" then
		label = J.SlotLabel(i)
		if rec.rank then
			label = label.." "..H.Format.Roman(rec.rank)
		end
	else
		label = rec.name
	end
	H.Text.Fit(row.name, label, fullW - H.R(ROW_H + 8) - tagW)
end

-- Сбросить кэши подгонки (смена шрифта, масштаба, языка).
function J.ForgetFit(row)
	row.tagVer = nil
	row.name.huiFitText = nil
end
