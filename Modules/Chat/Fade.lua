-- HyoukaUI: Chat\Fade, затухание чата по таймеру с показом при наведении (опция fade, в ретейле выключена: FadeEnabled=false).
--
-- Когда включено: нет новых строк, мыши над панелью и открытого поля ввода fadeAfter секунд - прозрачность панели и стоковых
-- окон плавно уходит в 0 за OUT_TIME; наведение, новая строка (Touch), клик по вкладке или открытое поле ввода возвращают ее
-- за IN_TIME. Прозрачность панели наследуют ее дети (ленты и вкладки), поэтому на них SetAlpha не ставится (иначе двойное
-- затухание): [НЕ ПРОВЕРЕНО в игре] наследование alpha детьми у кадров 1.12. Стоковые окна лежат вне панели и получают
-- alpha сами. Свой счет вместо нативного SetFading: он дает одинаковое поведение для стоковых окон и лент и проверяем.
-- Состояние читается раз в тик (0.05 с): MouseIsOver и IsShown, без выделения памяти.

local H = HyoukaUI
local C = H.Chat

local getn = table.getn

local Fd = {}
C.Fade = Fd

Fd.OUT_TIME = 1.0
Fd.IN_TIME = 0.15

Fd.alpha = 1
local idle = 0
local applied = 1

function Fd.Touch()
	idle = 0
end

function Fd.Idle()
	return idle
end

local function Apply(a)
	applied = a
	local P = C.Panel
	if P.frame then
		P.frame:SetAlpha(a)
	end
	local placed = C.Stock.placed
	for i = 1, getn(P.texts) do
		local w = P.texts[i]
		if placed[w] then
			w:SetAlpha(a)
		end
	end
end

local function Hovering()
	local mo = H.Env.MouseIsOver
	local f = C.Panel.frame
	if mo and f and mo(f) then
		return true
	end
	local edit = H.Env.ChatFrameEditBox
	if edit and edit.IsShown and edit:IsShown() then
		return true
	end
	return false
end

--@frame
function Fd.Tick(dt)
	if not C.Opt("fade") then
		if Fd.alpha ~= 1 or applied ~= 1 then
			Fd.alpha = 1
			idle = 0
			Apply(1)
		end
		return
	end
	if Hovering() then
		idle = 0
	else
		idle = idle + dt
	end
	local target = 1
	if idle >= C.Opt("fadeAfter") then
		target = 0
	end
	local a = Fd.alpha
	if a < target then
		a = a + dt / Fd.IN_TIME
		if a > target then
			a = target
		end
	elseif a > target then
		a = a - dt / Fd.OUT_TIME
		if a < target then
			a = target
		end
	end
	Fd.alpha = a
	if a ~= applied then
		Apply(a)
	end
end

function Fd.Enable(mode)
	Fd.alpha = 1
	idle = 0
	applied = 1
end

function Fd.Disable()
	Fd.alpha = 1
	idle = 0
	Apply(1)
end

function Fd.Refresh()
	if not C.Opt("fade") then
		Fd.alpha = 1
		Apply(1)
	end
	idle = 0
end
