-- HyoukaUI: Data\Plates, слой данных неймплейтов (модуль Plates). Читает AZS_* для плашек только этот файл.
--
-- Что дает слой (все без аллокаций после прогрева, кроме ответов самого движка):
--   PD.Available()        есть ли мировые якоря и проекция (без них классификация идет по именам и AZS_UnitKind)
--   PD.ReadAnchors()      каталог живых элит, стражей и боссов (AZS_GetWorldAnchors, kinds elite/guardian/boss/finalBoss,
--                         state alive, до 4 страниц по 256); записи переиспользуются. true, если чтение удалось
--   PD.Project()          проекция точек "overhead" этих якорей на экран (AZS_ProjectWorldAnchors); true, если удалась
--   PD.Count(), PD.Anchor(i) -> запись { id, kind, name, unit, on, sx, sy } (kind: elite, guardian, boss, final)
--   PD.NameKind(name)     вид по имени среди якорей: "elite" | "guardian" | "boss" | "final" | "mixed" | nil
--   PD.StaticKind(name)   запасной вид по спискам имен боссов и элит десяти зон: "boss" | "elite" | nil
--   PD.UnitKind(token)    вид юнита клиента по AZS_UnitKind: "normal" | "elite" | "boss" | "final" | nil
--   PD.version            растет, когда каталог якорей изменился (плашки перечитывают вид)
--   PD.Foreign()          загружен ли SurvivorPlates; PD.ForeignActive() - и он не в режиме ожидания
--   PD.Overlap(), PD.SetOverlap(on)   CVar nameplateLayout (overlap или stack), nil, если CVar нет
--   PD.ApplyShown(enemies, friends, friendsChosen)   стоковые ShowNameplates/HideNameplates и дружественные
--   PD.PartyCount(), PD.TargetHostile()   число членов группы клиента, враждебна ли цель
-- Мир: проекция отдает x, y в единицах WorldFrame (azs-api.md 2.9). Имена списков ниже взяты из игровых таблиц
-- десяти зон так, как их приводит SurvivorPlates; список элит и боссов в игре сверяется /hui dump plates.

local H = HyoukaUI

local PD = {}
H.PlatesData = PD

PD.version = 0

local QUERY = { kinds = { "elite", "guardian", "boss", "finalBoss" }, states = { "alive" } }
local KIND_OF = { elite = "elite", guardian = "guardian", boss = "boss", finalBoss = "final", final = "final",
	normal = "normal" }
local MAX_ANCHORS = 256

local anchors = {}        -- записи { id, kind, name, unit, on, sx, sy }
local count = 0
local named = {}          -- имя -> вид или "mixed"
local scratch = {}        -- следующий named: собирается при чтении и подменяет named, только если чтение удалось
local requests = {}       -- запросы проекции, переиспользуются
local layoutKnown = true

----------------------------------------------------------------------------------------
-- Списки имен (запасной путь классификации)
----------------------------------------------------------------------------------------

local BOSSES = {
	"Hogger", "Mother Fang", "Rhahk'Zor", "Mr. Smite", "Edwin VanCleef",
	"Naraxis", "Mor'Ladim", "Stitches", "Lupos", "Morbent Fel",
	"Doomguard Commander", "Mannoroth's Herald", "Varimathras", "Lord Hel'nurath", "Lord Kazzak",
	"Patchwerk", "Lord Blackwood", "Baron Rivendare", "Anub'Rekhan", "Kel'Thuzad",
	"Zevrim Thornhoof", "Alzzin the Wildshaper", "Tendris Warpwood", "Immol'thar", "King Gordok",
	"High Priestess Jeklik", "High Priest Venoxis", "Bloodlord Mandokir", "Jin'do the Hexxer", "Hakkar the Soulflayer",
	"Korrak the Bloodrager", "Ivus the Forest Lord", "Lokholar the Ice Lord", "Glacius the Frozen Titan", "Azuregos",
	"General Angerforge", "Warchief Rend Blackhand", "Emperor Dagran Thaurissan", "Majordomo Executus", "Nefarian",
	"Kurinnaxx", "General Rajaxx", "Princess Huhuran", "Ossirian the Unscarred", "C'Thun",
}

local ELITES = {
	"Kobold Taskmaster", "Gruff Swiftbite", "Bellygrub",
	"Nightbane Worgen Alpha", "Carrion Recluse", "Flesh Eating Abomination",
	"Felguard Elite", "Infernal", "Doomguard",
	"Crypt Fiend", "Bone Golem", "Death Knight Captain",
	"Gordunni Brute", "Warpwood Treant", "Ironbark Protector",
	"Gurubashi Berserker", "Zulian Crocolisk", "Gurubashi Champion",
	"Alterac Yeti Lord", "Mountain Giant", "Winterax Warlord",
	"Core Hound", "Black Drake", "Molten Giant",
	"Qiraji Champion", "Anubisath Sentinel", "Obsidian Destroyer",
}

local byName = {}
for i = 1, table.getn(ELITES) do
	byName[ELITES[i]] = "elite"
end
for i = 1, table.getn(BOSSES) do
	byName[BOSSES[i]] = "boss"
end

function PD.StaticKind(name)
	return name and byName[name] or nil
end

----------------------------------------------------------------------------------------
-- Каталог якорей
----------------------------------------------------------------------------------------

function PD.Available()
	return AZS_GetWorldAnchors ~= nil and AZS_ProjectWorldAnchors ~= nil
end

function PD.Count()
	return count
end

function PD.Anchor(i)
	return anchors[i]
end

function PD.NameKind(name)
	return named[name]
end

local function Trim(list, keep)
	for i = table.getn(list), keep + 1, -1 do
		table.remove(list, i)
	end
end

-- Одна запись каталога на месте i. Возвращает true, если запись отличается от прежней.
local function Put(i, e, kind)
	local rec = anchors[i]
	local changed = false
	if not rec then
		rec = { on = false, sx = 0, sy = 0 }
		anchors[i] = rec
		changed = true
	end
	if rec.id ~= e.anchorId or rec.kind ~= kind or rec.name ~= e.name then
		changed = true
	end
	rec.id, rec.kind, rec.name, rec.unit = e.anchorId, kind, e.name, e.unitId
	return changed
end

function PD.ReadAnchors()
	if not AZS_GetWorldAnchors then
		return false
	end
	local n, changed, cursor = 0, false, nil
	local fresh = scratch
	H.Wipe(fresh)
	for page = 1, 4 do
		local ok, r = pcall(AZS_GetWorldAnchors, QUERY, cursor, MAX_ANCHORS)
		if not ok or type(r) ~= "table" or type(r.entries) ~= "table" then
			return false
		end
		for i = 1, table.getn(r.entries) do
			local e = r.entries[i]
			local kind = type(e) == "table" and KIND_OF[e.kind or ""] or nil
			if kind and e.name and e.anchorId then
				n = n + 1
				if Put(n, e, kind) then
					changed = true
				end
				fresh[e.name] = fresh[e.name] and fresh[e.name] ~= kind and "mixed" or kind
			end
		end
		if not r.hasMore or not r.nextCursor then
			break
		end
		cursor = r.nextCursor
	end
	if n ~= count then
		changed = true
	end
	count = n
	Trim(anchors, n)
	named, scratch = fresh, named
	if changed then
		PD.version = PD.version + 1
	end
	return true
end

-- Проекция "overhead" всех якорей каталога. Запросы переиспользуются: после прогрева таблиц не создается.
function PD.Project()
	if count == 0 or count > MAX_ANCHORS or not AZS_ProjectWorldAnchors then
		return false
	end
	for i = 1, count do
		local rq = requests[i]
		if not rq then
			rq = { anchorId = false, attachment = "overhead", offset = { x = 0, y = 0, z = 0 } }
			requests[i] = rq
		end
		rq.anchorId = anchors[i].id
	end
	Trim(requests, count)
	local ok, r = pcall(AZS_ProjectWorldAnchors, requests)
	local entries = ok and type(r) == "table" and r.entries
	if not entries then
		return false
	end
	for i = 1, count do
		local rec, spot = anchors[i], entries[i]
		if spot and spot.state == "onScreen" and type(spot.x) == "number" and type(spot.y) == "number" then
			rec.on, rec.sx, rec.sy = true, spot.x, spot.y
		else
			rec.on = false
		end
	end
	return true
end

----------------------------------------------------------------------------------------
-- Вид юнита клиента, SurvivorPlates рядом, CVar и стоковое включение плашек
----------------------------------------------------------------------------------------

function PD.UnitKind(token)
	if not AZS_UnitKind then
		return nil
	end
	local ok, kind = pcall(AZS_UnitKind, token)
	if not ok or not kind then
		return nil
	end
	return KIND_OF[kind]
end

function PD.Foreign()
	if IsAddOnLoaded then
		local ok, loaded = pcall(IsAddOnLoaded, "SurvivorPlates")
		if ok and loaded then
			return true
		end
	end
	return H.Env.SurvivorPlatesRegistry ~= nil
end

-- SurvivorPlates загружен и не ушел в режим ожидания (его SurvivorPlates_Standby): тогда он красит те же плашки.
function PD.ForeignActive()
	return PD.Foreign() and not H.Env.SurvivorPlates_Standby
end

local function Layout()
	if not layoutKnown then
		return nil
	end
	local ok, value = pcall(GetCVar, "nameplateLayout")
	if not ok then
		layoutKnown = false
		return nil
	end
	return value
end

-- true, если плашки не раздвигаются (CVar overlap); nil, если в игре нет такой настройки.
function PD.Overlap()
	local v = Layout()
	if v == nil then
		return nil
	end
	return v == "overlap"
end

function PD.SetOverlap(on)
	if Layout() ~= nil then
		SetCVar("nameplateLayout", on and "overlap" or "stack")
	end
end

-- Стоковые функции клиента 1.12 берутся из окружения (их может не быть в этой игре: тогда вызов пропускается).
local function Call(name)
	local fn = H.Env[name]
	if type(fn) == "function" then
		fn()
		return true
	end
	return false
end

-- Стоковое включение плашек: врагов и друзей. Движок не хранит признак, поэтому говорится заново (то же слово два раза
-- ничего не меняет, SurvivorPlates делает так же). Глобалы NAMEPLATES_ON и FRIENDNAMEPLATES_ON ставит игра.
function PD.ApplyShown(enemies, friends, friendsChosen)
	if enemies then
		if Call("ShowNameplates") then
			setglobal("NAMEPLATES_ON", 1)
		end
	elseif Call("HideNameplates") then
		setglobal("NAMEPLATES_ON", nil)
	end
	if friends then
		if Call("ShowFriendNameplates") then
			setglobal("FRIENDNAMEPLATES_ON", 1)
		end
	elseif friendsChosen and Call("HideFriendNameplates") then
		setglobal("FRIENDNAMEPLATES_ON", nil)
	end
end

-- Число членов группы клиента и враждебна ли цель (стоковые функции, чтение).
function PD.PartyCount()
	local fn = H.Env.GetNumPartyMembers
	return fn and fn() or 0
end

-- Положение курсора в пикселях экрана (стоковая GetCursorPosition) или nil.
function PD.Cursor()
	local fn = H.Env.GetCursorPosition
	if fn then
		return fn()
	end
	return nil
end

function PD.TargetHostile()
	local fn = H.Env.UnitCanAttack
	return fn and UnitExists("target") and fn("player", "target") and true or false
end

function PD.Reset()
	for i = table.getn(anchors), 1, -1 do
		table.remove(anchors, i)
	end
	count = 0
	H.Wipe(named)
	PD.version = PD.version + 1
end

H.Poll.AddLayer("plates", PD.Reset)
