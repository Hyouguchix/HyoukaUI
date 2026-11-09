-- HyoukaUI: Modules\Tracker\TrackerOptions, страница настроек "Трекер" (plan раздел 5, пункт 4).
-- Регистрируется из M:OnInit (Hub) через Tr.RegisterOptions, то есть при входе в мир и до включения модуля:
-- страница нужна и выключенному модулю (там же режим). Все значения идут через H.DB.Set("tracker", ключ, значение),
-- Hub слушает SETTING и применяет их на лету (захват частей HUD, видимость секций, пины).

local H = HyoukaUI

local Tr = H.Tr
local K = H.Kit

local function Opt(key, label, hint)
	return { label = Tr.T(label), hint = hint, mod = "tracker", key = key }
end

local function ModeOptions()
	local out = {}
	for i = 1, table.getn(H.MODES) do
		table.insert(out, { value = H.MODES[i], label = K.L("mode_"..H.MODES[i], H.MODE_LABELS[H.MODES[i]]) })
	end
	return out
end

local function Build(page, f)
	f:Header(Tr.T("o_title"))
	f:Segment({ label = Tr.T("label"), options = ModeOptions(), bw = 50, hint = Tr.T("o_mode_hint"),
		get = function()
			return H.GetMode("tracker")
		end,
		set = function(v)
			H.SetMode("tracker", v)
		end })
	f:Gap(4)
	f:Header(Tr.T("h_panel"))
	f:Toggle(Opt("panel", "o_panel"))
	f:Toggle(Opt("panelBg", "o_bg"))
	f:Toggle(Opt("timeline", "o_timeline"))
	f:Toggle(Opt("schedule", "o_schedule"))
	f:Toggle(Opt("guardians", "o_guardians"))
	f:Toggle(Opt("goal", "o_goal"))
	f:Toggle(Opt("tally", "o_tally"))
	f:Gap(4)
	f:Header(Tr.T("h_bars"))
	f:Toggle(Opt("bars", "o_bars"))
	local s = Opt("horizon", "o_horizon")
	s.min, s.max, s.step, s.fmt = 30, 300, 10, function(v)
		return tostring(v)
	end
	f:Slider(s)
	local r = Opt("relocate", "o_relocate")
	r.min, r.max, r.step, r.fmt = 5, 60, 5, function(v)
		return tostring(v)
	end
	f:Slider(r)
	f:Toggle(Opt("messages", "o_messages"))
	f:Toggle(Opt("countdown", "o_countdown"))
	f:Toggle(Opt("hideBanners", "o_hide_banners"))
	f:Gap(4)
	f:Header(Tr.T("h_frames"))
	f:Toggle(Opt("bossFrames", "o_boss_frames"))
	f:Toggle(Opt("thisRun", "o_this_run"))
	f:Toggle(Opt("crits", "o_crits"))
	f:Gap(4)
	f:Header(Tr.T("h_map"))
	f:Toggle(Opt("skin", "o_skin"))
	f:Toggle(Opt("clock", "o_clock"))
	f:Toggle(Opt("pins", "o_pins"))
	f:Toggle(Opt("pinBosses", "o_pin_bosses"))
	f:Toggle(Opt("flagHide", "o_flag"))
	local p = Opt("pinRange", "o_pin_range")
	p.min, p.max, p.step, p.fmt = 40, 300, 10, function(v)
		return tostring(v)
	end
	f:Slider(p)
	f:Note(Tr.T("n_pin_range"))
	f:Refresh()
end

function Tr.RegisterOptions()
	if not H.Options or not H.Options.AddPage then
		return
	end
	H.Options.AddPage("tracker", function()
		return K.L("page_tracker", Tr.T("label"))
	end, Build, 40)
end
