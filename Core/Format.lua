-- HyoukaUI: форматирование чисел, времени и текста (spec 1.6).
--
-- Small(n)       Short, но дробное меньше 1 с сотыми (0.04)
-- Short(n)       K/M/B с отсечением, не округлением: 999 -> "999", 12345 -> "12.3K",
--                1234567 -> "1.23M", 1500000000 -> "1.50B"
-- Time(sec)      m:ss (от часа h:mm:ss)
-- HpText(cur, max)  "315K | 100%"; Pct(cur, max) -> целый процент без округления вверх
-- CdText(sec, decimalBelow)  текст отката: "45", "2m", "1h", при decimalBelow "4.2"
-- Int(n)         строка целого из кэша (без аллокаций для 0..199)
-- Roman(n)       римские цифры до 39
-- Utf8Len / Utf8Cut(s, chars) / Fit(s, chars)  работа с UTF-8 по символам, середину символа не режет

local H = HyoukaUI

local Fm = {}
H.Format = Fm

local floor = math.floor
local mod = math.mod
local fmt = string.format

-- Кэш строк целых: покадровый код ставит текст без склейки и форматирования.
local INT = {}
for i = 0, 199 do
	INT[i] = tostring(i)
end

function Fm.Int(n)
	n = floor(n)
	local s = INT[n]
	if s then
		return s
	end
	return fmt("%d", n)
end

function Fm.Short(n)
	if n == nil then
		return "0"
	end
	if n < 0 then
		return "-"..Fm.Short(-n)
	end
	if n < 1000 then
		return Fm.Int(n)
	end
	if n < 1000000 then
		local tenths = floor(n / 100)
		return fmt("%d.%dK", floor(tenths / 10), mod(tenths, 10))
	end
	if n < 1000000000 then
		local hundredths = floor(n / 10000)
		return fmt("%d.%02dM", floor(hundredths / 100), mod(hundredths, 100))
	end
	local hundredths = floor(n / 10000000)
	return fmt("%d.%02dB", floor(hundredths / 100), mod(hundredths, 100))
end

-- Short для малых дробных значений (лечение, скорость лечения): Short усекает 0.04 до "0" и прячет живое число.
-- Целые и числа от 1 идут как в Short; меньше 1 две цифры после точки (усечение), меньше 0.01 "<0.01". Причина жалобы "лечение всегда 0": скорость 12 лечения за 5 минут = 0.04 в секунду.
function Fm.Small(n)
	if n == nil or n == 0 then
		return "0"
	end
	if n < 0 then
		return "-"..Fm.Small(-n)
	end
	if n >= 1 or n == floor(n) then
		return Fm.Short(n)
	end
	local hundredths = floor(n * 100)
	if hundredths <= 0 then
		return "<0.01"
	end
	return fmt("0.%02d", hundredths)
end

-- Время: секунды -> "m:ss"; отрицательное и nil дают "0:00".
function Fm.Time(sec)
	if not sec or sec < 0 then
		sec = 0
	end
	sec = floor(sec)
	if sec >= 3600 then
		local h = floor(sec / 3600)
		local rest = sec - h * 3600
		return fmt("%d:%02d:%02d", h, floor(rest / 60), mod(rest, 60))
	end
	return fmt("%d:%02d", floor(sec / 60), mod(sec, 60))
end

-- Целый процент, без округления вверх: 99.9 -> 99, 100 только при cur >= max.
function Fm.Pct(cur, max)
	if not max or max <= 0 then
		return 0
	end
	if cur >= max then
		return 100
	end
	if cur <= 0 then
		return 0
	end
	return floor(cur / max * 100)
end

-- "315K | 100%". dead = true даст "DEAD" (метку подставляет вызывающий через Locale).
function Fm.HpText(cur, max, deadText)
	if deadText and (not cur or cur <= 0) then
		return deadText
	end
	return Fm.Short(cur or 0).." | "..Fm.Pct(cur or 0, max).."%"
end

-- Откат: целые секунды вверх; от минуты "Nm", от часа "Nh". decimalBelow > 0: до этого порога
-- одна цифра после точки (отсечение).
function Fm.CdText(sec, decimalBelow)
	if not sec or sec <= 0 then
		return ""
	end
	if decimalBelow and decimalBelow > 0 and sec < decimalBelow then
		local tenths = floor(sec * 10)
		return fmt("%d.%d", floor(tenths / 10), mod(tenths, 10))
	end
	if sec >= 3600 then
		return fmt("%dh", math.ceil(sec / 3600))
	end
	if sec >= 60 then
		return fmt("%dm", math.ceil(sec / 60))
	end
	return Fm.Int(math.ceil(sec))
end

local ROMAN_ONES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX" }
local ROMAN_TENS = { "X", "XX", "XXX" }

function Fm.Roman(n)
	n = floor(n or 0)
	if n < 1 or n > 39 then
		return Fm.Int(n)
	end
	local tens = floor(n / 10)
	local ones = mod(n, 10)
	local s = tens > 0 and ROMAN_TENS[tens] or ""
	if ones > 0 then
		s = s..ROMAN_ONES[ones]
	end
	return s
end

-- Код цвета для строки: "|cffRRGGBB" из долей 0..1.
function Fm.ColorCode(r, g, b)
	return fmt("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

----------------------------------------------------------------------------------------
-- UTF-8 по символам. Байт продолжения: 128..191. Кириллица занимает 2 байта.
----------------------------------------------------------------------------------------

local function IsCont(b)
	return b and b >= 128 and b < 192
end

function Fm.Utf8Len(s)
	local n = 0
	for i = 1, string.len(s) do
		if not IsCont(string.byte(s, i)) then
			n = n + 1
		end
	end
	return n
end

-- Первые chars символов строки; границу берет по началу символа.
function Fm.Utf8Cut(s, chars)
	if chars <= 0 then
		return ""
	end
	local count = 0
	local len = string.len(s)
	for i = 1, len do
		if not IsCont(string.byte(s, i)) then
			count = count + 1
			if count > chars then
				return string.sub(s, 1, i - 1)
			end
		end
	end
	return s
end

-- Обрезать до chars символов, с "..." если пришлось резать (многоточие входит в лимит).
function Fm.Fit(s, chars)
	if Fm.Utf8Len(s) <= chars then
		return s
	end
	if chars <= 3 then
		return Fm.Utf8Cut(s, chars)
	end
	return Fm.Utf8Cut(s, chars - 3).."..."
end

-- Без последнего символа.
function Fm.Utf8Chop(s)
	local len = string.len(s)
	local i = len
	while i > 0 and IsCont(string.byte(s, i)) do
		i = i - 1
	end
	return string.sub(s, 1, i - 1)
end
