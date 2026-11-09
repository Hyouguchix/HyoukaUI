-- HyoukaUI: пробы этапа 0, которые создают временные кадры, требуют клика или трогают
-- стоковые кадры: 0.2, 0.10, 0.11, 0.14, 0.15. В "probe all" не входят.
--
-- 0.2 (риск): /hui probe 2 park [секунд] ставит MainMenuBar под скрытый кадр и следит
--     за ним; /hui probe 2 unpark возвращает. Возврат гарантирован тремя путями:
--     команда unpark, таймер (по умолчанию 600 с, максимум 3600) и PLAYER_LOGOUT.
--     Кадры 1.12 не переживают /reload: после него все стоковое на месте в любом случае.
-- 0.14: /hui probe 14 snap запоминает состояние стоковых кадров, compare сравнивает.
--     Кадры не двигаются, это только чтение.

local H = HyoukaUI
local P = H.Probes
local D = H.Debug

local EXPRESSWAY = "Interface\\AddOns\\SurvivorUITweaks\\Fonts\\Expressway.ttf"
local BACKGROUND = "Interface\\ChatFrame\\ChatFrameBackground"

local function Val(v)
	return D.Val(v)
end

local function Fx(v, digits)
	if type(v) ~= "number" then
		return tostring(v)
	end
	return string.format("%."..(digits or 3).."f", v)
end

local function NameOrNil(frame)
	if not frame then
		return "nil"
	end
	return tostring(frame.GetName and frame:GetName() or frame)
end

local function Hidden()
	if not P.hidden then
		P.hidden = CreateFrame("Frame", nil, UIParent)
		P.hidden:Hide()
	end
	return P.hidden
end

----------------------------------------------------------------------------------------
-- 0.2 Парковка MainMenuBar
----------------------------------------------------------------------------------------
local p2 = { parked = false, log = {}, saved = nil, last = {} }
local ACTION_SLOTS = { 1, 2, 3, 4, 5, 6, 12 }

local function P2Log(text)
	if table.getn(p2.log) < 40 then
		table.insert(p2.log, string.format("t=%.1f %s", GetTime(), text))
	end
end

local function P2Describe(r, tag)
	local mb = MainMenuBar
	if not mb then
		r:Add(tag.."MainMenuBar: нет такого кадра")
		return
	end
	r:Add(tag.."MainMenuBar: родитель "..NameOrNil(mb:GetParent())..", IsShown "..tostring(mb:IsShown())..", IsVisible "..tostring(mb:IsVisible())..", alpha "..Fx(mb:GetAlpha(), 2))
	local exp = MainMenuExpBar
	r:Add(tag.."MainMenuExpBar: "..(exp and ("IsVisible "..tostring(exp:IsVisible())) or "нет такого кадра"))
	local b1 = ActionButton1
	r:Add(tag.."ActionButton1: "..(b1 and ("родитель "..NameOrNil(b1:GetParent())..", IsVisible "..tostring(b1:IsVisible())) or "нет такого кадра"))
	for i = 1, table.getn(ACTION_SLOTS) do
		local slot = ACTION_SLOTS[i]
		local start, duration = 0, 0
		if GetActionCooldown then
			start, duration = GetActionCooldown(slot)
		end
		r:Add(tag.."  слот "..slot..": HasAction "..tostring(HasAction and HasAction(slot))..", текстура "..tostring(GetActionTexture and GetActionTexture(slot))..", cooldown "..Fx(start).." / "..tostring(duration))
	end
end

local function P2Watch()
	local mb = MainMenuBar
	if not mb then
		return
	end
	local hidden = Hidden()
	local reparented = (mb:GetParent() ~= hidden)
	if reparented and not p2.last.reparented then
		P2Log("ВОЗВРАТ: стоковый код вернул MainMenuBar родителя "..NameOrNil(mb:GetParent()))
	end
	p2.last.reparented = reparented
	local visible = mb:IsVisible() and true or false
	if visible and not p2.last.visible then
		P2Log("MainMenuBar снова ВИДИМ")
	end
	p2.last.visible = visible
	local exp = MainMenuExpBar
	local expVisible = exp and exp:IsVisible() and true or false
	if exp and expVisible ~= p2.last.exp then
		P2Log("MainMenuExpBar IsVisible "..tostring(expVisible))
	end
	p2.last.exp = expVisible
end

local function P2Unpark(why)
	if not p2.parked then
		return false
	end
	local mb = MainMenuBar
	local s = p2.saved
	local ok, err = pcall(function()
		mb:SetParent(s.parent or UIParent)
		mb:ClearAllPoints()
		for i = 1, table.getn(s.points) do
			local pt = s.points[i]
			mb:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
		end
		mb:SetFrameStrata(s.strata)
		mb:SetFrameLevel(s.level)
		if s.shown then
			mb:Show()
		else
			mb:Hide()
		end
	end)
	H.Clock.Stop("probe2")
	if not ok then
		P2Log("ОШИБКА возврата: "..tostring(err)..". Страховка: /reload")
		return false
	end
	p2.parked = false
	H.counters.parks = math.max(0, H.counters.parks - 1)
	P2Log("возвращен ("..tostring(why)..")")
	return true
end

local function P2Park(r, seconds)
	if p2.parked then
		r:Add("MainMenuBar уже запаркован. /hui probe 2 unpark вернет.")
		return
	end
	local mb = MainMenuBar
	if not mb then
		r:Add("MainMenuBar нет, парковать нечего")
		return
	end
	seconds = H.Clamp(tonumber(seconds) or 600, 10, 3600)
	local saved = { parent = mb:GetParent(), strata = mb:GetFrameStrata(), level = mb:GetFrameLevel(), shown = mb:IsShown(), points = {} }
	for i = 1, mb:GetNumPoints() do
		local point, rel, relPoint, x, y = mb:GetPoint(i)
		saved.points[i] = { point, rel, relPoint, x, y }
	end
	p2.saved = saved
	p2.last = {}
	local ok, err = pcall(function()
		mb:SetParent(Hidden())
	end)
	p2.parked = true
	H.counters.parks = H.counters.parks + 1
	if not ok then
		r:Add("SetParent упал: "..tostring(err)..", возвращаю")
		P2Unpark("ошибка парковки")
		return
	end
	H.Clock.Every("probe2", 1, P2Watch)
	H.Clock.After("probe2", seconds, function()
		P2Unpark("таймер "..seconds.." с")
	end)
	P2Log("запаркован на "..seconds.." с")
	r:Add("MainMenuBar ЗАПАРКОВАН под скрытый кадр на "..seconds.." с. Вернуть: /hui probe 2 unpark (или /reload).")
	P2Describe(r, "после парковки: ")
	r:Add("Проверь в игре: спеллы кастуются сами; цифры/текстуры слотов выше читаются у спрятанной панели; нужны ли '=' и автокаст. Потом получи уровень и карточки и смотри /hui probe 2 status: вернулась ли панель.")
end

P.Define(2, {
	title = "MainMenuBar под скрытый кадр (риск, вручную)",
	question = "Идут ли автокаст и '=' при спрятанной панели, читаются ли слоты 1..6 и 12 и не возвращается ли панель и опыт после уровня и карточек?",
	auto = false,
	run = function(r, arg)
		local _, _, cmd, rest = string.find(arg or "", "^(%S*)%s*(.-)$")
		cmd = string.lower(cmd or "")
		if cmd == "park" then
			P2Park(r, rest)
			return
		end
		if cmd == "unpark" then
			local ok = P2Unpark("команда")
			r:Add(ok and "MainMenuBar возвращен на место" or "возвращать нечего или возврат не удался (см. журнал)")
			P2Describe(r, "после возврата: ")
			return
		end
		r:Add("Состояние: запаркован = "..tostring(p2.parked))
		P2Describe(r, "")
		r:Add("Журнал наблюдения ("..table.getn(p2.log).."):")
		for i = 1, table.getn(p2.log) do
			r:Add("  "..p2.log[i])
		end
		r:Add("Команды: /hui probe 2 park [секунд]   /hui probe 2 unpark   /hui probe 2 status")
		r:Add("Риск: кадр родного интерфейса перевешивается. Возврат: unpark, таймер (по умолчанию 600 с), PLAYER_LOGOUT, /reload.")
	end,
})

H.On("PLAYER_LOGOUT", "debug", function()
	P2Unpark("выход")
end)

----------------------------------------------------------------------------------------
-- 0.10 Клик по своей кнопке: цель и ПКМ-меню
----------------------------------------------------------------------------------------
local p10 = { button = nil }

local function P10Pick()
	local units = H.Global("AZS_UNITS")
	if type(units) == "table" then
		for i = 1, table.getn(units) do
			local k = units[i].kind
			if k == "boss" or k == "final" or k == "guardian" or k == "elite" then
				return tostring(units[i].name)
			end
		end
	end
	return UnitName("target")
end

local function P10Say(text)
	local r = P.results[10]
	if r then
		r:Add(text)
		P.shown = { 10 }
		P.Save(r)
		P.Redraw()
	end
end

local function P10Click(self, button)
	if button == "RightButton" then
		local ok, err = pcall(function()
			if not PlayerFrameDropDown then
				error("PlayerFrameDropDown нет")
			end
			ToggleDropDownMenu(1, nil, PlayerFrameDropDown, "cursor")
		end)
		P10Say("[ПКМ] ToggleDropDownMenu(PlayerFrameDropDown): ok="..tostring(ok)..", "..tostring(err)..", PlayerFrame родитель "..NameOrNil(PlayerFrame and PlayerFrame:GetParent())..", DropDownList1 IsShown "..tostring(DropDownList1 and DropDownList1:IsShown()))
		return
	end
	local name = P10Pick()
	local before = UnitName("target")
	if not name then
		P10Say("[ЛКМ] нет цели-кандидата (ни AZS_UNITS, ни текущей цели): запусти в забеге рядом с врагом")
		return
	end
	local ok, err = pcall(TargetByName, name)
	P10Say("[ЛКМ] TargetByName("..name.."): ok="..tostring(ok)..", ошибка "..tostring(err)..", цель до "..Val(before)..", после "..Val(UnitName("target")))
	local ok2, err2 = pcall(TargetLastTarget)
	P10Say("[ЛКМ] TargetLastTarget: ok="..tostring(ok2)..", ошибка "..tostring(err2)..", цель теперь "..Val(UnitName("target")))
end

P.Define(10, {
	title = "TargetByName и ПКМ-меню из OnClick своей кнопки (вручную)",
	question = "Можно ли брать цель из OnClick своего кадра и открывается ли меню игрока при запаркованном PlayerFrame?",
	auto = false,
	run = function(r, arg)
		if arg == "off" then
			if p10.button then
				p10.button:Hide()
			end
			r:Add("кнопка пробы 0.10 скрыта")
			return
		end
		if not p10.button then
			local b = CreateFrame("Button", "HyoukaUI_ProbeBtn", UIParent)
			b:SetWidth(300)
			b:SetHeight(36)
			b:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
			b:SetFrameStrata("TOOLTIP")
			b:SetBackdrop({ bgFile = BACKGROUND })
			b:SetBackdropColor(0.1, 0.2, 0.6, 0.95)
			local label = b:CreateFontString(nil, "OVERLAY")
			label:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
			label:SetPoint("CENTER", b, "CENTER", 0, 0)
			label:SetText("Проба 0.10: ЛКМ - цель, ПКМ - меню")
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			H.Script("debug", b, "OnClick", P10Click)
			p10.button = b
		end
		p10.button:Show()
		r:Add("Синяя кнопка по центру сверху. ЛКМ: TargetByName по первому врагу из AZS_UNITS или по текущей цели. ПКМ: ToggleDropDownMenu(PlayerFrameDropDown). Результат каждого клика дописывается сюда.")
		r:Add("Убрать кнопку: /hui probe 10 off")
	end,
})

----------------------------------------------------------------------------------------
-- 0.11 Cooldown-модель, рамка 0.5333 AS, глифы, маска миникарты
----------------------------------------------------------------------------------------
local p11 = { box = nil }

local function Edge(parent, point1, point2, width, height, thick)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(BACKGROUND)
	t:SetVertexColor(1, 1, 1, 1)
	t:SetPoint(point1, parent, point1, 0, 0)
	t:SetPoint(point2, parent, point2, 0, 0)
	if width then
		t:SetWidth(thick)
	else
		t:SetHeight(thick)
	end
	return t
end

local function Square(parent, x, thick)
	local sq = CreateFrame("Frame", nil, parent)
	sq:SetWidth(36)
	sq:SetHeight(36)
	sq:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -14)
	local bg = sq:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(BACKGROUND)
	bg:SetVertexColor(0, 0, 0, 1)
	bg:SetAllPoints(sq)
	Edge(sq, "TOPLEFT", "TOPRIGHT", false, nil, thick)
	Edge(sq, "BOTTOMLEFT", "BOTTOMRIGHT", false, nil, thick)
	Edge(sq, "TOPLEFT", "BOTTOMLEFT", true, nil, thick)
	Edge(sq, "TOPRIGHT", "BOTTOMRIGHT", true, nil, thick)
	return sq
end

local GLYPHS = { { "бесконечность", "\226\136\158" }, { "закрывающий уголок", "\194\187" }, { "средняя точка", "\194\183" }, { "кириллица", "Тест" } }

local function P11Fonts()
	local fonts = { { "Expressway", EXPRESSWAY }, { "STANDARD_TEXT_FONT", STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" } }
	return fonts
end

local function P11Build(r)
	local box = CreateFrame("Frame", "HyoukaUI_ProbeBox", UIParent)
	box:SetWidth(330)
	box:SetHeight(150)
	box:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	box:SetFrameStrata("TOOLTIP")
	box:SetBackdrop({ bgFile = BACKGROUND })
	box:SetBackdropColor(0.15, 0.15, 0.15, 1)
	box:EnableMouse(true)
	H.Script("debug", box, "OnMouseDown", function() box:Hide() end)
	Square(box, 10, 0.5333333)
	Square(box, 60, 1)
	Square(box, 110, 2)
	local note = box:CreateFontString(nil, "OVERLAY")
	note:SetFont("Fonts\\ARIALN.TTF", 10, "")
	note:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -4)
	note:SetText("рамка 0.5333 / 1 / 2 AS (клик закрывает)")
	-- Cooldown-модель 1.12 поверх квадрата.
	local icon = CreateFrame("Frame", nil, box)
	icon:SetWidth(36)
	icon:SetHeight(36)
	icon:SetPoint("TOPLEFT", box, "TOPLEFT", 170, -14)
	local bg = icon:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(BACKGROUND)
	bg:SetVertexColor(0.2, 0.5, 0.2, 1)
	bg:SetAllPoints(icon)
	local ok, cd = pcall(CreateFrame, "Model", "HyoukaUI_ProbeCD", icon, "CooldownFrameTemplate")
	if ok and cd then
		pcall(cd.SetAllPoints, cd, icon)
		local ok2, err2 = pcall(CooldownFrame_SetTimer, cd, GetTime(), 10, 1)
		r:Add("Cooldown-модель: CreateFrame(Model, CooldownFrameTemplate) ok, CooldownFrame_SetTimer(10 с) ok="..tostring(ok2)..(ok2 and "" or (", "..tostring(err2)))..". Зеленый квадрат справа от рамок: идет ли шторка?")
	else
		r:Add("Cooldown-модель: CreateFrame упал: "..tostring(cd))
	end
	-- Глифы.
	local fonts = P11Fonts()
	for i = 1, table.getn(fonts) do
		local line = box:CreateFontString(nil, "OVERLAY")
		local fok, ferr = pcall(line.SetFont, line, fonts[i][2], 13, "OUTLINE")
		line:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -64 - (i - 1) * 24)
		line:SetText("Тест \226\136\158 \194\187 \194\183 0123")
		r:Add("шрифт "..fonts[i][1]..": SetFont ok="..tostring(fok)..(fok and "" or (" "..tostring(ferr)))..", ширина образца "..Fx(line:GetStringWidth(), 1))
		local ref = box:CreateFontString(nil, "OVERLAY")
		pcall(ref.SetFont, ref, fonts[i][2], 13, "OUTLINE")
		ref:SetText("x")
		local xw = ref:GetStringWidth()
		for g = 1, table.getn(GLYPHS) do
			ref:SetText(GLYPHS[g][2])
			r:Add("  "..GLYPHS[g][1]..": ширина "..Fx(ref:GetStringWidth(), 2).." (буква x: "..Fx(xw, 2)..", ширина около 0 значит нет глифа; точный ответ дает скриншот)")
		end
	end
	return box
end

P.Define(11, {
	title = "Cooldown-модель, рамка 0.5333 AS, глифы, маска миникарты (вручную)",
	question = "Рисуется ли Cooldown-модель, четка ли рамка 0.5333 AS, есть ли глифы бесконечность, уголок, точка и кириллица, есть ли Minimap:SetMaskTexture?",
	auto = false,
	run = function(r, arg)
		if arg == "off" then
			if p11.box then
				p11.box:Hide()
			end
			r:Add("окно пробы 0.11 скрыто")
			return
		end
		if not p11.box then
			p11.box = P11Build(r)
		else
			r:Add("окно уже собрано, показываю снова (значения ширин см. в сохраненном результате при первом запуске)")
		end
		p11.box:Show()
		r:Add("Minimap.SetMaskTexture: "..tostring(Minimap and type(Minimap.SetMaskTexture)))
		r:Add("Снять скриншот области рамок через zoom в исходном разрешении: толщина первой рамки должна быть ровно 1 физический пиксель. Закрыть: клик по окну или /hui probe 11 off.")
		H.Clock.After("probe11", 120, function()
			if p11.box then
				p11.box:Hide()
			end
		end)
	end,
})

----------------------------------------------------------------------------------------
-- 0.14 Состояние стоковых кадров до и после выключения рамок SurvivorUI
----------------------------------------------------------------------------------------
local WATCH_FRAMES = { "MainMenuBar", "MainMenuExpBar", "MainMenuBarMaxLevelBar", "BonusActionBarFrame", "MultiBarBottomLeft",
	"MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "ShapeshiftBarFrame", "PetActionBarFrame", "PlayerFrame", "TargetFrame", "MinimapCluster" }

local function P14Snapshot()
	local snap = { frames = {}, flags = {} }
	local names = {}
	for i = 1, table.getn(WATCH_FRAMES) do
		table.insert(names, WATCH_FRAMES[i])
	end
	for i = 1, 12 do
		table.insert(names, "ActionButton"..i)
	end
	for i = 1, table.getn(names) do
		local f = H.Global(names[i])
		if f and f.GetParent then
			local point = "-"
			if f.GetPoint and f:GetNumPoints() > 0 then
				local p1, rel, rp, x, y = f:GetPoint(1)
				point = tostring(p1).." "..NameOrNil(rel).." "..tostring(rp).." "..Fx(x, 1).." "..Fx(y, 1)
			end
			snap.frames[names[i]] = "parent="..NameOrNil(f:GetParent()).." shown="..tostring(f:IsShown()).." visible="..tostring(f:IsVisible()).." alpha="..Fx(f:GetAlpha(), 2).." scale="..Fx(f:GetScale(), 2).." strata="..tostring(f:GetFrameStrata()).." point="..point
		else
			snap.frames[names[i]] = "нет кадра"
		end
	end
	local db = H.Global("SurvivorUIDB")
	if type(db) == "table" then
		local n = 0
		for k, v in pairs(db) do
			local t = type(v)
			if (t == "number" or t == "string" or t == "boolean") and n < 80 then
				snap.flags[tostring(k)] = tostring(v)
				n = n + 1
			end
		end
	end
	snap.loaded = H.IsCoexist()
	return snap
end

local function P14Store()
	HyoukaUIDB.probeData = HyoukaUIDB.probeData or {}
	return HyoukaUIDB.probeData
end

P.Define(14, {
	title = "SurvivorUI с выключенными рамками не трогает MainMenuBar и ActionButton (вручную)",
	question = "Меняет ли SurvivorUI положение или видимость стоковой панели и кнопок, когда его рамки выключены?",
	auto = false,
	run = function(r, arg)
		arg = string.lower(arg or "")
		local store = P14Store()
		if arg == "snap" then
			store.p14 = P14Snapshot()
			store.p14.when = date and date("%Y-%m-%d %H:%M:%S") or "?"
			local n = 0
			for _ in pairs(store.p14.frames) do
				n = n + 1
			end
			r:Add("Снимок сохранен: кадров "..n..", флагов SurvivorUIDB "..table.getn(H.SortedKeys(store.p14.flags))..", SurvivorUI загружен "..tostring(store.p14.loaded))
			r:Add("Дальше: выключи рамки в настройках SurvivorUI, при необходимости /reload, затем /hui probe 14 compare")
			return
		end
		if arg == "compare" then
			local was = store.p14
			if not was then
				r:Add("Нет снимка: сначала /hui probe 14 snap")
				return
			end
			local now = P14Snapshot()
			r:Add("Снимок от "..tostring(was.when).."; сейчас SurvivorUI загружен: "..tostring(now.loaded))
			local diffs = 0
			local keys = H.SortedKeys(now.frames)
			for i = 1, table.getn(keys) do
				local k = keys[i]
				if was.frames[k] ~= now.frames[k] then
					diffs = diffs + 1
					r:Add("ИЗМЕНИЛСЯ "..k..": было "..tostring(was.frames[k]))
					r:Add("                  стало "..tostring(now.frames[k]))
				end
			end
			local fk = H.SortedKeys(now.flags)
			for i = 1, table.getn(fk) do
				if was.flags[fk[i]] ~= now.flags[fk[i]] then
					r:Add("флаг SurvivorUIDB."..fk[i]..": было "..tostring(was.flags[fk[i]])..", стало "..tostring(now.flags[fk[i]]))
				end
			end
			r:Add("Кадров с отличиями: "..diffs..(diffs == 0 and ". SurvivorUI эти кадры не трогал (при условии, что рамки в SurvivorUI были выключены между снимками)." or ""))
			return
		end
		r:Add("Только чтение, кадры не двигаются.")
		r:Add("/hui probe 14 snap - запомнить состояние MainMenuBar, ActionButton1..12 и др. при включенных рамках SurvivorUI")
		r:Add("/hui probe 14 compare - сравнить после выключения рамок SurvivorUI")
		local was = store.p14
		r:Add("Сохраненный снимок: "..(was and ("от "..tostring(was.when)) or "нет"))
	end,
})

----------------------------------------------------------------------------------------
-- 0.15 Дробные размеры шрифта
----------------------------------------------------------------------------------------
local SIZES = { 6, 6.4, 6.9, 7, 7.5, 8, 9.07, 12.27 }

P.Define(15, {
	title = "FontString:SetFont с дробным размером (6.4, 6.9, ...)",
	question = "Клиент рисует дробные размеры иначе, чем 6 и 7, или округляет?",
	auto = false,
	run = function(r)
		local f = P.Scratch()
		local fonts = P11Fonts()
		for fi = 1, table.getn(fonts) do
			local fs = f:CreateFontString(nil, "OVERLAY")
			local result = {}
			r:Add("шрифт "..fonts[fi][1].." ("..fonts[fi][2].."), текст: Hg Test 0123456789")
			for i = 1, table.getn(SIZES) do
				local size = SIZES[i]
				local ok, err = pcall(fs.SetFont, fs, fonts[fi][2], size, "OUTLINE")
				fs:SetText("Hg Test 0123456789")
				local w = fs:GetStringWidth()
					-- Факт из игры (2026-11-09): у FontString нет GetStringHeight, размеры различаем по ширине.
					local h = fs.GetStringHeight and fs:GetStringHeight() or 0
				local _, back = fs:GetFont()
				result[size] = { w = w, h = h }
				r:Add(string.format("  размер %-5s: SetFont ok=%s, ширина %s, высота %s, GetFont вернул размер %s%s", tostring(size), tostring(ok), Fx(w, 3), Fx(h, 3), tostring(back), ok and "" or (" "..tostring(err))))
			end
			local function Same(a, b)
				return result[a] and result[b] and math.abs(result[a].w - result[b].w) < 0.01 and math.abs(result[a].h - result[b].h) < 0.01
			end
			r:Add("  6.4 совпадает с 6: "..tostring(Same(6.4, 6))..", с 7: "..tostring(Same(6.4, 7)).."; 6.9 с 6: "..tostring(Same(6.9, 6))..", с 7: "..tostring(Same(6.9, 7)))
			r:Add("  вывод: "..((Same(6.4, 6) or Same(6.4, 7) or Same(6.9, 7)) and "клиент, вероятно, округляет размер: переводить размеры в целые AS и добирать SetScale" or "дробные размеры различимы по метрикам: сверить глазами скриншотом"))
		end
	end,
})
