-- HyoukaUI: список с пулом строк и прокруткой колесом.
--
-- Строк-кадров создается ровно столько, сколько помещается (плюс одна неполная): остальные данные
-- показываются теми же строками при прокрутке. Обновление не создает таблиц и замыканий.
--
-- List.New(parent, opts)   opts: w, h (ретейл-px), row (высота строки, ретейл-px), gap (шаг между строками, 1),
--                          bg (по умолчанию нет), border, create(row, list), update(row, item, index, list), owner
--   create вызывается один раз для каждой новой строки-кадра (внутри строк ставят свои тексты и иконки);
--   update вызывается при каждом обновлении для каждой видимой строки.
-- List.SetItems(list, items, count)  данные: массив и число (count по умолчанию table.getn)
-- List.Refresh(list)                 перерисовать видимые строки
-- List.SetOffset(list, n)            первая видимая строка (0 - сверху); List.Scroll(list, delta)
-- List.Visible(list)                 сколько строк помещается; List.Rows(list) - число созданных строк-кадров
-- Полоса прокрутки 2 ретейл-px показывается только при переполнении.

local H = HyoukaUI
local T = H.Theme
local P = H.Panel

local Li = {}
H.List = Li

local reg = setmetatable({}, { __mode = "k" })

local function Visible(list)
	local step = H.R(list.huiRowH + list.huiGap)
	if step <= 0 then
		return 0
	end
	local inner = (list:GetHeight() or 0)
	local n = math.floor((inner + H.R(list.huiGap)) / step + 0.0001)
	if n < 1 then
		n = 1
	end
	return n
end

function Li.Visible(list)
	return list.huiVisible
end

function Li.Rows(list)
	return table.getn(list.huiRows)
end

local function EnsureRows(list)
	local want = list.huiVisible
	local rows = list.huiRows
	local step = H.R(list.huiRowH + list.huiGap)
	for i = table.getn(rows) + 1, want do
		local row = CreateFrame("Frame", nil, list)
		row:SetHeight(H.R(list.huiRowH))
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * step)
		row:SetPoint("TOPRIGHT", list, "TOPRIGHT", list.huiBar and -H.R(3) or 0, -(i - 1) * step)
		row.huiIndex = 0
		table.insert(rows, row)
		if list.huiCreate then
			list.huiCreate(row, list)
		end
	end
end

local function PlaceThumb(list)
	local bar = list.huiBar
	if not bar then
		return
	end
	local n = list.huiCount
	local vis = list.huiVisible
	if list.huiThumbOff == list.huiOffset and list.huiThumbCnt == n and list.huiThumbVis == vis then
		return
	end
	list.huiThumbOff, list.huiThumbCnt, list.huiThumbVis = list.huiOffset, n, vis
	if n <= vis then
		bar:Hide()
		return
	end
	local h = list:GetHeight() or 0
	local thumb = math.max(H.R(8), h * vis / n)
	local travel = h - thumb
	local maxOff = n - vis
	local pos = maxOff > 0 and (list.huiOffset / maxOff * travel) or 0
	bar:ClearAllPoints()
	bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -pos)
	bar:SetWidth(H.R(2))
	bar:SetHeight(thumb)
	bar:Show()
end

function Li.Refresh(list)
	EnsureRows(list)
	local rows = list.huiRows
	local items = list.huiItems
	local n = list.huiCount
	local off = list.huiOffset
	local update = list.huiUpdate
	for i = 1, table.getn(rows) do
		local row = rows[i]
		local idx = off + i
		if i <= list.huiVisible and idx <= n then
			row.huiIndex = idx
			row:Show()
			if update then
				update(row, items[idx], idx, list)
			end
		else
			row.huiIndex = 0
			row:Hide()
		end
	end
	PlaceThumb(list)
end

function Li.SetOffset(list, n)
	local maxOff = list.huiCount - list.huiVisible
	if maxOff < 0 then
		maxOff = 0
	end
	n = H.Clamp(math.floor(n), 0, maxOff)
	if n ~= list.huiOffset then
		list.huiOffset = n
		Li.Refresh(list)
	end
end

function Li.Scroll(list, delta)
	Li.SetOffset(list, list.huiOffset - delta)
end

function Li.SetItems(list, items, count)
	list.huiItems = items
	list.huiCount = count or table.getn(items)
	local maxOff = list.huiCount - list.huiVisible
	if maxOff < 0 then
		maxOff = 0
	end
	if list.huiOffset > maxOff then
		list.huiOffset = maxOff
	end
	Li.Refresh(list)
end

function Li.New(parent, opts)
	opts = opts or {}
	local list = P.New(parent, { w = opts.w, h = opts.h, bg = opts.bg or false, border = opts.border or false })
	list.huiRowH = opts.row or 24
	list.huiGap = opts.gap or 1
	list.huiCreate = opts.create
	list.huiUpdate = opts.update
	list.huiRows = {}
	list.huiItems = {}
	list.huiCount = 0
	list.huiOffset = 0
	list.huiVisible = Visible(list)
	local bar = list:CreateTexture(nil, "OVERLAY")
	bar:SetTexture(T.TEX.solid)
	local r, g, b = T.AccentRGB()
	bar:SetVertexColor(r, g, b, 0.6)
	bar:Hide()
	list.huiBar = bar
	list:EnableMouseWheel(true)
	H.Script(opts.owner or "w_list", list, "OnMouseWheel", function(self, delta)
		Li.Scroll(list, delta or 0)
	end)
	reg[list] = true
	EnsureRows(list)
	return list
end

-- THEME: размеры строк и число видимых пересчитываются.
function Li.Reflow()
	for list in pairs(reg) do
		list.huiThumbOff = nil
		list.huiVisible = Visible(list)
		local step = H.R(list.huiRowH + list.huiGap)
		for i = 1, table.getn(list.huiRows) do
			local row = list.huiRows[i]
			row:SetHeight(H.R(list.huiRowH))
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * step)
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", list.huiBar and -H.R(3) or 0, -(i - 1) * step)
		end
		Li.Refresh(list)
	end
end

H.On("THEME", "w_list", Li.Reflow)
