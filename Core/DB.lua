-- HyoukaUI: настройки (HyoukaUIDB), умолчания, схема и миграции.
--
-- В SavedVariables лежат только отличия от умолчаний: Set стирает значение, равное
-- умолчанию, поэтому смена умолчаний в новой версии не требует миграции.
-- Миграции идут один раз на ADDON_LOADED под pcall. Сбой миграции модуля: его настройки
-- возвращаются к умолчаниям, ошибка уходит в журнал (корзина "db").
-- Перед первой миграцией сессии делается одна копия HyoukaUIDB.prev.

local H = HyoukaUI

local D = {}
H.DB = D

D.defaults = {}        -- раздел -> таблица умолчаний
D.specs = {}           -- раздел -> { schema, migrations }
D.coreMigrations = {}  -- [n] = function(db): поднимает схему ядра с n-1 до n
D.targetSchema = H.SCHEMA
D.ready = false
D.backedUp = false
D.newer = false        -- сохранения написаны более новой версией: ничего не трогаем
D.stats = { migrated = 0, failed = 0, backups = 0 }
D.log = {}

-- Что не копируется в резервную копию: сама копия и данные разработки.
local BACKUP_SKIP = { prev = true, fixtures = true, probes = true, report = true }

local function Section(mod, create)
	local db = HyoukaUIDB
	if type(db) ~= "table" then
		return nil
	end
	if mod == "general" then
		return db.general
	end
	local s = db.modules and db.modules[mod]
	if not s and create and db.modules then
		s = {}
		db.modules[mod] = s
	end
	return s
end

function D.Defaults(mod, defaults)
	D.defaults[mod] = defaults or {}
end

function D.Default(mod, key)
	local d = D.defaults[mod]
	return d and d[key]
end

function D.Get(mod, key)
	local s = D.ready and Section(mod, false)
	if s then
		local v = s[key]
		if v ~= nil then
			return v
		end
	end
	local d = D.defaults[mod]
	return d and d[key]
end

-- Записать значение. Равное умолчанию стирается. Возвращает true, если значение изменилось.
function D.Set(mod, key, value)
	if not D.ready then
		return false
	end
	local old = D.Get(mod, key)
	if value == D.Default(mod, key) then
		local s = Section(mod, false)
		if s then
			s[key] = nil
		end
	else
		Section(mod, true)[key] = value
	end
	if old ~= value then
		H.Fire("SETTING", mod, key)
		return true
	end
	return false
end

-- Вернуть раздел к умолчаниям.
function D.Reset(mod)
	local s = Section(mod, false)
	if s then
		H.Wipe(s)
	end
end

-- Доступ модуля к своим настройкам: M.db.key читает значение или умолчание, писать только через Set.
function D.Module(name, defaults, spec)
	D.defaults[name] = defaults or {}
	D.specs[name] = { schema = (spec and spec.schema) or 1, migrations = (spec and spec.migrations) or {} }
	if D.ready then
		D.MigrateModule(name)
	end
	return setmetatable({}, {
		__index = function(t, key)
			return D.Get(name, key)
		end,
		__newindex = function(t, key, value)
			error("HyoukaUI: настройки пишутся через H.DB.Set(модуль, ключ, значение)", 2)
		end,
	})
end

function D.Global()
	return HyoukaUIDB and HyoukaUIDB.global
end

-- Хук резервной копии: вызывается перед первой миграцией сессии.
function D.Backup()
	if D.backedUp then
		return
	end
	D.backedUp = true
	HyoukaUIDB.prev = H.Copy(HyoukaUIDB, 8, BACKUP_SKIP)
	D.stats.backups = D.stats.backups + 1
end

-- Поднять данные с версии from до to. migs[n] поднимает с n-1 до n. Под pcall.
-- Возвращает true или false, текст ошибки.
function D.RunMigrations(data, from, to, migs)
	for n = from + 1, to do
		local fn = migs[n]
		if fn then
			local ok, err = pcall(fn, data)
			if not ok then
				return false, "миграция до версии "..n..": "..tostring(err)
			end
		end
	end
	return true
end

local function Failed(owner, err)
	D.stats.failed = D.stats.failed + 1
	table.insert(D.log, owner..": "..err)
	H.Errors.Add("db", owner..": "..err)
end

function D.MigrateModule(name)
	local spec = D.specs[name]
	local db = HyoukaUIDB
	local store = db.modules[name]
	local have = db.schemas[name]
	if not store then
		db.schemas[name] = spec.schema
		return
	end
	have = have or 1
	if have == spec.schema then
		return
	end
	if have > spec.schema then
		D.newer = true
		return
	end
	D.Backup()
	local ok, err = D.RunMigrations(store, have, spec.schema, spec.migrations)
	if not ok then
		H.Wipe(store)
		Failed(name, err)
	else
		D.stats.migrated = D.stats.migrated + 1
	end
	db.schemas[name] = spec.schema
end

-- ADDON_LOADED: создать разделы, мигрировать ядро и модули.
function D.Init()
	if type(HyoukaUIDB) ~= "table" then
		HyoukaUIDB = {}
	end
	local db = HyoukaUIDB
	local fresh = (db.schema == nil)
	local seed = fresh and next(db.modules or {}) == nil
	db.general = db.general or {}
	db.modules = db.modules or {}
	db.layout = db.layout or {}
	db.schemas = db.schemas or {}
	db.global = db.global or {}
	db.global.hud = db.global.hud or { owned = {}, cleanExit = true }
	db.global.hud.owned = db.global.hud.owned or {}

	local target = D.targetSchema
	if fresh then
		db.schema = target
	elseif db.schema > target then
		D.newer = true
	elseif db.schema < target then
		D.Backup()
		local ok, err = D.RunMigrations(db, db.schema, target, D.coreMigrations)
		if not ok then
			-- Ядро: общие настройки к умолчаниям, остальное не трогаем.
			H.Wipe(db.general)
			Failed("core", err)
		else
			D.stats.migrated = D.stats.migrated + 1
		end
		db.schema = target
	end
	D.ready = true
	if seed and H.DefaultProfile and H.DefaultProfile.auto ~= false then
		H.DefaultProfile.Apply()
	end
	for name in pairs(D.specs) do
		D.MigrateModule(name)
	end
end

-- Только для тестов: сбросить состояние и начать с пустых сохранений.
function D.Wipe()
	HyoukaUIDB = nil
	D.ready = false
	D.backedUp = false
	D.newer = false
	D.stats.migrated = 0
	D.stats.failed = 0
	D.stats.backups = 0
	H.Wipe(D.log)
	D.targetSchema = H.SCHEMA
	D.coreMigrations = {}
end
