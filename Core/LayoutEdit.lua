-- HyoukaUI: пользовательские изменения раскладки (дополнение к Core\Layout.lua): оторвать кусок,
-- масштаб, показ, "на место", снимки для отмены. Хранится только отличие от умолчаний:
-- HyoukaUIDB.layout[id] = { p, rp, x, y, scale, hidden }, запись без отличий удаляется.
-- Каждое изменение шлет событие LAYOUT(id).

local H = HyoukaUI
local L = H.Layout

local getn = table.getn
local FRAC = L.FRAC
local Store, SavedMake, SavedClean, Changed, R, PX = L.Store, L.SavedMake, L.SavedClean, L.Changed, L.R, L.PX

function L.Snapshot(id)
	local r = L.Saved(id)
	if not r then
		return false
	end
	return H.Copy(r, 2)
end

function L.Restore(id, snap)
	local s = Store()
	if not s then
		return
	end
	if snap then
		s[id] = H.Copy(snap, 2)
	else
		s[id] = nil
	end
	Changed(id)
end

local function SameAsDefault(id, point, relPoint, xpx, ypx)
	local dl, dt, dw, dh = L.DefaultRect(id)
	if not dl then
		return false
	end
	local scale = L.Scale(id)
	local fp, fr = FRAC[point], FRAC[relPoint]
	local sw, sh = L.Screen()
	local l = fr[1] * sw + R(xpx) * scale - fp[1] * dw
	local t = fr[2] * sh - R(ypx) * scale - fp[2] * dh
	local eps = PX() * 0.01
	return math.abs(l - dl) < eps and math.abs(t - dt) < eps
end

-- Оторвать кусок: точка угла экрана и смещение в ретейл-px. Если это и есть умолчание, ничего не пишется.
function L.SetPlace(id, point, relPoint, xpx, ypx)
	if not L.Has(id) then
		return false
	end
	if SameAsDefault(id, point, relPoint, xpx, ypx) then
		local r = L.Saved(id)
		if r then
			r.p, r.rp, r.x, r.y = nil, nil, nil, nil
			SavedClean(id)
		end
	else
		local r = SavedMake(id)
		if not r then
			return false
		end
		r.p, r.rp, r.x, r.y = point, relPoint, xpx, ypx
	end
	Changed(id)
	return true
end

-- Поставить кусок так, чтобы его левый верхний угол был в (left, top) AS. Угол экрана выбирается по
-- четверти, куда попал центр: при смене разрешения кусок остается у своего края. Позиция - целые px.
function L.PlaceRect(id, left, top)
	local _, _, w, h = L.Rect(id)
	if not w then
		return false
	end
	local sw, sh = L.Screen()
	local fx = (left + w / 2 < sw / 2) and 0 or 1
	local fy = (top + h / 2 < sh / 2) and 0 or 1
	local name
	if fy == 0 then
		name = (fx == 0) and "TOPLEFT" or "TOPRIGHT"
	else
		name = (fx == 0) and "BOTTOMLEFT" or "BOTTOMRIGHT"
	end
	local scale = L.Scale(id)
	local unit = PX() * scale
	-- Ближе чем на полпикселя к умолчанию: это и есть умолчание, ничего не пишем.
	local dl, dt = L.DefaultRect(id)
	if dl and math.abs(left - dl) <= unit * 0.5 + 0.000001 and math.abs(top - dt) <= unit * 0.5 + 0.000001 then
		local r = L.Saved(id)
		if r then
			r.p, r.rp, r.x, r.y = nil, nil, nil, nil
			SavedClean(id)
		end
		Changed(id)
		return true
	end
	local xas = (left + fx * w) - fx * sw
	local yas = -((top + fy * h) - fy * sh)
	return L.SetPlace(id, name, name, H.Round(xas / unit), H.Round(yas / unit))
end

function L.SetScale(id, scale)
	if not L.Has(id) then
		return false
	end
	scale = H.Clamp(scale, 0.5, 2)
	scale = math.floor(scale * 100 + 0.5) / 100
	if scale == 1 and not L.Saved(id) then
		return false
	end
	local r = SavedMake(id)
	if not r then
		return false
	end
	r.scale = (scale ~= 1) and scale or nil
	SavedClean(id)
	Changed(id)
	return true
end

function L.SetHidden(id, hidden)
	if not L.Has(id) then
		return false
	end
	if hidden then
		local r = SavedMake(id)
		if not r then
			return false
		end
		r.hidden = true
		L.HideRaw(id)
	else
		local r = L.Saved(id)
		if r then
			r.hidden = nil
			SavedClean(id)
		end
	end
	Changed(id)
	return true
end

-- Вернуть кусок целиком на место: позиция, масштаб, показ.
function L.Reset(id)
	local s = Store()
	if s and s[id] then
		s[id] = nil
	end
	Changed(id)
end

function L.ResetAll()
	local s = Store()
	if s then
		for k in pairs(s) do
			s[k] = nil
		end
	end
	L.Reflow()
	H.Fire("LAYOUT", nil)
end

-- Сколько кусков оторвано, изменено в масштабе или скрыто (для Options и selftest).
function L.SavedCount()
	local s, n = Store(), 0
	if s then
		for _ in pairs(s) do
			n = n + 1
		end
	end
	return n
end

-- Строки для /hui geometry: AS и ретейл-px (левый верх, ширина, высота).
function L.GeometryLines()
	local out = {}
	local ids = L.Ids()
	for i = 1, getn(ids) do
		local id = ids[i]
		local l, t, w, h = L.Rect(id)
		local pl, pt, pw, ph = L.RectPx(id)
		table.insert(out, string.format("%s  AS %.1f,%.1f %.1fx%.1f  px %.1f,%.1f %.1fx%.1f%s%s", id, l, t, w, h,
			pl, pt, pw, ph, L.IsCollapsed(id) and " [схлопнут]" or "", L.IsDetached(id) and " [оторван]" or ""))
	end
	return out
end

