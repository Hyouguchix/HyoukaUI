-- HyoukaUI: Frames\Player, рамка героя (кусок uf.player) на ретейл-месте слева от колонки (plan 3.1, решение 7).
--
-- 272x45 ретейл-px, центр (-385.5, -290): dark mode, справа "315K | 100%" (роль body, RIGHT -1,+2), имени и
-- портрета в ретейле нет (опции playerName, portrait). Щит из H.Hero.Health (AZS_RUN.sh), максимум здоровья
-- из AZS_RUN.hpm, текущее здоровье из UnitHealth("player") (числа, проба 0.12). "DEAD", в коопе при
-- падении "DOWN" (H.Run.IsDowned). Класс героя из H.Hero (клиентский UnitClass отдает не героя забега).
-- События: UNIT_HEALTH (player), UNIT_MAXHEALTH, RUN, HERO_CHANGED, DOWN_CHANGED, PLAYER_DEAD, PLAYER_ALIVE и
-- опрос раз в 0.1 с (кэш значений: без смены чисел ничего не пишется).

local H = HyoukaUI
local F = H.Frames
local U = F.UnitFrame

local S = { uf = nil }
F.Player = S

local part = F.Part("player", {})

function part.Build()
	S.uf = U.New("player", "PlayerFrameDropDown", 106, 27)
end

function S.Update()
	local uf = S.uf
	if not uf then
		return
	end
	local hp = UnitHealth("player") or 0
	local rhp, hpm, sh = H.Hero.Health()
	if type(hpm) ~= "number" or hpm <= 0 then
		hpm = UnitHealthMax("player") or 0
	end
	-- клиентское здоровье молчит, а строка забега его знает: берется строка (проба 0.12 не снята при уроне)
	if hp <= 0 and type(rhp) == "number" and rhp > 0 then
		hp = rhp
	end
	local label = nil
	if H.Run.IsDowned() then
		label = F.T("down", "ЛЕЖИТ")
	elseif hpm > 0 and hp <= 0 then
		label = F.T("dead", "Мертв")
	end
	H.Bar.Set(uf.bar, hp, hpm)
	U.SetHp(uf.right, hp, hpm, 0, label)
	U.Shield(uf, sh or 0, hpm)
	if F.Opt("barStyle") == "class" then
		U.SetFill(uf, H.Hero.ClassColor())
	end
	if F.Opt("playerName") then
		local name = H.Hero.Name()
		if name then
			local r, g, b = H.Hero.ClassColor()
			U.SetName(uf.left, name, r, g, b, H.R(U.W * 0.9))
		end
	elseif uf.left.uName ~= "" then
		uf.left.uName = ""
		uf.left:SetText("")
	end
	U.Power(uf)
end

function S.Apply()
	local uf = S.uf
	if uf then
		U.Style(uf)
		U.Portrait(uf)
		S.Update()
	end
end

function part.Enable(mode)
	F.Piece("uf.player", S.uf.bar)
	F.M:Every(0.1, S.Update)
	S.Apply()
end

function part.Disable()
	F.Unpiece("uf.player")
end

function part.Refresh()
	F.Show("uf.player", F.Opt("showPlayer"))
	S.Update()
end

function part.Setting(key)
	if key == "barStyle" or key == "portrait" or key == "playerName" or key == "shield" or key == "power" then
		if S.uf then
			S.uf.shield = -1
			S.uf.right.uCur = nil
		end
		S.Apply()
	end
end

F.On("UNIT_HEALTH", function(ev, unit)
	if unit == "player" then
		S.Update()
	end
end)
F.On("UNIT_MAXHEALTH", function(ev, unit)
	if unit == "player" then
		S.Update()
	end
end)
F.On("RUN", S.Update)
F.On("HERO_CHANGED", S.Apply)
F.On("DOWN_CHANGED", S.Update)
F.On("PLAYER_DEAD", S.Update)
F.On("PLAYER_ALIVE", S.Update)
F.On("UNIT_PORTRAIT_UPDATE", function(ev, unit)
	if unit == "player" and S.uf then
		U.Portrait(S.uf)
	end
end)
