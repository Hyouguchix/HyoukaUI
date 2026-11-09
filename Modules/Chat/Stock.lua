-- HyoukaUI: Chat\Stock, переходник к стоковым кадрам чата и их переодевание в режиме Вместо.
--
-- Все стоковые имена читаются через H.Env (getglobal в модулях запрещен): ChatFrame1..N (окна, ScrollingMessageFrame),
-- ChatFrameNTab, ChatFrameNUpButton / DownButton / BottomButton, ChatFrameNResize<край>, ChatFrameNBackground и другие
-- куски арта из CHAT_FRAME_TEXTURES, ChatFrameEditBox, ChatFrameMenuButton, функции FCF_*, списки DOCKED_CHAT_FRAMES,
-- SELECTED_CHAT_FRAME, SELECTED_DOCK_FRAME. Факты SurvivorUI (Chat.lua, SurvivorUI.lua StyleChat), проверенные в игре.
--
-- Режим Вместо (S.Enable("replace")) делает с каждым окном и возвращает в S.Disable():
--   арт окна (SetTexture("") с запоминанием файла), края размера (EnableMouse(false)), стоковые вкладки, кнопки
--   прокрутки и кнопка меню (H.Park: скрытый родитель, возврат по Unpark), колесо (свой скрипт, старый запомнен),
--   шрифт (Expressway, размер роли title), затухание стока (SetFading(false)), положение ChatFrame1 (две точки на текст
--   панели, старые точки запомнены, FCF_DockUpdate после возврата).
-- В режиме Рядом стоковые кадры не трогаются совсем.

local H = HyoukaUI
local C = H.Chat

local getn = table.getn

local S = {}
C.Stock = S

local OWNER = "chat"

local DEFAULT_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local EDGES = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right" }
local BUTTONS = { "UpButton", "DownButton", "BottomButton" }

S.dressed = false
S.wins = {}          -- список окон, отобранных при последней сборке
S.saved = {}         -- окно -> запись переодевания
S.placed = {}        -- окно -> запомненное положение

local names = {}     -- i -> { win, tab, buttons = {}, edges = {}, art = {} }

local function Names(i)
	local n = names[i]
	if not n then
		local w = "ChatFrame"..i
		n = { win = w, tab = w.."Tab", buttons = {}, edges = {}, art = {} }
		for k = 1, getn(BUTTONS) do
			n.buttons[k] = w..BUTTONS[k]
		end
		for k = 1, getn(EDGES) do
			n.edges[k] = w.."Resize"..EDGES[k]
		end
		local list = H.Env.CHAT_FRAME_TEXTURES
		if type(list) ~= "table" or getn(list) == 0 then
			list = DEFAULT_ART
		end
		for k = 1, getn(list) do
			n.art[k] = w..list[k]
		end
		names[i] = n
	end
	return n
end

----------------------------------------------------------------------------------------
-- Доступ к стоковым кадрам
----------------------------------------------------------------------------------------

function S.Count()
	local n = H.Env.NUM_CHAT_WINDOWS
	if type(n) == "number" and n >= 1 then
		return n
	end
	return 7
end

function S.Window(i)
	local f = H.Env[Names(i).win]
	if type(f) == "table" and f.AddMessage then
		return f
	end
	return nil
end

function S.General()
	return S.Window(1) or H.Env.DEFAULT_CHAT_FRAME
end

function S.Edit()
	return H.Env.ChatFrameEditBox
end

function S.TypeInfo()
	local t = H.Env.ChatTypeInfo
	if type(t) == "table" then
		return t
	end
	return nil
end

-- Окна, которые есть в клиенте: заполняет out, возвращает число.
function S.Windows(out)
	H.Wipe(out)
	for i = 1, S.Count() do
		local w = S.Window(i)
		if w then
			table.insert(out, w)
		end
	end
	return getn(out)
end

-- Пристыкованные окна по порядку вкладок (без пристыкованных в 1.12 - одно General).
function S.Docked(out)
	H.Wipe(out)
	local d = H.Env.DOCKED_CHAT_FRAMES
	if type(d) == "table" and getn(d) > 0 then
		for i = 1, getn(d) do
			table.insert(out, d[i])
		end
	else
		local g = S.General()
		if g then
			table.insert(out, g)
		end
	end
	return getn(out)
end

function S.Selected()
	return H.Env.SELECTED_DOCK_FRAME or H.Env.DEFAULT_CHAT_FRAME or S.Window(1)
end

function S.IdOf(window)
	if window and window.GetID then
		return window:GetID()
	end
	return nil
end

-- Имя окна, как его знает игра ("" если неизвестно).
function S.NameOf(window)
	local fn = H.Env.GetChatWindowInfo
	local id = S.IdOf(window)
	if type(fn) == "function" and id then
		local ok, name = pcall(fn, id)
		if ok and type(name) == "string" then
			return name
		end
	end
	return ""
end

-- Выбрать пристыкованное окно как это делает игра (показывает его, прячет остальные).
function S.Select(window)
	H.Env.SELECTED_CHAT_FRAME = window
	local fn = H.Env.FCF_SelectDockFrame
	if window.isDocked and type(fn) == "function" then
		pcall(fn, window)
	end
end

-- Спрятать все пристыкованные окна (выбрана вкладка-лента).
function S.HideDocked()
	local d = H.Env.DOCKED_CHAT_FRAMES
	if type(d) ~= "table" or getn(d) == 0 then
		local g = S.General()
		if g and g:IsShown() then
			g:Hide()
		end
		return
	end
	for i = 1, getn(d) do
		if d[i]:IsShown() then
			d[i]:Hide()
		end
	end
end

-- Стоковое меню окна (правый клик по вкладке): шрифт, цвета, имя, фильтры.
function S.Menu(window)
	local name = window and window.GetName and window:GetName()
	local fn = H.Env.ToggleDropDownMenu
	if not name or type(fn) ~= "function" then
		return false
	end
	local menu = H.Env[name.."TabDropDown"]
	if not menu then
		return false
	end
	pcall(fn, 1, nil, menu, "cursor", 0, 0)
	return true
end

----------------------------------------------------------------------------------------
-- Колесо
----------------------------------------------------------------------------------------

-- Колесо листает окно на C.Opt("wheelLines") строк, с Shift в начало или в конец.
function S.Wheel(frame, delta)
	if type(delta) ~= "number" or delta == 0 then
		return
	end
	local shift = H.Env.IsShiftKeyDown and H.Env.IsShiftKeyDown()
	if delta > 0 then
		if shift then
			frame:ScrollToTop()
		else
			for _ = 1, C.Opt("wheelLines") do
				frame:ScrollUp()
			end
		end
	elseif shift then
		frame:ScrollToBottom()
	else
		for _ = 1, C.Opt("wheelLines") do
			frame:ScrollDown()
		end
	end
end

----------------------------------------------------------------------------------------
-- Положение и шрифт окна
----------------------------------------------------------------------------------------

-- Запомнить положение окна (один раз) до первой постановки на кусок.
function S.SavePlacement(w)
	if S.placed[w] then
		return
	end
	local rec = { points = {}, width = w:GetWidth(), height = w:GetHeight(), level = w:GetFrameLevel() }
	local n = w:GetNumPoints() or 0
	for i = 1, n do
		local p, rel, rp, x, y = w:GetPoint(i)
		rec.points[i] = { p, rel, rp, x, y }
	end
	S.placed[w] = rec
end

function S.RestorePlacement(w)
	local rec = S.placed[w]
	if not rec then
		return
	end
	S.placed[w] = nil
	local n = getn(rec.points)
	w:ClearAllPoints()
	for i = 1, n do
		local p = rec.points[i]
		w:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
	if n <= 1 then
		if rec.width and rec.width > 0 then
			w:SetWidth(rec.width)
		end
		if rec.height and rec.height > 0 then
			w:SetHeight(rec.height)
		end
	end
	if rec.level then
		w:SetFrameLevel(rec.level)
	end
end

-- Шрифт окна ролью title (размер C.Opt("textSize")); старый шрифт запоминается один раз.
function S.StyleFont(w, on)
	local rec = S.saved[w]
	if not rec then
		return
	end
	if on then
		if not rec.font then
			local f, size, flags = w:GetFont()
			rec.font = { f, size, flags }
		end
		local path, size, flags = H.Fonts.Role("title", C.Opt("textSize") - 14)
		w:SetFont(path, size, flags)
	elseif rec.font then
		w:SetFont(rec.font[1], rec.font[2], rec.font[3])
		rec.font = nil
	end
end

----------------------------------------------------------------------------------------
-- Переодевание
----------------------------------------------------------------------------------------

local function Park(name)
	local f = H.Env[name]
	if type(f) == "table" and f.SetParent then
		H.Park(f, OWNER)
	end
end

local function DressWindow(i, w)
	local n = Names(i)
	local rec = { art = {}, files = {}, edges = {}, edgeOn = {} }
	S.saved[w] = rec
	for k = 1, getn(n.art) do
		local t = H.Env[n.art[k]]
		if type(t) == "table" and t.SetTexture then
			table.insert(rec.art, t)
			table.insert(rec.files, t:GetTexture() or "")
			t:SetTexture("")
		end
	end
	for k = 1, getn(n.edges) do
		local e = H.Env[n.edges[k]]
		if type(e) == "table" and e.EnableMouse then
			table.insert(rec.edges, e)
			table.insert(rec.edgeOn, (not e.IsMouseEnabled or e:IsMouseEnabled()) and true or false)
			e:EnableMouse(false)
		end
	end
	Park(n.tab)
	for k = 1, getn(n.buttons) do
		Park(n.buttons[k])
	end
	rec.wheelScript = w:GetScript("OnMouseWheel")
	rec.wheelOn = w.IsMouseWheelEnabled and w:IsMouseWheelEnabled() and true or false
	w:EnableMouseWheel(true)
	H.Script(OWNER, w, "OnMouseWheel", S.Wheel)
	if w.SetFading then
		pcall(w.SetFading, w, false)
	end
	S.StyleFont(w, true)
end

local function UndressWindow(w)
	local rec = S.saved[w]
	if not rec then
		return
	end
	S.StyleFont(w, false)
	for k = 1, getn(rec.art) do
		rec.art[k]:SetTexture(rec.files[k])
	end
	for k = 1, getn(rec.edges) do
		rec.edges[k]:EnableMouse(rec.edgeOn[k])
	end
	w:SetScript("OnMouseWheel", rec.wheelScript)
	w:EnableMouseWheel(rec.wheelOn)
	if w.SetFading then
		pcall(w.SetFading, w, true)
	end
	S.saved[w] = nil
end

function S.Dress()
	if S.dressed then
		return
	end
	S.dressed = true
	S.Windows(S.wins)
	for i = 1, S.Count() do
		local w = S.Window(i)
		if w then
			DressWindow(i, w)
		end
	end
	Park("ChatFrameMenuButton")
end

function S.Undress()
	if not S.dressed then
		return
	end
	S.dressed = false
	H.Unpark(OWNER)
	for i = 1, getn(S.wins) do
		UndressWindow(S.wins[i])
		S.RestorePlacement(S.wins[i])
	end
	H.Wipe(S.wins)
	local fn = H.Env.FCF_DockUpdate
	if type(fn) == "function" then
		pcall(fn)
	end
end

function S.Enable(mode)
	if mode == "replace" then
		S.Dress()
	end
end

function S.Disable()
	S.Undress()
end

function S.Refresh()
	if S.dressed then
		for i = 1, getn(S.wins) do
			S.StyleFont(S.wins[i], true)
		end
	end
end

-- Раз в секунду: запаркованное стоковым кодом перевешено обратно - Reassert возвращает его под скрытый родитель.
function S.Verify()
	if not S.dressed then
		return
	end
	H.Parking.Reassert()
end
