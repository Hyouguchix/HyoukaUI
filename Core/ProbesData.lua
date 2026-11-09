-- HyoukaUI: пробы этапа 0, которые только читают данные и ничего не двигают:
-- 0.1, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.12, 0.13, 0.16.
-- Результат: сырые значения простым текстом (plan 6.4).

local H = HyoukaUI
local P = H.Probes
local D = H.Debug

local function G(name)
	return H.Global(name)
end

local function Val(v)
	return D.Val(v)
end

local function Fx(v, digits)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%."..(digits or 3).."f", v)
end

-- Скрытый кадр для проверки методов (один на аддон; кадры 1.12 удалить нельзя).
function P.Scratch()
	if not P.scratch then
		P.scratch = CreateFrame("Frame", nil, UIParent)
		P.scratch:Hide()
	end
	return P.scratch
end

----------------------------------------------------------------------------------------
-- 0.1 ErrorLog
----------------------------------------------------------------------------------------
P.Define(1, {
	title = "seterrorhandler, geterrorhandler, debugstack",
	question = "Можно ли поставить свой обработчик ошибок поверх прежнего и доходит ли ошибка до журнала?",
	auto = true,
	run = function(r)
		r:Add("seterrorhandler: "..type(seterrorhandler))
		r:Add("geterrorhandler: "..type(geterrorhandler))
		r:Add("debugstack: "..type(debugstack))
		-- Факт из игры (2026-11-09): GetCVar на неизвестное имя бросает ошибку, а не возвращает nil.
		local okc, cvar = pcall(GetCVar, "ScriptErrors")
		r:Add("GetCVar(\"ScriptErrors\"): "..(okc and Val(cvar) or ("бросает ошибку: "..tostring(cvar))))
		r:Add("ErrorLog: установлен "..tostring(H.Errors.installed)..", прежний обработчик был "..tostring(H.Errors.previous ~= nil))
		if type(geterrorhandler) == "function" then
			local current = geterrorhandler()
			r:Add("текущий обработчик совпадает с нашим: "..tostring(current == H.Errors.Handler))
			local marker = "HyoukaUI probe 0.1 test error"
			local before = H.Errors.Count()
			H.Errors.quiet = marker
			local ok, err = pcall(current, marker)
			H.Errors.quiet = nil
			local after = H.Errors.Count()
			r:Add("тестовая ошибка отправлена в обработчик: ok="..tostring(ok)..(ok and "" or (" ("..tostring(err)..")")))
			r:Add("журнал HyoukaUI принял ее: "..(after > before and "да" or "НЕТ")..", счетчик "..before.." -> "..after)
			H.Errors.Forget(marker)
			r:Add("тестовая запись из журнала убрана, счетчик теперь "..H.Errors.Count())
		else
			r:Add("geterrorhandler нет: ставить поверх прежнего нечем, ErrorLog ставит свой без цепочки")
		end
		if type(debugstack) == "function" then
			local ok, stack = pcall(debugstack, 1, 2, 0)
			r:Add("debugstack(1, 2, 0): ok="..tostring(ok)..", "..Val(stack))
		end
	end,
})

----------------------------------------------------------------------------------------
-- 0.3 Частота кадров, язык, разрешение
----------------------------------------------------------------------------------------
P.Define(3, {
	title = "GetFramerate, azsLanguage, gxResolution",
	question = "Какое разрешение и масштаб у окна и сколько получается AS на физический пиксель (Theme.PX)?",
	auto = true,
	run = function(r)
		r:Add("GetFramerate: "..(GetFramerate and Fx(GetFramerate(), 2) or "нет функции"))
		r:Add("GetCVar(\"azsLanguage\") = "..Val(GetCVar and GetCVar("azsLanguage")))
		local res = GetCVar and GetCVar("gxResolution")
		r:Add("GetCVar(\"gxResolution\") = "..Val(res))
		local _, _, w, h = string.find(res or "", "(%d+)[xX*](%d+)")
		r:Add("разбор string.find: ширина "..tostring(w)..", высота "..tostring(h))
		r:Add("GetCVar(\"uiScale\") = "..Val(GetCVar and GetCVar("uiScale"))..", useUiScale = "..Val(GetCVar and GetCVar("useUiScale")))
		r:Add("UIParent: ширина "..Fx(UIParent:GetWidth())..", высота "..Fx(UIParent:GetHeight())..", scale "..Fx(UIParent:GetScale())..", effectiveScale "..Fx(UIParent:GetEffectiveScale()))
		if GetScreenWidth and GetScreenHeight then
			r:Add("GetScreenWidth/Height: "..Fx(GetScreenWidth())..", "..Fx(GetScreenHeight()))
		end
		if w and h then
			local scale = UIParent:GetEffectiveScale()
			local px = (768 / tonumber(h)) / scale
			r:Add("PX = (768 / "..h..") / "..Fx(scale, 4).." = "..Fx(px, 5).." AS на физический пиксель (ожидалось 0.5333 при 1440p)")
		else
			r:Add("PX не посчитан: gxResolution не разобрана (запасное значение в плане: высота 1440)")
		end
	end,
})

----------------------------------------------------------------------------------------
-- 0.4 Части HUD
----------------------------------------------------------------------------------------
P.Define(4, {
	title = "AZS_HUD_CVARS",
	question = "Какие части HUD есть у игры и в какие cvar они записываются?",
	auto = true,
	run = function(r)
		local lines, why = D.DumpLines("hudcvars")
		if not lines then
			r:Add("нет данных: "..tostring(why))
			return
		end
		for i = 1, table.getn(lines) do
			r:Add(lines[i])
		end
		r:Add("AZS_SetHudShown: "..type(G("AZS_SetHudShown"))..", AZS_IsHudShown: "..type(G("AZS_IsHudShown")))
	end,
})

----------------------------------------------------------------------------------------
-- 0.5 Метка уже обновлена в момент CHAT_MSG_ADDON?
----------------------------------------------------------------------------------------
local STAMP_OF = { AZSRUN = "AZS_RUN_UPDATED", AZSZONE = "AZS_ZONE_UPDATED", AZSUNITS = "AZS_UNITS_UPDATED",
	AZSSPELLS = "AZS_SPELLS_UPDATED", AZSMETER = "AZS_METER_UPDATED", AZSTGT = "AZS_TARGET_UPDATED",
	AZSBUFFS = "AZS_BUFFS_UPDATED", AZSPARTY = "AZS_PARTY_UPDATED", AZSBOSSES = "AZS_SCHEDULE_UPDATED" }
local WATCH_SECONDS = 10

local p5 = { tally = {}, active = false }

local function P5Message(ev, prefix)
	local stampName = STAMP_OF[prefix]
	if not stampName then
		return
	end
	local row = p5.tally[prefix]
	if not row then
		row = { seen = 0, fresh = 0, stale = 0 }
		p5.tally[prefix] = row
	end
	row.seen = row.seen + 1
	local stamp = G(stampName)
	if stamp and math.abs(stamp - GetTime()) < 0.0005 then
		row.fresh = row.fresh + 1
	else
		row.stale = row.stale + 1
	end
end

P.Define(5, {
	title = "порядок обработчиков CHAT_MSG_ADDON и метки *_UPDATED",
	question = "Метка уже обновлена движком, когда наш обработчик получает то же сообщение?",
	auto = true,
	run = function(r)
		if p5.active then
			r:Add("проба уже идет, подожди результат")
			return
		end
		p5.active = true
		p5.tally = {}
		H.On("CHAT_MSG_ADDON", "debug", P5Message)
		r:Async()
		r:Add("Слушаю CHAT_MSG_ADDON "..WATCH_SECONDS.." с. Нужны сообщения сервера: проба имеет смысл внутри забега.")
		H.Clock.After("debug", WATCH_SECONDS, function()
			H.Off("CHAT_MSG_ADDON", "debug")
			p5.active = false
			local keys = H.SortedKeys(p5.tally)
			if table.getn(keys) == 0 then
				r:Add("сообщений AZS за "..WATCH_SECONDS.." с не пришло: результат не получен, повтори в забеге")
			end
			local fresh, stale = 0, 0
			for i = 1, table.getn(keys) do
				local row = p5.tally[keys[i]]
				r:Add(keys[i]..": сообщений "..row.seen..", метка уже новая "..row.fresh..", еще старая "..row.stale)
				fresh = fresh + row.fresh
				stale = stale + row.stale
			end
			if fresh + stale > 0 then
				r:Add("итог: движок обновляет метку ДО нашего обработчика: "..(stale == 0 and "да" or (fresh == 0 and "нет, мы получаем сообщение раньше" or "по-разному")))
			end
			r:Finish()
		end)
	end,
})

----------------------------------------------------------------------------------------
-- 0.6 Ключи AZS_RUN, ZONE, TARGET, REVIVE, END, UNITS; смена run; пауза
----------------------------------------------------------------------------------------
local p6 = { history = {}, last = {}, watching = false }

local function P6Check()
	local ph = AZS_RUN and AZS_RUN.ph
	local run = AZS_ZONE and AZS_ZONE.run
	local down = AZS_REVIVE and AZS_REVIVE.down
	local items = { { "фаза", ph }, { "AZS_ZONE.run", run }, { "AZS_REVIVE.down", down } }
	for i = 1, 3 do
		local name, value = items[i][1], items[i][2]
		if p6.last[name] ~= value then
			if table.getn(p6.history) < 80 then
				table.insert(p6.history, string.format("t=%.1f %s: %s -> %s", GetTime(), name, tostring(p6.last[name]), tostring(value)))
			end
			p6.last[name] = value
		end
	end
end

P.Define(6, {
	title = "ключи AZS_RUN, ZONE, TARGET, REVIVE, END, UNITS; смена run; пауза",
	question = "Какие поля реально приходят, меняется ли AZS_ZONE.run между забегами, что в AZS_RUN.ph на паузе (Esc)?",
	auto = true,
	run = function(r, arg)
		if arg == "stop" then
			H.Clock.Stop("probe6")
			p6.watching = false
			r:Add("наблюдение за сменой фазы и run выключено")
			return
		end
		if not p6.watching then
			p6.watching = true
			P6Check()
			H.Clock.Every("probe6", 0.25, P6Check)
			r:Add("Включено наблюдение (4 раза в секунду) за AZS_RUN.ph, AZS_ZONE.run, AZS_REVIVE.down. Нажми Esc в забеге, потом повтори /hui probe 6. Выключить: /hui probe 6 stop")
		else
			r:Add("Наблюдение идет. Выключить: /hui probe 6 stop")
		end
		r:Add("текущая фаза AZS_GetPhase() = "..Val(AZS_GetPhase and AZS_GetPhase()))
		r:Add("журнал смен ("..table.getn(p6.history).."):")
		for i = 1, table.getn(p6.history) do
			r:Add("  "..p6.history[i])
		end
		local names = { "AZS_RUN", "AZS_ZONE", "AZS_TARGET", "AZS_REVIVE", "AZS_END" }
		for i = 1, table.getn(names) do
			local t = G(names[i])
			r:Add("---- "..names[i].." ----")
			if type(t) == "table" then
				local keys = H.SortedKeys(t)
				r:Add("ключей "..table.getn(keys))
				local parts = {}
				for j = 1, table.getn(keys) do
					table.insert(parts, tostring(keys[j]).."="..Val(t[keys[j]]))
				end
				r:Add(table.concat(parts, "  "))
			else
				r:Add(Val(t))
			end
		end
		local units = G("AZS_UNITS")
		r:Add("---- AZS_UNITS ----")
		if type(units) == "table" then
			local kinds = {}
			for i = 1, table.getn(units) do
				local k = tostring(units[i].kind)
				kinds[k] = (kinds[k] or 0) + 1
			end
			local parts = {}
			local ks = H.SortedKeys(kinds)
			for i = 1, table.getn(ks) do
				table.insert(parts, ks[i].."="..kinds[ks[i]])
			end
			r:Add("записей "..table.getn(units)..", по видам (kind): "..(table.getn(parts) > 0 and table.concat(parts, " ") or "-"))
			for i = 1, math.min(table.getn(units), 5) do
				r:Add(i..": "..D.Row(units[i]))
			end
		end
	end,
})

----------------------------------------------------------------------------------------
-- 0.7 AZS_SPELLS.cd против GetActionCooldown
----------------------------------------------------------------------------------------
P.Define(7, {
	title = "AZS_SPELLS.cd против GetActionCooldown",
	question = "Совпадает ли расчет кулдауна из AZS_SPELLS с GetActionCooldown у автокаста, в том числе на паузе?",
	auto = true,
	run = function(r)
		local now = GetTime()
		r:Add("GetTime = "..Fx(now)..", фаза "..Val(AZS_GetPhase and AZS_GetPhase())..", AZS_SPELLS_UPDATED = "..Fx(G("AZS_SPELLS_UPDATED")))
		local spells = G("AZS_SPELLS")
		local n = type(spells) == "table" and table.getn(spells) or 0
		r:Add("AZS_SPELLS: записей "..n.." (расчет start = UPDATED - (cdmax - cd), duration = cdmax)")
		local stamp = G("AZS_SPELLS_UPDATED")
		for i = 1, n do
			local s = spells[i]
			local start = "?"
			if stamp and type(s.cd) == "number" and type(s.cdmax) == "number" then
				start = Fx(stamp - (s.cdmax - s.cd))
			end
			r:Add(string.format("%2d  key=%s spell=%s rank=%s cd=%s cdmax=%s -> start %s, duration %s", i, tostring(s.key), tostring(s.spell), tostring(s.rank), tostring(s.cd), tostring(s.cdmax), start, tostring(s.cdmax)))
		end
		r:Add("GetActionCooldown по слотам 1..6 и 12 (start, duration, остаток):")
		local slots = { 1, 2, 3, 4, 5, 6, 12 }
		for i = 1, table.getn(slots) do
			local slot = slots[i]
			if GetActionCooldown then
				local start, duration = GetActionCooldown(slot)
				local left = "?"
				if type(start) == "number" and type(duration) == "number" and duration > 0 then
					left = Fx(start + duration - now, 2)
				elseif duration == 0 then
					left = "0"
				end
				r:Add("  слот "..slot..": start "..Fx(start)..", duration "..tostring(duration)..", остаток "..left..", HasAction "..tostring(HasAction and HasAction(slot))..", текстура "..tostring(GetActionTexture and GetActionTexture(slot)))
			else
				r:Add("  GetActionCooldown: нет функции")
				break
			end
		end
		r:Add("Сравнить построчно: запись i против слота по конвенции 1..n-1 -> 1..6, последняя -> 12. Повторить на паузе (Esc).")
	end,
})

----------------------------------------------------------------------------------------
-- 0.8 loadout
----------------------------------------------------------------------------------------
local function DumpFirst(r, label, list, count)
	r:Add(label..": "..(type(list) == "table" and table.getn(list) or 0).." шт.")
	if type(list) ~= "table" then
		return
	end
	for i = 1, math.min(table.getn(list), count) do
		local lines = D.DumpTable(list[i], {}, "    ", 2, 30)
		r:Add("  ["..i.."]")
		for j = 1, table.getn(lines) do
			r:Add(lines[j])
		end
	end
end

P.Define(8, {
	title = "AZS_GetMeterLoadout: иконки, abilityKey, itemKey, effectSourceKeys",
	question = "Какие поля есть у способностей, предметов и бижутерии (icon.status, abilityKey против AZS_SPELLS.key, itemKey, rank)?",
	auto = true,
	run = function(r)
		if not (AZS_GetMeterContext and AZS_GetMeterLoadout) then
			r:Add("meter API недоступен")
			return
		end
		local ctx, cerr = AZS_GetMeterContext()
		if not ctx then
			r:Add("AZS_GetMeterContext: нет ("..Val(cerr and cerr.code)..") - нужен забег")
			return
		end
		r:Add("context: runId "..Val(ctx.runId)..", фаза "..Val(ctx.phase)..", localOwnerId "..Val(ctx.localOwnerId)..", party "..Val(ctx.partyState))
		local lo, err = AZS_GetMeterLoadout({ apiVersion = 1, runId = ctx.runId })
		if not lo then
			r:Add("AZS_GetMeterLoadout: ошибка "..Val(err and err.code)..", "..Val(err and err.message))
			return
		end
		r:Add("loadout: revision "..Val(lo.loadoutRevision)..", ownerId "..Val(lo.ownerId))
		r:Add("ключи верхнего уровня: "..table.concat(H.SortedKeys(lo), ", "))
		local spells = G("AZS_SPELLS")
		local abilities = lo.abilities or {}
		for i = 1, table.getn(abilities) do
			local a = abilities[i]
			local status = type(a.icon) == "table" and a.icon.status or a.icon
			local match = "нет записи"
			if type(spells) == "table" and spells[i] then
				match = tostring(spells[i].key == a.abilityKey)
			end
			r:Add(string.format("ability %d: slotId=%s abilityKey=%s icon.status=%s, abilityKey == AZS_SPELLS[%d].key: %s", i, tostring(a.slotId), tostring(a.abilityKey), tostring(status), i, match))
		end
		DumpFirst(r, "abilities, полный вид первых", abilities, 1)
		local equipment = lo.equipment or {}
		for i = 1, table.getn(equipment) do
			local e = equipment[i]
			r:Add(string.format("equipment %d: slotId=%s itemKey=%s rank=%s", i, tostring(e.slotId), tostring(e.itemKey), tostring(e.rank)))
		end
		local jewelry = lo.runJewelry or {}
		for i = 1, table.getn(jewelry) do
			local j = jewelry[i]
			r:Add(string.format("runJewelry %d: slotId=%s itemKey=%s effectSourceKeys=%d, первый %s", i, tostring(j.slotId), tostring(j.itemKey), table.getn(j.effectSourceKeys or {}), tostring((j.effectSourceKeys or {})[1])))
		end
		DumpFirst(r, "equipment, полный вид первого", equipment, 1)
		DumpFirst(r, "runJewelry, полный вид первого", jewelry, 1)
		r:Add("talents: "..table.getn(lo.talents or {}).." шт.")
	end,
})

----------------------------------------------------------------------------------------
-- 0.9 Combat text
----------------------------------------------------------------------------------------
P.Define(9, {
	title = "AZS_GetCombatTextEvents: поля событий",
	question = "Какие поля у событий combat text (источник, цель, крит, число)?",
	auto = true,
	run = function(r)
		if AZS_GetCombatTextCapabilities then
			local caps, cerr = AZS_GetCombatTextCapabilities()
			r:Add("capabilities: "..(caps and D.Row(caps) or ("ошибка "..Val(cerr and cerr.code))))
		end
		if not AZS_GetCombatTextEvents then
			r:Add("AZS_GetCombatTextEvents: нет функции")
			return
		end
		local res, err = AZS_GetCombatTextEvents()
		if not res then
			r:Add("AZS_GetCombatTextEvents(): ошибка "..Val(err and err.code)..", "..Val(err and err.message))
			return
		end
		r:Add("тип результата "..type(res))
		if type(res) ~= "table" then
			r:Add(Val(res))
			return
		end
		r:Add("ключи результата: "..table.concat(H.SortedKeys(res), ", "))
		local list = res.events or res
		local count = type(list) == "table" and table.getn(list) or 0
		r:Add("событий в списке: "..count..". Если 0: ударь по врагу и повтори /hui probe 9")
		for i = 1, math.min(count, 3) do
			r:Add("событие "..i..": "..D.Row(list[i]))
		end
		if type(res.nextCursor) ~= "nil" or type(res.cursor) ~= "nil" then
			r:Add("курсор: nextCursor="..Val(res.nextCursor)..", cursor="..Val(res.cursor))
		end
	end,
})

----------------------------------------------------------------------------------------
-- 0.12 Здоровье и цель цели
----------------------------------------------------------------------------------------
P.Define(12, {
	title = "UnitHealth(player) против AZS_RUN.hpm, targettarget",
	question = "Отдает ли UnitHealth числа или проценты и работает ли UnitName(targettarget)?",
	auto = true,
	run = function(r)
		r:Add("UnitHealth(\"player\") = "..tostring(UnitHealth("player"))..", UnitHealthMax(\"player\") = "..tostring(UnitHealthMax("player")))
		r:Add("AZS_RUN.hpm = "..Val(AZS_RUN and AZS_RUN.hpm)..", AZS_RUN.sh = "..Val(AZS_RUN and AZS_RUN.sh))
		r:Add("UnitExists(\"target\") = "..tostring(UnitExists("target"))..", UnitName(\"target\") = "..Val(UnitName("target")))
		r:Add("UnitHealth(\"target\") = "..tostring(UnitHealth("target"))..", UnitHealthMax(\"target\") = "..tostring(UnitHealthMax("target")))
		r:Add("UnitExists(\"targettarget\") = "..tostring(UnitExists("targettarget"))..", UnitName(\"targettarget\") = "..Val(UnitName("targettarget")))
		local t = G("AZS_TARGET")
		if type(t) == "table" then
			r:Add("AZS_TARGET: "..D.Row(t))
		end
		r:Add("Сравнить: UnitHealthMax(player) и hpm одинаковы (числа) или первое равно 100 (проценты)")
	end,
})

----------------------------------------------------------------------------------------
-- 0.13 Атомарные чекпойнты
----------------------------------------------------------------------------------------
P.Define(13, {
	title = "atomicCheckpoints и цикл создать/снять чекпойнт",
	question = "Поддерживает ли игра атомарные чекпойнты счетчика (Reset колонки без гонок)?",
	auto = true,
	run = function(r)
		if not AZS_GetMeterCapabilities then
			r:Add("AZS_GetMeterCapabilities: нет функции")
			return
		end
		local caps = AZS_GetMeterCapabilities()
		r:Add("apiVersion "..Val(caps.apiVersion)..", maxCheckpoints "..Val(caps.maxCheckpoints)..", языков "..table.getn(caps.languageCodes or {}))
		local features = caps.features or {}
		r:Add("features: "..D.Row(features))
		r:Add("features.atomicCheckpoints = "..tostring(features.atomicCheckpoints))
		local ctx = AZS_GetMeterContext and AZS_GetMeterContext()
		if not ctx then
			r:Add("нет забега: цикл создать/снять не проверялся (повтори в забеге)")
			return
		end
		local cp, err = AZS_CreateMeterCheckpoint(ctx.runId)
		if not cp then
			r:Add("AZS_CreateMeterCheckpoint: ошибка "..Val(err and err.code)..", "..Val(err and err.message))
			return
		end
		r:Add("чекпойнт создан: "..D.Row(cp))
		local ok, rerr = AZS_ReleaseMeterCheckpoint(cp.checkpointId)
		r:Add("снят: "..tostring(ok)..(rerr and (", ошибка "..Val(rerr.code)) or ""))
	end,
})

----------------------------------------------------------------------------------------
-- 0.16 Что есть в движке
----------------------------------------------------------------------------------------
local function Split(list, check)
	local yes, no = {}, {}
	for i = 1, table.getn(list) do
		if check(list[i]) then
			table.insert(yes, list[i])
		else
			table.insert(no, list[i])
		end
	end
	return table.concat(yes, ", "), table.concat(no, ", ")
end

local function Report(r, label, list, check)
	local yes, no = Split(list, check)
	r:Add(label.." есть: "..(yes == "" and "-" or yes))
	r:Add(label.." НЕТ: "..(no == "" and "-" or no))
end

P.Define(16, {
	title = "наличие функций и методов в benilla",
	question = "Что из нужного есть: hooksecurefunc, SetUserPlaced, SetDesaturated, Is*KeyDown, CooldownFrame_SetTimer и запретные для Lua 5.0 вещи?",
	auto = true,
	run = function(r)
		Report(r, "Нужные глобалы", { "hooksecurefunc", "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "CooldownFrame_SetTimer",
			"GetFramerate", "getglobal", "setglobal", "debugstack", "gcinfo", "collectgarbage", "loadstring", "xpcall", "date", "time",
			"strsplit", "strjoin", "strtrim", "tinsert", "format", "UnitClass", "GetMouseFocus", "EnumerateFrames", "GetActionCooldown",
			"UseAction", "TargetByName", "TargetUnit", "TargetLastTarget", "ToggleDropDownMenu", "SendAddonMessage", "IsAddOnLoaded" },
			function(name) return H.Has(name) end)
		Report(r, "Lua 5.0 (должно быть)", { "table.getn", "table.setn", "table.concat", "table.sort", "table.insert", "math.mod", "math.floor",
			"string.gfind", "string.find", "string.gsub", "string.format", "string.sub", "string.byte", "string.rep", "unpack", "getfenv", "setmetatable", "pcall" },
			function(name) return H.Has(name) end)
		Report(r, "Lua 5.1+ (быть НЕ должно, если версия 5.0)", { "string.match", "string.gmatch", "select", "table.unpack", "math.huge", "math.fmod" },
			function(name) return H.Has(name) end)
		local f = P.Scratch()
		Report(r, "Методы кадра", { "SetUserPlaced", "SetClampedToScreen", "SetAlpha", "SetScale", "SetFrameLevel", "EnableMouseWheel", "GetEffectiveScale",
			"GetNumPoints", "SetBackdrop", "SetMovable", "StartMoving", "RegisterForDrag", "SetToplevel", "SetFrameStrata", "SetHitRectInsets" },
			function(name) return type(f[name]) == "function" end)
		local tex = f:CreateTexture(nil, "ARTWORK")
		Report(r, "Методы Texture", { "SetDesaturated", "SetVertexColor", "SetTexCoord", "SetBlendMode", "SetGradient", "SetGradientAlpha", "SetRotation" },
			function(name) return type(tex[name]) == "function" end)
		local fs = f:CreateFontString(nil, "OVERLAY")
		Report(r, "Методы FontString", { "SetFont", "GetFont", "GetStringWidth", "GetStringHeight", "SetShadowColor", "SetShadowOffset", "SetSpacing", "SetTextHeight", "SetJustifyV" },
			function(name) return type(fs[name]) == "function" end)
		local res = GetCVar and GetCVar("gxResolution")
		local _, _, w, h = string.find(res or "", "(%d+)[xX*](%d+)")
		r:Add("GetCVar(\"gxResolution\") = "..Val(res)..", string.find с захватами: "..tostring(w).." и "..tostring(h))
		r:Add("Minimap.SetMaskTexture: "..tostring(Minimap and type(Minimap.SetMaskTexture)))
	end,
})
