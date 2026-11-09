-- HyoukaUI: Core\DefaultProfile, стартовый профиль автора: его режимы модулей и настройки.
--
-- Применяется один раз на чистой установке (в HyoukaUIDB еще нет схемы), чтобы новый игрок сразу получил готовый интерфейс.
-- Команда /hui preset default применяет его заново поверх своих настроек (потом /reload). Здесь только то, что одинаково
-- на любом экране: режимы, переключатели и размеры; положения, зависящие от разрешения, сюда не кладем.
-- Менять профиль: правка таблицы PROFILE ниже. Ключи как в HyoukaUIDB: general, modules[имя], layout[id].

local H = HyoukaUI

local PROFILE = {
	general = { moveKey = "alt" },
	modules = {
		frames = { mode = "replace", rank = false },
		meter = { mode = "replace", slot1 = "dps" },
		tracker = { mode = "replace", pinBosses = true },
		build = { mode = "replace" },
		plates = { mode = "replace", dimPct = 100, normalPct = 100, w_normal = 166 },
		chat = { mode = "replace" },
	},
	layout = {
		["tr.bars"] = { p = "TOPRIGHT", rp = "TOPRIGHT", x = -3, y = -231 },
	},
}

local P = {}
H.DefaultProfile = P

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			Merge(dst[k], v)
		else
			dst[k] = v
		end
	end
end

-- Кладет профиль в HyoukaUIDB. Режим модулей и настройки перезаписываются, остальное не трогается.
function P.Apply()
	local db = HyoukaUIDB
	if type(db) ~= "table" then
		return false
	end
	db.general = db.general or {}
	db.modules = db.modules or {}
	db.layout = db.layout or {}
	db.schemas = db.schemas or {}
	Merge(db.general, PROFILE.general)
	Merge(db.layout, PROFILE.layout)
	for name, settings in pairs(PROFILE.modules) do
		db.modules[name] = db.modules[name] or {}
		Merge(db.modules[name], settings)
		db.schemas[name] = db.schemas[name] or 1
	end
	return true
end

H.Slash.Register("preset", function(arg)
	if arg == "default" then
		P.Apply()
		H.Print(H.L.profile_applied)
	else
		H.Print(H.L.profile_help)
	end
end, "preset default - author default preset")
