-- HyoukaUI: модуль Build, свое окно персонажа (решение 4 плана, inv build#27 и #28).
--
-- Окно в скине AES: фон #080808 0.85, рамка 1 px, заголовок акцентом, кнопка закрытия X, закрывается по Esc через
-- UISpecialFrames и перетаскивается за заголовок (место запоминается в настройках модуля). Слева экипировка (слоты
-- с рамкой по качеству, подсказка предмета), модель героя клиента, ряд способностей сборки; справа бонус урона
-- крупно, строка забега и прокручиваемый список статов (CharacterStats.lua) с разделом талантов.
-- ОТКРЫТИЕ: клавиша C через обертку ToggleCharacter (CharacterWrap.lua; в режиме "Вместо" C открывает это окно,
-- в режиме "Рядом" его открывает Shift+C, обычная C открывает стоковое). Нулевые значения скрыты, пока есть данные (настройка hideZero); без данных (до
-- первого забега) справа строка "Начните забег, чтобы увидеть статы".
-- Данные статов: слой H.Stats (запрос к ядру). Состав талантов: H.Loadout.Get().talents (поля записи не сняты,
-- читаются осторожно). Модель: PlayerModel:SetUnit("player") показывает героя клиента, не героя забега [НЕ ПРОВЕРЕНО].
-- Кадр с именем HyoukaUI_Character; создается при первом открытии. На карточках выбора окно прячется (Visibility).

local H = HyoukaUI
local B = H.Build
local T = H.Theme
local Fm = H.Format
local X = B.StatDefs

local C = {}
B.Character = C

local W, HGT, TITLE = 600, 480, 28
local SLOT = 34
local LEFT_IDS = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT_IDS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local WEAPON_IDS = { 16, 17, 18 }
local ROW_H = 15

local S = { slots = {}, abil = {}, items = {}, vis = {}, last = {}, talents = {} }
C.S = S

-- Предметы-заглушки списка: создаются один раз, список только переставляет ссылки.
local HEAD, STAT = {}, {}
for i = 1, table.getn(X.SECTIONS) do
	HEAD[i] = { kind = "head", sec = i }
end
for key in pairs(X.DEF) do
	STAT[key] = { kind = "stat", key = key }
end
local NOTE = { kind = "note" }
local TALENT_HEAD = { kind = "head", sec = 0 }
local TALENT_NOTE = { kind = "none" }

local function Settings()
	return B.M.db
end

local function At(f, x, y)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", S.frame, "TOPLEFT", H.R(x), -H.R(y))
end

----------------------------------------------------------------------------------------
-- Список статов
----------------------------------------------------------------------------------------

local function TipShow(row)
	local item = row.item
	if not item then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if item.kind == "stat" then
		GameTooltip:SetText(X.Label(item.key).." "..X.Text(item.key, X.Value(item.key)), 1, 1, 1)
		GameTooltip:AddLine(X.Tip(item.key), 1, 0.82, 0, 1)
		local gear = X.GearText(item.key)
		if gear ~= "" then
			GameTooltip:AddLine(gear, 0.3, 0.8, 0.4, 1)
		end
		GameTooltip:Show()
	elseif item.kind == "talent" then
		GameTooltip:SetText(item.name, 1, 1, 1)
		GameTooltip:Show()
	end
end

local function CreateRow(row, list)
	row.label = H.Text.New(row, "body")
	row.label:SetPoint("LEFT", row, "LEFT", H.R(3), 0)
	row.value = H.Text.New(row, "body", { justify = "RIGHT" })
	row.value:SetPoint("RIGHT", row, "RIGHT", -H.R(3), 0)
	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetTexture(T.TEX.solid)
	row.hover:SetAllPoints(row)
	local hc = T.C.hover
	row.hover:SetVertexColor(hc[1], hc[2], hc[3], hc[4])
	row.hover:Hide()
	row:EnableMouse(true)
	H.Script("build", row, "OnEnter", function(self)
		if row.item and (row.item.kind == "stat" or row.item.kind == "talent") then
			row.hover:Show()
			TipShow(row)
		end
	end)
	H.Script("build", row, "OnLeave", function(self)
		row.hover:Hide()
		GameTooltip:Hide()
	end)
end

local function UpdateRow(row, item)
	row.item = item
	local kind = item.kind
	row.hover:Hide()
	if kind == "head" then
		H.Text.SetColor(row.label, "accent")
		row.label:SetText(item.sec == 0 and B.T("sec_talents") or B.T(X.SECTIONS[item.sec].key))
		row.value:SetText("")
	elseif kind == "stat" then
		H.Text.SetColor(row.label, "text")
		row.label:SetText(X.Label(item.key))
		row.value:SetText(X.Text(item.key, X.Value(item.key)))
	elseif kind == "talent" then
		H.Text.SetColor(row.label, "text")
		H.Text.Fit(row.label, item.name, H.R(250))
		row.value:SetText(item.rank and Fm.Int(item.rank) or "")
	elseif kind == "note" then
		H.Text.SetColor(row.label, "muted")
		row.label:SetText(B.T("char_empty"))
		row.value:SetText("")
	else
		H.Text.SetColor(row.label, "muted")
		row.label:SetText(B.T("char_no_talents"))
		row.value:SetText("")
	end
end

-- Таланты героя из loadout (записи с положительным рангом; поля читаются осторожно).
local function TalentItems(items)
	table.insert(items, TALENT_HEAD)
	local data = H.Loadout.Get(nil)
	local list = data and data.talents
	local n = 0
	if type(list) == "table" then
		for i = 1, table.getn(list) do
			local row = list[i]
			if type(row) == "table" and row.rank ~= 0 and row.learned ~= false and row.selected ~= false then
				local src = row.sourceKey and H.Loadout.Source(row.sourceKey)
				local name = src and src.name or row.name or row.sourceKey
				if name then
					n = n + 1
					local it = S.talents[n]
					if not it then
						it = { kind = "talent" }
						S.talents[n] = it
					end
					it.name, it.rank = tostring(name), type(row.rank) == "number" and row.rank or nil
					table.insert(items, it)
				end
			end
		end
	end
	if n == 0 then
		table.insert(items, TALENT_NOTE)
	end
end

-- Собрать список по текущим данным (по событиям и смене значений).
function C.RebuildItems()
	local items = S.items
	H.Wipe(items)
	if not X.HasData() then
		table.insert(items, NOTE)
	else
		for sec = 1, table.getn(X.SECTIONS) do
			if X.VisibleRows(sec, Settings().hideZero, S.vis) > 0 then
				table.insert(items, HEAD[sec])
				for i = 1, table.getn(S.vis) do
					table.insert(items, STAT[S.vis[i]])
				end
			end
		end
	end
	TalentItems(items)
	if S.list then
		H.List.SetItems(S.list, items, table.getn(items))
	end
end

----------------------------------------------------------------------------------------
-- Кадры окна
----------------------------------------------------------------------------------------

local function SlotTip(icon, id)
	icon:EnableMouse(true)
	H.Script("build", icon, "OnEnter", function(self)
		GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
		GameTooltip:SetInventoryItem("player", id)
		GameTooltip:Show()
	end)
	H.Script("build", icon, "OnLeave", function(self)
		GameTooltip:Hide()
	end)
end

local function MakeSlots(ids, x, y)
	for i = 1, table.getn(ids) do
		local icon = H.Icon.New(S.frame, { size = SLOT, digits = false })
		At(icon, x, y + (i - 1) * (SLOT + 4))
		SlotTip(icon, ids[i])
		table.insert(S.slots, { id = ids[i], icon = icon, x = x, y = y + (i - 1) * (SLOT + 4) })
	end
end

local function MakeWeapons(x, y)
	for i = 1, 3 do
		local icon = H.Icon.New(S.frame, { size = SLOT, digits = false })
		At(icon, x + (i - 1) * (SLOT + 4), y)
		SlotTip(icon, WEAPON_IDS[i])
		table.insert(S.slots, { id = WEAPON_IDS[i], icon = icon, x = x + (i - 1) * (SLOT + 4), y = y })
	end
end

local function MakeAbilities(x, y)
	for i = 1, 7 do
		local icon = H.Icon.New(S.frame, { size = 24, digits = false })
		At(icon, x + (i - 1) * 28, y)
		icon:EnableMouse(true)
		H.Script("build", icon, "OnEnter", function(self)
			local slot = icon.slot
			if slot then
				GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
				GameTooltip:SetAction(slot)
				GameTooltip:Show()
			end
		end)
		H.Script("build", icon, "OnLeave", function(self)
			GameTooltip:Hide()
		end)
		S.abil[i] = icon
	end
end

local function Place()
	local db = Settings()
	S.frame:ClearAllPoints()
	if db.charPlaced then
		S.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", H.R(db.charX), -H.R(db.charY))
	else
		S.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
end

local function SavePosition()
	local left, top = S.frame:GetLeft(), S.frame:GetTop()
	if left and top then
		local _, sh = H.Layout.Screen()
		local px = T.PX
		H.DB.Set("build", "charX", math.floor(left / px + 0.5))
		H.DB.Set("build", "charY", math.floor((sh - top) / px + 0.5))
		H.DB.Set("build", "charPlaced", true)
	end
	Place()
end

local function MakeFrame()
	local f = CreateFrame("Frame", "HyoukaUI_Character", UIParent)
	S.frame = f
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	H.Panel.SetBg(f, "panel")
	T.AddBorder(f)
	H.Panel.Size(f, W, HGT)
	S.title = H.Text.New(f, "title", { color = "accent" })
	At(S.title, 10, 7)
	S.hero = H.Text.New(f, "body")
	At(S.hero, 10, TITLE + 4)
	S.close = H.Kit.Button(f, "X", H.R(18), H.R(18), function()
		C.Close()
	end, "build")
	S.close:ClearAllPoints()
	S.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -H.R(5), -H.R(5))
	local drag = CreateFrame("Frame", nil, f)
	drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -H.R(28), 0)
	drag:SetHeight(H.R(TITLE))
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	S.drag = drag
	H.Script("build", drag, "OnDragStart", function(self)
		f:StartMoving()
	end)
	H.Script("build", drag, "OnDragStop", function(self)
		f:StopMovingOrSizing()
		SavePosition()
	end)
	MakeSlots(LEFT_IDS, 12, 52)
	MakeSlots(RIGHT_IDS, 196, 52)
	MakeWeapons(12, 52 + 8 * (SLOT + 4) + 6)
	S.abilTitle = H.Text.New(f, "body", { color = "accent" })
	At(S.abilTitle, 12, 52 + 8 * (SLOT + 4) + 6 + SLOT + 14)
	MakeAbilities(12, 52 + 8 * (SLOT + 4) + 6 + SLOT + 34)
	local ok, model = pcall(CreateFrame, "PlayerModel", nil, f)
	if ok and model then
		S.model = model
		At(model, 54, 52)
		model:SetWidth(H.R(138))
		model:SetHeight(H.R(8 * (SLOT + 4) - 4))
		pcall(model.SetUnit, model, "player")
	end
	S.headline = H.Text.New(f, "msg", { color = "accent" })
	At(S.headline, 250, TITLE + 6)
	S.caption = H.Text.New(f, "body", { color = "muted" })
	At(S.caption, 250, TITLE + 36)
	S.run = H.Text.New(f, "body")
	At(S.run, 250, TITLE + 56)
	S.runTime = H.Text.New(f, "body", { color = "accent" })
	S.runTime:SetPoint("LEFT", S.run, "RIGHT", H.R(4), 0)
	S.list = H.List.New(f, { w = 338, h = HGT - TITLE - 84, row = ROW_H, gap = 1, create = CreateRow, update = UpdateRow, owner = "build" })
	At(S.list, 250, TITLE + 80)
	local found = false
	for i = 1, table.getn(UISpecialFrames) do
		if UISpecialFrames[i] == "HyoukaUI_Character" then
			found = true
		end
	end
	if not found then
		table.insert(UISpecialFrames, "HyoukaUI_Character")
	end
	f:Hide()
	Place()
	return f
end

function C.Ensure()
	if not S.frame then
		MakeFrame()
	end
	return S.frame
end

function C.Frame()
	return S.frame
end

----------------------------------------------------------------------------------------
-- Обновление содержимого
----------------------------------------------------------------------------------------

local function UpdateSlot(slot)
	local link = GetInventoryItemLink("player", slot.id)
	local tex = GetInventoryItemTexture("player", slot.id)
	local icon = slot.icon
	if link then
		icon:SetAlpha(1)
		H.Icon.SetTexture(icon, tex)
		local r, g, b, q = B.Jewelry.LinkColor(link)
		if q > 1 then
			H.Icon.SetBorderColor(icon, r, g, b, 1)
		else
			local c = T.C.border
			H.Icon.SetBorderColor(icon, c[1], c[2], c[3], c[4])
		end
	else
		icon:SetAlpha(0.35)
		H.Icon.SetTexture(icon, nil)
	end
end

function C.UpdateGear()
	for i = 1, table.getn(S.slots) do
		UpdateSlot(S.slots[i])
	end
end

function C.UpdateAbilities()
	S.abilTitle:SetText(B.T("char_build"))
	local n = H.Spells.Count()
	for i = 1, 7 do
		local icon = S.abil[i]
		if i <= n then
			icon.slot = H.Spells.SlotOf(i)
			H.Icon.SetTexture(icon, H.Spells.Icon(i))
			icon:Show()
		else
			icon.slot = nil
			icon:Hide()
		end
	end
end

function C.UpdateHero()
	if not S.frame then
		return
	end
	S.title:SetText(B.T("char_title"))
	local name = H.Hero.Name()
	local text = name or B.T("char_hero")
	local cname = H.Hero.ClassName()
	if cname then
		text = text.."  "..cname
	end
	local lvl = H.Run.Level()
	if lvl then
		text = text.."  "..B.T("char_level").." "..Fm.Int(lvl)
	end
	local r, g, b = H.Hero.ClassColor()
	S.hero:SetTextColor(r, g, b, 1)
	S.hero:SetText(text)
end

-- Строка забега: уровень, убийства, золото (по смене значений) и время (отдельная строка, раз в секунду).
local function UpdateRun()
	local t = H.Run.Time()
	local key = t and math.floor(t) or -1
	if S.timeKey ~= key then
		S.timeKey = key
		S.runTime:SetText(Fm.Time(t or 0))
	end
	local kills, gold, lvl = H.Run.Get("kills") or 0, H.Run.Get("gold") or 0, H.Run.Level() or 0
	if S.runKills == kills and S.runGold == gold and S.runLvl == lvl and S.runLoc == H.Locale.code then
		return
	end
	S.runKills, S.runGold, S.runLvl, S.runLoc = kills, gold, lvl, H.Locale.code
	S.run:SetText(B.T("char_level")..": "..Fm.Int(lvl).."   "..B.T("char_kills")..": "..Fm.Short(kills).."   "..B.T("char_gold")..": "
		..Fm.Short(gold).."   "..B.T("char_time")..":")
end

local STAT_KEYS = {}
for sec = 1, table.getn(X.SECTIONS) do
	for i = 1, table.getn(X.SECTIONS[sec].rows) do
		table.insert(STAT_KEYS, X.SECTIONS[sec].rows[i])
	end
end

-- Значения изменились с прошлого раза? Без таблиц.
local function StatsChanged()
	local changed = false
	local has = X.HasData()
	if has ~= S.lastHas then
		S.lastHas = has
		changed = true
	end
	for i = 1, table.getn(STAT_KEYS) do
		local key = STAT_KEYS[i]
		local v = X.Value(key)
		if S.last[key] ~= v then
			S.last[key] = v
			changed = true
		end
	end
	return changed
end

function C.UpdateStats(force)
	local changed = StatsChanged()
	if changed or force then
		C.RebuildItems()
		S.headline:SetText(X.HasData() and X.Headline() or "-")
		local hp = X.Value("hp")
		S.caption:SetText(B.T("char_headline")..string.format(" %s %s: %d", H.Fonts.SYM.dot, B.T("char_health"), hp))
	end
end

function C.Tick()
	if not S.frame or not S.frame:IsShown() then
		return
	end
	C.UpdateStats(false)
	UpdateRun()
end

function C.RefreshAll()
	C.UpdateHero()
	C.UpdateGear()
	C.UpdateAbilities()
	C.UpdateStats(true)
	S.timeKey, S.runKills = nil, nil
	UpdateRun()
end

----------------------------------------------------------------------------------------
-- Открытие и закрытие
----------------------------------------------------------------------------------------

function C.Open()
	if not Settings().charWindow then
		return false
	end
	C.Ensure()
	if not S.registered then
		S.registered = true
		H.Vis.Register(S.frame, { id = "character" })
	end
	if H.Vis.IsChoosing() then
		return false
	end
	Place()
	S.frame:Show()
	C.RefreshAll()
	return true
end

function C.Close()
	if S.frame and S.frame:IsShown() then
		S.frame:Hide()
	end
end

function C.IsOpen()
	return S.frame ~= nil and S.frame:IsShown()
end

function C.Toggle()
	if C.IsOpen() then
		C.Close()
		return true
	end
	return C.Open()
end

-- Публичное для модуля.
function B.ToggleCharacter()
	return C.Toggle()
end

function B.OpenCharacter()
	return C.Open()
end

function B.CloseCharacter()
	C.Close()
end

----------------------------------------------------------------------------------------
-- Подключение к модулю
----------------------------------------------------------------------------------------

local function Relayout()
	if not S.frame then
		return
	end
	H.Panel.Size(S.frame, W, HGT)
	S.drag:SetHeight(H.R(TITLE))
	for i = 1, table.getn(S.slots) do
		At(S.slots[i].icon, S.slots[i].x, S.slots[i].y)
	end
	if S.frame:IsShown() then
		C.RefreshAll()
	end
end

local function OnInventory(ev, unit)
	if S.frame and S.frame:IsShown() and (unit == nil or unit == "player") then
		C.UpdateGear()
	end
end

local function OnLoadout()
	if S.frame and S.frame:IsShown() then
		C.UpdateAbilities()
		C.UpdateStats(true)
	end
end

local function OnSetting(ev, mod, key)
	if mod ~= "build" or not S.frame then
		return
	end
	if key == "charWindow" and not Settings().charWindow then
		C.Close()
	elseif key == "hideZero" and S.frame:IsShown() then
		C.UpdateStats(true)
	end
end

B.AddPart("character", function(M)
	B.Listen("SETTING", OnSetting)
	B.Listen("THEME", Relayout)
	B.Listen("FONTS", Relayout)
	B.Listen("LOCALE", Relayout)
	B.Listen("UNIT_INVENTORY_CHANGED", OnInventory)
	B.Listen("LOADOUT_CHANGED", OnLoadout)
	B.Listen("SPELLS_CHANGED", OnLoadout)
	B.Listen("HERO_CHANGED", C.UpdateHero)
	B.Listen("PHASE_CHANGED", function()
		if S.frame and S.frame:IsShown() then
			C.UpdateHero()
		end
	end)
	M:Every(0.3, C.Tick)
end, function()
	if S.frame then
		S.frame:Hide()
		if S.registered then
			S.registered = false
			H.Vis.Unregister(S.frame)
		end
	end
end)
