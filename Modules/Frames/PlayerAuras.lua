-- HyoukaUI: Frames\PlayerAuras, ауры героя слева от места миникарты (куски uf.buffs и uf.debuffs) (plan 3.1, spec 3.9).
--
-- Баффы: иконки 32 ретейл-px, 12 в ряд, до 3 рядов, рост влево, длительность роль small снизу внутри иконки,
-- правый клик снимает (CancelPlayerBuff). Дебафы: иконки 37, 16 в ряд, один ряд, длительность роль title, рамка
-- по типу снятия, иначе красная. Подсказка: GameTooltip:SetPlayerBuff(индекс). Шторки нет (spec 3.9).
-- Источник: стоковые GetPlayerBuff(i, "HELPFUL" | "HARMFUL") с нулевого индекса до -1 (ответ -1 или nil
-- конец списка), GetPlayerBuffTexture, GetPlayerBuffApplications, GetPlayerBuffTimeLeft,
-- GetPlayerBuffDispelType [НЕ ПРОВЕРЕНО: что для героя забега отдает клиент]. События PLAYER_AURAS_CHANGED,
-- UNIT_AURA (player) и опрос раз в 0.5 с для секунд; значения кэшируются, строк на кадр нет.
-- Стоковые BuffFrame и TemporaryEnchantFrame в режиме Вместо уходят под скрытый кадр (StockBar).
-- Пока Трекер не зарегистрировал кусок миникарты tr.minimap, куски стоят на запасном якоре (Frames.lua).

local H = HyoukaUI
local F = H.Frames
local B = F.Buttons
local I = H.Icon
local T = H.Theme
local Fm = H.Format

local S = { buffs = nil, debuffs = nil }
F.PlayerAuras = S

local part = F.Part("playerauras", {})

local KINDS = {
	{ id = "uf.buffs", filter = "HELPFUL", size = 32, perRow = 12, role = "small", cancel = true, key = "buffs" },
	{ id = "uf.debuffs", filter = "HARMFUL", size = 37, perRow = 16, role = "title", cancel = false, key = "debuffs" },
}
local GAP = 1
local MAX = 32

local function Fn(name)
	local fn = H.Env[name]
	if type(fn) == "function" then
		return fn
	end
	return nil
end

local function Tip(ic)
	local tip = H.Env.GameTooltip
	if not tip or not ic.huiIndex then
		return
	end
	local anchor = H.Env.GameTooltip_SetDefaultAnchor
	if type(anchor) == "function" then
		anchor(tip, ic)
	else
		tip:SetOwner(ic, "ANCHOR_BOTTOMLEFT")
	end
	if pcall(tip.SetPlayerBuff, tip, ic.huiIndex) then
		tip:Show()
	end
end

local function NewIcon(k, pool, n)
	local ic = I.New(pool.parent, pool.opts)
	ic:EnableMouse(true)
	local fs = H.Text.New(ic, k.role, { justify = "CENTER", layer = "OVERLAY" })
	fs:SetPoint("BOTTOM", ic, "BOTTOM", 0, H.R(1))
	ic.huiTime = fs
	ic.huiTimeKey = -1
	ic:RegisterForClicks("RightButtonUp")
	F.M:Script(ic, "OnEnter", function(self)
		Tip(ic)
	end)
	F.M:Script(ic, "OnLeave", function(self)
		local tip = H.Env.GameTooltip
		if tip then
			tip:Hide()
		end
	end)
	if k.cancel then
		F.M:Script(ic, "OnClick", function(self, button)
			local cancel = Fn("CancelPlayerBuff")
			if button == "RightButton" and cancel and ic.huiIndex then
				pcall(cancel, ic.huiIndex)
			end
		end)
	end
	return ic
end

function part.Build()
	for i = 1, table.getn(KINDS) do
		local k = KINDS[i]
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetFrameStrata("MEDIUM")
		f:Hide()
		local pool = B.Pool(f, { size = k.size, button = true, digits = false, stackRole = "small" })
		pool.kind = k
		S[k.key] = { frame = f, pool = pool, kind = k }
	end
end

-- Текст длительности: секунды, от минуты "Nm", от часа "Nh"; строка собирается только при смене ключа.
local function TimeText(ic, rem)
	local key
	if rem == nil or rem <= 0 then
		key = 0
	elseif rem >= 3600 then
		key = 2000000 + math.ceil(rem / 3600)
	elseif rem >= 60 then
		key = 1000000 + math.ceil(rem / 60)
	else
		key = math.ceil(rem)
	end
	if ic.huiTimeKey == key then
		return
	end
	ic.huiTimeKey = key
	if key == 0 then
		ic.huiTime:SetText("")
	else
		ic.huiTime:SetText(Fm.CdText(rem))
	end
end

local function Place(set, n)
	local k = set.kind
	local step = H.R(k.size) + H.R(GAP)
	if not B.NeedPlace(set.pool, n, step) then
		return
	end
	for j = 1, n do
		local ic = set.pool.list[j]
		local col = math.mod(j - 1, k.perRow)
		local row = math.floor((j - 1) / k.perRow)
		ic:ClearAllPoints()
		ic:SetPoint("TOPRIGHT", set.frame, "TOPRIGHT", -col * step, -row * step)
	end
end

local function Fill(set)
	local k = set.kind
	local get = Fn("GetPlayerBuff")
	local tex, apps, left, dispel = Fn("GetPlayerBuffTexture"), Fn("GetPlayerBuffApplications"),
		Fn("GetPlayerBuffTimeLeft"), Fn("GetPlayerBuffDispelType")
	local cap = MAX
	if k.key == "buffs" then
		cap = k.perRow * 3
	end
	local n = 0
	if get and tex and F.Opt("showPlayerAuras") then
		for i = 0, cap - 1 do
			local idx, forever = get(i, k.filter)
			if not idx or idx < 0 then
				break
			end
			n = n + 1
			local pool = set.pool
			local ic = pool.list[n]
			if not ic then
				ic = NewIcon(k, pool, n)
				pool.list[n] = ic
			end
			if not ic:IsShown() then
				ic:Show()
			end
			ic.huiIndex = idx
			I.SetTexture(ic, tex(idx) or B.UNKNOWN)
			I.SetStack(ic, apps and apps(idx) or 0)
			if forever and forever ~= 0 then
				TimeText(ic, nil)
			else
				TimeText(ic, left and left(idx) or nil)
			end
			if k.key == "debuffs" then
				local d = dispel and dispel(idx)
				local c = d and T.DISPEL[d]
				if c then
					I.SetBorderColor(ic, c[1], c[2], c[3], 1)
				else
					local e = T.C.error
					I.SetBorderColor(ic, e[1], e[2], e[3], 1)
				end
			end
		end
	end
	B.Finish(set.pool, n)
	if n > 0 then
		Place(set, n)
	end
	F.Show(k.id, n > 0)
end

--@frame
function S.Update()
	if S.buffs then
		Fill(S.buffs)
	end
	if S.debuffs then
		Fill(S.debuffs)
	end
end

function part.Enable(mode)
	for i = 1, table.getn(KINDS) do
		local set = S[KINDS[i].key]
		F.Piece(set.kind.id, set.frame)
	end
	F.M:Every(0.5, S.Update)
	S.Update()
end

function part.Disable()
	for i = 1, table.getn(KINDS) do
		local set = S[KINDS[i].key]
		B.Finish(set.pool, 0)
		F.Unpiece(set.kind.id)
	end
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showPlayerAuras" then
		S.Update()
	end
end

F.On("PLAYER_AURAS_CHANGED", S.Update)
F.On("UNIT_AURA", function(ev, unit)
	if unit == "player" then
		S.Update()
	end
end)
F.On("THEME", S.Update)
