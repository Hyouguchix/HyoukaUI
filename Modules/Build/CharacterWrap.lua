-- HyoukaUI: модуль Build, открытие своего окна персонажа клавишей C (ручная обертка ToggleCharacter).
--
-- hooksecurefunc в игре нет (проба 0.16), поэтому глобал ToggleCharacter подменяется вручную. Защита от двойной
-- обертки: у каждой установки свой объект { orig, active }; пока установка активна, вторая не ставится. При
-- выключении модуля обертка становится прозрачной (active = false), а если она на вершине цепочки, глобал
-- возвращается как был. Так чужая обертка поверх нашей не ломается и цикла нет.
-- Поведение обертки: вызов без вкладки или с "PaperDollFrame" в режиме "Вместо" открывает окно HyoukaUI и не зовет
-- стоковую функцию; в режиме "Рядом" так делает только вызов с зажатым Shift. Другие вкладки (репутация) и выключенная
-- настройка charWindow идут в стоковую функцию (в движке она уже обернута AZS_ToggleCharacter).
-- [НЕ ПРОВЕРЕНО] что клавиша C и кнопка персонажа вызывают именно глобал ToggleCharacter (проверка в handoff_build.md).

local H = HyoukaUI
local B = H.Build
local C = B.Character

local S = { owner = "HyoukaUI" }

local function MakeWrapper(orig)
	local inst = { orig = orig, active = true }
	inst.fn = function(tab)
		if inst.active and (tab == nil or tab == "PaperDollFrame") and B.M.db.charWindow then
			local mode = B.Mode()
			if mode == "replace" or (mode == "side" and IsShiftKeyDown()) then
				C.Toggle()
				return
			end
		end
		return inst.orig(tab)
	end
	return inst
end

function C.InstallWrap()
	if S.wrap and S.wrap.active then
		return false
	end
	local env = H.Env
	if type(env.ToggleCharacter) ~= "function" then
		return false
	end
	S.wrap = MakeWrapper(env.ToggleCharacter)
	env.ToggleCharacter = S.wrap.fn
	H.RegisterHook("ToggleCharacter", S.owner)
	return true
end

function C.RemoveWrap()
	local w = S.wrap
	if not w then
		return false
	end
	w.active = false
	if H.Env.ToggleCharacter == w.fn then
		H.Env.ToggleCharacter = w.orig
	end
	S.wrap = nil
	H.hooks.ToggleCharacter = nil
	return true
end

function C.WrapActive()
	return S.wrap ~= nil and S.wrap.active
end

B.AddPart("charwrap", function(M)
	C.InstallWrap()
end, function()
	C.RemoveWrap()
end)
