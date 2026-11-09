-- HyoukaUI: Frames\ColumnAuras, баффы забега (кусок col.buffs) и статичные значки (col.statics) (plan 3.1).
--
-- col.buffs: иконки 34 ретейл-px по центру колонки, рост от центра, только активные. Строка AZS_BUFFS дает
-- { spell, left }; иконка берется у способности героя с тем же id (H.Spells), остаток от часов забега
-- (H.Buffs.Left), полная длительность выводится по росту left (H.Buffs.Duration). Цифры отката (роль body)
-- по центру иконки. Баффы без известной способности получают значок вопроса.
-- col.statics: по краям колонки жизни (справа, зеленые стаки) и перебросы (слева). Значков-картинок для них
-- в игре не известно, поэтому ячейка 37 ретейл-px: короткая подпись и число [отступление: картинки
-- не выдумываются]. Число из H.Run.Get("lives" | "rr").
-- Схлопывание: пустой кусок скрыт, Layout опускает цепочку выше.

local H = HyoukaUI
local F = H.Frames
local B = F.Buttons
local I = H.Icon

local S = { buffFrame = nil, pool = nil, statFrame = nil, lives = nil, rolls = nil }
F.ColumnAuras = S

local bpart = F.Part("colbuffs", {})
local spart = F.Part("colstatics", {})

local BUFF = 34
local STATIC = 37
local MAX_BUFFS = 9            -- (321 + 1) / 35 = 9 иконок в ширину колонки

----------------------------------------------------------------------------------------
-- Баффы
----------------------------------------------------------------------------------------

function bpart.Build()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	f:Hide()
	S.buffFrame = f
	S.pool = B.Pool(f, { size = BUFF, digitsRole = "body", stackRole = "small" })
end

-- Иконка способности героя с этим id заклинания.
local function IconOf(spell)
	local n = H.Spells.Count()
	for j = 1, n do
		if H.Spells.SpellId(j) == spell then
			return H.Spells.Icon(j)
		end
	end
	return nil
end

function S.UpdateBuffs()
	local f = S.buffFrame
	if not f then
		return
	end
	local count = H.Buffs.Count()
	local n = 0
	if F.Opt("showBuffs") then
		for i = 1, count do
			local row = H.Buffs.Row(i)
			if row and row.spell ~= nil and n < MAX_BUFFS then
				local left = H.Buffs.Left(row.spell) or row.left
				if type(left) == "number" and left > 0 then
					n = n + 1
					local ic = B.Get(S.pool, n)
					I.SetTexture(ic, IconOf(row.spell) or B.UNKNOWN)
					local dur = H.Buffs.Duration(row.spell)
					if not dur or dur < left then
						dur = left
					end
					B.SetEnds(ic, dur, left)
				end
			end
		end
	end
	B.Finish(S.pool, n)
	if n > 0 then
		B.PlaceCentered(f, S.pool, n, BUFF, 1)
	end
	F.Show("col.buffs", n > 0)
end

function bpart.Enable(mode)
	F.Piece("col.buffs", S.buffFrame)
end

function bpart.Disable()
	B.Finish(S.pool, 0)
	F.Unpiece("col.buffs")
end

function bpart.Refresh()
	S.UpdateBuffs()
end

function bpart.Setting(key)
	if key == "showBuffs" then
		S.UpdateBuffs()
	end
end

F.On("BUFFS_CHANGED", S.UpdateBuffs)
F.On("SPELLS_CHANGED", S.UpdateBuffs)
F.On("THEME", S.UpdateBuffs)

----------------------------------------------------------------------------------------
-- Статичные: жизни и перебросы
----------------------------------------------------------------------------------------

local function NewCell(parent, label)
	local cell = H.Panel.New(parent, { w = STATIC, h = STATIC, bg = "dock" })
	local cap = H.Text.New(cell, "small", { justify = "CENTER", color = "muted" })
	cap:SetPoint("TOP", cell, "TOP", 0, -H.R(3))
	cap:SetText(label)
	cell.huiCap = cap
	local num = H.Text.New(cell, "stat", { justify = "CENTER", color = "green" })
	num:SetPoint("CENTER", cell, "CENTER", 0, -H.R(3))
	cell.huiNum = num
	return cell
end

function spart.Build()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	f:Hide()
	S.statFrame = f
	S.lives = NewCell(f, F.T("lives_short", "ЖИЗН"))
	S.lives:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	S.rolls = NewCell(f, F.T("rerolls_short", "ПЕР"))
	S.rolls:SetPoint("LEFT", f, "LEFT", 0, 0)
end

F.On("LOCALE", function()
	if S.lives then
		S.lives.huiCap:SetText(F.T("lives_short", "ЖИЗН"))
		S.rolls.huiCap:SetText(F.T("rerolls_short", "ПЕР"))
	end
end)

local function Number(v)
	if type(v) == "number" and v > 0 then
		return v
	end
	return 0
end

function S.UpdateStatics()
	if not S.statFrame then
		return
	end
	local lives, rolls = Number(H.Run.Get("lives")), Number(H.Run.Get("rr"))
	local want = F.Opt("showStatics")
	if want and lives > 0 then
		H.Text.SetInt(S.lives.huiNum, lives)
		S.lives:Show()
	else
		S.lives:Hide()
	end
	if want and rolls > 0 then
		H.Text.SetInt(S.rolls.huiNum, rolls)
		S.rolls:Show()
	else
		S.rolls:Hide()
	end
	F.Show("col.statics", want and (lives > 0 or rolls > 0))
end

function spart.Enable(mode)
	F.Piece("col.statics", S.statFrame)
end

function spart.Disable()
	F.Unpiece("col.statics")
end

function spart.Refresh()
	S.UpdateStatics()
end

function spart.Setting(key)
	if key == "showStatics" then
		S.UpdateStatics()
	end
end

F.On("RUN", S.UpdateStatics)
