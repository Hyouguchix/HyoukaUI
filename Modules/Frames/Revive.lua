-- HyoukaUI: Frames\Revive, полоса подъема (кусок col.revive) под таймерами колонки (plan 3.1, spec 3.6, inv frames#31).
--
-- 171.2x11.7 AS (321x22 ретейл-px): иконка слева, справа полоса с акцентной заливкой по доле подъема. Видна, пока
-- герой лежит (H.Party.Revive: down == 1; текст "<имя> поднимает вас" и доля share) или пока героя ведет подъем
-- соратника (reviving: "Вы поднимаете <имя>", доля rshare). Справа процент. Остальное время кусок скрыт и схлопывается
-- (collapse в LayoutDefaults). Режим Вместо: Claim части HUD "revive" (игровая полоса подъема скрыта). Включением
-- управляет настройка showParty вместе с рамками группы. Сообщение "ВЫ ЛЕЖИТЕ" на экране принадлежит Трекеру.
-- Данные только через H.Party, события REVIVE, DOWN_CHANGED, опрос 0.1 с.

local H = HyoukaUI
local F = H.Frames
local T = H.Theme
local Bar = H.Bar

local S = { box = nil, bar = nil, left = nil, right = nil, icon = nil, claimed = false }
F.Revive = S

local part = F.Part("revive", {})

local OWNER = "frames"
S.ICON = "Interface\\Icons\\Spell_Holy_Resurrection"
local H_PX = 22
local W_PX = 321

function part.Build()
	local box = CreateFrame("Frame", nil, UIParent)
	box:SetFrameStrata("MEDIUM")
	box:Hide()
	S.box = box
	local ib = H.Panel.New(box, { w = H_PX, h = H_PX, bg = "iconBg" })
	ib:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
	local tex = ib:CreateTexture(nil, "ARTWORK")
	local b = T.Border()
	tex:SetPoint("TOPLEFT", ib, "TOPLEFT", b, -b)
	tex:SetPoint("BOTTOMRIGHT", ib, "BOTTOMRIGHT", -b, b)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tex:SetTexture(S.ICON)
	S.icon = ib
	local bar = Bar.New(box, { w = W_PX - H_PX - 1, h = H_PX, bg = "dock" })
	bar:SetPoint("TOPLEFT", ib, "TOPRIGHT", H.R(1), 0)
	Bar.SetColor(bar, T.AccentRGB())
	S.bar = bar
	local l = H.Text.New(bar, "body", { justify = "LEFT" })
	l:SetPoint("LEFT", bar, "LEFT", H.R(3), 0)
	S.left = l
	local r = H.Text.New(bar, "body", { justify = "RIGHT" })
	r:SetPoint("RIGHT", bar, "RIGHT", -H.R(3), 0)
	S.right = r
end

-- Строка слева; собирается только при смене состояния.
local function SetText(who, mode)
	if S.textWho == who and S.textMode == mode then
		return
	end
	S.textWho, S.textMode = who, mode
	local text
	if mode == "by" then
		text = who.." "..F.T("revive_by", "поднимает вас")
	elseif mode == "you" then
		text = F.T("revive_you", "Вы поднимаете").." "..who
	else
		text = F.T("down_you", "Вы лежите")
	end
	S.left:SetText(text)
	S.left.huiText = nil
end

local function SetPct(share)
	local pct = math.floor(share * 100 + 0.5)
	if S.pct ~= pct then
		S.pct = pct
		S.right:SetText(pct.."%")
		S.right.huiText = nil
	end
end

function S.Update()
	if not S.box then
		return
	end
	local down, share, by, reviving, rshare = H.Party.Revive()
	local want = F.Opt("showParty")
	if want and down == 1 then
		SetText(by or "", by and "by" or "down")
		share = share or 0
	elseif want and reviving then
		SetText(reviving, "you")
		share = rshare or 0
	else
		S.textWho, S.textMode, S.pct = nil, nil, nil
		F.Show("col.revive", false)
		return
	end
	if share > 1 then
		share = 1
	end
	Bar.Set(S.bar, share, 1)
	SetPct(share)
	F.Show("col.revive", true)
end

function S.SyncClaim(mode)
	local want = (mode == "replace") and F.Opt("showParty") and true or false
	if want and not S.claimed then
		S.claimed = true
		H.Hud.Claim("revive", OWNER)
	elseif not want and S.claimed then
		S.claimed = false
		H.Hud.Release("revive", OWNER)
	end
end

function part.Enable(mode)
	F.Piece("col.revive", S.box)
	F.M:Every(0.1, S.Update)
	S.SyncClaim(mode)
	S.Update()
end

function part.Disable()
	S.SyncClaim("off")
	F.Unpiece("col.revive")
end

function part.Mode(mode)
	S.SyncClaim(mode)
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showParty" then
		S.SyncClaim(F.mode)
	end
end

F.On("REVIVE", S.Update)
F.On("DOWN_CHANGED", S.Update)
F.On("THEME", function()
	if S.bar then
		Bar.SetColor(S.bar, T.AccentRGB())
	end
end)
F.On("LOGOUT", function()
	S.claimed = false
end)
