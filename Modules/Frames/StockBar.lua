-- HyoukaUI: Frames\StockBar, стоковые рамки и части HUD игры в режиме Вместо (plan 3.1 "Обходы", раздел 4).
--
-- В режиме Вместо (и только в нем; "Рядом" и "Выкл" ничего не трогают):
--  * Park (H.Park) под скрытый кадр: MainMenuBar (на нем же ActionButton1-12, микрокнопки, опыт: слоты 1-6 и 12
--    остаются читаемыми через GetActionCooldown/HasAction/GetActionTexture, автокаст идет, проба 0.2),
--    BonusActionBarFrame, PlayerFrame, TargetFrame, BuffFrame, TemporaryEnchantFrame, ReputationWatchBar.
--    Кадры берутся по имени из окружения, чего нет в клиенте - пропускается. Выпадающие меню юнитов остаются
--    рабочими (проба 0.10 для незапаркованного PlayerFrame; при запаркованном НЕ ПРОВЕРЕНО).
--  * Claim части HUD "levels" (свой квадрат уровней), если кусок Level Up включен.
--  * Cover("build", "col.utility"): игровая часть "build" скрывается, только когда покрыты ВСЕ три куска двух
--    модулей (GameRules.cover: build.list, uf.jewelry, col.utility): пока Build не покрыт, она остается видимой.
-- Парковку держит Park.Reassert (раз в секунду), здесь он еще и сразу на PHASE_CHANGED, LEVEL_CHANGED, WORLD, RUN_STARTED
-- (вернется ли стоковая панель после уровня и карточек - НЕ ПРОВЕРЕНО, проба 0.2).
-- Выключение модуля или переход в Рядом возвращает все: Unpark, Release, Uncover.
-- Опция parkStock = false оставляет claims, но стоковые кадры не трогает.

local H = HyoukaUI
local F = H.Frames

local S = { parked = false, levels = false, cover = false }
F.StockBar = S

local part = F.Part("stock", {})

local OWNER = "frames"
S.NAMES = { "MainMenuBar", "BonusActionBarFrame", "PlayerFrame", "TargetFrame", "BuffFrame",
	"TemporaryEnchantFrame", "ReputationWatchBar" }

local function SyncPark(want)
	if want and not S.parked then
		S.parked = true
		for i = 1, table.getn(S.NAMES) do
			local fr = H.Env[S.NAMES[i]]
			if type(fr) == "table" and fr.SetParent then
				H.Park(fr, OWNER)
			end
		end
	elseif not want and S.parked then
		S.parked = false
		H.Unpark(OWNER)
	end
end

local function SyncHud(replace)
	local wantLevels = replace and F.Opt("showLevelUp") and true or false
	if wantLevels and not S.levels then
		S.levels = true
		H.Hud.Claim("levels", OWNER)
	elseif not wantLevels and S.levels then
		S.levels = false
		H.Hud.Release("levels", OWNER)
	end
	local wantCover = replace and F.Opt("showUtility") and true or false
	if wantCover and not S.cover then
		S.cover = true
		H.Hud.Cover("build", "col.utility")
	elseif not wantCover and S.cover then
		S.cover = false
		H.Hud.Uncover("build", "col.utility")
	end
end

function S.Apply(mode)
	local replace = (mode == "replace")
	SyncPark(replace and F.Opt("parkStock"))
	SyncHud(replace)
end

function S.Reassert()
	if S.parked then
		H.Parking.Reassert()
	end
	H.Hud.Reassert()
end

function part.Enable(mode)
	S.Apply(mode)
end

function part.Mode(mode)
	S.Apply(mode)
end

function part.Disable()
	S.Apply("off")
end

function part.Setting(key)
	if key == "parkStock" or key == "showLevelUp" or key == "showUtility" then
		S.Apply(F.mode)
	end
end

-- Выход из игры: ядро уже вернуло кадры и части HUD (UnparkAll, RestoreAll), здесь только забываются флаги.
F.On("LOGOUT", function()
	S.parked, S.levels, S.cover = false, false, false
end)
F.On("PHASE_CHANGED", S.Reassert)
F.On("LEVEL_CHANGED", S.Reassert)
F.On("RUN_STARTED", S.Reassert)
F.On("WORLD", S.Reassert)
