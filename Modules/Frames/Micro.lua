-- HyoukaUI: Frames\Micro, две кнопки сбоку (кусок ui.micro) (plan 3.1, spec 4.3, audit frames-23).
--
-- Микрокнопки персонажа и талантов стоят на MainMenuBar и уходят вместе с ней при парковке, поэтому две свои
-- кнопки в слоте боковой панели (85x214 ретейл-px справа от места чата): видны только по наведению на зону,
-- подсветка мгновенная (spec 1.7). Кнопки зовут стоковые ToggleCharacter("PaperDollFrame") и
-- ToggleTalentFrame() (окно персонажа Build переопределит первую, это его дело). Наведение: MouseIsOver(зона)
-- раз в 0.1 с, без функции - флаги OnEnter/OnLeave.
-- Зона принимает мышь, пока модуль включен: клики мира в этом прямоугольнике она забирает.

local H = HyoukaUI
local F = H.Frames
local K = H.Kit

local S = { zone = nil, btns = {}, alpha = -1, flag = false }
F.Micro = S

local part = F.Part("micro", {})

local SIZE = 24

local function Call(name, a)
	local fn = H.Env[name]
	if type(fn) == "function" then
		pcall(fn, a)
	end
end

function part.Build()
	local z = CreateFrame("Frame", nil, UIParent)
	z:SetFrameStrata("MEDIUM")
	z:EnableMouse(true)
	z:Hide()
	S.zone = z
	F.M:Script(z, "OnEnter", function(self)
		S.flag = true
	end)
	F.M:Script(z, "OnLeave", function(self)
		S.flag = false
	end)
	S.btns[1] = K.Button(z, F.T("micro_char", "Пер"), H.R(SIZE), H.R(SIZE), function()
		Call("ToggleCharacter", "PaperDollFrame")
	end, "frames")
	S.btns[1]:SetPoint("BOTTOMLEFT", z, "BOTTOMLEFT", H.R(1), H.R(1))
	S.btns[2] = K.Button(z, F.T("micro_talents", "Тал"), H.R(SIZE), H.R(SIZE), function()
		Call("ToggleTalentFrame", nil)
	end, "frames")
	S.btns[2]:SetPoint("BOTTOMLEFT", z, "BOTTOMLEFT", H.R(SIZE + 2), H.R(1))
end

F.On("LOCALE", function()
	if S.btns[1] then
		S.btns[1]:SetLabel(F.T("micro_char", "Пер"))
		S.btns[2]:SetLabel(F.T("micro_talents", "Тал"))
	end
end)

function S.Tick()
	local z = S.zone
	if not z then
		return
	end
	local over = S.flag
	local mo = H.Env.MouseIsOver
	if type(mo) == "function" then
		over = mo(z) and true or false
	end
	local want = over and 1 or 0
	if S.alpha ~= want then
		S.alpha = want
		z:SetAlpha(want)
	end
end

function part.Enable(mode)
	S.alpha = -1
	F.Piece("ui.micro", S.zone)
	F.M:Every(0.1, S.Tick)
	S.Tick()
end

function part.Disable()
	F.Unpiece("ui.micro")
end

function part.Refresh()
	F.Show("ui.micro", F.Opt("showMicro"))
end

function part.Setting(key)
	if key == "showMicro" then
		part.Refresh()
	end
end
