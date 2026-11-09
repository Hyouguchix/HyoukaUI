-- HyoukaUI: Frames\ColumnUtility, таймеры талантов, призывы и тотемы под рядом способностей (кусок col.utility)
-- (plan 3.1).
--
-- Иконки 37 ретейл-px по центру колонки (до 8). Источники через H.Buffs без таблиц на вызов:
--   Timers   внутренние кулдауны талантов и бижутерии, вторая жизнь: только пока идет откат;
--   Summons  призывы по видам (счет "N" и самый долгий остаток); постоянные только по опции permanentPets;
--   Totems   тотемы: "N" или "N/cap" (cap > 0).
-- Лимиты призывов в данных не приходят (GameRules.summonCap = nil), поэтому "N/limit" у призывов не рисуется.
-- События TIMERS, PETS, TOTEMS и раз в секунду (остаток откатов считается от часов забега).
-- Часть HUD игры "build" закрывает покрытие Hud.Cover("build", "col.utility") в StockBar (режим Вместо).

local H = HyoukaUI
local F = H.Frames
local B = F.Buttons
local I = H.Icon

local S = { frame = nil, pool = nil }
F.ColumnUtility = S

local part = F.Part("utility", {})

local SIZE = 37
local MAX = 8

-- Массивы записей, заполняются обходом без таблиц на вызов.
local E = { n = 0, icon = {}, dur = {}, rem = {}, count = {}, cap = {}, key = {}, tot = {} }

function part.Build()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("MEDIUM")
	f:Hide()
	S.frame = f
	S.pool = B.Pool(f, { size = SIZE, digitsRole = "num", stackRole = "small" })
end

local function Push(icon, dur, rem, count, cap, key, totem)
	if E.n >= MAX then
		return
	end
	-- Запись без текстуры иконки не рисуется: раньше она показывалась темным квадратом-заглушкой, и пользователь
	-- видел под рядом способностей "какую-то иконку, которая иногда появляется" (2026-11-09).
	if type(icon) ~= "string" or icon == "" then
		return
	end
	local j = E.n + 1
	E.n = j
	E.icon[j], E.dur[j], E.rem[j] = icon, dur, rem
	E.count[j], E.cap[j], E.key[j], E.tot[j] = count or 0, cap or 0, key, totem
end

local function OnTimer(name, icon, kind, duration, remaining, ready)
	if not ready and remaining and remaining > 0 then
		Push(icon, duration, remaining, 0, 0, nil, false)
	end
end

local function OnSummon(id, key, kind, name, icon, permanent, duration, remaining)
	if permanent and not F.Opt("permanentPets") then
		return
	end
	for j = 1, E.n do
		if E.key[j] == key and not E.tot[j] then
			E.count[j] = E.count[j] + 1
			if remaining and (E.rem[j] or 0) < remaining then
				E.rem[j], E.dur[j] = remaining, duration
			end
			return
		end
	end
	Push(icon, duration, remaining, 1, 0, key, false)
end

local function OnTotem(key, spell, name, icon, count, cap, duration, remaining)
	Push(icon, duration, remaining, count, cap, key, true)
end

local function CountText(ic, count, cap)
	local fs = ic.huiCount
	if not fs then
		fs = H.Text.New(ic, "num", { justify = "CENTER" })
		fs:SetPoint("CENTER", ic, "CENTER", 0, -H.R(15))
		ic.huiCount = fs
		ic.huiCountKey = -1
	end
	local key = count * 1000 + cap
	if ic.huiCountKey == key then
		return
	end
	ic.huiCountKey = key
	if cap > 0 then
		fs:SetText(count.."/"..cap)
	elseif count > 1 then
		fs:SetText(count)
	else
		fs:SetText("")
	end
end

function S.Update()
	local f = S.frame
	if not f then
		return
	end
	E.n = 0
	if F.Opt("showUtility") then
		H.Buffs.Timers(OnTimer)
		H.Buffs.Summons(OnSummon)
		H.Buffs.Totems(OnTotem)
	end
	local n = E.n
	for j = 1, n do
		local ic = B.Get(S.pool, j)
		local path = E.icon[j]
		if type(path) ~= "string" or path == "" then
			path = B.UNKNOWN
		end
		I.SetTexture(ic, path)
		B.SetEnds(ic, E.dur[j], E.rem[j])
		CountText(ic, E.count[j], E.cap[j])
	end
	B.Finish(S.pool, n)
	if n > 0 then
		B.PlaceCentered(f, S.pool, n, SIZE, 1)
	end
	F.Show("col.utility", n > 0)
end

function part.Enable(mode)
	F.Piece("col.utility", S.frame)
	F.M:Every(1.0, S.Update)
end

function part.Disable()
	B.Finish(S.pool, 0)
	F.Unpiece("col.utility")
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showUtility" or key == "permanentPets" then
		S.Update()
	end
end

F.On("TIMERS", S.Update)
F.On("PETS", S.Update)
F.On("TOTEMS", S.Update)
F.On("THEME", S.Update)
