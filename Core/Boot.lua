-- HyoukaUI: жизненный цикл (plan 2.5).
--   загрузка файлов      - только определения
--   ADDON_LOADED         - DB и миграции
--   PLAYER_LOGIN         - OnInit всех модулей, затем OnEnable включенных
--   PLAYER_ENTERING_WORLD - только обновление состояния (OnWorld модулей)
--   PLAYER_LOGOUT        - отчет в HyoukaUIDB.report, cleanExit

local H = HyoukaUI

local B = {}
H.Boot = B

B.loaded = false
B.logins = 0
B.worlds = 0

function B.OnLoaded(ev, name)
	if name ~= H.name or B.loaded then
		return
	end
	B.loaded = true
	H.DB.Init()
	H.Fire("LOADED")
end

function B.OnLogin()
	B.logins = B.logins + 1
	H.booted = true
	H.StartModules()
	H.Fire("LOGIN")
end

function B.OnWorld()
	B.worlds = B.worlds + 1
	for i = 1, table.getn(H.moduleList) do
		local m = H.moduleList[i]
		if m.enabled then
			H.CallModule(m, "OnWorld")
		end
	end
	H.Fire("WORLD")
end

-- Отчет для ассистента: читается из файла SavedVariables после выхода или /reload.
function B.WriteReport()
	if type(HyoukaUIDB) ~= "table" then
		return
	end
	local report = H.Errors.Report()
	local ok, lines, passed = pcall(H.Debug.SelftestLines)
	report.checks = {}
	if ok then
		report.checks.selftest = lines
		report.checks.stage0Passed = passed and true or false
	else
		report.checks.selftest = { "ошибка selftest: "..tostring(lines) }
	end
	report.hudOwned = {}
	local hud = HyoukaUIDB.global and HyoukaUIDB.global.hud
	if hud and hud.owned then
		for k, v in pairs(hud.owned) do
			report.hudOwned[k] = v
		end
	end
	report.claims = H.counters.claims
	report.parks = H.counters.parks
	HyoukaUIDB.report = report
	if hud then
		hud.cleanExit = true
	end
end

function B.OnLogout()
	H.Fire("LOGOUT")
	B.WriteReport()
end

H.On("ADDON_LOADED", "boot", B.OnLoaded)
H.On("PLAYER_LOGIN", "boot", B.OnLogin)
H.On("PLAYER_ENTERING_WORLD", "boot", B.OnWorld)
H.On("PLAYER_LOGOUT", "boot", B.OnLogout)
