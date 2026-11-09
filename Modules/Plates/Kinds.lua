-- HyoukaUI: Modules\Plates\Kinds, вид плашки: обычный враг, элита, страж логова, босс, финальный босс, друг (группа, питомец,
-- тотем). Клиент выдает плашку юниту из пула и заполняет ее за кадр-два (имя, цвет и здоровье стоковой полосы), поэтому
-- вид перечитывается при смене любого из них, а не только имени.
--
-- Откуда вид врага (по убыванию надежности): якорь мира (каталог живых элит, стражей и боссов Data\Plates, спроецированный
-- на экран; каждый якорь забирает ближайшую плашку своего имени, до NEAR единиц от точки над юнитом, плашка держит захват
-- CLAIM_LASTS секунд); AZS_UnitKind цели; имя среди якорей; имя по спискам Data\Plates и по списку забега H.Units (страж
-- называется как элиты его зоны, его отличает здоровье). Остальные плашки обычные враги.
-- Друг узнается по цвету стоковой полосы (зеленая или синяя), его вид: группа (имя среди party1..4), тотем, иначе питомец.
--
-- Kn.Rebuild()                      пересобрать списки по H.Units (UNITS_CHANGED), версия видов растет
-- Kn.Reclassify(o, name, lo, hi, friendly)   базовый вид плашки o (o.baseKind) и цвет класса (o.cr, o.cg, o.cb)
-- Kn.Resolve(o, name, isTarget, now) -> kind, итоговый вид с захватом и целью
-- Kn.Claim()                        якоря забирают плашки (раз в 0.1 с, после PD.Project)

local H = HyoukaUI

local Pl = H.Plates

local Kn = {}
Pl.Kinds = Kn

local NEAR = 24
local CLAIM_LASTS = 0.6

local live = {}        -- имя -> "boss" | "final" | "elite" по списку забега
local guardians = {}   -- имя -> массив максимальных здоровий живых стражей

local FRIEND = { party = true, pet = true, totem = true }

function Kn.Rebuild()
	H.Wipe(live)
	guardians = {}
	local all = H.Units and H.Units.All() or nil
	if all then
		for i = 1, table.getn(all) do
			local u = all[i]
			local name, kind = u.name, u.kind
			if name then
				if kind == "guardian" then
					local list = guardians[name]
					if not list then
						list = {}
						guardians[name] = list
					end
					table.insert(list, tonumber(u.hpm) or 0)
				elseif kind == "boss" or kind == "final" then
					live[name] = kind
				elseif kind == "elite" and not live[name] then
					live[name] = "elite"
				end
			end
		end
	end
	Pl.S.kindsVer = Pl.S.kindsVer + 1
end

-- Вид врага по имени и максимальному здоровью, если клиент его знает (most).
function Kn.Classify(name, most)
	if not name then
		return "normal"
	end
	local named = H.PlatesData.StaticKind(name) or live[name]
	local lair = guardians[name]
	if lair then
		for i = 1, table.getn(lair) do
			if most and math.abs(most - lair[i]) <= 1 then
				return "guardian"
			end
		end
		if not named then
			return "guardian"
		end
	end
	return named or "normal"
end

-- Класс члена группы по имени (party1..party4) или nil.
function Kn.PartyClass(name)
	if not name then
		return nil
	end
	for i = 1, 4 do
		local unit = "party"..i
		if UnitExists(unit) and UnitName(unit) == name then
			local _, class = UnitClass(unit)
			return class or "?"
		end
	end
	return nil
end

local function IsTotem(name)
	if not name then
		return false
	end
	return name == "Totem" or string.find(name, " Totem$") ~= nil or string.find(name, "\208\162\208\190\209\130\208\181\208\188", 1, true) ~= nil
end

function Kn.FriendKind(name)
	if Kn.PartyClass(name) then
		return "party"
	end
	if IsTotem(name) then
		return "totem"
	end
	return "pet"
end

function Kn.Reclassify(o, name, lo, hi, friendly)
	o.lastName, o.lastFriend, o.lastHigh = name, friendly, hi
	o.kindsVer = Pl.S.kindsVer
	o.name:SetText(name or "")
	local known = lo and hi and hi - lo ~= 100 and hi > 1
	if friendly then
		o.baseKind = Kn.FriendKind(name)
	else
		o.baseKind = Kn.Classify(name, known and hi or nil)
	end
	o.cr, o.cg, o.cb = nil, nil, nil
	if o.baseKind == "party" then
		local class = Kn.PartyClass(name)
		if class and H.Theme and H.Theme.ClassColor then
			o.cr, o.cg, o.cb = H.Theme.ClassColor(class)
		end
	end
	o.painted = nil
end

--@frame
function Kn.Resolve(o, name, isTarget, now)
	local kind = o.baseKind
	if FRIEND[kind] then
		return kind
	end
	local S = Pl.S
	if o.claim and o.claimName == name and now - o.claimAt < CLAIM_LASTS then
		return o.claim
	end
	if isTarget and S.targetKind then
		return S.targetKind
	end
	local named = H.PlatesData.NameKind(name)
	if named and named ~= "mixed" then
		return named
	end
	return kind
end

-- Каждый якорь на экране забирает ближайшую плашку своего имени (по одной на якорь). Плашки лежат в единицах WorldFrame.
function Kn.Claim()
	local PD = H.PlatesData
	local S = Pl.S
	local n = PD.Count()
	if n == 0 or S.visN == 0 then
		return
	end
	S.round = S.round + 1
	local round = S.round
	local world = WorldFrame:GetEffectiveScale()
	local now = GetTime()
	local vis = S.vis
	for i = 1, n do
		local a = PD.Anchor(i)
		if a.on then
			local best, bestFar
			for j = 1, S.visN do
				local o = vis[j]
				if o.lastName == a.name and o.takenRound ~= round then
					local x, y = o.plate:GetCenter()
					if x then
						local scale = o.plate:GetEffectiveScale() / world
						local dx, dy = x * scale - a.sx, y * scale - a.sy
						local far = dx * dx + dy * dy
						if far <= NEAR * NEAR and (not bestFar or far < bestFar) then
							best, bestFar = o, far
						end
					end
				end
			end
			if best then
				best.takenRound = round
				best.claim, best.claimName, best.claimAt, best.unit = a.kind, a.name, now, a.unit
			end
		end
	end
end
