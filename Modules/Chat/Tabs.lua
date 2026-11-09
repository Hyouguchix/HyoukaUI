-- HyoukaUI: Chat\Tabs, ряд вкладок и выбор окна (spec 3.8).
--
-- Ряд высотой 22 ретейл-px сверху панели, без фона: текст 14 outline, неактивные #7C7C7C, активная белая, под активной
-- линия акцента. Модель вкладок собирается из двух источников:
--   Вместо: пристыкованные стоковые окна по порядку (General первым; Combat Log только при showCombat) плюс ленты
--           "Добыча и система" и "Группа" (опции tabLoot, tabParty);
--   Рядом:  только ленты (General как копия потока, затем те же две).
-- Клик выбирает вкладку: стоковое окно выбирается как это делает игра (FCF_SelectDockFrame, SELECTED_CHAT_FRAME), лента
-- показывается, остальные прячутся; правый клик по стоковой вкладке открывает стоковое меню окна. Точка рядом с названием:
-- в невыбранное окно или ленту пришла строка (Note* зовет обертка AddMessage). Названия стоковых окон читаются раз в
-- секунду (окно переименовали из его меню). Ширина строки до первой отрисовки может быть 0, поэтому после сборки
-- раскладка повторяется несколько кадров (SETTLE).

local H = HyoukaUI
local C = H.Chat

local getn = table.getn

local T = {}
C.Tabs = T

local SETTLE = 3
local PADX = 7          -- ретейл-px слева и справа от названия
local GAP = 2           -- зазор между вкладками
local START = 5         -- первая вкладка от левого края панели
local LINE = 2          -- толщина линии под активной

local model = {}        -- { key, kind = "stock" | "feed", window, label, unread }
local btns = {}
local sel = 1
local underline
local docked = {}
local active = {}
local placed = {}       -- стоковые окна, поставленные на текст панели этим файлом
local settle = 0

local function R(px)
	return H.R(px)
end

function T.Count()
	return getn(model)
end

function T.Model()
	return model
end

function T.SelectedKey()
	local e = model[sel]
	return e and e.key or nil
end

function T.Button(i)
	return btns[i]
end

local function IndexOfKey(key)
	for i = 1, getn(model) do
		if model[i].key == key then
			return i
		end
	end
	return nil
end

local function IndexOfWindow(w)
	for i = 1, getn(model) do
		if model[i].window == w then
			return i
		end
	end
	return nil
end

----------------------------------------------------------------------------------------
-- Покраска
----------------------------------------------------------------------------------------

local function PaintOne(i)
	local b = btns[i]
	local e = model[i]
	if not b or not e then
		return
	end
	local on = (i == sel)
	if on then
		H.Text.SetColor(b.text, "text")
	elseif b.hover or e.unread then
		H.Text.SetColor(b.text, "text")
	else
		H.Text.SetColor(b.text, "dim")
	end
	if e.unread and not on then
		local r, g, bl = H.Theme.AccentRGB()
		b.dot:SetVertexColor(r, g, bl, 1)
		b.dot:Show()
	else
		b.dot:Hide()
	end
end

local function PaintUnderline()
	local b = btns[sel]
	if not b or not model[sel] or not underline then
		if underline then
			underline:Hide()
		end
		return
	end
	local r, g, bl = H.Theme.AccentRGB()
	underline:SetVertexColor(r, g, bl, 1)
	underline:ClearAllPoints()
	underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", R(PADX), 0)
	underline:SetWidth(b.text:GetStringWidth() or 0)
	underline:SetHeight(R(LINE))
	underline:Show()
end

function T.Paint()
	for i = 1, getn(model) do
		PaintOne(i)
	end
	PaintUnderline()
end

----------------------------------------------------------------------------------------
-- Кнопки
----------------------------------------------------------------------------------------

local function OnClick(self, button)
	local i = self.index
	local e = model[i]
	if not e then
		return
	end
	C.Fade.Touch()
	if button == "RightButton" then
		if e.kind == "stock" then
			C.Stock.Menu(e.window)
		end
		return
	end
	T.Select(i)
end

local function NewButton(i)
	local b = CreateFrame("Button", nil, C.Panel.frame)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.index = i
	b.text = H.Text.New(b, "title", { color = "dim" })
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.dot = b:CreateTexture(nil, "OVERLAY")
	b.dot:SetTexture(H.Theme.TEX.solid)
	b.dot:Hide()
	H.Script(C.M.name, b, "OnClick", OnClick)
	H.Script(C.M.name, b, "OnEnter", function(self)
		self.hover = true
		PaintOne(self.index)
	end)
	H.Script(C.M.name, b, "OnLeave", function(self)
		self.hover = nil
		PaintOne(self.index)
	end)
	btns[i] = b
	return b
end

-- Раскладка ряда: ширина кнопки по тексту, зазор, линия под активной.
function T.Layout()
	local f = C.Panel.frame
	if not f then
		return
	end
	local x = START
	for i = 1, getn(model) do
		local b = btns[i] or NewButton(i)
		local e = model[i]
		b.text:SetText(e.label)
		local w = (b.text:GetStringWidth() or 0) + 2 * R(PADX)
		b:SetWidth(w)
		b:SetHeight(R(C.Panel.TAB_H))
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", R(x), 0)
		b.dot:SetWidth(R(4))
		b.dot:SetHeight(R(4))
		b.dot:ClearAllPoints()
		b.dot:SetPoint("LEFT", b.text, "RIGHT", R(2), R(4))
		b:Show()
		x = x + (w / H.Kit.PX()) + GAP
	end
	for i = getn(model) + 1, getn(btns) do
		btns[i]:Hide()
	end
	T.Paint()
end

----------------------------------------------------------------------------------------
-- Выбор
----------------------------------------------------------------------------------------

local function ShowSelected()
	local e = model[sel]
	if not e then
		return
	end
	local replace = (C.mode == "replace")
	if e.kind == "stock" then
		for i = 1, getn(C.Feeds.FEEDS) do
			local fr = C.Feeds.FEEDS[i].frame
			if fr and fr:IsShown() then
				fr:Hide()
			end
		end
		if replace then
			C.Stock.Select(e.window)
			if not e.window:IsShown() then
				e.window:Show()
			end
		end
	else
		if replace then
			C.Stock.HideDocked()
		end
		for i = 1, getn(C.Feeds.FEEDS) do
			local feed = C.Feeds.FEEDS[i]
			if feed.frame then
				if feed.key == e.key then
					if not feed.frame:IsShown() then
						feed.frame:Show()
					end
				elseif feed.frame:IsShown() then
					feed.frame:Hide()
				end
			end
		end
	end
end

function T.Select(i)
	if not model[i] then
		return false
	end
	sel = i
	model[i].unread = false
	ShowSelected()
	T.Paint()
	return true
end

function T.SelectKey(key)
	local i = IndexOfKey(key)
	if i then
		return T.Select(i)
	end
	return false
end

-- В ленту key пришла строка.
function T.NoteFeed(key)
	local i = IndexOfKey(key)
	if i and i ~= sel and not model[i].unread then
		model[i].unread = true
		PaintOne(i)
	end
end

-- В стоковое окно пришла строка.
function T.NoteWindow(w)
	local i = IndexOfWindow(w)
	if i and i ~= sel and not model[i].unread then
		model[i].unread = true
		PaintOne(i)
	end
end

----------------------------------------------------------------------------------------
-- Сборка модели
----------------------------------------------------------------------------------------

local function WindowLabel(w)
	local name = C.Stock.NameOf(w)
	if name == "" then
		if w == C.Stock.General() then
			return C.T("tab_general")
		end
		return tostring(C.Stock.IdOf(w) or "?")
	end
	return name
end

local function InList(list, v)
	for i = 1, getn(list) do
		if list[i] == v then
			return true
		end
	end
	return false
end

function T.Rebuild()
	local keep = model[sel] and model[sel].key
	local old = model
	model = {}
	local replace = (C.mode == "replace")
	if replace then
		C.Stock.Docked(docked)
		local combat = C.Stock.Window(2)
		for i = 1, getn(docked) do
			local w = docked[i]
			C.Panel.AddText(w, true)
			if not (w == combat and not C.Opt("showCombat")) then
				table.insert(model, { key = "w"..tostring(C.Stock.IdOf(w) or i), kind = "stock", window = w, label = WindowLabel(w) })
			end
		end
		for i = getn(placed), 1, -1 do
			if not InList(docked, placed[i]) then
				C.Panel.RemoveText(placed[i])
				table.remove(placed, i)
			end
		end
		H.Wipe(placed)
		for i = 1, getn(docked) do
			table.insert(placed, docked[i])
		end
	end
	C.Feeds.Active(active)
	for i = 1, getn(active) do
		table.insert(model, { key = active[i], kind = "feed", label = C.Feeds.Label(active[i]) })
	end
	for i = 1, getn(old) do
		local e = old[i]
		for j = 1, getn(model) do
			if model[j].key == e.key then
				model[j].unread = e.unread
			end
		end
	end
	sel = (keep and IndexOfKey(keep)) or 1
	if model[sel] then
		model[sel].unread = false
	end
	T.Layout()
	ShowSelected()
	settle = SETTLE
end

function T.Enable(mode)
	if not underline then
		underline = C.Panel.frame:CreateTexture(nil, "ARTWORK")
		underline:SetTexture(H.Theme.TEX.solid)
	end
	T.Rebuild()
end

function T.Disable()
	local was = model[sel]
	for i = 1, getn(btns) do
		btns[i]:Hide()
	end
	if underline then
		underline:Hide()
	end
	if was and was.kind == "feed" and C.mode == "replace" then
		-- стоковое окно, которое мы спрятали ради ленты, возвращается как выбранное в игре
		local w = C.Stock.Selected()
		if w then
			C.Stock.Select(w)
			if not w:IsShown() then
				w:Show()
			end
		end
	end
	for i = getn(placed), 1, -1 do
		C.Panel.RemoveText(placed[i])
	end
	H.Wipe(placed)
	model = {}
	sel = 1
end

function T.Refresh()
	T.Rebuild()
end

-- Названия окон, выбор окна игрой и спрятанное ради ленты окно: раз в секунду.
function T.Verify()
	if C.mode ~= "replace" then
		return
	end
	local e = model[sel]
	if not e then
		return
	end
	-- состав пристыкованных окон изменился без события: пересборка
	C.Stock.Docked(docked)
	local same = (getn(docked) == getn(placed))
	for i = 1, getn(docked) do
		if not InList(placed, docked[i]) then
			same = false
		end
	end
	if not same then
		T.Rebuild()
		return
	end
	local changed = false
	for i = 1, getn(model) do
		local m = model[i]
		if m.kind == "stock" then
			local label = WindowLabel(m.window)
			if label ~= m.label then
				m.label = label
				changed = true
			end
		end
	end
	if changed then
		T.Layout()
	end
	if e.kind == "stock" then
		local cur = C.Stock.Selected()
		if cur and cur ~= e.window then
			local i = IndexOfWindow(cur)
			if i then
				sel = i
				model[i].unread = false
				ShowSelected()
				T.Paint()
			end
		end
	else
		C.Stock.HideDocked()
	end
end

--@frame
function T.Tick()
	if settle > 0 then
		settle = settle - 1
		if settle == 0 then
			T.Layout()
		end
	end
end
