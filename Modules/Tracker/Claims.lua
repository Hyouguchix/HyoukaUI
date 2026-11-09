-- HyoukaUI: Modules\Tracker\Claims, захват частей HUD игры модулем Трекер (plan раздел 4): только в режиме Вместо.
--
-- Таблица WANT связывает часть игры с куском раскладки и настройками, которые все должны быть включены. Часть
-- захватывается Claim, а если GameRules описывает для нее список покрытий (Rules.Required), то Cover по id куска:
-- тогда игровая часть скрыта, только когда покрыты все обязательные куски. Часть прячется, только если у нас есть чем ее
-- заменить (GATE): часы устройства известны, слой мира для пинов есть; иначе игровая часть остается (дубль лучше пустоты).
-- Tr.SyncHud() приводит захваты к настройкам; зовут Hub (режим, настройки) и Minimap (часы устройства появились).

local H = HyoukaUI

local Tr = H.Tr
local S = Tr.S
local M = Tr.M

local getn = table.getn

----------------------------------------------------------------------------------------

-- { часть игры, кусок, настройки, которые все должны быть включены }
local WANT = {
	{ "clock", "tr.tracker", "panel" },
	{ "tally", "tr.tally", "tally" },
	{ "loot", "tr.loot", "lootLog" },
	{ "bosses", "tr.bossFrames", "bossFrames" },
	{ "banners", "tr.msg", "messages", "hideBanners" },
	{ "localClock", "tr.minimap", "clock" },
	{ "flag", "tr.minimap", "pins", "flagHide" },
}

-- Часть игры прячется, только если у нас есть чем ее заменить: часы устройства известны, слой мира для пинов есть.
-- Иначе игровая часть остается (дубль лучше пустоты).
local GATE = {
	localClock = function()
		return H.Run.LocalClock() ~= nil
	end,
	flag = function()
		return H.World ~= nil and H.World.Player ~= nil
	end,
}

local function Wanted(row)
	if not S.replace then
		return false
	end
	local gate = GATE[row[1]]
	if gate and not gate() then
		return false
	end
	for i = 3, getn(row) do
		if not M.db[row[i]] then
			return false
		end
	end
	return S.pieces[row[2]] ~= nil
end

local function Grab(part, piece)
	if not H.Hud then
		return
	end
	if H.Rules and H.Rules.Required(part) then
		H.Hud.Cover(part, piece)
	else
		H.Hud.Claim(part, "tracker")
	end
end

local function Drop(part, piece)
	if not H.Hud then
		return
	end
	if H.Rules and H.Rules.Required(part) then
		H.Hud.Uncover(part, piece)
	else
		H.Hud.Release(part, "tracker")
	end
end

function Tr.SyncHud()
	for i = 1, getn(WANT) do
		local row = WANT[i]
		local part = row[1]
		local want = Wanted(row)
		if want and not S.claims[part] then
			S.claims[part] = row[2]
			Grab(part, row[2])
		elseif not want and S.claims[part] then
			Drop(part, S.claims[part])
			S.claims[part] = nil
		end
	end
end

function Tr.ClaimedParts()
	local out = {}
	for i = 1, getn(WANT) do
		if S.claims[WANT[i][1]] then
			table.insert(out, WANT[i][1])
		end
	end
	return out
end

