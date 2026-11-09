-- HyoukaUI: Frames\Xp, полоса опыта забега (кусок col.xp) (plan 2.8, решение 5, inv frames#25).
--
-- По умолчанию сверху по центру, 400x18 ретейл-px (213.3x9.6 AS): заливка акцентом на #080808 0.85, текст
-- по центру "Ур. 23  64%", накопленные уровни золотом справа "+2". Вариант "над колонкой" (опция xpPlace) задает
-- LayoutDefaults.variants. Пока забег не идет (фаза ready) полоса скрыта.
-- Подсказка по наведению: опыт, накопленные уровни, темп (опыт в минуту) и время до следующего уровня.
-- Темп (окно 45 секунд часов забега, цифра после 10 секунд) считает слой данных Data\Xp: H.Xp.Pace() и NextIn();
-- H.Frames.Xp.Pace() и NextIn() только обертки.
-- Данные: H.Run.Get("xp"|"xpn"), H.Run.Level(), H.Run.StoredLevels(), событие RUN.

local H = HyoukaUI
local F = H.Frames
local Fm = H.Format

local S = { bar = nil, text = nil, stored = nil }
local X = S
F.Xp = X

local part = F.Part("xp", {})

function part.Build()
	local bar = H.Bar.New(UIParent, { w = 400, h = 18, bg = "panel" })
	H.Bar.SetColor(bar, H.Theme.AccentRGB())
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	S.bar = bar
	local fs = H.Text.New(bar, "body", { justify = "CENTER" })
	fs:SetPoint("CENTER", bar, "CENTER", 0, H.R(2))
	S.text = fs
	local st = H.Text.New(bar, "body", { justify = "RIGHT", color = "glow" })
	st:SetPoint("RIGHT", bar, "RIGHT", -H.R(3), H.R(2))
	S.stored = st
	bar:EnableMouse(true)
	F.M:Script(bar, "OnEnter", function(self)
		S.Tip()
	end)
	F.M:Script(bar, "OnLeave", function(self)
		local tip = H.Env.GameTooltip
		if tip then
			tip:Hide()
		end
	end)
end

----------------------------------------------------------------------------------------
-- Темп: считает слой данных H.Xp (читает и Трекер)
----------------------------------------------------------------------------------------

function S.Pace()
	return H.Xp.Pace()
end

function S.NextIn()
	return H.Xp.NextIn()
end

function S.Tip()
	local tip = H.Env.GameTooltip
	local xpn = H.Run.Get("xpn")
	if not tip or not xpn then
		return
	end
	local anchor = H.Env.GameTooltip_SetDefaultAnchor
	if type(anchor) == "function" then
		anchor(tip, S.bar)
	else
		tip:SetOwner(S.bar, "ANCHOR_BOTTOM")
	end
	local xp = H.Run.Get("xp") or 0
	tip:AddLine(F.T("xp_title", "Опыт забега"))
	tip:AddDoubleLine(F.T("xp_level", "Уровень"), Fm.Int(H.Run.Level() or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddDoubleLine(F.T("xp_xp", "Опыт"), Fm.Short(xp).." / "..Fm.Short(xpn), 0.8, 0.8, 0.8, 1, 1, 1)
	local stored = H.Run.StoredLevels()
	if stored > 0 then
		tip:AddDoubleLine(F.T("xp_stored", "Накоплено уровней"), Fm.Int(stored), 0.8, 0.8, 0.8, 1, 0.79, 0.14)
	end
	local pace = S.Pace()
	if pace then
		tip:AddDoubleLine(F.T("xp_pace", "Темп"), Fm.Short(pace).."/"..F.T("xp_min", "мин"), 0.8, 0.8, 0.8, 1, 1, 1)
		local nxt = S.NextIn()
		if nxt then
			tip:AddDoubleLine(F.T("xp_next", "Следующий уровень через"), Fm.Time(nxt), 0.8, 0.8, 0.8, 1, 1, 1)
		end
	end
	tip:Show()
end

----------------------------------------------------------------------------------------
-- Вид
----------------------------------------------------------------------------------------

function S.Update()
	local bar = S.bar
	if not bar then
		return
	end
	local lvl, xp, xpn = H.Run.Level(), H.Run.Get("xp") or 0, H.Run.Get("xpn")
	local show = F.Opt("showXp") and lvl ~= nil and xpn ~= nil and xpn > 0 and H.Run.Phase() ~= "ready"
	if show then
		H.Bar.Set(bar, xp, xpn)
		local pct = Fm.Pct(xp, xpn)
		local key = lvl * 1000 + pct
		if S.shown ~= key then
			S.shown = key
			S.text:SetText(F.T("xp_lv", "Ур.").." "..lvl.."  "..pct.."%")
		end
		local stored = H.Run.StoredLevels()
		if stored > 0 then
			H.Text.Set(S.stored, "+"..stored)
		else
			H.Text.Set(S.stored, "")
		end
	end
	F.Show("col.xp", show)
end

function part.Enable(mode)
	S.shown = nil
	F.Piece("col.xp", S.bar)
end

function part.Disable()
	F.Unpiece("col.xp")
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showXp" or key == "xpPlace" then
		S.Update()
	end
end

F.On("RUN", S.Update)
F.On("THEME", function()
	if S.bar then
		H.Bar.SetColor(S.bar, H.Theme.AccentRGB())
	end
end)
F.On("LOCALE", function()
	S.shown = nil
	S.Update()
end)
F.On("RUN_STARTED", function()
	S.shown = nil
	S.Update()
end)
