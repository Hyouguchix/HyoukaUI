-- HyoukaUI: Frames\LevelUp, кнопка накопленных уровней (кусок uf.levelup) (plan 3.1, inv frames#27).
--
-- Когда в игре включено "копить уровни", левелапы не ставят бой на паузу, а ждут. Квадрат 52 ретейл-px (27.7 AS)
-- под колонкой появляется, пока уровни накоплены: иконка, "xN" справа снизу (роль num), клавиша справа
-- сверху (роль small, сокращенно), золотая рамка. Клик открывает накопленные уровни.
-- Открыть уровни и узнать клавишу может только слой данных (глобалы AZS_ модулям запрещены), а в нем таких функций
-- нет: DATA REQUEST H.Run.OpenLevels() и H.Run.LevelKey(). Пока их нет, клик ставит тот же CVar, что и движок
-- (spendLevels = 1, engine azs_api.lua:393), а клавиша не рисуется.
-- Часть HUD игры "levels" в режиме Вместо закрывает Claim из StockBar. Кнопка прячется в фазах ready и choosing.
-- Данные: H.Run.StoredLevels(), события LEVEL_CHANGED, RUN, PHASE_CHANGED.

local H = HyoukaUI
local F = H.Frames
local I = H.Icon
local T = H.Theme

local S = { btn = nil, count = nil, key = nil, shown = nil }
F.LevelUp = S

local part = F.Part("levelup", {})

S.ICON = "Interface\\Icons\\Spell_ChargePositive"   -- [НЕ ПРОВЕРЕНО] картинка стоковая по имени из набора 1.12

function S.Open()
	if H.Run.OpenLevels then
		H.Run.OpenLevels()
		return
	end
	if SetCVar then
		SetCVar("spendLevels", "1")
	end
end

local function KeyText()
	local fn = H.Run.LevelKey
	if type(fn) ~= "function" then
		return ""
	end
	local key = fn()
	if type(key) ~= "string" or key == "" then
		return ""
	end
	key = string.gsub(key, "SHIFT%-", "S")
	key = string.gsub(key, "CTRL%-", "C")
	key = string.gsub(key, "ALT%-", "A")
	return key
end

function part.Build()
	local btn = I.New(UIParent, { size = 52, button = true, digits = false })
	btn:SetFrameStrata("MEDIUM")
	btn:Hide()
	I.SetTexture(btn, S.ICON)
	local g = T.C.glow
	I.SetBorderColor(btn, g[1], g[2], g[3], 1)
	local cnt = H.Text.New(btn, "num", { justify = "RIGHT", layer = "OVERLAY", color = "glow" })
	cnt:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", H.R(1), H.R(1))
	local key = H.Text.New(btn, "small", { justify = "RIGHT", layer = "OVERLAY" })
	key:SetPoint("TOPRIGHT", btn, "TOPRIGHT", H.R(2), -H.R(1))
	S.btn, S.count, S.key = btn, cnt, key
	btn:EnableMouse(true)
	btn:RegisterForClicks("LeftButtonUp")
	F.M:Script(btn, "OnClick", function(self, button)
		S.Open()
	end)
	F.M:Script(btn, "OnEnter", function(self)
		local tip = H.Env.GameTooltip
		if not tip then
			return
		end
		local anchor = H.Env.GameTooltip_SetDefaultAnchor
		if type(anchor) == "function" then
			anchor(tip, btn)
		else
			tip:SetOwner(btn, "ANCHOR_TOP")
		end
		tip:AddLine(F.T("levelup_title", "Новый уровень"))
		tip:AddLine(F.T("levelup_hint", "Нажмите, чтобы открыть накопленные уровни"), 0.8, 0.8, 0.8)
		tip:Show()
	end)
	F.M:Script(btn, "OnLeave", function(self)
		local tip = H.Env.GameTooltip
		if tip then
			tip:Hide()
		end
	end)
end

function S.Update()
	local btn = S.btn
	if not btn then
		return
	end
	local stored = H.Run.StoredLevels()
	local ph = H.Run.Phase()
	local show = F.Opt("showLevelUp") and stored > 0 and ph ~= nil and ph ~= "ready" and ph ~= "choosing"
	if show and S.shown ~= stored then
		S.shown = stored
		S.count:SetText("x"..stored)
		S.key:SetText(KeyText())
	end
	F.Show("uf.levelup", show)
end

function part.Enable(mode)
	S.shown = nil
	F.Piece("uf.levelup", S.btn)
end

function part.Disable()
	F.Unpiece("uf.levelup")
end

function part.Refresh()
	S.Update()
end

function part.Setting(key)
	if key == "showLevelUp" then
		S.Update()
	end
end

F.On("LEVEL_CHANGED", S.Update)
F.On("RUN", S.Update)
