-- HyoukaUI: Modules\Meter\MeterOptions.lua, страница настроек "Урон" (H.Options.AddPage, порядок 50).
--
-- Режим модуля (Выкл, Рядом, Вместо) выбирается на странице "Модули". Здесь: страницы трех мест дока, число справа,
-- сворачивание мелких строк в "Прочее", питомцы отдельно, показ вне забега, криты в карточке, сброс колонок и
-- разбивка своего героя. Все значения идут через H.DB (ключи модуля "meter", умолчания в Module.lua); модуль слушает SETTING.

local H = HyoukaUI
local MU = H.MeterUI

local function PageOptions(extra)
	local out = {}
	local Mo = MU.Model
	if extra == "auto" then
		table.insert(out, { value = "auto", label = MU.S("page_auto") })
	end
	for i = 1, table.getn(Mo.ORDER) do
		local id = Mo.ORDER[i]
		table.insert(out, { value = id, label = MU.S(Mo.PAGES[id].label) })
	end
	if extra == "off" then
		table.insert(out, { value = "off", label = MU.S("page_off") })
	end
	return out
end

local function RightOptions()
	return {
		{ value = "dps", label = MU.S("o_right_dps") },
		{ value = "total", label = MU.S("o_right_total") },
		{ value = "full", label = MU.S("o_right_full") },
	}
end

local function Build(page, f)
	f:Header(MU.S("o_cols"))
	f:Dropdown({ label = MU.S("o_slot1"), mod = "meter", key = "slot1", options = PageOptions(nil) })
	f:Dropdown({ label = MU.S("o_slot2"), mod = "meter", key = "slot2", options = PageOptions("auto") })
	f:Dropdown({ label = MU.S("o_slot3"), mod = "meter", key = "slot3", options = PageOptions("off") })
	f:Gap(4)
	f:Header(MU.S("o_view"))
	f:Dropdown({ label = MU.S("o_right"), mod = "meter", key = "rightText", options = RightOptions() })
	f:Slider({ label = MU.S("o_fold"), mod = "meter", key = "foldPct", min = 0, max = 20, step = 1,
		fmt = function(v)
			if v <= 0 then
				return MU.S("o_fold_off")
			end
			return string.format("%d%%", v)
		end })
	f:Toggle({ label = MU.S("o_pets"), mod = "meter", key = "pets" })
	f:Toggle({ label = MU.S("o_always"), mod = "meter", key = "always" })
	f:Toggle({ label = MU.S("o_crits"), mod = "meter", key = "crits" })
	f:Gap(4)
	f:Header(MU.S("o_actions"))
	f:Button({ label = MU.S("o_reset_all"), onClick = function()
		if MU.M.enabled then
			MU.Dock.ResetAll()
		end
	end })
	f:Button({ label = MU.S("o_open"), width = 170, onClick = function()
		if MU.M.enabled then
			MU.Breakdown.OpenSelf()
		end
	end })
	f:Gap(4)
	f:Note(MU.S("o_hint"))
end

-- Заголовок страницы: функция, чтобы язык читался в момент показа меню.
local function Label()
	return H.Kit.L("page_meter", MU.S("page_damage"))
end

if H.Options then
	H.Options.AddPage("meter", Label, Build, 50)
end
