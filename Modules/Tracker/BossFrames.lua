-- HyoukaUI: Modules\Tracker\BossFrames, рамки боссов (plan 3.2, spec 3.1, tracker#21, #22).
--
-- До 5 рамок 220x43 стопкой вверх (шаг 45) от куска tr.bossFrames: финальный босс первым, затем боссы, затем
-- проснувшиеся стражи. Данные только из H.Units: настоящие HP (hp, hpm), состояние state (1 = ярость босса,
-- проснулся страж), дебаффы через H.Units.Debuffs. Рамка: имя слева сверху, "HP | %" слева снизу, справа "ЯРОСТЬ"
-- красным при ярости (ресурса у боссов в данных нет: только состояние). Заливка по виду: финальный акцентом,
-- босс #7471C3, страж #7C7C7C на темной основе #111111; вне боя рамка бледнеет до 0.4. Слева квадраты дебаффов
-- до 5 (иконка, стаки, откат от duration и remaining; свой дебафф с акцентной рамкой). Наведение дает белую рамку,
-- цель (UnitName("target") совпадает с именем) тоже; клик берет цель H.Units.TargetById (TargetByName проверена
-- пробой 0.10, при промахе игра вернет прошлую цель).
-- Перерисовка по UNITS_CHANGED; дебаффы раз в 0.25 с и только если данные менялись (AZS_GetDebuffs создает
-- таблицу на вызов). Режим Вместо: Claim "bosses" (полосы HP боссов игры).

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local getn = table.getn

local MAXR, MAXD = 5, 5
local DEB_STEP = 0.25

local BF = { rows = {}, list = {}, debDirty = false, debAt = 0, shown = 0 }
Tr.BossFrames = BF

local function R(px)
	return H.R(px)
end

local function Collect()
	H.Wipe(BF.list)
	local bosses = H.Units.Bosses()
	for i = 1, getn(bosses) do
		if bosses[i].kind == "final" and getn(BF.list) < MAXR then
			table.insert(BF.list, bosses[i])
		end
	end
	for i = 1, getn(bosses) do
		if bosses[i].kind ~= "final" and getn(BF.list) < MAXR then
			table.insert(BF.list, bosses[i])
		end
	end
	local guards = H.Units.Guardians()
	for i = 1, getn(guards) do
		if guards[i].state == 1 and getn(BF.list) < MAXR then
			table.insert(BF.list, guards[i])
		end
	end
end

local function Border(row)
	local white = row.hover or row.isTarget
	if white ~= row.white then
		row.white = white
		row.border:SetColor(white and "white" or "edge")
	end
end

local function Highlight()
	local name = UnitName and UnitName("target")
	for i = 1, MAXR do
		local row = BF.rows[i]
		row.isTarget = (row.id ~= nil and name ~= nil and row.name == name)
		Border(row)
	end
end

local function Fill(row, u)
	local inner = row.inner
	local frac = 0
	if u.hpm and u.hpm > 0 and u.hp then
		frac = u.hp / u.hpm
		if frac > 1 then
			frac = 1
		elseif frac < 0 then
			frac = 0
		end
	end
	local w = H.Theme.Snap(inner * frac)
	if w ~= row.w then
		row.w = w
		if w <= 0 then
			row.fill:Hide()
		else
			row.fill:SetWidth(w)
			row.fill:Show()
		end
	end
end

local function Bind(row, u)
	row.id = u.id
	if row.name ~= u.name then
		row.name = u.name
		H.Text.Fit(row.nameFs, u.name or "", row.inner - R(60))
	end
	local rest = Tr.C.rest
	row.fill:SetVertexColor(rest[1], rest[2], rest[3], rest[4])
	row.hpFs:SetText(Fm.HpText(u.hp or 0, u.hpm or 0))
	local enraged = (u.kind ~= "guardian" and u.state == 1)
	if enraged then
		row.rageFs:SetText(Tr.T("rage"))
		row.rageFs:Show()
		Tr.Color(row.nameFs, Tr.C.red)
	else
		row.rageFs:Hide()
		-- вид босса только цветом имени (заливка и фон не инвертируются, dark mode ретейла)
		if u.kind == "final" then
			local r, g, b = Tr.Accent()
			row.nameFs:SetTextColor(r, g, b, 1)
		elseif u.kind == "guardian" then
			Tr.Color(row.nameFs, Tr.C.gray)
		else
			Tr.Color(row.nameFs, Tr.C.bossKind)
		end
	end
	Fill(row, u)
	row.frame:SetAlpha(H.Units.InFight(u) and 1 or 0.4)
	row.frame:Show()
end

local function Debuffs(now)
	local icons = H.Icon
	for i = 1, BF.shown do
		local row = BF.rows[i]
		local list = row.id and H.Units.Debuffs(row.id) or nil
		local n = list and getn(list) or 0
		if n > MAXD then
			n = MAXD
		end
		for j = 1, MAXD do
			local ic = row.icons[j]
			if j <= n then
				local d = list[j]
				icons.SetTexture(ic, d.icon)
				icons.SetStack(ic, d.stacks)
				if not d.permanent and d.duration and d.remaining and d.duration > 0 then
					icons.SetCooldown(ic, now - (d.duration - d.remaining), d.duration)
				else
					icons.SetCooldown(ic, 0, 0)
				end
				if d.spell and H.Units.Owns(d.spell) then
					local r, g, b = Tr.Accent()
					icons.SetBorderColor(ic, r, g, b, 1)
				else
					icons.SetBorderColor(ic, 0, 0, 0, 1)
				end
				ic:Show()
			else
				icons.SetCooldown(ic, 0, 0)
				ic:Hide()
			end
		end
	end
	for i = BF.shown + 1, MAXR do
		for j = 1, MAXD do
			BF.rows[i].icons[j]:Hide()
		end
	end
end

local function Refresh()
	if not BF.container then
		return
	end
	Collect()
	local n = getn(BF.list)
	BF.shown = n
	for i = 1, MAXR do
		local row = BF.rows[i]
		if i <= n then
			Bind(row, BF.list[i])
		else
			row.id, row.name = nil, nil
			row.hover = false
			row.frame:Hide()
		end
	end
	Highlight()
	BF.debDirty = true
	BF.debAt = 0
end

local function MarkDebuffs()
	BF.debDirty = true
end

--@frame
local function Tick(now)
	if BF.debDirty and now >= BF.debAt then
		BF.debDirty = false
		BF.debAt = now + DEB_STEP
		Debuffs(now)
	end
end

local function MakeRow(i)
	local FRAME_W, FRAME_H, STEP = Tr.Def("tr.bossFrames", "w", 220), Tr.Def("tr.bossFrames", "h", 43), Tr.Def("tr.bossFrames", "step", 45)
	BF.fw, BF.fh, BF.fstep = FRAME_W, FRAME_H, STEP
	local f = CreateFrame("Button", nil, BF.container)
	f:SetWidth(R(FRAME_W))
	f:SetHeight(R(FRAME_H))
	f:SetPoint("BOTTOMLEFT", BF.container, "BOTTOMLEFT", 0, (i - 1) * R(STEP))
	f:EnableMouse(true)
	-- Темный режим ретейла (spec 1, 3.1): остаток здоровья #111111, потерянное #4F4F4F (у игрока и цели так же).
	Tr.Fill(f, Tr.C.lost, "BACKGROUND"):SetAllPoints(f)
	local b = H.Theme.Border()
	local fill = Tr.Fill(f, Tr.C.rest, "ARTWORK")
	fill:SetPoint("TOPLEFT", f, "TOPLEFT", b, -b)
	fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", b, b)
	fill:Hide()
	local border = K.Border(f, "edge")
	local nameFs = K.Text(f, "body", nil, "LEFT")
	nameFs:SetPoint("TOPLEFT", f, "TOPLEFT", R(4), -R(5))
	local hpFs = K.Text(f, "body", nil, "LEFT")
	hpFs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", R(4), R(5))
	local rageFs = K.Text(f, "body", nil, "RIGHT")
	rageFs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -R(4), R(5))
	Tr.Color(rageFs, Tr.C.red)
	rageFs:Hide()
	local row = { frame = f, fill = fill, border = border, nameFs = nameFs, hpFs = hpFs, rageFs = rageFs, icons = {},
		inner = R(FRAME_W) - 2 * b, w = -1, hover = false, isTarget = false, white = false }
	local prev
	for j = 1, MAXD do
		local ic = H.Icon.New(f, { size = FRAME_H, digitsRole = "num" })
		if prev then
			ic:SetPoint("RIGHT", prev, "LEFT", -R(1), 0)
		else
			ic:SetPoint("RIGHT", f, "LEFT", -R(1), 0)
		end
		ic:Hide()
		row.icons[j] = ic
		prev = ic
	end
	H.Script("tracker", f, "OnEnter", function()
		row.hover = true
		Border(row)
	end)
	H.Script("tracker", f, "OnLeave", function()
		row.hover = false
		Border(row)
	end)
	H.Script("tracker", f, "OnClick", function()
		if row.id then
			H.Units.TargetById(row.id)
		end
	end)
	f:Hide()
	return row
end

local function Build()
	BF.container = CreateFrame("Frame", nil, UIParent)
	for i = 1, MAXR do
		BF.rows[i] = MakeRow(i)
	end
end

local function Place()
	if not BF.container then
		return
	end
	Tr.Set(BF.container, Tr.Opt("bossFrames") and Tr.InRun())
end

Tr.Part("bossframes", {
	build = Build,
	show = function()
		Tr.Register("tr.bossFrames", BF.container)
	end,
	hide = function()
		BF.shown = 0
		for i = 1, MAXR do
			BF.rows[i].frame:Hide()
			BF.rows[i].id, BF.rows[i].name = nil, nil
		end
	end,
	refresh = Refresh,
	place = Place,
	tick = Tick,
	theme = function()
		for i = 1, MAXR do
			local row = BF.rows[i]
			local f = row.frame
			local b = H.Theme.Border()
			f:SetWidth(R(BF.fw))
			f:SetHeight(R(BF.fh))
			f:ClearAllPoints()
			f:SetPoint("BOTTOMLEFT", BF.container, "BOTTOMLEFT", 0, (i - 1) * R(BF.fstep))
			row.fill:ClearAllPoints()
			row.fill:SetPoint("TOPLEFT", f, "TOPLEFT", b, -b)
			row.fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", b, b)
			row.inner = R(BF.fw) - 2 * b
			row.w = -1
			row.name = nil
		end
	end,
	reset = function()
		BF.debDirty = false
	end,
	settings = function(key)
		Place()
	end,
	on = { UNITS_CHANGED = Refresh, DEBUFFS = MarkDebuffs, PLAYER_TARGET_CHANGED = Highlight },
	dump = function(out)
		table.insert(out, "рамки боссов: показано "..BF.shown)
		for i = 1, BF.shown do
			local r = BF.rows[i]
			table.insert(out, "  "..i..". "..tostring(r.name).."  "..tostring(r.hpFs:GetText()).."  id "..tostring(r.id))
		end
	end,
})
