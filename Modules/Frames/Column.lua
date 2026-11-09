-- HyoukaUI: Frames\Column, центральная колонка: главный ряд способностей (кусок col.main) (plan 3.1, 2.8).
--
-- 7 квадратов 45 ретейл-px с зазором 1 (321 = 171.2 AS при PX 0.5333): способности 1..6 и расовая "=" седьмой.
-- Пустые слоты рисуются квадратами #080808 0.8 с рамкой. Расклад: записи AZS_SPELLS 1..n-1 стоят на местах
-- 1..6, последняя запись (расовая) на седьмом (слот действий 12). Остальные куски колонки (класс-ресурс,
-- баффы, статичные, таймеры) лежат в соседних файлах и цепляются к col.main через Layout (ширина колонки
-- у всех одна, widthMatch). Кусок col.main корень цепочки.
-- События: SPELLS_CHANGED (состав), LOADOUT_CHANGED (иконки), сырое SPELLS (кулдауны), стоковое
-- ACTIONBAR_UPDATE_COOLDOWN, THEME (пересчет позиций). Кулдауны еще и раз в 0.1 с (GetActionCooldown).

local H = HyoukaUI
local F = H.Frames
local B = F.Buttons

local C = { btns = {}, frame = nil, n = 7 }
F.Column = C

local part = F.Part("column", {})

function part.Build()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	f:Hide()
	C.frame = f
	for p = 1, C.n do
		C.btns[p] = B.NewMain(f, p)
	end
	C.Place()
end

-- Позиции кнопок: шаг = 45 + 1 ретейл-px.
function C.Place()
	local f = C.frame
	if not f then
		return
	end
	local step = H.R(B.SIZE) + H.R(B.GAP)
	for p = 1, C.n do
		local b = C.btns[p]
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", (p - 1) * step, 0)
	end
end

-- Привязка кнопок к способностям: 1..6 по порядку, расовая седьмой.
function C.Assign()
	if not C.frame then
		return
	end
	local n = H.Spells.Count()
	for p = 1, C.n - 1 do
		local i = nil
		if p <= n - 1 then
			i = p
		end
		B.Assign(C.btns[p], i)
	end
	local last = nil
	if n >= 1 then
		last = n
	end
	B.Assign(C.btns[C.n], last)
	C.Cooldowns()
end

--@frame
function C.Cooldowns()
	for p = 1, C.n do
		B.UpdateCd(C.btns[p])
	end
end

function part.Enable(mode)
	F.Piece("col.main", C.frame)
	F.M:Every(0.1, C.Cooldowns)
	C.Assign()
end

function part.Disable()
	for p = 1, C.n do
		H.Icon.Clear(C.btns[p])
	end
	F.Unpiece("col.main")
end

function part.Refresh()
	F.Show("col.main", F.Opt("showMain"))
end

function part.Setting(key)
	if key == "rank" or key == "binds" or key == "cdMin" then
		C.Assign()
	elseif key == "greyCd" then
		for p = 1, C.n do
			B.ApplyGrey(C.btns[p])
		end
	end
end

F.On("SPELLS_CHANGED", C.Assign)
F.On("LOADOUT_CHANGED", C.Assign)
F.On("SPELLS", C.Cooldowns)
F.On("ACTIONBAR_UPDATE_COOLDOWN", C.Cooldowns)
F.On("THEME", C.Place)
