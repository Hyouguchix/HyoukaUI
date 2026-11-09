-- HyoukaUI: Modules\Tracker\Minimap, плоская миникарта tr.minimap (plan 3.2, spec 3.9). Только перекрой стокового
-- кадра Minimap, своей карты нет.
--
-- Кусок tr.minimap это держатель 230x230 с рамкой 1 px и тремя строками: зона слева сверху (#E6D90D 0.9), часы
-- устройства и FPS слева снизу (часы из H.Run.LocalClock, FPS из GetFramerate раз в 3 с). Режим Рядом: держатель
-- только с рамкой и текстами, стоковая миникарта не трогается. Режим Вместо (и настройка skin): Minimap
-- переносится в держатель (SetParent, точка CENTER, масштаб под размер), маска меняется на сплошной квадрат
-- (Minimap:SetMaskTexture, проба 0.11), украшения (MinimapCluster и кнопки) уходят в H.Park, текстуры прячутся,
-- колесо мыши меняет зум. Все возвращается при выключении: родитель, точки, страта, масштаб, стоковая маска
-- "Textures\\MinimapMask" (читать маску назад в 1.12 нельзя). Claim "localClock" ставит Hub (часы игры рисуются вне
-- интерфейса и сдвинуть их нельзя, api 2.9).
-- [НЕ ПРОВЕРЕНО] состав украшений в benilla (имена кадров из FrameXML 1.12), поведение SetScale на Minimap и
-- маски-квадрата: проверка в игре, строки ниже в записке передачи. Имена стоковых кадров читаются H.Global.

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit
local Fm = H.Format

local floor = math.floor

local STOCK_MASK = "Textures\\MinimapMask"

-- Украшения и кнопки стоковой миникарты (1.12). Кадры идут в H.Park, текстуры прячутся.
local DECOR = { "MinimapCluster", "MinimapBackdrop", "MinimapBorder", "MinimapBorderTop", "MiniMapMailFrame",
	"MiniMapTrackingFrame", "MiniMapBattlefieldFrame", "MiniMapMeetingStoneFrame", "MinimapZoomIn", "MinimapZoomOut",
	"MiniMapWorldMapButton", "GameTimeFrame", "MinimapToggleButton", "MinimapZoneTextButton", "MinimapNorthTag" }

local MM = { styled = false, saved = nil, hidden = {}, nHidden = 0, clockStr = {}, fpsStr = {}, lastMin = -1, fpsTick = 0, lastFps = -1 }
Tr.Minimap = MM

local function R(px)
	return H.R(px)
end

----------------------------------------------------------------------------------------
-- Перекрой стоковой карты
----------------------------------------------------------------------------------------

local function Rescale()
	local mm = H.Global("Minimap")
	if not MM.styled or not mm or not MM.holder then
		return
	end
	local inner = (MM.holder:GetWidth() or R(Tr.Def("tr.minimap", "w", 230))) - 2 * H.Theme.Border()
	local mw = MM.saved.w
	if mw and mw > 0 and inner > 0 then
		mm:SetScale(inner / mw)
	end
end

local function Zoom(delta)
	local mm = H.Global("Minimap")
	if not mm or not mm.GetZoom or not delta then
		return
	end
	local z = (mm:GetZoom() or 0) + (delta > 0 and 1 or -1)
	if z < 0 then
		z = 0
	elseif z > 5 then
		z = 5
	end
	mm:SetZoom(z)
end

local function Restyle()
	if MM.styled or not Tr.Opt("skin") or not MM.holder then
		return
	end
	local mm = H.Global("Minimap")
	if type(mm) ~= "table" or not mm.SetParent then
		return
	end
	local saved = { parent = mm:GetParent(), strata = mm:GetFrameStrata(), level = mm:GetFrameLevel(), scale = mm:GetScale(),
		w = mm:GetWidth(), points = {} }
	for i = 1, mm:GetNumPoints() or 0 do
		local p, rel, rp, x, y = mm:GetPoint(i)
		saved.points[i] = { p, rel, rp, x, y }
	end
	MM.saved = saved
	MM.styled = true
	mm:SetParent(MM.holder)
	mm:SetFrameStrata("LOW")
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", MM.holder, "CENTER", 0, 0)
	Rescale()
	if mm.SetMaskTexture then
		pcall(mm.SetMaskTexture, mm, H.Theme.TEX.solid)
	end
	-- Украшения: после переноса карты стоковый держатель уносится целиком.
	for i = 1, table.getn(DECOR) do
		local obj = H.Global(DECOR[i])
		if type(obj) == "table" and obj ~= mm then
			if obj.GetObjectType and obj:GetObjectType() == "Texture" then
				if obj:IsShown() then
					obj:Hide()
					MM.nHidden = MM.nHidden + 1
					MM.hidden[MM.nHidden] = obj
				end
			elseif obj.SetParent then
				H.Park(obj, "tracker")
			end
		end
	end
	if mm.EnableMouseWheel then
		mm:EnableMouseWheel(true)
		H.Script("tracker", mm, "OnMouseWheel", function(self, delta)
			Zoom(delta)
		end)
	end
	MM.bg:Show()
end

local function Restore()
	if not MM.styled then
		return
	end
	MM.styled = false
	local mm = H.Global("Minimap")
	local s = MM.saved
	H.Unpark("tracker")
	for i = 1, MM.nHidden do
		MM.hidden[i]:Show()
		MM.hidden[i] = nil
	end
	MM.nHidden = 0
	if type(mm) == "table" and s then
		if mm.SetMaskTexture then
			pcall(mm.SetMaskTexture, mm, STOCK_MASK)
		end
		mm:SetScript("OnMouseWheel", nil)
		if s.parent then
			mm:SetParent(s.parent)
		end
		mm:SetFrameStrata(s.strata or "LOW")
		mm:SetFrameLevel(s.level or 1)
		mm:SetScale(s.scale or 1)
		mm:ClearAllPoints()
		for i = 1, table.getn(s.points) do
			local p = s.points[i]
			mm:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	end
	MM.saved = nil
	if MM.bg then
		MM.bg:Hide()
	end
end

----------------------------------------------------------------------------------------
-- Тексты
----------------------------------------------------------------------------------------

local function Zone()
	if MM.zoneFs then
		MM.zoneFs:SetText(H.Run.Zone("zname") or "")
	end
end

local function ClockText(hh, mm)
	local key = hh * 60 + mm
	local s = MM.clockStr[key]
	if not s then
		s = string.format("%02d:%02d", hh, mm)
		MM.clockStr[key] = s
	end
	return s, key
end

local function FpsText(fps)
	local s = MM.fpsStr[fps]
	if not s then
		s = Fm.Int(fps).." "..Tr.T("fps")
		MM.fpsStr[fps] = s
	end
	return s
end

local function Texts()
	local on = Tr.Opt("clock")
	if on then
		MM.clockFs:Show()
		MM.fpsFs:Show()
	else
		MM.clockFs:Hide()
		MM.fpsFs:Hide()
	end
end

local function Slow(now)
	if not Tr.Opt("clock") or not MM.clockFs then
		return
	end
	local hh, mi = H.Run.LocalClock()
	-- Часы игры прячутся, только когда свои часы известны: смена доступности пересматривает захват.
	if (hh ~= nil) ~= MM.clockOk then
		MM.clockOk = (hh ~= nil)
		Tr.SyncHud()
	end
	if hh then
		local s, key = ClockText(hh, mi)
		if key ~= MM.lastMin then
			MM.lastMin = key
			MM.clockFs:SetText(s)
		end
	end
	MM.fpsTick = MM.fpsTick + 1
	if MM.fpsTick >= 3 then
		MM.fpsTick = 0
		if GetFramerate then
			local fps = floor(GetFramerate() or 0)
			if fps < 0 then
				fps = 0
			end
			if fps ~= MM.lastFps then
				MM.lastFps = fps
				MM.fpsFs:SetText(FpsText(fps))
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- Кадры и часть
----------------------------------------------------------------------------------------

local function Build()
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetFrameStrata("LOW")
	MM.holder = holder
	MM.bg = K.Fill(holder, "bg", "BACKGROUND")
	MM.bg:Hide()
	K.Border(holder, "edge")
	local over = CreateFrame("Frame", nil, holder)
	over:SetAllPoints(holder)
	over:SetFrameLevel(holder:GetFrameLevel() + 20)
	MM.zoneFs = K.Text(over, "title", nil, "LEFT")
	MM.zoneFs:SetPoint("TOPLEFT", over, "TOPLEFT", R(4), -R(4))
	Tr.Color(MM.zoneFs, Tr.C.zone)
	MM.clockFs = K.Text(over, "title", nil, "LEFT")
	MM.clockFs:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", R(4), R(16))
	MM.clockFs:SetTextColor(1, 1, 1, 0.9)
	MM.fpsFs = K.Text(over, "title", nil, "LEFT")
	MM.fpsFs:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", R(4), R(4))
	MM.fpsFs:SetTextColor(1, 1, 1, 0.9)
end

local function Place()
	if not MM.holder then
		return
	end
	Tr.Set(MM.holder, true)
	Texts()
	if Tr.IsReplace() and Tr.Opt("skin") then
		Restyle()
	else
		Restore()
	end
end

Tr.Part("minimap", {
	build = Build,
	show = function()
		Tr.Register("tr.minimap", MM.holder)
		MM.lastMin, MM.lastFps, MM.clockOk = -1, -1, nil
		MM.fpsTick = 3
	end,
	hide = function()
		Restore()
	end,
	refresh = function()
		Zone()
		Rescale()
		Slow(0)
	end,
	place = Place,
	slow = Slow,
	replace = function(on)
		Place()
	end,
	settings = function(key)
		Place()
	end,
	on = { ZONE = Zone, LOGOUT = function()
		Restore()
	end },
	dump = function(out)
		table.insert(out, "миникарта: перекроена "..tostring(MM.styled).."  скрытых текстур "..MM.nHidden
			.."  запаркованных кадров "..H.Parking.Count())
	end,
})
