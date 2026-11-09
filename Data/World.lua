-- HyoukaUI: Data\World, слой мира: положение героя, сундуки, боссы из мировых якорей. Читает AZS_* только этот
-- файл, ничего не рисует (azs-api.md 2.5 и 2.9: AZS_CHESTS, AZS_GetPlayerPosition, AZS_GetWorldAnchors).
--   H.World.Player()  -> x, y, z, facing (числа) или nil, если положение сейчас не известно
--   H.World.Chests()  -> массив { id, x, y, z, mx, my } (живая таблица движка, только чтение) или пустой массив, если
--                        данные не свежие (метка старше строки зоны нового забега)
--   H.World.Bosses()  -> массив { kind, name, x, y, state } из якорей kinds boss и finalBoss; перечитывается не чаще
--                        раза в секунду, записи переиспользуются; пусто, пока каталог якорей не готов
--   H.World.Reset()   -> забыть кэш боссов (DataReset)
-- Мир (SurvivorUI MapPins.lua): x растет на север, y на запад, facing игры держит камеру, а не модель героя.
-- Все три API версионированные и при ошибке возвращают nil, err: ответ всегда проверяется, вызов под pcall.
-- AZS_GetPlayerPosition создает таблицу на вызов (мусор движка): звать только пока пины видны.

local H = HyoukaUI

local W_ = {}
H.World = W_

local EMPTY = {}
local bosses = {}
local readAt = -100
local KINDS = { kinds = { "boss", "finalBoss" } }

function W_.Player()
	if not AZS_GetPlayerPosition then
		return nil
	end
	local ok, p = pcall(AZS_GetPlayerPosition)
	if not ok or type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then
		return nil
	end
	return p.x, p.y, p.z, p.facing
end

function W_.Chests()
	local stamp = AZS_CHESTS_UPDATED
	if type(AZS_CHESTS) == "table" and stamp and H.Run.IsFresh(stamp) then
		return AZS_CHESTS
	end
	return EMPTY
end

function W_.Bosses()
	local now = GetTime()
	if now - readAt < 1 then
		return bosses
	end
	readAt = now
	local n = 0
	if AZS_GetWorldAnchors then
		local ok, r = pcall(AZS_GetWorldAnchors, KINDS, nil, 64)
		if ok and type(r) == "table" and type(r.entries) == "table" then
			for i = 1, table.getn(r.entries) do
				local e = r.entries[i]
				if type(e) == "table" and type(e.x) == "number" and type(e.y) == "number" and e.state ~= "dead" then
					n = n + 1
					local rec = bosses[n]
					if not rec then
						rec = {}
						bosses[n] = rec
					end
					rec.kind, rec.name, rec.x, rec.y, rec.state = e.kind, e.name, e.x, e.y, e.state
				end
			end
		end
	end
	for i = table.getn(bosses), n + 1, -1 do
		table.remove(bosses, i)
	end
	return bosses
end

function W_.Reset()
	readAt = -100
	for i = table.getn(bosses), 1, -1 do
		table.remove(bosses, i)
	end
end

H.Poll.AddLayer("world", W_.Reset)
