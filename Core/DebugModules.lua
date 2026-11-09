-- HyoukaUI: отладка и управление модулями (этап 2-5): /hui modules, /hui module <имя|all> <off|alongside|replace>,
-- дампы frames, build, stats, world, дополнение дампа meter и строки модулей в /hui selftest.
-- Читает модули только через их открытые функции и только при вызове команды (в кадре ничего не считает); отсутствующий модуль
-- (файл не загружен) молча пропускается. Загружается после Core\DebugData.lua, модули к этому моменту уже загружены.

local H = HyoukaUI
local D = H.Debug
local X = D.Extra

local function YN(v)
	return v and "да" or "нет"
end

local function Add(out, text)
	table.insert(out, text)
end

-- Режим на деле: Вместо превращается в Рядом, пока на экране кадры SurvivorUI (у каждого модуля своя проверка).
-- Возвращает "off", "side" или "replace"; "?" если модуль не отвечает.
local EFFECTIVE = {
	frames = function()
		return H.Frames and H.Frames.EffectiveMode and H.Frames.EffectiveMode()
	end,
	meter = function()
		return H.MeterUI and H.MeterUI.EffectiveMode and (H.MeterUI.EffectiveMode())
	end,
	build = function()
		return H.Build and H.Build.Mode and H.Build.Mode()
	end,
	tracker = function()
		local Tr = H.Tr
		if not Tr or not Tr.IsEnabled then
			return nil
		end
		if not Tr.IsEnabled() then
			return "off"
		end
		return Tr.IsReplace() and "replace" or "side"
	end,
}

function D.EffectiveMode(name)
	local fn = EFFECTIVE[name]
	if not fn then
		return H.GetMode(name)
	end
	local ok, mode = pcall(fn)
	if ok and mode then
		return mode
	end
	return H.GetMode(name)
end

local function ModeLabel(mode)
	return H.MODE_LABELS[mode] or tostring(mode)
end

-- Строки списка модулей (без модулей ядра): имя, режим, режим на деле, включен, приостановлен, ошибки, claims.
function D.ModuleLines()
	local out = {}
	for i = 1, table.getn(H.moduleList) do
		local m = H.moduleList[i]
		if not m.internal then
			local req = H.GetMode(m.name)
			local eff = D.EffectiveMode(m.name)
			local text = m.name.."  режим "..ModeLabel(req)
			if eff ~= req then
				text = text.." (на деле "..ModeLabel(eff)..")"
			end
			text = text.."  включен "..YN(m.enabled).."  приостановлен "..YN(m.suspended).."  ошибок "..m.errors
			Add(out, text)
		end
	end
	local claims, covers, owned = H.Hud.Stats()
	Add(out, "claims "..claims.."  покрытий "..covers.."  частей игры скрыто нами "..owned.."  запаркованно "..H.counters.parks)
	Add(out, "/hui module <имя|all> <off|alongside|replace>")
	return out
end

local WORDS = { off = "off", ["выкл"] = "off", side = "side", alongside = "side", ["рядом"] = "side", replace = "replace",
	["вместо"] = "replace" }

local function SetOne(name, mode)
	local m = H.modules[name]
	if not m or m.internal then
		H.Print("нет такого модуля: "..tostring(name))
		return false
	end
	H.SetMode(name, mode)
	local eff = D.EffectiveMode(name)
	H.Print(name..": режим "..ModeLabel(mode)..(eff ~= mode and (", на деле "..ModeLabel(eff)) or "")..", включен "..YN(m.enabled))
	return true
end

H.Slash.Register("modules", function()
	D.Show(D.ModuleLines(), "modules")
end, "modules - список модулей, их режимы и захваты частей игры")

H.Slash.Register("module", function(rest)
	local _, _, name, word = string.find(rest or "", "^(%S+)%s+(%S+)$")
	local mode = word and WORDS[string.lower(word)]
	if not name or not mode then
		D.Show(D.ModuleLines(), "modules")
		return
	end
	name = string.lower(name)
	if name == "all" then
		for i = 1, table.getn(H.moduleList) do
			local m = H.moduleList[i]
			if not m.internal then
				SetOne(m.name, mode)
			end
		end
		return
	end
	SetOne(name, mode)
end, "module <имя|all> <off|alongside|replace> - режим модуля (frames, meter, tracker, build)")

----------------------------------------------------------------------------------------
-- Дампы
----------------------------------------------------------------------------------------

X.modules = function(out)
	local lines = D.ModuleLines()
	for i = 1, table.getn(lines) do
		Add(out, lines[i])
	end
end

X.frames = function(out)
	local F = H.Frames
	if not F then
		Add(out, "Frames: модуль не загружен")
		return
	end
	Add(out, "== Frames ==")
	Add(out, "режим "..tostring(H.GetMode("frames")).."  на деле "..tostring(F.mode).."  кусков "..tostring(F.stats and F.stats.pieces))
	if F.Selftest then
		local lines = F.Selftest()
		for i = 1, table.getn(lines) do
			Add(out, lines[i])
		end
	end
	Add(out, "claims levels "..H.Hud.ClaimCount("levels").."  покрытий build "..H.Hud.CoverCount("build").."  запаркованно "..H.Parking.Count())
	local ids = { "col.main", "col.class", "col.buffs", "col.statics", "col.utility", "col.xp", "uf.player", "uf.target", "uf.targetAuras",
		"uf.buffs", "uf.debuffs", "uf.levelup", "ui.micro" }
	for i = 1, table.getn(ids) do
		local l, t, w, h = H.Layout.Rect(ids[i])
		Add(out, "  "..ids[i].."  "..(l and (string.format("%.1f", w).." x "..string.format("%.1f", h).." AS") or "нет"))
	end
end

X.build = function(out)
	local B = H.Build
	if not B then
		Add(out, "Build: модуль не загружен")
		return
	end
	Add(out, "== Build ==")
	Add(out, "режим "..tostring(H.GetMode("build")).."  на деле "..tostring(B.Mode()).."  SurvivorUI занят "..YN(B.SurvivorActive()))
	Add(out, "покрытий части build "..H.Hud.CoverCount("build").."  скрыта нами "..YN(H.Hud.WantsHidden("build")))
	Add(out, "окно персонажа открыто "..YN(B.Character and B.Character.IsOpen and B.Character.IsOpen())
		.."  обертка ToggleCharacter "..YN(B.Character and B.Character.WrapActive and B.Character.WrapActive()))
	Add(out, "статы забега: данные есть "..YN(H.Stats and H.Stats.Has()))
end

local prevMeter = X.meter
X.meter = function(out)
	if prevMeter then
		prevMeter(out)
	end
	local MU = H.MeterUI
	if not MU then
		return
	end
	Add(out, "== Meter (док) ==")
	local eff = MU.EffectiveMode()
	Add(out, "режим "..tostring(H.GetMode("meter")).."  на деле "..tostring(eff).."  claims meter "..H.Hud.ClaimCount("meter")
		.."  док создан "..YN(MU.Dock.Frame()).."  разбивка открыта "..YN(MU.Breakdown.IsOpen()))
	for i = 1, 2 do
		local sec = MU.Dock.Section(i)
		local items = sec and sec.view and sec.view.items
		if items then
			Add(out, "колонка "..i..": строк "..tostring(sec.view.n))
			local rows = sec.list and sec.list.huiRows
			for j = 1, rows and math.min(table.getn(rows), 8) or 0 do
				local r = rows[j]
				local tx = r.huiIcon
				Add(out, "  кадр "..j..": "..tostring(r.huiItem and r.huiItem.name).." показан "..tostring(r:IsShown()).." знач "..tostring(r.huiHasIcon).." текст.показана "..tostring(tx and tx:IsShown()).." tex "..tostring(tx and tx:GetTexture()).." ключ "..tostring(r.huiIconKey).." w "..tostring(tx and tx:GetWidth()))
			end
			for j = 1, math.min(tonumber(sec.view.n) or 0, 8) do
				local it = items[j]
				Add(out, "  "..tostring(it.name).."  icon="..tostring(it.icon).."  class="..tostring(it.classKey).."  owner="..tostring(it.ownerId).."  key="..tostring(it.sourceKey))
			end
		end
	end
end

X.stats = function(out)
	Add(out, "== Stats (AZS_STATS через H.Stats) ==")
	Add(out, "данные есть "..YN(H.Stats.Has()))
	local keys = { "hp", "dmg", "cd", "crit", "cm", "arm", "area", "cnt", "echo", "spd", "reg", "pick", "xp", "gold", "luck" }
	local line = ""
	for i = 1, table.getn(keys) do
		line = line..keys[i].."="..tostring(H.Stats.Get(keys[i])).." "
	end
	Add(out, line)
end

X.world = function(out)
	local W = H.World
	Add(out, "== World (положение, сундуки, боссы) ==")
	local x, y, z, f = W.Player()
	Add(out, "герой "..(x and (string.format("%.1f", x)..", "..string.format("%.1f", y)..", facing "..tostring(f)) or "положение не известно"))
	Add(out, "сундуков "..table.getn(W.Chests()).."  боссов в якорях "..table.getn(W.Bosses()))
end

----------------------------------------------------------------------------------------
-- selftest: строки модулей. Приемка не меняется: при Выкл и Рядом claims, parks и hudOwned нулевые.
----------------------------------------------------------------------------------------

table.insert(D.SelftestParts, function(L)
	if H.Frames and H.Frames.Selftest then
		local ok, lines = pcall(H.Frames.Selftest)
		if ok and lines then
			for i = 1, table.getn(lines) do
				Add(L, lines[i])
			end
		end
	end
	local MU = H.MeterUI
	if MU then
		Add(L, "meter: режим "..tostring(H.GetMode("meter"))..", на деле "..tostring(MU.EffectiveMode())..", claims meter "..H.Hud.ClaimCount("meter")
			..", док создан "..YN(MU.Dock.Frame()))
	end
	local Tr = H.Tr
	if Tr then
		Add(L, "tracker: режим "..tostring(H.GetMode("tracker"))..", захвачено частей игры "..table.getn(Tr.ClaimedParts())
			..", показано сообщений "..tostring(Tr.MsgCount and Tr.MsgCount()))
	end
	if H.Build then
		Add(L, "build: режим "..tostring(H.GetMode("build"))..", на деле "..tostring(H.Build.Mode())..", покрытий build "..H.Hud.CoverCount("build"))
	end
	Add(L, "Stats: данные есть "..YN(H.Stats.Has())..".  World: герой "..YN(H.World.Player() ~= nil)..", сундуков "..table.getn(H.World.Chests()))
end)

----------------------------------------------------------------------------------------
-- /hui watch <панель|id куска> [секунд]: запись смен текста всех строк панели с частотой кадров. Нужна для поиска мигания:
-- строка, которая возвращается к прежнему значению быстрее чем за 2 с (A, B, A), попадает в "возвраты".
-- Панели: tracker (tr.tracker, tr.tally, tr.thisRun, tr.bars), build, frames, meter; или любой id куска раскладки.
----------------------------------------------------------------------------------------

local WATCH_SETS = {
	tracker = { "tr.tracker", "tr.tally", "tr.thisRun", "tr.bars", "tr.barsEmph", "tr.msg", "tr.loot" },
	build = { "build.list", "uf.jewelry" },
	frames = { "col.main", "col.utility", "col.buffs", "col.statics", "uf.player", "uf.target", "col.xp" },
	meter = { "mt.dock" },
}

local W = { fs = {}, piece = {}, last = {}, prev = {}, since = {}, chg = {}, flip = {}, hist = {}, n = 0, untilT = 0, frame = nil }

local function WatchCollect(frame, pieceId, depth)
	if depth > 5 then
		return
	end
	local regions = { frame:GetRegions() }
	for i = 1, table.getn(regions) do
		local r = regions[i]
		if r.GetObjectType and r:GetObjectType() == "FontString" then
			local n = W.n + 1
			W.n = n
			W.fs[n], W.piece[n] = r, pieceId
			W.last[n], W.prev[n], W.since[n] = r:GetText() or "", "", 0
			W.chg[n], W.flip[n], W.hist[n] = 0, 0, ""
		end
	end
	local kids = { frame:GetChildren() }
	for i = 1, table.getn(kids) do
		WatchCollect(kids[i], pieceId, depth + 1)
	end
end

local function WatchFinish()
	if W.frame then
		W.frame:SetScript("OnUpdate", nil)
	end
	local idx = {}
	for n = 1, W.n do
		if W.chg[n] > 0 then
			table.insert(idx, n)
		end
	end
	table.sort(idx, function(a, b)
		if W.flip[a] ~= W.flip[b] then
			return W.flip[a] > W.flip[b]
		end
		return W.chg[a] > W.chg[b]
	end)
	local out = {}
	table.insert(out, "строк под наблюдением: "..W.n..", менявшихся: "..table.getn(idx))
	for k = 1, math.min(table.getn(idx), 16) do
		local n = idx[k]
		local x, y = W.fs[n]:GetLeft(), W.fs[n]:GetTop()
		table.insert(out, string.format("[%s] (%d,%d) смен %d, возвратов A-B-A %d: %s", W.piece[n], x or 0, y or 0, W.chg[n], W.flip[n], W.hist[n]))
	end
	if table.getn(idx) == 0 then
		table.insert(out, "ни одна строка не менялась: выбери панель, на которой что-то идет (нужен забег)")
	end
	D.Show(out, "watch")
	W.active = false
end

local function WatchStep()
	local now = H.Now()
	for n = 1, W.n do
		local fs = W.fs[n]
		local txt = fs:GetText() or ""
		if not fs:IsVisible() then
			txt = "<скрыт>"
		end
		if txt ~= W.last[n] then
			W.chg[n] = W.chg[n] + 1
			if txt == W.prev[n] and now - W.since[n] < 2 then
				W.flip[n] = W.flip[n] + 1
			end
			W.prev[n], W.last[n], W.since[n] = W.last[n], txt, now
			local h = W.hist[n].."|"..txt
			if string.len(h) > 150 then
				h = string.sub(h, string.len(h) - 149)
			end
			W.hist[n] = h
		end
	end
	if now >= W.untilT then
		WatchFinish()
	end
end

H.Slash.Register("watch", function(rest)
	local _, _, what, secs = string.find(rest or "", "^(%S*)%s*(%d*)$")
	what = (what and what ~= "") and what or "tracker"
	secs = tonumber(secs) or 20
	if secs > 120 then
		secs = 120
	end
	if W.active then
		return
	end
	W.n = 0
	local list = WATCH_SETS[what] or { what }
	for i = 1, table.getn(list) do
		local fr = H.Layout.Frame and H.Layout.Frame(list[i])
		if fr and fr.GetRegions then
			WatchCollect(fr, list[i], 0)
		end
	end
	if W.n == 0 then
		H.Print("watch: у выбранного не нашлось строк текста (панель выключена или нет такого куска)")
		return
	end
	W.active = true
	W.untilT = H.Now() + secs
	if not W.frame then
		W.frame = CreateFrame("Frame", nil, UIParent)
	end
	H.Script("debug", W.frame, "OnUpdate", WatchStep)
	H.Print("watch: пишу "..W.n.." строк "..secs.." с, результат появится в окне отладки")
end, "watch <tracker|build|frames|meter|id куска> [секунд] - запись мигающих текстов")
