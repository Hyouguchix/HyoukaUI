-- HyoukaUI: текст. Строка роли, кэш показанного значения, обрезка по ширине без поломки UTF-8.
--
-- Text.New(parent, role, opts)   opts: color (имя или массив), justify, layer, w (ретейл-px)
-- Text.Set(fs, text)             ставит текст, только если он изменился
-- Text.SetNumber(fs, n)          K/M/B, форматирует только при смене числа
-- Text.SetInt(fs, n)             целое из кэша строк
-- Text.SetColor(fs, color)       имя из Theme.C или массив
-- Text.Fit(fs, text, maxWidth)   ставит текст, обрезая до ширины (AS) с "...": середину символа не режет

local H = HyoukaUI
local T = H.Theme
local Fm = H.Format

local X = {}
H.Text = X

local function ColorOf(color)
	if type(color) == "string" then
		return T.C[color] or T.C.text
	end
	return color or T.C.text
end

function X.SetColor(fs, color)
	local c = ColorOf(color)
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	fs.huiColor = c
end

function X.New(parent, role, opts)
	opts = opts or {}
	local fs = parent:CreateFontString(nil, opts.layer or "OVERLAY")
	H.Fonts.Apply(fs, role or "body", opts.delta)
	X.SetColor(fs, opts.color)
	fs:SetJustifyH(opts.justify or "LEFT")
	if opts.w then
		fs:SetWidth(H.R(opts.w))
	end
	return fs
end

--@frame
function X.Set(fs, text)
	if fs.huiText ~= text then
		fs.huiText = text
		fs:SetText(text)
	end
end

--@frame
function X.SetNumber(fs, n)
	if fs.huiNum ~= n then
		fs.huiNum = n
		fs.huiText = nil
		fs:SetText(Fm.Short(n))
	end
end

--@frame
function X.SetInt(fs, n)
	if fs.huiNum ~= n then
		fs.huiNum = n
		fs.huiText = nil
		fs:SetText(Fm.Int(n))
	end
end

-- Самый длинный префикс text (в символах), который с "..." помещается в maxWidth.
-- Поиск половинным делением: несколько SetText вместо перебора по одному символу.
function X.Fit(fs, text, maxWidth)
	if fs.huiFitText == text and fs.huiFitW == maxWidth then
		return fs.huiFitShown
	end
	fs:SetText(text)
	local shown = text
	if fs:GetStringWidth() > maxWidth then
		local lo, hi = 0, Fm.Utf8Len(text) - 1
		while lo < hi do
			local mid = math.floor((lo + hi + 1) / 2)
			fs:SetText(Fm.Utf8Cut(text, mid).."...")
			if fs:GetStringWidth() <= maxWidth then
				lo = mid
			else
				hi = mid - 1
			end
		end
		shown = Fm.Utf8Cut(text, lo).."..."
		fs:SetText(shown)
	end
	fs.huiFitText, fs.huiFitW, fs.huiFitShown = text, maxWidth, shown
	fs.huiText = shown
	fs.huiNum = nil
	return shown
end

-- H.Text(parent, role, delta) -> FontString: вызов для слоя Kit (окна ядра). delta в ретейл-пикселях.
setmetatable(X, {
	__call = function(self, parent, role, delta)
		return X.New(parent, role, { delta = delta })
	end,
})
