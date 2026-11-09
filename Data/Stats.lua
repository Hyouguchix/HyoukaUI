-- HyoukaUI: Data\Stats, числа забега с панели персонажа (plan 2.2). Читает AZS_STATS (префикс AZS, строка
-- "k=v;" без метки обновления; engine-lua\framexml_fixes.lua: AZS_Parse, нечисловое значение = 0).
-- Движок на каждое сообщение кладет в AZS_STATS НОВУЮ таблицу, поэтому смена определяется по ссылке,
-- а при новой ссылке значения сверяются со снимком: событие STATS_CHANGED только если что-то изменилось.
--
--   H.Stats.Get(key)  число или nil, если данных нет; ключ, которого нет в строке, равен 0 (правило движка)
--   H.Stats.Has()     пришли ли данные в этой сессии (true, пока AZS_STATS это таблица)
--   H.Stats.Check()   сверить сейчас (тесты); то же делает кадр после сообщения AZS
-- Ключи: azs-api.md 2.2 (hp dmg cd crit cm arm area cnt echo spd reg pick lch heal thn liv xp gold luck bp
-- dots doth big exe cc dotd shd auto pet, вклад экипировки g*, bwk bwa).
-- Событие: STATS_CHANGED(). Читать после него через Get. Сверка идет по сообщению AZS и по событию RUN, без таймера.

local H = HyoukaUI

local S = {}
H.Stats = S

local snap = {}            -- последние увиденные значения
local lastRef = nil        -- последняя увиденная таблица AZS_STATS
local count = 0            -- число ключей в снимке

function S.Has()
	return type(AZS_STATS) == "table"
end

function S.Get(key)
	local t = AZS_STATS
	if type(t) ~= "table" then
		return nil
	end
	local v = t[key]
	if type(v) == "number" then
		return v
	end
	return 0
end

-- Сверка: нулевые аллокации (pairs по таблицам, снимок обновляется на месте).
function S.Check()
	local t = AZS_STATS
	if type(t) ~= "table" then
		t = nil
	end
	if t == lastRef then
		return false
	end
	lastRef = t
	local changed = false
	if t == nil then
		if count > 0 then
			H.Wipe(snap)
			count = 0
			changed = true
		end
	else
		local n = 0
		for k, v in pairs(t) do
			n = n + 1
			if snap[k] ~= v then
				snap[k] = v
				changed = true
			end
		end
		if changed or n ~= count then
			-- ключ мог пропасть из новой строки: убрать его из снимка
			for k in pairs(snap) do
				if t[k] == nil then
					snap[k] = nil
				end
			end
			count = n
			changed = true
		end
	end
	if changed then
		H.Fire("STATS_CHANGED")
	end
	return changed
end

-- Сообщения с префиксом AZS (ровно "AZS") несут AZS_STATS. Порядок наших обработчиков и обработчика движка не известен
-- (проба 0.5), поэтому сверка идет в следующем кадре, один раз на пачку сообщений. Таймера опроса нет.
local scheduled = false

local function Later()
	scheduled = false
	S.Check()
end

local function OnMessage(ev, prefix)
	if prefix == "AZS" and not scheduled then
		scheduled = true
		H.Clock.After("stats", 0, Later)
	end
end

function S.Reset()
	H.Wipe(snap)
	lastRef, count = nil, 0
	scheduled = false
end

H.Poll.AddLayer("stats", S.Reset)
H.On("CHAT_MSG_ADDON", "stats", OnMessage)
H.On("RUN", "stats", S.Check)
