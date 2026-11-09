-- HyoukaUI: стек для Layout (дополнение к Core\Layout.lua): дети друг за другом, скрытые схлопываются.

local H = HyoukaUI
local L = H.Layout

local getn = table.getn
local R, PX = L.R, L.PX

----------------------------------------------------------------------------------------
-- Стек: дети друг за другом, скрытые схлопываются (audit meter-20, tracker-15/18)
----------------------------------------------------------------------------------------

-- Layout.Stack(id, frame, { children = {frame...}, gap = retail px, dir = "down"|"up", collapse = true })
-- Возвращает { Reflow, Add, height }. Высоту стека (AS) ставит на frame и передает куску id.
function L.Stack(id, frame, opts)
	local S = { children = {}, gap = opts.gap or 1, dir = opts.dir or "down", collapse = opts.collapse ~= false, height = 0 }
	function S.Reflow()
		local top = (S.dir == "down")
		local prev, total = nil, 0
		local gapAs = R(S.gap)
		for i = 1, getn(S.children) do
			local c = S.children[i]
			if c:IsShown() or not S.collapse then
				c:ClearAllPoints()
				if prev then
					if top then
						c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gapAs)
					else
						c:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, gapAs)
					end
					total = total + gapAs
				elseif top then
					c:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
				else
					c:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
				end
				total = total + (c:GetHeight() or 0)
				prev = c
			end
		end
		S.height = total
		frame:SetHeight(total)
		if id and L.Has(id) then
			L.SetSize(id, nil, total / PX())
		end
	end
	function S.Add(child)
		table.insert(S.children, child)
		local origShow, origHide = child.Show, child.Hide
		child.Show = function(self, a)
			origShow(self, a)
			S.Reflow()
		end
		child.Hide = function(self, a)
			origHide(self, a)
			S.Reflow()
		end
		S.Reflow()
	end
	for i = 1, getn(opts.children or {}) do
		S.Add(opts.children[i])
	end
	return S
end
