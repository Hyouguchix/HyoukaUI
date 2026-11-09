-- HyoukaUI: отладка слоев данных, Hud, Park и Visibility (этап 1a).
--
-- /hui dump <run|zone|spells|units|party|schedule|loadout|meter|hud|park|poll>: вид слоя данных
-- (то, что видят модули), для run, zone, spells, units и party следом идут сырые глобалы движка.
-- /hui hud: состояние всех 11 частей, claims, покрытия, owned. /hui hud reset: аварийный возврат всего.
-- selftest получает строки Hud, Park, Poll, Spells (расхождение источников CD), MeterData, Visibility.
-- Читает данные через API слоев и только на выводе по команде: в кадре ничего не считает.

local H = HyoukaUI

local D = H.Debug
local X = D.Extra

local function F(v, fmt)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format(fmt or "%.2f", v)
end

local function YN(v)
	return v and "да" or "нет"
end

local function Add(out, text)
	table.insert(out, text)
end

----------------------------------------------------------------------------------------
-- Дампы слоев
----------------------------------------------------------------------------------------

X.run = function(out)
	local R = H.Run
	Add(out, "== Run (слой данных) ==")
	Add(out, "фаза "..tostring(R.Phase()).."  runId "..tostring(R.Id()).."  часы "..F(R.Time()).."  длина "..F(R.Length())
		.."  до финала "..F(R.Left()))
	Add(out, "бесконечный "..YN(R.IsEndless()).."  конец забега (RUN_ENDED) "..tostring(R.Ended()).."  после /reload "..YN(R.ReloadedMidRun())
		.."  герой лежит "..YN(R.IsDowned()))
	Add(out, "метка начала "..F(R.StartStamp(), "%.3f").."  уровень "..tostring(R.Level()).."  накоплено "..tostring(R.StoredLevels())
		.."  аффиксы "..tostring(R.Affixes()))
	local meter, endScreen = R.Damage()
	Add(out, "урон: счетчик "..tostring(meter).."  экран итогов "..tostring(endScreen))
	local hh, mm = R.LocalClock()
	Add(out, "часы устройства "..(hh and string.format("%02d:%02d", hh, mm) or "нет"))
end

X.zone = function(out)
	local O = H.Hero
	Add(out, "== Hero (слой данных) ==")
	local r, g, b = O.ClassColor()
	local race, rname = O.Race()
	Add(out, "класс "..tostring(O.Class()).." ("..tostring(O.ClassName())..")  имя "..tostring(O.Name()).."  раса "..tostring(race).." / "..tostring(rname)
		.."  пол "..tostring(O.Sex()))
	Add(out, "цвет класса "..F(r).." "..F(g).." "..F(b))
	local hp, hpm, sh = O.Health()
	Add(out, "здоровье "..tostring(hp).." / "..tostring(hpm).."  щит "..tostring(sh))
	Add(out, "зона из "..(AZS_ZONE_UPDATED and "строки сервера" or "снимка DB или пусто").."  карта "..tostring(H.Run.Zone("map")).."  зона "..tostring(H.Run.Zone("zone")))
end

X.spells = function(out)
	local P = H.Spells
	local n = P.Count()
	Add(out, "== Spells (слой данных), записей "..n.." ==")
	local worst, compared = P.Reconcile()
	for i = 1, n do
		local slot, src = P.SlotOf(i)
		local conv = P.ConventionSlot(i)
		local start, dur = P.Cooldown(i)
		local aStart, aDur = P.ActionCooldown(i)
		Add(out, i..": "..tostring(P.Key(i)).." r"..tostring(P.Rank(i)).." id "..tostring(P.SpellId(i)).."  слот "..tostring(slot).." ("..tostring(src)
			..(slot ~= conv and (", по конвенции "..tostring(conv).." РАСХОДИТСЯ") or "")..")  CD расчет "..F(start, "%.2f").."+"..F(dur)
			.." ост. "..F(P.Remaining(i)).."  GetActionCooldown "..F(aStart, "%.2f").."+"..F(aDur).."  пол "..YN(P.IsFloor(i))
			..(P.IsRacial(i) and "  расовая" or ""))
	end
	Add(out, "расхождение двух источников ост. CD: сейчас "..F(worst, "%.3f").." с по "..compared.." способностям, максимум за сессию "..F(P.stats.maxDelta, "%.3f"))
end

X.units = function(out)
	local U = H.Units
	Add(out, "== Units (слой данных) ==")
	Add(out, "свежий список "..YN(U.IsFresh()).."  всего "..U.Count().."  боссов "..table.getn(U.Bosses()).."  стражей "..table.getn(U.Guardians())
		.."  элит "..table.getn(U.Elites()))
	local all = U.All()
	for i = 1, table.getn(all) do
		local u = all[i]
		Add(out, "  "..tostring(u.kind).." "..tostring(u.id).." "..tostring(u.name).." "..tostring(u.hp).."/"..tostring(u.hpm).."  в бою "..YN(U.InFight(u)))
	end
	local hp, hpm, name, kind = U.Target()
	Add(out, "цель с настоящими HP: "..(hp and (tostring(name).." "..hp.."/"..tostring(hpm).." ("..tostring(kind)..")") or "нет"))
	Add(out, "опознание цели клиента (IdOf target): "..tostring((U.IdOf("target"))))
end

X.party = function(out)
	local P = H.Party
	Add(out, "== Party (слой данных) ==")
	Add(out, "героев в строках "..P.Count().."  в группе "..YN(P.InParty()).."  метка свежая "..YN(P.IsFresh()).."  снимок на dead/victory "..table.getn(P.Snapshot()))
	local down, share, by, reviving, rshare = P.Revive()
	Add(out, "герой лежит "..YN(P.IsDown()).."  подъем "..F(share).." кем "..tostring(by).."  поднимает "..tostring(reviving).." "..F(rshare))
	local n = P.DownedCount()
	Add(out, "лежат соратники: "..n)
	local list = P.Downed()
	for i = 1, n do
		Add(out, "  "..tostring(list[i].name).." id "..tostring(list[i].id).."  "..(list[i].dist and (F(list[i].dist, "%.1f").." ярдов") or "расстояние неизвестно"))
	end
end

X.schedule = function(out)
	local C = H.Schedule
	Add(out, "== Schedule (слой данных) ==")
	local line, left = C.Next()
	Add(out, "свежее "..YN(C.IsFresh()).."  строк "..C.Count().."  ближайший "..(line and tostring(line.name) or "нет").." через "..F(left).."  бесконечный до босса "..F(C.NextEndless()))
	local lines = C.Lines()
	for i = 1, table.getn(lines) do
		local l = lines[i]
		Add(out, "  "..tostring(l.index)..": "..tostring(l.name).." at "..tostring(l.at).." "..tostring(l.state)..(l.final == 1 and " (финал)" or "")
			.."  осталось "..F(C.Left(l)).."  переезд "..YN(C.Relocating(l)))
	end
	for i = 1, C.LairCount() do
		local l = H.Schedule.Lairs()[i]
		Add(out, "  логово "..tostring(l.index)..": "..tostring(l.state).." "..tostring(l.name).." left "..tostring(l.left).."  возрождение через "..F(C.RespawnIn(i)))
	end
end

X.loadout = function(out)
	local L = H.Loadout
	Add(out, "== Loadout (слой данных) ==")
	local changed = L.Refresh(nil, true)
	local err = L.Error(nil)
	Add(out, "запрос сейчас: ревизия сменилась "..YN(changed).."  ревизия "..tostring(L.Revision(nil)).."  ошибка "..(err and tostring(err.code) or "нет")
		.."  запросов "..L.stats.requests.." смен "..L.stats.changed.." ошибок "..L.stats.errors)
	local data = L.Get(nil)
	if not data then
		Add(out, "ответа нет (счетчик еще не готов или нет забега)")
		return
	end
	local abilities = data.abilities or {}
	for i = 1, table.getn(abilities) do
		local a = abilities[i]
		Add(out, "  "..tostring(a.sourceKey).." -> ключ "..tostring(L.AbilityKey(a)).."  slotId "..tostring(a.slotId).."  выучена "..tostring(a.learned).."  выбрана "..tostring(a.selected))
	end
	for i = 1, table.getn(L.JEWELRY_SLOTS) do
		local slot = L.JEWELRY_SLOTS[i]
		Add(out, "  экипировка слот "..slot..": itemKey "..tostring(L.ItemKey(slot)).." ранг "..tostring(L.ItemRank(slot)))
	end
	Add(out, "  бижутерии забега: "..table.getn(L.Jewelry(nil)))
end

X.meter = function(out)
	local M = H.MeterData
	Add(out, "== MeterData (слой данных) ==")
	local ctx, err = M.Context(true)
	if ctx then
		Add(out, "контекст: runId "..tostring(ctx.runId).."  ревизия "..tostring(ctx.counterRevision).."  фаза "..tostring(ctx.phase).."  владелец "..tostring(ctx.localOwnerId)
			.."  группа "..tostring(ctx.partyState))
	else
		Add(out, "контекста нет: "..(err and tostring(err.code) or "?"))
	end
	local caps = M.Caps()
	Add(out, "возможности: "..(caps and ("apiVersion "..tostring(caps.apiVersion).."  язык "..tostring(caps.languageCode).."  чекпойнты "..YN(M.AtomicCheckpoints())) or "нет"))
	local s = M.stats
	Add(out, "снимков "..s.snapshots.."  ошибок "..s.errors.."  пропущено лимитом "..s.skipped.."  контекстов "..s.contexts.."  последний код "..tostring(s.lastCode)
		.."  чекпойнтов "..M.CheckpointCount())
	local c = H.CombatText.stats
	Add(out, "CombatText: чтений "..c.reads.." страниц "..c.pages.." событий "..c.events.." ошибок "..c.errors.." потеряно "..c.dropped.." код "..tostring(c.lastCode))
	Add(out, "источники первого запроса: ключ | имя | иконка")
	M.DebugActors(out)
	local t = H.TooltipScan.stats
	Add(out, "TooltipScan: чтений "..t.reads.." в очереди "..H.TooltipScan.QueueSize().." готово "..t.ready.." снято "..t.dropped)
end

X.hud = function(out)
	local U = H.Hud
	Add(out, "== Hud ==")
	local claims, covers, owned = U.Stats()
	Add(out, "claims "..claims.."  покрытий "..covers.."  частей в owned "..owned.."  SurvivorUI загружен "..YN(H.IsCoexist()))
	local parts = U.Parts()
	for i = 1, table.getn(parts) do
		local p = parts[i]
		local shown = U.IsShown(p)
		local req = H.Rules.Required(p)
		local hud = H.DB.Global() and H.DB.Global().hud
		Add(out, "  "..p..": показана "..(shown == nil and "?" or YN(shown)).."  claims "..U.ClaimCount(p).."  покрытий "..U.CoverCount(p)..(req and (" из "..table.getn(req)) or "")
			.."  хотим скрыть "..YN(U.WantsHidden(p)).."  наша (owned) "..YN(hud and hud.owned[p]))
	end
end

X.park = function(out)
	local K = H.Parking
	Add(out, "== Park ==")
	Add(out, "запаркованно "..K.Count().."  всего парковок "..K.stats.parked.."  возвратов "..K.stats.unparked.."  Reassert перенес "..K.stats.reasserted)
	local list = K.Describe()
	for i = 1, table.getn(list) do
		Add(out, "  "..list[i])
	end
end

X.poll = function(out)
	local P = H.Poll
	Add(out, "== Poll ==")
	Add(out, "запущен "..YN(P.IsStarted()).."  кадров опроса "..P.stats.samples.."  событий "..P.stats.events.."  сообщений AZS "..P.stats.messages
		.."  меток увидено "..P.stats.seen.." из "..table.getn(P.EVENTS))
	local now = H.Now()
	for i = 1, table.getn(P.EVENTS) do
		local ev = P.EVENTS[i]
		local st = P.LastStamp(ev)
		Add(out, "  "..ev..": "..(st and (F(st, "%.2f").." (назад "..F(now - st).." с)") or "не приходила"))
	end
	local last = P.LastEvents()
	Add(out, "последние события: "..(table.getn(last) == 0 and "нет" or table.concat(last, ", ")))
end

----------------------------------------------------------------------------------------
-- selftest
----------------------------------------------------------------------------------------

table.insert(D.SelftestParts, function(L)
	local claims, covers, owned = H.Hud.Stats()
	Add(L, "Hud: claims "..claims..", покрытий "..covers..", частей в owned "..owned)
	local K = H.Parking
	Add(L, "Park: запаркованно "..K.Count()..", Reassert перенес "..K.stats.reasserted)
	local P = H.Poll
	local last = P.LastEvents()
	Add(L, "Poll: запущен "..YN(P.IsStarted())..", меток увидено "..P.stats.seen.." из "..table.getn(P.EVENTS)..", событий "..P.stats.events
		..", сообщений AZS "..P.stats.messages..", последние: "..(table.getn(last) == 0 and "нет" or table.concat(last, ", ")))
	Add(L, "Spells: расхождение двух источников CD, максимум "..F(H.Spells.stats.maxDelta, "%.3f").." с по "..H.Spells.stats.samples.." сравнениям (считается по /hui dump spells)")
	local s = H.MeterData.stats
	Add(L, "MeterData: снимков "..s.snapshots..", ошибок "..s.errors..", чекпойнтов "..H.MeterData.CheckpointCount()..", Loadout запросов "..H.Loadout.stats.requests
		..", CombatText событий "..H.CombatText.stats.events)
	Add(L, "Visibility: кусков "..H.Vis.Count()..", выбор карточек сейчас "..YN(H.Vis.IsChoosing()))
end)

----------------------------------------------------------------------------------------
-- Команда /hui hud
----------------------------------------------------------------------------------------

H.Slash.Register("hud", function(rest)
	if rest == "reset" then
		local n = H.Hud.RestoreAll()
		H.Print("hud: возвращено частей "..n..", все claims и покрытия сняты")
		return
	end
	local out = {}
	X.hud(out)
	D.Show(out, "hud")
end, "hud [reset] - состояние частей HUD игры; reset возвращает все, что скрыли мы")
