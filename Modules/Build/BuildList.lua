-- HyoukaUI: модуль Build, список сборки (кусок build.list, plan 3.3).
--
-- Стопка полос в геометрии KickTracker (225x24 ретейл-px (было 199, расширено под длинные значения отката; ширина строк бижутерии Jewelry.ROW_W та же), шаг 25, рост вверх). Сверху заголовок "Сборка" акцентом
-- и счетчик "N/6" (красный при 6/6), затем 6 строк способностей по рангу (старший первым, при равенстве раньше
-- по слоту), недостающие слоты бледными строками "пустой слот", отдельная строка расовой способности с меткой
-- "(раса)", ниже раздел "Бижутерия" (строки Jewelry.lua). Строка: иконка, имя, справа колонки Info, Откат, Ранг.
--  * способности и ранги: H.Spells (AZS_SPELLS: ключ, ранг, id); имя и иконка из loadout, запасные из слота;
--  * откат: H.Spells.Cooldown с полом 0.25 с (две цифры до 1 с, одна до 10 с, дальше целые);
--  * Info: Build\AbilityInfo (подсказка кнопки через TooltipScan, ключи только из sourceKey, не из имен);
--  * пока баф способности активен (H.Buffs.Left, Duration), строка заливается цветом способности и убывает;
--  * подсказка строки: стоковая через GameTooltip:SetAction(слот), своих текстов нет.
-- Кадр с именем HyoukaUI_BuildList: AZS_SetOnTopOfScreens видит кадр и его детей (список виден на карточках).
-- Два уровня обновления: Rebuild (структура: порядок, имена, иконки, ранги, Info) по событиям, Tick раз в 0.1 с
-- (откат и убывание бафа) без таблиц и строк, пока данные не меняются.
-- Высота куска сообщается Layout (H.Layout.SetSize, ретейл-px): рамка растет вверх от якоря.

local H = HyoukaUI
local B = H.Build
local T = H.Theme
local Fm = H.Format

local L = {}
B.List = L

local C = { W = 225, ROW = 24, STEP = 25, HEAD = 16, SLOTS = 6, PAD = 4, RANKW = 20, CDW = 46, INFOW = 28, SYM = 7 }
local S = { rows = {}, jrows = {}, order = {}, height = 0, shown = false }
L.S, L.C = S, C

local function Settings()
	return B.M.db
end

----------------------------------------------------------------------------------------
-- Строки способностей
----------------------------------------------------------------------------------------

local function NewRow()
	local row = H.Panel.New(S.frame, { w = C.W, h = C.ROW, bg = "panel" })
	local b = T.Border()
	row.fill = row:CreateTexture(nil, "ARTWORK")
	row.fill:SetTexture(T.TEX.solid)
	row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", b, -b)
	row.fill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", b, b)
	row.fill:Hide()
	row.icon = H.Icon.New(row, { size = C.ROW - 2, border = false, digits = false })
	row.icon:SetPoint("LEFT", row, "LEFT", H.R(1), 0)
	row.name = H.Text.New(row, "body")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", H.R(3), 0)
	row.tag = H.Text.New(row, "small", { color = "muted" })
	row.tag:SetPoint("LEFT", row.name, "RIGHT", H.R(3), 0)
	row.rank = H.Text.New(row, "small", { justify = "RIGHT", w = C.RANKW, color = "dim" })
	row.cd = H.Text.New(row, "small", { justify = "RIGHT", w = C.CDW })
	row.info = H.Text.New(row, "small", { justify = "RIGHT", w = C.INFOW - C.SYM - 3, color = "muted" })
	row.sym = row:CreateTexture(nil, "OVERLAY")
	row.sym:SetWidth(H.R(C.SYM))
	row.sym:SetHeight(H.R(C.SYM))
	row.sym:SetVertexColor(0.5, 0.5, 0.5, 1)
	row.hover = row:CreateTexture(nil, "OVERLAY")
	row.hover:SetTexture(T.TEX.solid)
	row.hover:SetAllPoints(row)
	local hc = T.C.hover
	row.hover:SetVertexColor(hc[1], hc[2], hc[3], hc[4])
	row.hover:Hide()
	row.idx, row.slot, row.spellId, row.cdKey, row.fillW, row.kind = 0, nil, nil, -1, -1, 0
	row:EnableMouse(true)
	H.Script("build", row, "OnEnter", function(self)
		row.hover:Show()
		if row.slot then
			local left = S.frame:GetLeft()
			local half = H.Layout.Screen() / 2
			GameTooltip:SetOwner(row, (left and left > half) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
			GameTooltip:SetAction(row.slot)
			GameTooltip:Show()
		end
	end)
	H.Script("build", row, "OnLeave", function(self)
		row.hover:Hide()
		GameTooltip:Hide()
	end)
	return row
end

-- Колонки справа: положение каждой зависит от настроек. Возвращает ширину под колонками (ретейл-px).
local function PlaceColumns()
	local db = Settings()
	local x = C.PAD
	local rankX, cdX, infoX
	if db.showRank then
		rankX = x
		x = x + C.RANKW
	end
	if db.showCd then
		cdX = x
		x = x + C.CDW
	end
	if db.showInfo and not B.Info.Dead() then
		infoX = x
		x = x + C.INFOW
	end
	S.colRank, S.colCd, S.colInfo, S.colWidth = rankX, cdX, infoX, x
	for i = 1, table.getn(S.rows) do
		local row = S.rows[i]
		row.rank:ClearAllPoints()
		row.cd:ClearAllPoints()
		row.info:ClearAllPoints()
		row.sym:ClearAllPoints()
		if rankX then
			row.rank:SetPoint("RIGHT", row, "RIGHT", -H.R(rankX), 0)
		end
		if cdX then
			row.cd:SetPoint("RIGHT", row, "RIGHT", -H.R(cdX), 0)
		end
		if infoX then
			row.info:SetPoint("RIGHT", row, "RIGHT", -H.R(infoX), 0)
			row.sym:SetPoint("RIGHT", row.info, "LEFT", -H.R(3), 0)
		end
	end
	return x
end

local function ColorOfKey(key)
	local row = H.Loadout.AbilityRow(key)
	local sk = row and row.sourceKey or ("ability:"..key)
	return H.SourceColor(sk)
end

local function SetFill(row, r, g, b)
	row.fill:SetVertexColor(r, g, b, 0.45)
end

-- Заполнить строку способностью i из AZS_SPELLS (racial = расовая).
local function FillAbility(row, i, racial)
	local key = H.Spells.Key(i)
	local r, g, b = ColorOfKey(key)
	row.idx, row.slot, row.spellId = i, H.Spells.SlotOf(i), H.Spells.SpellId(i)
	row.empty = false
	row:SetAlpha(1)
	row.icon:Show()
	local path = H.Spells.Icon(i)
	if path ~= row.iconPath then
		row.iconPath = path
		H.Icon.SetTexture(row.icon, path)
	end
	H.Text.SetColor(row.name, "text")
	local room = H.R(C.W - C.ROW - 7 - S.colWidth)
	if racial then
		row.tag:SetText(B.T("racial"))
		row.tag:Show()
		room = room - (row.tag:GetStringWidth() or 0) - H.R(3)
	else
		row.tag:Hide()
	end
	H.Text.Fit(row.name, H.Spells.Name(i) or key, room)
	SetFill(row, r, g, b)
	T.SetBorderColor(row, 0, 0, 0, 1)
	row.rank:SetText("")
	row.info:SetText("")
	row.sym:Hide()
	row.kind = 0
	if racial then
		return
	end
	local rank = H.Spells.Rank(i)
	if rank and S.colRank then
		row.rank:SetText(Settings().roman and Fm.Roman(rank) or Fm.Int(rank))
	end
	if S.colInfo then
		local kind, value, ready = B.Info.Get(i)
		if not ready then
			S.pendingInfo = true
		end
		if kind then
			row.info:SetText(B.Info.NumText(value))
			row.sym:SetTexture(kind == "area" and T.TEX.ring or T.TEX.pip)
			row.sym:Show()
			row.kind = (kind == "area") and 2 or 1
		end
	end
end

local function FillEmpty(row)
	row.idx, row.slot, row.spellId, row.empty = 0, nil, nil, true
	row.iconPath = nil
	row:SetAlpha(0.45)
	row.icon:Hide()
	row.tag:Hide()
	row.fill:Hide()
	row.fillW = -1
	row.rank:SetText("")
	row.cd:SetText("")
	row.cdKey = 0
	row.info:SetText("")
	row.sym:Hide()
	H.Text.SetColor(row.name, "dim")
	H.Text.Fit(row.name, B.T("empty_slot"), H.R(C.W - C.ROW - 7 - S.colWidth))
end

-- Порядок обычных способностей: ранг по убыванию, при равенстве меньший индекс. Без таблиц.
local function SortOrder(n)
	local order = S.order
	for i = 1, n do
		order[i] = i
	end
	for i = 2, n do
		local v = order[i]
		local rv = H.Spells.Rank(v) or 0
		local j = i - 1
		while j >= 1 and (H.Spells.Rank(order[j]) or 0) < rv do
			order[j + 1] = order[j]
			j = j - 1
		end
		order[j + 1] = v
	end
end

----------------------------------------------------------------------------------------
-- Раскладка и обновление
----------------------------------------------------------------------------------------

local function PlaceAt(f, y)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", S.frame, "TOPLEFT", 0, -H.R(y))
end

local function Head(text)
	local h = CreateFrame("Frame", nil, S.frame)
	h.title = H.Text.New(h, "body", { color = "accent" })
	h.title:SetPoint("LEFT", h, "LEFT", H.R(2), 0)
	h.title:SetText(text)
	h.count = H.Text.New(h, "body", { justify = "RIGHT" })
	h.count:SetPoint("RIGHT", h, "RIGHT", -H.R(2), 0)
	return h
end

local function SizeHead(h)
	h:SetWidth(H.R(C.W))
	h:SetHeight(H.R(C.HEAD))
end

-- Создать кадры (один раз). Кусок регистрирует Build.lua через L.Ensure.
function L.Ensure()
	if S.frame then
		S.height = -1
		H.Layout.Piece("build.list", S.frame)
		return S.frame
	end
	S.height = -1
	S.frame = CreateFrame("Frame", "HyoukaUI_BuildList", UIParent)
	S.frame:SetFrameStrata("MEDIUM")
	S.head = Head(B.T("title"))
	S.jhead = Head(B.T("jewelry"))
	SizeHead(S.head)
	SizeHead(S.jhead)
	for i = 1, C.SLOTS + 1 do
		S.rows[i] = NewRow()
	end
	for i = 1, 5 do
		S.jrows[i] = B.Jewelry.NewRow(S.frame)
	end
	S.frame:Hide()
	H.Layout.Piece("build.list", S.frame)
	return S.frame
end

function L.Frame()
	return S.frame
end

function L.Remove()
	if S.frame then
		S.frame:Hide()
		S.height = -1
		H.Layout.Unpiece("build.list")
	end
end

local function CountText(n)
	local fs = S.head.count
	H.Text.Set(fs, string.format(H.L.build_count, n, C.SLOTS))
	H.Text.SetColor(fs, n >= C.SLOTS and "error" or "text")
end

local function UpdateJewelry(y)
	local db = Settings()
	local show = db.jewelryRows
	if not show then
		S.jhead:Hide()
		for i = 1, 5 do
			S.jrows[i]:Hide()
		end
		return y
	end
	S.jhead.title:SetText(B.T("jewelry"))
	S.jhead.count:SetText(string.format(H.L.build_count, B.Jewelry.Count(), 5))
	PlaceAt(S.jhead, y)
	S.jhead:Show()
	y = y + C.HEAD + 1
	for i = 1, 5 do
		local row = S.jrows[i]
		if B.Jewelry.Slot(i).link or db.jewelryEmpty then
			PlaceAt(row, y)
			B.Jewelry.UpdateRow(row, i, db.jewelryNames and "names" or "slot")
			row:Show()
			y = y + C.STEP
		else
			row:Hide()
		end
	end
	return y
end

-- Структура: порядок, имена, иконки, ранги, Info, высота куска. Вызывать по событиям.
function L.Rebuild()
	if not S.frame then
		return
	end
	S.pendingInfo = false
	PlaceColumns()
	for i = 1, table.getn(S.rows) do
		S.rows[i].name.huiFitText = nil
	end
	local count = H.Spells.Count()
	local n = count - 1
	if n < 0 then
		n = 0
	end
	if n > C.SLOTS then
		n = C.SLOTS
	end
	local y = 0
	PlaceAt(S.head, y)
	S.head.title:SetText(B.T("title"))
	S.head:Show()
	CountText(n)
	y = y + C.HEAD + 1
	if count > 0 then
		SortOrder(n)
		for i = 1, C.SLOTS do
			local row = S.rows[i]
			PlaceAt(row, y)
			if i <= n then
				FillAbility(row, S.order[i], false)
			else
				FillEmpty(row)
			end
			row:Show()
			y = y + C.STEP
		end
		local racial = S.rows[C.SLOTS + 1]
		PlaceAt(racial, y)
		FillAbility(racial, count, true)
		racial:Show()
		y = y + C.STEP
	else
		for i = 1, C.SLOTS + 1 do
			S.rows[i]:Hide()
		end
	end
	y = UpdateJewelry(y)
	if y > 0 then
		y = y - 1
	end
	if S.colInfo and B.Info.Dead() and not S.again then
		-- разбор подсказок не удался: колонка Info уходит, строки пересобираются уже без нее
		S.again = true
		L.Rebuild()
		S.again = false
		return
	end
	if y ~= S.height then
		S.height = y
		H.Layout.SetSize("build.list", nil, y)
	end
	L.Tick()
end

----------------------------------------------------------------------------------------
-- Динамика: откат и убывание бафа
----------------------------------------------------------------------------------------

-- Колонка "Откат" показывает время восстановления способности (полный кулдаун из AZS_SPELLS), а не бегущий таймер:
-- живой откат пользователь и так видит на панели способностей, а статичный текст не мигает (жалобы 2026-11-09 и 2026-11-10).
-- Меняется только вместе с самим кулдауном (улучшение способности), поэтому пишется по смене значения.
local function CdKey(dur)
	if not dur or dur <= 0 then
		return 0
	end
	return math.floor(dur * 100 + 0.5)
end

local function CdString(dur)
	if dur >= 60 then
		return Fm.CdText(dur)
	end
	local hundredths = math.floor(dur * 100 + 0.5)
	local tenths = math.floor(hundredths / 10 + 0.5)
	if hundredths < 100 and hundredths ~= tenths * 10 then
		return string.format("%d.%02d%s", math.floor(hundredths / 100), math.mod(hundredths, 100), H.L.unit_sec)
	end
	if math.mod(tenths, 10) == 0 then
		return string.format("%d%s", math.floor(tenths / 10), H.L.unit_sec)
	end
	return string.format("%d.%d%s", math.floor(tenths / 10), math.mod(tenths, 10), H.L.unit_sec)
end

local function TickRow(row)
	local i = row.idx
	if i == 0 then
		return
	end
	if S.colCd then
		local r = H.Spells.Row(i)
		local dur = r and type(r.cdmax) == "number" and r.cdmax > 0 and H.Rules.CooldownDuration(r.cdmax) or 0
		local key = CdKey(dur)
		if key ~= row.cdKey then
			row.cdKey = key
			row.cd:SetText(key == 0 and "" or CdString(dur))
		end
	end
	local id = row.spellId
	local w = 0
	if id and row.idx ~= S.racialIdx then
		local left = H.Buffs.Left(id)
		local dur = H.Buffs.Duration(id)
		if left and dur and dur > 0 and left > 0 then
			w = H.Bar.FillWidth(H.R(C.W) - 2 * T.Border(), left / dur)
		end
	end
	if w ~= row.fillW then
		row.fillW = w
		if w > 0 then
			row.fill:SetWidth(w)
			row.fill:Show()
		else
			row.fill:Hide()
		end
	end
end

--@frame
function L.Tick()
	if not S.frame or not S.frame:IsShown() then
		return
	end
	S.racialIdx = H.Spells.Count()
	for i = 1, C.SLOTS + 1 do
		TickRow(S.rows[i])
	end
end

function L.SetShown(on)
	if not S.frame then
		return
	end
	if on and not S.frame:IsShown() then
		S.frame:Show()
		L.Rebuild()
	elseif not on and S.frame:IsShown() then
		S.frame:Hide()
	end
end

function L.IsShown()
	return S.frame ~= nil and S.frame:IsShown()
end

-- Размеры, шрифты и шаги после смены PX, шрифта или языка.
function L.Relayout()
	if not S.frame then
		return
	end
	SizeHead(S.head)
	SizeHead(S.jhead)
	for i = 1, 5 do
		B.Jewelry.ForgetFit(S.jrows[i])
	end
	for i = 1, table.getn(S.rows) do
		local row = S.rows[i]
		row.sym:SetWidth(H.R(C.SYM))
		row.sym:SetHeight(H.R(C.SYM))
		row.cdKey, row.fillW = -1, -1
	end
	L.Rebuild()
end

function L.RowCount()
	local n = 0
	for i = 1, table.getn(S.rows) do
		if S.rows[i]:IsShown() then
			n = n + 1
		end
	end
	return n
end

function L.Row(i)
	return S.rows[i]
end

function L.JewelryRow(i)
	return S.jrows[i]
end

----------------------------------------------------------------------------------------
-- Подключение к модулю
----------------------------------------------------------------------------------------

local function OnData()
	S.retries = 0
	L.Rebuild()
end

local function OnScan(ev, kind)
	if kind == "spell" then
		L.Rebuild()
	end
end

local function OnLoadoutChanged()
	B.Info.Invalidate()
	OnData()
end

local function OnSpellsChanged()
	B.Info.Invalidate()
	OnData()
end

-- Подсказка способности может не прийти (очередь сканера снимает запись после 6 попыток): структура
-- перестраивается не чаще раза в 2 с и не больше 4 раз подряд, потом ждем события состава.
local retryTick = 0
local function OnTick()
	L.Tick()
	if S.pendingInfo and (S.retries or 0) < 4 then
		retryTick = retryTick + 1
		if retryTick >= 20 then
			retryTick = 0
			S.retries = (S.retries or 0) + 1
			L.Rebuild()
		end
	end
end

B.AddPart("list", function(M)
	B.Listen("SPELLS_CHANGED", OnSpellsChanged)
	B.Listen("LOADOUT_CHANGED", OnLoadoutChanged)
	B.Listen("SCAN_READY", OnScan)
	B.Listen("THEME", L.Relayout)
	B.Listen("FONTS", L.Relayout)
	B.Listen("LOCALE", L.Relayout)
	B.Listen("RUN_STARTED", OnData)
	M:Every(0.1, OnTick)
	B.Jewelry.Subscribe(OnData)
end, function()
	B.Jewelry.Unsubscribe(OnData)
	L.Remove()
end)
