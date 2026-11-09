-- HyoukaUI: элементы окна настроек (plan 5). Плоский стиль: #0E0E0E 0.90, рамка 1 px, наведение
-- #D9D9D9 0.15 мгновенно, акцент на выбранном. Каждый элемент читает и пишет через H.DB.Get/Set
-- (spec = { mod, key }) или через свои get/set (режим модуля, демо, перемещение).
--
-- local f = H.Controls.Flow(page, width)   поток элементов сверху вниз
--   f:Header(text)  f:Note(text)  f:Gap(n)
--   f:Toggle{ label, hint, mod, key | get, set, onChange }
--   f:Slider{ label, mod, key, min, max, step, fmt(v) }
--   f:Dropdown{ label, mod, key, options = { { value, label } ... } }
--   f:Swatches{ label, mod, key, options = { { value, color = { r, g, b } } ... } }
--   f:Segment{ label, hint, options = { { value, label } ... }, get, set, bw }
--   f:Button{ label, onClick, width } -> кнопка
--   f:Refresh()   перечитать значения всех элементов (без записи)
-- Размеры в AS. Высоты подсказок считаются по ширине строки (у FontString нет GetStringHeight).

local H = HyoukaUI
local K = H.Kit

local getn = table.getn

local C = {}
H.Controls = C

C.ROW = 16
C.COL = 140      -- x правой колонки элементов
C.OWNER = "options"

local FLOW = {}
local FLOW_META = { __index = FLOW }

local function Get(spec)
	if spec.get then
		return spec.get()
	end
	return H.DB.Get(spec.mod, spec.key)
end

local function Put(spec, value)
	if spec.set then
		spec.set(value)
	else
		H.DB.Set(spec.mod, spec.key, value)
	end
	if spec.onChange then
		spec.onChange(value)
	end
end
C.Get, C.Put = Get, Put

local function Lines(fs, width)
	local w = fs:GetStringWidth() or 0
	if w <= 0 or width <= 0 then
		return 1
	end
	return math.max(1, math.ceil(w / width))
end

-- Подсветка наведения для кадра без своей (K.Button уже имеет).
local function Hoverable(frame)
	local hover = frame:CreateTexture(nil, "ARTWORK")
	hover:SetTexture(K.FLAT)
	hover:SetAllPoints(frame)
	K.Paint(hover, "hover")
	hover:Hide()
	H.Script(C.OWNER, frame, "OnEnter", function()
		hover:Show()
	end)
	H.Script(C.OWNER, frame, "OnLeave", function()
		hover:Hide()
	end)
end

function C.Flow(page, width)
	return setmetatable({ page = page, width = width or 280, y = 0, items = {}, busy = false }, FLOW_META)
end

function FLOW:Gap(n)
	self.y = self.y + (n or 6)
end

function FLOW:Header(text)
	local fs = K.Text(self.page, "normal")
	fs:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, -self.y)
	fs:SetText(text)
	K.TextColor(fs, "accent")
	table.insert(self.items, function()
		K.TextColor(fs, "accent")
	end)
	self.y = self.y + 14
	return fs
end

function FLOW:Note(text, token)
	local fs = K.Text(self.page, "small")
	fs:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, -self.y)
	fs:SetWidth(self.width)
	fs:SetText(text)
	K.TextColor(fs, token or "note")
	self.y = self.y + Lines(fs, self.width) * 9 + 4
	return fs
end

local function RowLabel(self, text, hint)
	local fs = K.Text(self.page, "normal")
	fs:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, -(self.y + 2))
	fs:SetText(text or "")
	return fs
end

-- Подсказка под строкой: увеличивает y.
local function RowHint(self, hint, indent)
	if not hint then
		return
	end
	local w = self.width - (indent or 0)
	local fs = K.Text(self.page, "small")
	fs:SetPoint("TOPLEFT", self.page, "TOPLEFT", indent or 0, -self.y)
	fs:SetWidth(w)
	fs:SetText(hint)
	K.TextColor(fs, "note")
	self.y = self.y + Lines(fs, w) * 9 + 2
end

function FLOW:Refresh()
	self.busy = true
	for i = 1, getn(self.items) do
		self.items[i]()
	end
	self.busy = false
end

----------------------------------------------------------------------------------------
-- Переключатель
----------------------------------------------------------------------------------------

function FLOW:Toggle(spec)
	local page, flow = self.page, self
	local box = CreateFrame("Button", nil, page)
	box:SetWidth(10)
	box:SetHeight(10)
	box:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(self.y + 2))
	K.Fill(box, "inner", "BACKGROUND")
	box.border = K.Border(box, "edge")
	local tick = box:CreateTexture(nil, "ARTWORK")
	tick:SetTexture(K.FLAT)
	tick:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
	tick:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
	K.Paint(tick, "accent")
	Hoverable(box)
	local name = K.Text(page, "normal")
	name:SetPoint("LEFT", box, "RIGHT", 6, 0)
	name:SetText(spec.label or "")
	H.Script(C.OWNER, box, "OnClick", function()
		Put(spec, not Get(spec))
		flow:Refresh()
	end)
	local function Paint()
		K.Paint(tick, "accent")
		if Get(spec) then
			tick:Show()
		else
			tick:Hide()
		end
	end
	table.insert(self.items, Paint)
	Paint()
	self.y = self.y + C.ROW
	RowHint(self, spec.hint, 16)
	box.refresh = Paint
	box.tick = tick
	return box
end

----------------------------------------------------------------------------------------
-- Ползунок
----------------------------------------------------------------------------------------

function FLOW:Slider(spec)
	local page, flow = self.page, self
	RowLabel(self, spec.label)
	local s = CreateFrame("Slider", nil, page)
	s:SetOrientation("HORIZONTAL")
	s:SetWidth(110)
	s:SetHeight(8)
	s:SetPoint("TOPLEFT", page, "TOPLEFT", C.COL, -(self.y + 3))
	K.Fill(s, "inner", "BACKGROUND")
	s.border = K.Border(s, "edge")
	s:SetMinMaxValues(spec.min, spec.max)
	s:SetValueStep(spec.step or 1)
	s:SetThumbTexture(K.FLAT)
	local th = s.GetThumbTexture and s:GetThumbTexture()
	if th then
		th:SetWidth(K.R(6))
		th:SetHeight(K.R(14))
		K.Paint(th, "accent")
	end
	local value = K.Text(page, "normal")
	value:SetPoint("LEFT", s, "RIGHT", 6, 0)
	local function Show(v)
		if spec.fmt then
			value:SetText(spec.fmt(v))
		else
			value:SetText(string.format("%.2f", v))
		end
	end
	local step = spec.step or 1
	H.Script(C.OWNER, s, "OnValueChanged", function(self2, v)
		if flow.busy or s.busy or v == nil then
			return
		end
		v = math.floor(v / step + 0.5) * step
		Show(v)
		Put(spec, v)
	end)
	local function Paint()
		local v = Get(spec) or spec.min
		if th then
			K.Paint(th, "accent")
		end
		s.busy = true
		s:SetValue(v)
		s.busy = false
		Show(v)
	end
	table.insert(self.items, Paint)
	Paint()
	self.y = self.y + C.ROW
	s.refresh = Paint
	s.valueText = value
	return s
end

----------------------------------------------------------------------------------------
-- Выпадающий список: один общий всплывающий список на все элементы
----------------------------------------------------------------------------------------

local popup

local function BuildPopup()
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:EnableMouse(true)
	catcher:Hide()
	local list = CreateFrame("Frame", nil, UIParent)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:EnableMouse(true)
	K.Fill(list, "bg", "BACKGROUND")
	list.border = K.Border(list, "edge")
	list:Hide()
	popup = { catcher = catcher, list = list, buttons = {} }
	H.Script(C.OWNER, catcher, "OnClick", function()
		C.ClosePopup()
	end)
end

function C.ClosePopup()
	if popup then
		popup.catcher:Hide()
		popup.list:Hide()
	end
end

-- Для тестов: i-я кнопка всплывающего списка.
function C.PopupButton(i)
	return popup and popup.buttons[i]
end

function C.IsPopupOpen()
	return popup ~= nil and popup.list:IsShown() and true or false
end

-- Показать список под кадром anchor. options = { { value, label } }, current = значение.
function C.Popup(anchor, options, current, onPick)
	if not popup then
		BuildPopup()
	end
	local w, rowH = anchor:GetWidth() or 110, 14
	local n = getn(options)
	popup.list:ClearAllPoints()
	popup.list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -K.PX())
	popup.list:SetWidth(w)
	popup.list:SetHeight(n * rowH + 2)
	for i = 1, n do
		local b = popup.buttons[i]
		if not b then
			b = K.Button(popup.list, "", w - 2, rowH, nil, C.OWNER)
			popup.buttons[i] = b
		end
		local opt = options[i]
		b:SetWidth(w - 2)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", popup.list, "TOPLEFT", 1, -(1 + (i - 1) * rowH))
		b:SetLabel(opt.label)
		K.TextColor(b.label, opt.value == current and "accent" or "text")
		H.Script(C.OWNER, b, "OnClick", function()
			C.ClosePopup()
			onPick(opt.value)
		end)
		b:Show()
	end
	for i = n + 1, getn(popup.buttons) do
		popup.buttons[i]:Hide()
	end
	popup.catcher:Show()
	popup.list:Show()
end

local function LabelOf(options, value)
	for i = 1, getn(options) do
		if options[i].value == value then
			return options[i].label
		end
	end
	return tostring(value)
end

function FLOW:Dropdown(spec)
	local page, flow = self.page, self
	RowLabel(self, spec.label)
	local btn = K.Button(page, "", 110, 12, nil, C.OWNER)
	btn:SetPoint("TOPLEFT", page, "TOPLEFT", C.COL, -(self.y + 2))
	H.Script(C.OWNER, btn, "OnClick", function()
		if C.IsPopupOpen() then
			C.ClosePopup()
			return
		end
		C.Popup(btn, spec.options, Get(spec), function(v)
			Put(spec, v)
			flow:Refresh()
		end)
	end)
	local function Paint()
		btn:SetLabel(LabelOf(spec.options, Get(spec)))
	end
	table.insert(self.items, Paint)
	Paint()
	self.y = self.y + C.ROW
	btn.refresh = Paint
	return btn
end

----------------------------------------------------------------------------------------
-- Ряд цветов
----------------------------------------------------------------------------------------

function FLOW:Swatches(spec)
	local page, flow = self.page, self
	RowLabel(self, spec.label)
	local size, gap = 12, 4
	local list = {}
	for i = 1, getn(spec.options) do
		local opt = spec.options[i]
		local sw = CreateFrame("Button", nil, page)
		sw:SetWidth(size)
		sw:SetHeight(size)
		sw:SetPoint("TOPLEFT", page, "TOPLEFT", C.COL + (i - 1) * (size + gap), -(self.y + 2))
		sw.fill = sw:CreateTexture(nil, "ARTWORK")
		sw.fill:SetTexture(K.FLAT)
		sw.fill:SetPoint("TOPLEFT", sw, "TOPLEFT", 2, -2)
		sw.fill:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -2, 2)
		local c = opt.color
		if type(c) == "function" then
			c = { c() }
		end
		c = c or { 1, 1, 1 }
		sw.fill:SetVertexColor(c[1], c[2], c[3], 1)
		sw.border = K.Border(sw, "edge")
		sw.value = opt.value
		H.Script(C.OWNER, sw, "OnClick", function()
			Put(spec, opt.value)
			flow:Refresh()
		end)
		list[i] = sw
	end
	local function Paint()
		local cur = Get(spec)
		for i = 1, getn(list) do
			list[i].border:SetColor(list[i].value == cur and "white" or "edge")
		end
	end
	table.insert(self.items, Paint)
	Paint()
	self.y = self.y + C.ROW + 2
	return list
end

----------------------------------------------------------------------------------------
-- Выбор из нескольких кнопок в ряд (режим модуля Выкл / Рядом / Вместо)
----------------------------------------------------------------------------------------

function FLOW:Segment(spec)
	local page, flow = self.page, self
	RowLabel(self, spec.label)
	local bw = spec.bw or 44
	local list = {}
	for i = 1, getn(spec.options) do
		local opt = spec.options[i]
		local b = K.Button(page, opt.label, bw, 12, function()
			Put(spec, opt.value)
			flow:Refresh()
		end, C.OWNER)
		b:SetPoint("TOPLEFT", page, "TOPLEFT", C.COL + (i - 1) * (bw + 2), -(self.y + 2))
		b.value = opt.value
		list[i] = b
	end
	local function Paint()
		local cur = Get(spec)
		for i = 1, getn(list) do
			local on = (list[i].value == cur)
			K.Paint(list[i].fill, on and "accentSel" or "inner")
			K.TextColor(list[i].label, on and "accent" or "text")
		end
	end
	table.insert(self.items, Paint)
	Paint()
	self.y = self.y + C.ROW
	RowHint(self, spec.hint, 0)
	return list
end

function FLOW:Button(spec)
	local b = K.Button(self.page, spec.label, spec.width or 150, 14, spec.onClick, C.OWNER)
	b:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, -self.y)
	self.y = self.y + 18
	return b
end

function FLOW:Height()
	return self.y
end
