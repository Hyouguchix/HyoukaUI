-- HyoukaUI: режим перемещения (spec 4.9, plan 5).
--
-- Сетка акцентом каждые 32 ретейл-px (альфа 0.15, центр 0.25), белое перекрестие 20 px, муверы
-- #131D24 0.95 с рамкой акцента 0.6 (альфа 0.55 в покое, 0.85 при наведении, 0.95 при перетаскивании),
-- привязка в 6 px к краям и центрам соседей и экрана, затем к сетке физических пикселей.
-- Перетаскивание: StartMoving и SetClampedToScreen без своего OnUpdate; на отпускании место
-- пересчитывается и пишется через Layout (оторванный кусок хранит угол экрана и целые px).
-- Стрелки 1 px, Shift 10 px, Ctrl+Z отмена (40 шагов), Esc выход. Куски никогда не уходят за экран.
-- Клавиша удержания (general.moveKey: alt, ctrl, shift, none) включает режим, пока зажата.
--
-- Mover.On/Off/Toggle/IsOn, Select(id), Nudge(id, dx, dy), Commit(id, left, top), Snap(id, left, top),
-- Clamp(id, left, top), Undo(), ResetPiece(id), HandleKey(key), PollKey(). События: MOVE_MODE(on), LAYOUT(id).
-- Кадры создаются при первом включении, не при загрузке файла.

local H = HyoukaUI
local K = H.Kit
local L = H.Layout

local getn = table.getn

local Mv = {}
H.Mover = Mv

Mv.C = {
	SNAP = 6, GRID = 32, CROSS = 20, UNDO_MAX = 40, OPEN = 0.35, MIN = 8,
	IDLE = 0.55, HOVER = 0.85, DRAG = 0.95, NUDGE_JOIN = 1.5,
}

Mv.on = false
Mv.sel = nil
Mv.undo = {}
Mv.held = false

Mv.S = { movers = {}, gridV = {}, gridH = {}, cross = {}, fade = 0, lastNudge = nil, lastNudgeAt = -100, drag = nil }
local C, S = Mv.C, Mv.S

----------------------------------------------------------------------------------------
-- Геометрия: границы экрана, привязка, пиксельная сетка
----------------------------------------------------------------------------------------

function Mv.Clamp(id, left, top)
	local _, _, w, h = L.Rect(id)
	local sw, sh = L.Screen()
	w, h = w or 0, h or 0
	local maxL, maxT = sw - w, sh - h
	if maxL < 0 then
		maxL = 0
	end
	if maxT < 0 then
		maxT = 0
	end
	return H.Clamp(left, 0, maxL), H.Clamp(top, 0, maxT)
end

-- Потомок ли child куска ancestor по статической цепочке rel (при перемещении предка дети едут с ним).
local function Descends(child, ancestor)
	local hops = 0
	local d = L.Def(child)
	while d and d.rel and hops < 12 do
		if d.rel == ancestor then
			return true
		end
		d = L.Def(d.rel)
		hops = hops + 1
	end
	return false
end

local function Candidates(id)
	local xs, ys = {}, {}
	local sw, sh = L.Screen()
	xs[1], xs[2], xs[3] = 0, sw / 2, sw
	ys[1], ys[2], ys[3] = 0, sh / 2, sh
	local ids = L.Ids()
	for i = 1, getn(ids) do
		local o = ids[i]
		if o ~= id and L.IsVisible(o) and not Descends(o, id) then
			local l, t, w, h = L.Rect(o)
			table.insert(xs, l)
			table.insert(xs, l + w / 2)
			table.insert(xs, l + w)
			table.insert(ys, t)
			table.insert(ys, t + h / 2)
			table.insert(ys, t + h)
		end
	end
	return xs, ys
end

local function Pull(edges, targets, thr)
	local best, bestAbs = nil, thr
	for i = 1, getn(edges) do
		for j = 1, getn(targets) do
			local d = targets[j] - edges[i]
			local a = math.abs(d)
			if a < bestAbs then
				best, bestAbs = d, a
			end
		end
	end
	return best
end

-- Привязать позицию левого верха (AS) к краям и центрам соседей, затем к целым физическим пикселям.
-- Возвращает left, top, привязан ли по x, привязан ли по y.
function Mv.Snap(id, left, top)
	local _, _, w, h = L.Rect(id)
	if not w then
		return left, top, false, false
	end
	local px = K.PX()
	local thr = K.R(C.SNAP)
	local xs, ys = Candidates(id)
	local dx = Pull({ left, left + w / 2, left + w }, xs, thr)
	local dy = Pull({ top, top + h / 2, top + h }, ys, thr)
	if dx then
		left = left + dx
	end
	if dy then
		top = top + dy
	end
	left = H.Round(left / px) * px
	top = H.Round(top / px) * px
	left, top = Mv.Clamp(id, left, top)
	return left, top, dx ~= nil, dy ~= nil
end

----------------------------------------------------------------------------------------
-- Отмена и фиксация
----------------------------------------------------------------------------------------

local function Push(id, snap)
	table.insert(Mv.undo, { id = id, snap = snap })
	if getn(Mv.undo) > C.UNDO_MAX then
		table.remove(Mv.undo, 1)
	end
end

function Mv.Undo()
	local n = getn(Mv.undo)
	if n == 0 then
		return false
	end
	local e = table.remove(Mv.undo, n)
	L.Restore(e.id, e.snap)
	S.lastNudge = nil
	Mv.Refresh()
	return true
end

-- Поставить кусок: с привязкой (snap = true) или как есть. Записывает шаг отмены.
function Mv.Commit(id, left, top, noSnap)
	if not L.Has(id) then
		return false
	end
	local before = L.Snapshot(id)
	if noSnap then
		left, top = Mv.Clamp(id, left, top)
	else
		left, top = Mv.Snap(id, left, top)
	end
	Push(id, before)
	L.PlaceRect(id, left, top)
	Mv.Refresh()
	return true
end

-- Сдвиг на dx, dy физических пикселей (вправо и вниз положительные). Подряд идущие сдвиги одного куска
-- считаются одним шагом отмены.
function Mv.Nudge(id, dx, dy)
	local l, t = L.Rect(id)
	if not l then
		return false
	end
	local px = K.PX()
	local nl, nt = Mv.Clamp(id, l + dx * px, t + dy * px)
	local now = H.Now()
	local join = (S.lastNudge == id and now - S.lastNudgeAt < C.NUDGE_JOIN)
	local before = L.Snapshot(id)
	if not join then
		Push(id, before)
	end
	S.lastNudge, S.lastNudgeAt = id, now
	L.PlaceRect(id, nl, nt)
	Mv.Refresh()
	return true
end

function Mv.ResetPiece(id)
	if not L.Has(id) then
		return false
	end
	Push(id, L.Snapshot(id))
	L.Reset(id)
	S.lastNudge = nil
	Mv.Refresh()
	return true
end

function Mv.SetScale(id, scale)
	if not L.Has(id) then
		return false
	end
	local before = L.Snapshot(id)
	if L.SetScale(id, scale) then
		Push(id, before)
		S.lastNudge = nil
		Mv.Refresh()
		return true
	end
	return false
end

function Mv.ToggleShown(id)
	if not L.Has(id) then
		return false
	end
	Push(id, L.Snapshot(id))
	L.SetHidden(id, not L.IsHiddenByUser(id))
	Mv.Refresh()
	return true
end

local KEY_STEP = { UP = { 0, -1 }, DOWN = { 0, 1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

-- Клавиша в режиме перемещения. true, если обработана.
function Mv.HandleKey(key)
	if not Mv.on then
		return false
	end
	if key == "ESCAPE" then
		Mv.Off()
		return true
	end
	if key == "Z" and IsControlKeyDown and IsControlKeyDown() then
		return Mv.Undo()
	end
	local step = KEY_STEP[key]
	if step and Mv.sel then
		local m = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
		return Mv.Nudge(Mv.sel, step[1] * m, step[2] * m)
	end
	return false
end

----------------------------------------------------------------------------------------
-- Обновление и вход/выход
----------------------------------------------------------------------------------------

function Mv.Refresh()
	if not S.root or not Mv.on then
		return
	end
	local ids = L.Ids()
	local used = {}
	for i = 1, getn(ids) do
		local id = ids[i]
		local def = L.Def(id)
		if def and def.movable ~= false and (L.IsVisible(id) or L.IsHiddenByUser(id)) then
			local m = S.movers[id] or Mv.NewMover(id)
			m.label:SetText(L.PieceLabel(id, def))
			Mv.PlaceMover(m, id)
			Mv.PaintMover(m)
			m:Show()
			used[id] = true
		end
	end
	for id, m in pairs(S.movers) do
		if not used[id] then
			m:Hide()
		end
	end
	Mv.RefreshCard()
end

function Mv.Select(id)
	Mv.sel = id
	S.lastNudge = nil
	if S.root then
		-- клавиатуру занимаем только пока что-то выбрано (стрелки сдвигают выбранное)
		S.root:EnableKeyboard(id and true or false)
	end
	for _, m in pairs(S.movers) do
		Mv.PaintMover(m)
	end
	Mv.RefreshCard()
end

local function Fade(dt)
	S.fade = S.fade + dt
	if S.fade >= C.OPEN then
		S.root:SetAlpha(1)
		H.Clock.Stop("mover.fade")
	else
		S.root:SetAlpha(S.fade / C.OPEN)
	end
end

local function Build()
	if S.root then
		return
	end
	local root = CreateFrame("Frame", nil, UIParent)
	root:SetAllPoints(UIParent)
	root:SetFrameStrata("DIALOG")
	-- Факт из игры (2026-11-09): кадр с включенной клавиатурой забирает ВСЕ клавиши, чат не открывается,
	-- а Esc открывает меню игры и до кадра не доходит. Поэтому клавиатура включается только пока выбран
	-- элемент (стрелки), а выход - кнопкой "Готово", которая есть всегда.
	root:EnableKeyboard(false)
	root:EnableMouse(false)
	root:Hide()
	S.root = root
	S.done = K.Button(root, H.L.btn_done, K.R(140), K.R(28), function()
		Mv.Off()
	end, "mover")
	S.done:SetFrameStrata("TOOLTIP")
	S.done:SetPoint("TOP", root, "TOP", 0, -K.R(44))
	H.Script("mover", root, "OnKeyDown", function(self, key)
		Mv.HandleKey(key)
	end)
	Mv.BuildCard()
end

function Mv.On()
	if Mv.on then
		return
	end
	Build()
	Mv.on = true
	Mv.BuildGrid()
	S.root:SetAlpha(0)
	S.root:Show()
	S.fade = 0
	H.Clock.OnFrame("mover.fade", Fade)
	Mv.Refresh()
	H.Fire("MOVE_MODE", true)
end

function Mv.Off()
	if not Mv.on then
		return
	end
	Mv.on = false
	Mv.held = false
	Mv.sel = nil
	S.drag = nil
	H.Clock.Stop("mover.fade")
	if S.root then
		S.root:EnableKeyboard(false)
		S.root:Hide()
	end
	if S.card then
		S.card:Hide()
	end
	H.Fire("MOVE_MODE", false)
end

function Mv.Toggle()
	if Mv.on then
		Mv.Off()
	else
		Mv.On()
	end
end

function Mv.IsOn()
	return Mv.on
end

function Mv.ClearUndo()
	H.Wipe(Mv.undo)
end

-- Для тестов и selftest: кадры режима перемещения и число видимых линий сетки.
function Mv.Root()
	return S.root
end

function Mv.MoverFrame(id)
	return S.movers[id]
end

function Mv.CardFrame()
	return S.card
end

function Mv.GridLines()
	local nv, nh = 0, 0
	for i = 1, getn(S.gridV) do
		if S.gridV[i]:IsShown() then
			nv = nv + 1
		end
	end
	for i = 1, getn(S.gridH) do
		if S.gridH[i]:IsShown() then
			nh = nh + 1
		end
	end
	return nv, nh
end

----------------------------------------------------------------------------------------
-- Клавиша удержания (опрос раз в 0.1 с, пока настройка включена; событий модификаторов в 1.12 нет)
----------------------------------------------------------------------------------------

local KEYFN = { alt = "IsAltKeyDown", ctrl = "IsControlKeyDown", shift = "IsShiftKeyDown" }

function Mv.PollKey()
	local name = KEYFN[H.DB.Get("general", "moveKey") or "none"]
	local fn = name and H.Global(name)
	local down = fn and fn() and true or false
	if down and not Mv.on then
		Mv.On()
		Mv.held = true
	elseif not down and Mv.held then
		Mv.Off()
	end
end

function Mv.ApplyHoldSetting()
	H.Clock.Stop("mover.hold")
	if KEYFN[H.DB.Get("general", "moveKey") or "none"] then
		H.Clock.Every("mover.hold", 0.1, Mv.PollKey)
	end
end

H.On("LOGIN", "mover", function()
	Mv.ApplyHoldSetting()
end)
H.On("SETTING", "mover", function(ev, mod, key)
	if mod == "general" and key == "moveKey" then
		Mv.ApplyHoldSetting()
	end
end)
H.On("PHASE_CHANGED", "mover", function(ev, new)
	if new == "choosing" then
		Mv.Off()
	end
end)
H.On("LAYOUT", "mover", function()
	Mv.Refresh()
end)
-- Смена языка: надписи кнопки, муверов и карточки берутся заново.
H.On("LOCALE", "mover", function()
	if S.done then
		S.done:SetLabel(H.L.btn_done)
	end
	if S.card then
		S.card.showBtn:SetLabel(H.L.btn_show)
		S.card.reset:SetLabel(H.L.btn_put_back)
	end
	if Mv.on then
		Mv.Refresh()
		Mv.RefreshCard()
	end
end)
-- Смена акцента или размера пикселя: сетка и рамки муверов перекрашиваются и пересчитываются.
H.On("THEME", "mover", function()
	if Mv.on then
		Mv.BuildGrid()
		Mv.Refresh()
	end
end)
