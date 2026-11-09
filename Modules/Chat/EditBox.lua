-- HyoukaUI: Chat\EditBox, плоское поле ввода чата (spec 3.8, режим Вместо).
--
-- Поле ввода остается стоковым (ChatFrameEditBox): фокус, Enter, Esc, история, цели ввода ведет игра. Модуль не включает
-- захват клавиш ни на каком кадре. Что меняется: арт (Left, Mid, Right и безымянный средний кусок, узнается по файлу
-- chatinputborder) очищается с запоминанием файла, на самом поле рисуется плоский фон #080808 альфа 1 и рамка в физический
-- пиксель (текстуры на самом поле, поэтому они под текстом), высота 22 ретейл-px, шрифт роли title (и у заголовка "Say:"),
-- положение: внутри панели сверху, поверх ряда вкладок (spec: inferred). OnShow дополняется постановкой на место (цепочка:
-- сначала стоковый скрипт). Отступы текста стоковые (игра пересчитывает их сама при смене заголовка).
-- Возврат (E.Disable): файлы арта, шрифты, высота, точки и стоковый OnShow возвращаются, свои текстуры прячутся.

local H = HyoukaUI
local C = H.Chat

local getn = table.getn

local E = {}
C.Edit = E

E.dressed = false

local HEIGHT = 22
local INSET = 1

local rec            -- запомненное состояние поля
local fill

local function R(px)
	return H.R(px)
end

local function Header()
	return H.Env.ChatFrameEditBoxHeader
end

function E.Place()
	local edit = C.Stock.Edit()
	local f = C.Panel.frame
	if not edit or not f then
		return
	end
	edit:ClearAllPoints()
	edit:SetPoint("TOPLEFT", f, "TOPLEFT", R(INSET), -R(INSET))
	edit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -R(INSET), -R(INSET))
	edit:SetHeight(R(HEIGHT))
end

local function StyleFonts()
	local edit = C.Stock.Edit()
	local path, size, flags = H.Fonts.Role("title", C.Opt("textSize") - 14)
	edit:SetFont(path, size, flags)
	local head = Header()
	if type(head) == "table" and head.SetFont then
		head:SetFont(path, size, flags)
	end
end

local function Dress(edit)
	rec = { art = {}, files = {}, points = {}, height = edit:GetHeight(), onShow = edit:GetScript("OnShow") }
	local n = edit:GetNumPoints() or 0
	for i = 1, n do
		local p, rel, rp, x, y = edit:GetPoint(i)
		rec.points[i] = { p, rel, rp, x, y }
	end
	local f, size, flags = edit:GetFont()
	rec.font = { f, size, flags }
	local head = Header()
	if type(head) == "table" and head.GetFont then
		local hf, hs, hfl = head:GetFont()
		rec.headFont = { hf, hs, hfl }
	end
	local pieces = { "Left", "Mid", "Right" }
	for i = 1, getn(pieces) do
		local t = H.Env["ChatFrameEditBox"..pieces[i]]
		if type(t) == "table" and t.SetTexture then
			table.insert(rec.art, t)
			table.insert(rec.files, t:GetTexture() or "")
			t:SetTexture("")
		end
	end
	-- безымянный средний кусок: известен по файлу
	local regions = { edit:GetRegions() }
	for i = 1, getn(regions) do
		local t = regions[i]
		local file = t.GetTexture and t:GetTexture()
		if type(file) == "string" and string.find(string.lower(file), "chatinputborder", 1, true) then
			table.insert(rec.art, t)
			table.insert(rec.files, file)
			t:SetTexture("")
		end
	end
	if not fill then
		fill = edit:CreateTexture(nil, "BACKGROUND")
		fill:SetTexture(H.Theme.TEX.solid)
		fill:SetAllPoints(edit)
		local c = H.Theme.C.dock
		fill:SetVertexColor(c[1], c[2], c[3], 1)
	end
	fill:Show()
	H.Theme.AddBorder(edit)
	H.Theme.ShowBorder(edit, true)
	local stockShow = rec.onShow
	edit:SetScript("OnShow", function()
		if stockShow then
			pcall(stockShow)
		end
		E.Place()
	end)
end

function E.Enable(mode)
	if mode ~= "replace" or E.dressed then
		return
	end
	local edit = C.Stock.Edit()
	if type(edit) ~= "table" or not edit.GetScript then
		return
	end
	E.dressed = true
	Dress(edit)
	StyleFonts()
	E.Place()
end

function E.Disable()
	if not E.dressed then
		return
	end
	E.dressed = false
	local edit = C.Stock.Edit()
	for i = 1, getn(rec.art) do
		rec.art[i]:SetTexture(rec.files[i])
	end
	if fill then
		fill:Hide()
	end
	H.Theme.ShowBorder(edit, false)
	edit:SetFont(rec.font[1], rec.font[2], rec.font[3])
	local head = Header()
	if rec.headFont and type(head) == "table" then
		head:SetFont(rec.headFont[1], rec.headFont[2], rec.headFont[3])
	end
	edit:SetScript("OnShow", rec.onShow)
	edit:ClearAllPoints()
	for i = 1, getn(rec.points) do
		local p = rec.points[i]
		edit:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
	if rec.height and rec.height > 0 then
		edit:SetHeight(rec.height)
	end
	rec = nil
end

function E.Refresh()
	if E.dressed then
		StyleFonts()
		E.Place()
	end
end

-- Раз в секунду: поле ввода осталось на месте панели.
function E.Verify()
	if not E.dressed then
		return
	end
	local edit = C.Stock.Edit()
	local _, rel = edit:GetPoint(1)
	if rel ~= C.Panel.frame then
		E.Place()
	end
end
