-- HyoukaUI: Modules\Meter\Card.lua, карточка при наведении на строку счетчика (inv meter #15, #16; plan 3.4).
--
-- Строка способности (страницы Урон, Скорость, Лечение, Босс, 30 с): ранг, перезарядка с полом, "готово через",
-- длительность баффа (только свои способности героя, из H.Spells и H.Buffs), затем число, доля и скорость В ТОМ ЖЕ
-- периоде, что и полоса (после Reset места это значения после чекпойнта, critic meter "Card's Damage done ignore Reset"),
-- затем криты и обычные удары места (Crits, если боевой текст дал события).
-- Строка героя на странице Группа: число, доля, скорость, лучшая способность с ее скоростью, топ 8 способностей с долей,
-- бижутерия забега и число очков талантов (H.Loadout этого владельца).
--
-- Карточка своя (плоский кадр), а не GameTooltip: строки и числа не создают таблиц игры, подсказки игры над доком остаются
-- свободными. Показывается слева от дока, если док правее середины экрана, иначе справа; низ вровень с доком.
-- Card.Hover(row) / Card.Unhover(row) зовет строка; Card.Refresh() зовет Dock раз в 0.5 с, пока карточка видна.

local H = HyoukaUI
local MU = H.MeterUI
local K = H.Kit
local Fm = H.Format

local getn = table.getn
local min = math.min

local C = {}
MU.Card = C

local WIDTH, TITLE_H, LINE_H, PAD = 196, 18, 13, 5   -- ретейл-px
local MAX_LINES = 28

local S = { frame = nil, title = nil, lines = {}, n = 0, row = nil, shown = false, ownerView = nil }

local function Build()
	if S.frame then
		return
	end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("HIGH")
	K.Fill(f, "bg", "BACKGROUND")
	f.border = K.Border(f, "edge")
	f:Hide()
	S.frame = f
	S.title = K.Text(f, "chat", nil, "LEFT")
end

local function Line(i)
	local ln = S.lines[i]
	if not ln then
		local f = S.frame
		ln = { l = K.Text(f, "normal", nil, "LEFT"), v = K.Text(f, "normal", nil, "RIGHT") }
		S.lines[i] = ln
	end
	return ln
end

local function Begin(text, r, g, b)
	S.n = 0
	S.title:SetText(text or "")
	S.title:SetTextColor(r or 1, g or 1, b or 1, 1)
end

-- Строка "подпись - значение"; token - цвет значения.
local function Row(label, value, token)
	if S.n >= MAX_LINES then
		return
	end
	S.n = S.n + 1
	local ln = Line(S.n)
	ln.l:SetText(label or "")
	K.TextColor(ln.l, "muted")
	ln.v:SetText(value or "")
	K.TextColor(ln.v, token or "text")
	ln.l:Show()
	ln.v:Show()
end

local function Head(text)
	if S.n >= MAX_LINES then
		return
	end
	S.n = S.n + 1
	local ln = Line(S.n)
	ln.l:SetText(text)
	K.TextColor(ln.l, "accent")
	ln.v:SetText("")
	ln.l:Show()
	ln.v:Show()
end

-- Размеры и якоря в AS заново на каждый показ: PX мог смениться (разрешение, масштаб).
local function Finish()
	local f = S.frame
	f:SetWidth(H.R(WIDTH))
	S.title:ClearAllPoints()
	S.title:SetPoint("TOPLEFT", f, "TOPLEFT", H.R(PAD), -H.R(3))
	for i = 1, S.n do
		local ln = S.lines[i]
		local y = H.R(TITLE_H + (i - 1) * LINE_H)
		ln.l:ClearAllPoints()
		ln.l:SetPoint("TOPLEFT", f, "TOPLEFT", H.R(PAD), -y)
		ln.v:ClearAllPoints()
		ln.v:SetPoint("TOPRIGHT", f, "TOPRIGHT", -H.R(PAD), -y)
	end
	for i = S.n + 1, getn(S.lines) do
		S.lines[i].l:Hide()
		S.lines[i].v:Hide()
	end
	f:SetHeight(H.R(TITLE_H + S.n * LINE_H + PAD))
end

local function Sec(v)
	if v < 10 then
		return string.format("%.1f", v).." "..MU.S("sec")
	end
	return Fm.Small(v).." "..MU.S("sec")
end

local function Num(v)
	return v and Fm.Small(v) or "-"
end

----------------------------------------------------------------------------------------
-- Содержимое
----------------------------------------------------------------------------------------

local function Spell(item)
	local key, rank = H.Loadout.ParseSource(item.sourceKey)
	local si = key and H.Spells.Find(key)
	if not si then
		if rank then
			Row(MU.S("c_rank"), Fm.Int(rank))
		end
		return
	end
	rank = rank or H.Spells.Rank(si)
	if rank then
		Row(MU.S("c_rank"), Fm.Int(rank))
	end
	local rec = H.Spells.Row(si)
	local dur = rec and H.Rules.CooldownDuration(rec.cdmax) or 0
	if dur > 0 then
		Row(MU.S("c_cd"), Sec(dur))
		local rem = H.Spells.Remaining(si)
		if rem > 0 then
			Row(MU.S("c_ready"), Sec(rem), "warn")
		end
	end
	local spell = H.Spells.SpellId(si)
	local left = spell and H.Buffs.Left(spell)
	if left then
		Row(MU.S("c_buff"), Sec(H.Buffs.Duration(spell) or left))
		Row(MU.S("c_buff_for"), Sec(left), "ok")
	end
end

local function Crits(view, item)
	if not MU.opt.crits or not view.slot or view.slot < 1 or view.pageId == "last30" then
		return
	end
	local s = MU.Crits.Get(view.slot, item.sourceKey, item.name)
	if not s or s.hits == 0 then
		return
	end
	if s.crits > 0 then
		Head(MU.S("c_crits"))
		Row(MU.S("c_count"), Fm.Int(s.crits).." ("..Fm.Int(math.floor(s.crits / s.hits * 100)).."%)")
		Row(MU.S("c_best"), Num(s.critMax), "gold")
		Row(MU.S("c_avg"), Num(s.critSum / s.crits))
		Row(MU.S("c_min"), Num(s.critMin))
		Row(MU.S("c_last"), Num(s.critLast))
	end
	local normals = s.hits - s.crits
	if normals > 0 then
		Head(MU.S("c_hits"))
		Row(MU.S("c_count"), Fm.Int(normals))
		Row(MU.S("c_avg"), Num(s.normSum / normals))
		Row(MU.S("c_last"), Num(s.normLast))
	end
end

local function FillSource(view, item)
	Begin(item.name, item.r, item.g, item.b)
	if item.kind == "others" then
		Row(MU.S("c_damage"), Num(item.amount))
		Row(MU.S("c_share"), Fm.Int(item.pct).."%")
		return
	end
	if view.page and not view.page.heal then
		Spell(item)
	end
	local what = (view.page and view.page.heal) and "c_healing" or "c_damage"
	Row(MU.S(what), Num(item.amount))
	Row(MU.S("c_share"), Fm.Int(item.pct).."%")
	Row(MU.S("c_rate"), Num(item.rate))
	if item.proc then
		Row(MU.S("c_proc"), "(proc)", "accent")
	end
	if not (view.page and view.page.heal) then
		Crits(view, item)
	end
end

local function FillOwner(view, item)
	Begin(item.name, item.r, item.g, item.b)
	Row(MU.S("c_damage"), Num(item.amount))
	Row(MU.S("c_share"), Fm.Int(item.pct).."%")
	Row(MU.S("c_rate"), Num(item.rate))
	local ov = S.ownerView
	if not ov then
		ov = MU.Model.NewOwnerView("card")
		S.ownerView = ov
	end
	MU.Model.SetOwner(ov, item.ownerId)
	MU.Model.UpdateOwner(ov, false)
	if ov.n > 0 then
		local top = ov.items[1]
		Head(MU.S("c_top"))
		Row(top.name, Num(top.rate))
		Head(MU.S("c_spells"))
		for i = 1, min(8, ov.n) do
			local it = ov.items[i]
			Row(it.name, Fm.Int(it.pct).."%")
		end
	end
	H.Loadout.Request(item.ownerId)
	local data = H.Loadout.Get(item.ownerId)
	local jewelry = MU.Model.JewelryNames(data)
	if jewelry then
		Head(MU.S("c_jewelry"))
		Row(jewelry, "")
	end
	if data and data.talents and getn(data.talents) > 0 then
		Row(MU.S("c_talents"), Fm.Int(MU.Model.TalentPoints(data)).." "..MU.S("c_points"))
	end
end

----------------------------------------------------------------------------------------
-- Показ
----------------------------------------------------------------------------------------

local function Place()
	local dock = MU.Dock.Frame()
	local f = S.frame
	f:ClearAllPoints()
	if not dock then
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -H.R(430), H.R(1))
		return
	end
	local cx = dock:GetCenter()
	local sw = H.Layout.Screen()
	if cx and cx < sw / 2 then
		f:SetPoint("BOTTOMLEFT", dock, "BOTTOMRIGHT", H.R(2), 0)
	else
		f:SetPoint("BOTTOMRIGHT", dock, "BOTTOMLEFT", -H.R(2), 0)
	end
end

local function Fill()
	local row = S.row
	local item, view = row.huiItem, row.huiView
	if not item or not view then
		return false
	end
	if item.kind == "owner" then
		FillOwner(view, item)
	else
		FillSource(view, item)
	end
	Finish()
	return true
end

function C.Hover(row)
	Build()
	S.row = row
	if Fill() then
		Place()
		S.frame:Show()
		S.shown = true
	end
end

function C.Unhover(row)
	if S.row == row then
		C.Hide()
	end
end

function C.Hide()
	S.row, S.shown = nil, false
	if S.frame then
		S.frame:Hide()
	end
end

function C.IsShown()
	return S.shown
end

function C.Refresh()
	if S.shown and S.row then
		if Fill() then
			Place()
		else
			C.Hide()
		end
	end
end

-- Для тестов: показанные строки "подпись|значение" и заголовок.
function C.Lines(out)
	for i = 1, S.n do
		table.insert(out, S.lines[i].l:GetText().."|"..S.lines[i].v:GetText())
	end
	return S.title and S.title:GetText()
end

function C.Drop()
	C.Hide()
	if S.ownerView then
		MU.Model.Dispose(S.ownerView)
		S.ownerView = nil
	end
end
