-- HyoukaUI: демо-сцены (plan 2.2 Demo, этап 1). /hui demo solo | party | off.
--
-- Рисует заглушки кусков: плоские цветные прямоугольники с id куска и размером, на тех местах, где их
-- ставит Layout по таблице раскладки (plan 2.8). Нужно, чтобы сравнить геометрию на экране
-- (/hui geometry печатает те же числа) до появления модулей и вне забега.
--
-- Заглушка создается только для куска, которого нет в реестре Layout: настоящие кадры модулей не
-- подменяются. Заглушки регистрируются как обычные куски, поэтому работают схлопывание, масштаб и
-- режим перемещения (/hui move).
--
-- Demo.Show(scene) -> число заглушек; Demo.Hide(); Demo.Scene(); Demo.IsOn(); Demo.Pieces(scene) -> id.
-- scene: "solo" (без группы и подъема) или "party" (все куски). Событие DEMO(scene или nil).

local H = HyoukaUI
local K = H.Kit
local L = H.Layout

local getn = table.getn

local Demo = {}
H.Demo = Demo

-- Сцены общие с тестами: tests\test_demo.lua сверяет их со списком кусков из plan 2.8.
Demo.scenes = {
	solo = { skip = { ["uf.party"] = true, ["col.revive"] = true }, label = "соло" },
	party = { skip = {}, label = "группа" },
}
Demo.order = { "solo", "party" }

-- Цвет заливки по группе (первая часть id), только для различимости на экране.
local TINTS = {
	col = { 0.20, 0.30, 0.75 },
	uf = { 0.20, 0.55, 0.30 },
	tr = { 0.75, 0.45, 0.15 },
	mt = { 0.70, 0.20, 0.25 },
	build = { 0.15, 0.55, 0.60 },
	ui = { 0.45, 0.45, 0.50 },
}
local DEFAULT_TINT = { 0.4, 0.4, 0.4 }

local S = { scene = nil, stubs = {}, owned = {} }

local function GroupOf(id)
	local _, _, group = string.find(id, "^(%a+)")
	return group or "ui"
end

local function Describe(id)
	local l, t, w, h = L.Rect(id)
	if not l then
		return id
	end
	return string.format("%s\n%.1f x %.1f", id, w, h)
end

local function NewStub(id)
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("HIGH")
	local tex = f:CreateTexture(nil, "BACKGROUND")
	tex:SetTexture(K.FLAT)
	tex:SetAllPoints(f)
	local tint = TINTS[GroupOf(id)] or DEFAULT_TINT
	tex:SetVertexColor(tint[1], tint[2], tint[3], 0.6)
	f.border = K.Border(f, "edge")
	f.text = K.Text(f, "small", nil, "CENTER")
	f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
	return f
end

-- id кусков сцены по порядку таблицы раскладки.
function Demo.Pieces(scene)
	local sc = Demo.scenes[scene]
	local out = {}
	if not sc then
		return out
	end
	local defs, order = L.Defs()
	for i = 1, getn(order) do
		local id = order[i]
		if defs[id] and not sc.skip[id] then
			table.insert(out, id)
		end
	end
	return out
end

local function Drop()
	for id in pairs(S.owned) do
		local f = S.stubs[id]
		if f then
			f:Hide()
		end
		L.Unpiece(id)
	end
	S.owned = {}
end

function Demo.Hide()
	if S.scene == nil then
		return false
	end
	Drop()
	S.scene = nil
	H.Fire("DEMO", nil)
	return true
end

function Demo.Show(scene)
	if not Demo.scenes[scene] then
		return 0
	end
	local ids = Demo.Pieces(scene)
	if getn(ids) == 0 then
		return 0
	end
	Drop()
	S.scene = scene
	local made = 0
	for i = 1, getn(ids) do
		local id = ids[i]
		if not L.Has(id) then
			local f = S.stubs[id]
			if not f then
				f = NewStub(id)
				S.stubs[id] = f
			end
			L.Piece(id, f)
			S.owned[id] = true
			made = made + 1
		end
	end
	for id in pairs(S.owned) do
		S.stubs[id]:Show()
	end
	for id in pairs(S.owned) do
		S.stubs[id].text:SetText(Describe(id))
	end
	H.Fire("DEMO", scene)
	return made
end

function Demo.Scene()
	return S.scene
end

function Demo.IsOn()
	return S.scene ~= nil
end

function Demo.Count()
	local n = 0
	for _ in pairs(S.owned) do
		n = n + 1
	end
	return n
end

-- Размеры в подписях зависят от PX: обновить при смене масштаба.
H.On("THEME", "demo", function()
	for id in pairs(S.owned) do
		S.stubs[id].text:SetText(Describe(id))
	end
end)
