-- HyoukaUI: Modules\Meter\Menu.lua, меню страницы по клику на шапку места (вместо ряда пилюль SurvivorUI).
--
-- Общий выпадающий список Options\Controls (C.Popup) открывается ПОД кадром, а док стоит у нижнего края экрана,
-- поэтому меню дока свое: плоский список поверх всего, открывается вверх от шапки (вниз, если сверху не хватает места),
-- ловец кликов на весь экран закрывает меню по любому клику мимо. Клавиатуру меню не захватывает (Esc не нужен).
--
-- Menu.Open(anchor, options, current, onPick): options = { { value, label } }, current = выбранное значение.
-- Menu.Close(), Menu.IsOpen(), Menu.Button(i) (для тестов).

local H = HyoukaUI
local MU = H.MeterUI
local K = H.Kit

local getn = table.getn

local Me = {}
MU.Menu = Me

local S = { built = false, catcher = nil, list = nil, buttons = {} }

local ROW_H = 14   -- ретейл-px

local function Build()
	if S.built then
		return
	end
	S.built = true
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	catcher:Hide()
	local list = CreateFrame("Frame", nil, UIParent)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:EnableMouse(true)
	K.Fill(list, "bg", "BACKGROUND")
	list.border = K.Border(list, "edge")
	list:Hide()
	S.catcher, S.list = catcher, list
	H.Script(MU.OWNER, catcher, "OnClick", function()
		Me.Close()
	end)
end

function Me.IsOpen()
	return S.built and S.list:IsShown() and true or false
end

function Me.Close()
	if S.built then
		S.catcher:Hide()
		S.list:Hide()
	end
end

function Me.Button(i)
	return S.buttons[i]
end

-- Вверх от шапки, если над ней есть место; иначе вниз.
local function Place(anchor, height)
	local list = S.list
	list:ClearAllPoints()
	local top = anchor:GetTop()
	local _, screenH = H.Layout.Screen()
	if top and top + height > screenH then
		list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -H.R(1))
	else
		list:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, H.R(1))
	end
end

function Me.Open(anchor, options, current, onPick)
	Build()
	local w = anchor:GetWidth() or H.R(212)
	local rowH = H.R(ROW_H)
	local n = getn(options)
	S.list:SetWidth(w)
	S.list:SetHeight(n * rowH + H.R(2))
	Place(anchor, n * rowH + H.R(2))
	for i = 1, n do
		local b = S.buttons[i]
		if not b then
			b = K.Button(S.list, "", w - H.R(2), rowH, nil, MU.OWNER)
			S.buttons[i] = b
		end
		local opt = options[i]
		b:SetWidth(w - H.R(2))
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", S.list, "TOPLEFT", H.R(1), -(H.R(1) + (i - 1) * rowH))
		b:SetLabel(opt.label)
		b.label:ClearAllPoints()
		b.label:SetPoint("LEFT", b, "LEFT", H.R(5), 0)
		b.label:SetJustifyH("LEFT")
		K.TextColor(b.label, opt.value == current and "accent" or "text")
		H.Script(MU.OWNER, b, "OnClick", function()
			Me.Close()
			onPick(opt.value)
		end)
		b:Show()
	end
	for i = n + 1, getn(S.buttons) do
		S.buttons[i]:Hide()
	end
	S.catcher:Show()
	S.list:Show()
end
