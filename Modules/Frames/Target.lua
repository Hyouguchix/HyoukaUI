-- HyoukaUI: Frames\Target, рамка цели (кусок uf.target) на ретейл-месте справа от колонки (plan 3.1, решение 7).
--
-- 272x45 ретейл-px, центр (+385.5, -290). Слева сверху имя цвета вида (трэш #A23838, элита #7471C3, босс акцент,
-- игрок по классу, друг зеленым) и, если клиент отдает, "имя > цель цели" (UnitName("targettarget"), проба 0.12
-- не снята: без имени остается только имя цели). Слева снизу "HP | %": настоящие числа из AZS_TARGET при
-- совпадении имени (H.Units.Target), иначе процент клиента (UnitHealthMax = 100 дает только процент).
-- Справа снизу процент ресурса. Каст цели не рисуется: в 1.12 нет данных о кастах мобов.
-- Видна только при цели. Правый клик: TargetFrameDropDown. События: PLAYER_TARGET_CHANGED, UNIT_HEALTH (target),
-- TARGET, UNITS_CHANGED, опрос раз в 0.1 с.

local H = HyoukaUI
local F = H.Frames
local T = H.Theme
local U = F.UnitFrame
local Fm = H.Format

local S = { uf = nil }
F.Target = S

local part = F.Part("target", {})

function part.Build()
	S.uf = U.New("target", "TargetFrameDropDown", 120, 10)
end

-- Цвет имени и заливки: игрок по классу, друг, затем вид врага. Возвращает r, g, b и признак врага.
local function Colors(kind)
	local r, g, b
	if F.Unit("UnitIsPlayer", "target") then
		r, g, b = T.ClassColor(F.UnitClassToken("target"))
		return r, g, b, false
	end
	if F.Unit("UnitIsFriend", "player", "target") then
		local c = T.REACTION.friendly
		return c[1], c[2], c[3], false
	end
	if kind == "boss" or kind == "final" then
		r, g, b = T.KindColor("boss")
	elseif kind == "elite" then
		r, g, b = T.KindColor("elite")
	else
		r, g, b = T.KindColor("trash")
	end
	return r, g, b, true
end

-- Имя и цель цели одной строкой; пересчет только при смене любого из имен.
local function SetNames(uf, name, r, g, b)
	local fs = uf.left
	local tot = nil
	if F.Opt("targetOfTarget") and F.Unit("UnitExists", "targettarget") then
		tot = F.Unit("UnitName", "targettarget")
	end
	local maxW = H.R(U.W * 0.9)
	if not tot or tot == "" then
		if fs.uTot then
			-- строка была собрана с целью цели: кэш обрезки и имени сбрасывается, текст ставится заново
			fs.uName, fs.huiFitText = nil, nil
		end
		U.SetName(fs, name, r, g, b, maxW)
		fs.uTot = nil
		return
	end
	if fs.uName == name and fs.uTot == tot and fs.uColor == r * 1000000 + g * 1000 + b then
		return
	end
	fs.uName, fs.uTot = name, tot
	fs.uColor = r * 1000000 + g * 1000 + b
	local shown = H.Text.Fit(fs, name, maxW * 0.62)
	local tr, tg, tb = H.Hero.ClassColor()
	if not F.Unit("UnitIsUnit", "targettarget", "player") then
		local c = T.REACTION.hostile
		tr, tg, tb = c[1], c[2], c[3]
	end
	fs:SetTextColor(r, g, b, 1)
	fs:SetText(shown.."|cffffffff "..H.Fonts.SYM.arrow.." |r"..Fm.ColorCode(tr, tg, tb)..Fm.Fit(tot, 12).."|r")
	fs.huiText = nil
end

function S.Update()
	local uf = S.uf
	if not uf then
		return
	end
	if not F.Unit("UnitExists", "target") then
		F.Show("uf.target", false)
		return
	end
	F.Show("uf.target", F.Opt("showTarget"))
	local name = F.Unit("UnitName", "target") or ""
	local rhp, rhpm, _, kind = H.Units.Target()
	local cur, max, mode
	if rhp and rhpm and rhpm > 0 then
		cur, max, mode = rhp, rhpm, 0
	else
		cur = F.Unit("UnitHealth", "target") or 0
		max = F.Unit("UnitHealthMax", "target") or 0
		mode = max == 100 and 1 or 0
	end
	local r, g, b, enemy = Colors(kind)
	H.Bar.Set(uf.bar, cur, max)
	U.SetHp(uf.sub, cur, max, mode, nil)
	if F.Opt("barStyle") == "class" then
		if enemy then
			U.SetFill(uf, U.ENEMY[1], U.ENEMY[2], U.ENEMY[3])
		else
			U.SetFill(uf, r, g, b)
		end
	end
	if F.Opt("targetName") then
		SetNames(uf, name, r, g, b)
	elseif uf.left.uName ~= "" then
		uf.left.uName, uf.left.uTot = "", nil
		uf.left:SetText("")
	end
	U.Shield(uf, 0, max)
	U.Power(uf)
	S.Resource(uf)
end

-- Процент ресурса цели справа снизу цветом ресурса (только при включенной полоске ресурса).
function S.Resource(uf)
	local fs = uf.res
	if not F.Opt("power") then
		if fs.uShown then
			fs.uShown = nil
			fs:SetText("")
		end
		return
	end
	local cur, max = F.Unit("UnitMana", "target"), F.Unit("UnitManaMax", "target")
	if not max or max <= 0 then
		if fs.uShown then
			fs.uShown = nil
			fs:SetText("")
		end
		return
	end
	local pct = Fm.Pct(cur or 0, max)
	if fs.uShown ~= pct + 1 then
		fs.uShown = pct + 1
		fs:SetText(Fm.Int(pct).."%")
	end
end

function S.Apply()
	local uf = S.uf
	if uf then
		U.Style(uf)
		U.Portrait(uf)
		uf.left.uName = nil
		S.Update()
	end
end

function part.Enable(mode)
	F.Piece("uf.target", S.uf.bar)
	F.M:Every(0.1, S.Update)
	S.Apply()
end

function part.Disable()
	F.Unpiece("uf.target")
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "barStyle" or key == "portrait" or key == "targetName" or key == "targetOfTarget" or key == "power" then
		S.Apply()
	end
end

F.On("PLAYER_TARGET_CHANGED", function()
	if S.uf then
		S.uf.left.uName = nil
		U.Portrait(S.uf)
	end
	S.Update()
end)
F.On("UNIT_HEALTH", function(ev, unit)
	if unit == "target" then
		S.Update()
	end
end)
F.On("UNIT_MAXHEALTH", function(ev, unit)
	if unit == "target" then
		S.Update()
	end
end)
F.On("TARGET", S.Update)
F.On("UNITS_CHANGED", S.Update)
F.On("UNIT_PORTRAIT_UPDATE", function(ev, unit)
	if unit == "target" and S.uf then
		U.Portrait(S.uf)
	end
end)
