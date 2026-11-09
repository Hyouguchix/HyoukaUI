-- HyoukaUI: Chat\Feeds, обертка AddMessage на стоковых окнах, ленты, метки времени (spec 3.8, hack-audit frames-29).
--
-- Чат игры не отдает историю назад, а движок кладет строки в окно через this:AddMessage (framexml_fixes.lua, ChatFrame_OnEvent).
-- Поэтому на каждое стоковое окно ставится ОДНА обертка AddMessage (поле экземпляра): фиксированные аргументы
-- (self, text, r, g, b, id, hold), без "...", метка двойной обертки (повторный Install не добавляет вторую), под pcall,
-- строка в стоковое окно уходит всегда (сбой разбора не теряет сообщение). Что делает обертка:
--   * метка времени "%I:%M %p " серым 0.6 перед строкой (опция timestamps; в Рядом только в копиях лент, стоковое окно
--     не трогается);
--   * крики боссов и эмоции рейда (MONSTER_YELL, RAID_BOSS_EMOTE) прячутся по опциям (в Рядом только из лент);
--   * строка с окна General (ChatFrame1) уходит в ленты по виду сообщения: вид берется из ChatTypeInfo по id цвета
--     (id приходит пятым аргументом AddMessage), без id или с неизвестным id строка идет только в General;
--   * непрочитанное: строка в окно или ленту, которые сейчас не показаны, ставит точку на вкладке (Tabs.Note*);
--   * Fade.Touch (новая строка будит затухание).
-- Ленты: свои ScrollingMessageFrame на панели (500 строк, без нативного затухания, колесо, ссылки). В Рядом лента General
-- получает ВСЕ строки (копия потока), в Вместо General - стоковое окно. Ленты "Добыча и система" и "Группа" включаются
-- опциями. Выключение снимает обертки (поле возвращается к прежней функции), а если поверх нашей уже надета чужая -
-- обертка остается и пропускает все вызовы насквозь (rec.on = false).

local H = HyoukaUI
local C = H.Chat

local getn = table.getn

local F = {}
C.Feeds = F

F.stats = { lines = 0, errors = 0, routed = 0 }
F.wins = {}
F.general = nil

local OWNER = "chat"
local MAX_LINES = 500

local function Set(list)
	local t = {}
	for i = 1, getn(list) do
		t[list[i]] = true
	end
	return t
end

-- Виды сообщений 1.12 (ключи ChatTypeInfo). Состав лент подобран под роглайт: система, добыча, опыт, крики и эмоции
-- боссов; речь игроков, группа и шепот в кооперативе.
local LOOT_KINDS = Set({ "SYSTEM", "LOOT", "MONEY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE",
	"COMBAT_MISC_INFO", "TRADESKILLS", "OPENING", "PET_INFO", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_SAY",
	"MONSTER_WHISPER", "RAID_BOSS_EMOTE", "RAID_BOSS_WHISPER" })
local PARTY_KINDS = Set({ "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "WHISPER", "REPLY", "WHISPER_INFORM",
	"AFK", "DND", "SAY", "YELL", "EMOTE", "TEXT_EMOTE", "GUILD", "OFFICER", "CHANNEL" })

-- Ленты по порядку вкладок. opt = ключ настройки, при которой лента включена; general работает только в Рядом.
F.FEEDS = {
	{ key = "general", label = "tab_general", all = true, side = true },
	{ key = "loot", label = "tab_loot", opt = "tabLoot", kinds = LOOT_KINDS },
	{ key = "party", label = "tab_party", opt = "tabParty", kinds = PARTY_KINDS },
}

local byKey = {}
for i = 1, getn(F.FEEDS) do
	byKey[F.FEEDS[i].key] = F.FEEDS[i]
end

function F.Get(key)
	return byKey[key]
end

local function IsActive(feed)
	if feed.side then
		return C.mode == "side"
	end
	return C.Opt(feed.opt) and true or false
end

function F.IsActive(key)
	local feed = byKey[key]
	return feed ~= nil and C.live and IsActive(feed)
end

-- Ключи активных лент по порядку: заполняет out, возвращает число.
function F.Active(out)
	H.Wipe(out)
	for i = 1, getn(F.FEEDS) do
		if IsActive(F.FEEDS[i]) then
			table.insert(out, F.FEEDS[i].key)
		end
	end
	return getn(out)
end

function F.Frame(key)
	local feed = byKey[key]
	return feed and feed.frame or nil
end

function F.Label(key)
	local feed = byKey[key]
	return feed and C.T(feed.label) or key
end

----------------------------------------------------------------------------------------
-- Вид сообщения по id цвета
----------------------------------------------------------------------------------------

local byId

local function BuildKinds()
	byId = {}
	local info = C.Stock.TypeInfo()
	if info then
		for name, v in pairs(info) do
			if type(v) == "table" and type(v.id) == "number" then
				byId[v.id] = name
			end
		end
	end
end

local function KindOf(id)
	if id == nil then
		return nil
	end
	if not byId then
		BuildKinds()
	end
	return byId[id]
end
F.KindOf = KindOf

----------------------------------------------------------------------------------------
-- Ленты
----------------------------------------------------------------------------------------

local function Make(feed)
	local f = CreateFrame("ScrollingMessageFrame", nil, C.Panel.frame)
	f:SetJustifyH("LEFT")
	f:SetMaxLines(MAX_LINES)
	f:SetFading(false)
	f:EnableMouseWheel(true)
	H.Script(OWNER, f, "OnMouseWheel", C.Stock.Wheel)
	pcall(H.Script, OWNER, f, "OnHyperlinkClick", function(self, link, text, button)
		local fn = H.Env.SetItemRef
		if type(fn) == "function" then
			fn(link, text, button)
		end
	end)
	f:Hide()
	feed.frame = f
	return f
end

local function StyleFeed(f)
	local path, size, flags = H.Fonts.Role("title", C.Opt("textSize") - 14)
	f:SetFont(path, size, flags)
end

----------------------------------------------------------------------------------------
-- Обертка AddMessage
----------------------------------------------------------------------------------------

local wraps = {}     -- окно -> { orig, fn, on }

local function Stamp(text)
	local d = H.Env.date
	if type(d) ~= "function" then
		return text
	end
	return "|cff999999"..d("%I:%M %p").." |r"..text
end

-- Строка в ленты. Возвращает true, если она ушла в ленту, отличную от General (для dedupe).
local function Route(text, r, g, b, id, kind)
	local routed = false
	for i = 1, getn(F.FEEDS) do
		local feed = F.FEEDS[i]
		if feed.frame and IsActive(feed) and (feed.all or (kind and feed.kinds[kind])) then
			feed.frame:AddMessage(text, r, g, b, id)
			F.stats.lines = F.stats.lines + 1
			C.Tabs.NoteFeed(feed.key)
			if not feed.all then
				routed = true
			end
		end
	end
	if routed then
		F.stats.routed = F.stats.routed + 1
	end
	return routed
end

-- Что делать со строкой: возвращает (текст для стокового окна, спрятать ли строку из стокового окна).
local function Handle(win, text, r, g, b, id)
	if type(text) ~= "string" then
		return text, false
	end
	local kind = KindOf(id)
	local replace = (C.mode == "replace")
	local muted = (kind == "MONSTER_YELL" and C.Opt("hideYells")) or (kind == "RAID_BOSS_EMOTE" and C.Opt("hideBanners"))
	if muted and replace then
		return text, true
	end
	local stamped = text
	if C.Opt("timestamps") then
		stamped = Stamp(text)
	end
	local routed = false
	if win == F.general and not muted then
		routed = Route(stamped, r, g, b, id, kind)
	end
	if replace then
		C.Tabs.NoteWindow(win)
	end
	C.Fade.Touch()
	if replace then
		if routed and C.Opt("dedupe") then
			return text, true
		end
		return stamped, false
	end
	return text, false
end

local function Tap(rec, self, text, r, g, b, id, hold)
	local ok, shown, drop = pcall(Handle, self, text, r, g, b, id)
	if not ok then
		F.stats.errors = F.stats.errors + 1
		H.ModuleError(C.M.name, shown)
		shown, drop = text, false
	end
	if drop then
		return
	end
	return rec.orig(self, shown, r, g, b, id, hold)
end

local function Wrap(w)
	local old = wraps[w]
	if old then
		if w.AddMessage == old.fn then
			old.on = true
			return
		end
		-- поверх нашей надета чужая: наша остается в цепочке и пропускает вызовы насквозь, ставим новую
		old.on = false
	end
	local orig = w.AddMessage
	if type(orig) ~= "function" then
		return
	end
	local rec = { orig = orig, on = true }
	rec.fn = function(self, text, r, g, b, id, hold)
		if not rec.on then
			return orig(self, text, r, g, b, id, hold)
		end
		return Tap(rec, self, text, r, g, b, id, hold)
	end
	w.AddMessage = rec.fn
	wraps[w] = rec
end

local function Unwrap(w)
	local rec = wraps[w]
	if not rec then
		return
	end
	wraps[w] = nil
	rec.on = false
	if w.AddMessage == rec.fn then
		w.AddMessage = rec.orig
	end
end

function F.WrapCount()
	local n = 0
	for w, rec in pairs(wraps) do
		if rec.on then
			n = n + 1
		end
	end
	return n
end

----------------------------------------------------------------------------------------
-- Жизненный цикл части
----------------------------------------------------------------------------------------

function F.Refresh()
	for i = 1, getn(F.FEEDS) do
		local feed = F.FEEDS[i]
		if IsActive(feed) then
			local f = feed.frame or Make(feed)
			StyleFeed(f)
			f:SetFading(false)
			C.Panel.AddText(f, false)
		elseif feed.frame then
			C.Panel.RemoveText(feed.frame)
			feed.frame:Hide()
		end
	end
end

function F.Enable(mode)
	BuildKinds()
	F.general = C.Stock.General()
	C.Stock.Windows(F.wins)
	for i = 1, getn(F.wins) do
		Wrap(F.wins[i])
	end
	F.Refresh()
end

function F.Disable()
	for i = 1, getn(F.wins) do
		Unwrap(F.wins[i])
	end
	H.Wipe(F.wins)
	F.general = nil
	for i = 1, getn(F.FEEDS) do
		local f = F.FEEDS[i].frame
		if f then
			C.Panel.RemoveText(f)
			f:Hide()
			f:Clear()
		end
	end
end

-- Раз в секунду: окно, которое игра пересоздала или перевесила, получает обертку заново (двойная не ставится).
function F.Verify()
	for i = 1, getn(F.wins) do
		local w = F.wins[i]
		local rec = wraps[w]
		if not rec or w.AddMessage ~= rec.fn then
			Wrap(w)
		end
	end
end
