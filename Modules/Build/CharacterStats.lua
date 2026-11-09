-- HyoukaUI: модуль Build, описание статов забега для окна персонажа (inv build#28, #29).
--
-- Ключи и формулы взяты из кода движка (engine-lua\framexml_fixes.lua, AZS_Update и AZS_UpdateMore): значения чисел,
-- отсутствующее значение = 0. Тексты подсказок на английском повторяют движок, русские - перевод.
-- Данные дает слой H.Stats (запрос к ядру, см. handoff_build.md): H.Stats.Get(key) -> число или nil, H.Stats.Has() -> есть ли
-- данные забега. Если слоя нет, Has() считается ложным и окно показывает "Начните забег".
--
-- Виды значения (kind): add  +N% от (v - 1), haste +N% от (1 - v), spct +N% от v, pct1 N.N% от v x 100, pct0 N% от v x 100,
-- int N, plus +N, dec1 N.N, yd N yd. Строки "условного" урона (cond) скрыты, пока значение 0 (как у движка);
-- остальные скрываются при нуле настройкой hideZero.
-- Вклад надетой экипировки: поле gear = ключ g* (ghp, gdmg, ...), его вид gearKind (по умолчанию тот же).
--
-- X.SECTIONS - разделы по порядку, X.DEF[key] - описание, X.Value(key), X.IsZero(key, v), X.Text(key, v),
-- X.Label(key), X.Tip(key), X.GearText(key), X.Headline() -> текст бонуса урона.

local H = HyoukaUI
local B = H.Build

local X = {}
B.StatDefs = X

X.SECTIONS = {
	{ key = "sec_attack", rows = { "crit", "cm", "dmg", "cd", "echo" } },
	{ key = "sec_defense", rows = { "hp", "reg", "lch", "arm", "heal", "thn", "liv" } },
	{ key = "sec_reach", rows = { "area", "cnt", "pick" } },
	{ key = "sec_utility", rows = { "spd", "xp", "gold", "luck", "bp" } },
	{ key = "sec_dot", rows = { "dots", "doth" } },
	{ key = "sec_bonus", rows = { "big", "exe", "cc", "dotd", "shd", "auto", "pet" } },
}

local DEF = {
	crit = { kind = "pct1", gear = "gcrit", gearKind = "spct" },
	cm = { kind = "pct0", gear = "gcm", gearKind = "spct" },
	dmg = { kind = "add", gear = "gdmg", gearKind = "spct" },
	cd = { kind = "haste", gear = "gcd", gearKind = "spct" },
	echo = { kind = "pct0", gear = "gecho", gearKind = "spct" },
	hp = { kind = "int", gear = "ghp", gearKind = "plus" },
	reg = { kind = "dec1", gear = "greg", gearKind = "plus" },
	lch = { kind = "pct1" },
	arm = { kind = "pct0", gear = "garm", gearKind = "spct" },
	heal = { kind = "int" },
	thn = { kind = "pct0" },
	liv = { kind = "int" },
	area = { kind = "add", gear = "garea", gearKind = "spct" },
	cnt = { kind = "plus", gear = "gcnt", gearKind = "plus" },
	pick = { kind = "yd", gear = "gpick", gearKind = "spct" },
	spd = { kind = "add", gear = "gspd", gearKind = "spct" },
	xp = { kind = "add" },
	gold = { kind = "add", gear = "ggold", gearKind = "spct" },
	luck = { kind = "spct" },
	bp = { kind = "spct" },
	dots = { kind = "int" },
	doth = { kind = "spct" },
	big = { kind = "spct", cond = true },
	exe = { kind = "spct", cond = true },
	cc = { kind = "spct", cond = true },
	dotd = { kind = "spct", cond = true },
	shd = { kind = "spct", cond = true },
	auto = { kind = "spct", cond = true },
	pet = { kind = "spct", cond = true },
}
X.DEF = DEF

local TEXT = {
	enUS = {
		crit = { "Crit", "The chance a spell strikes critically. Past 100%, the rest adds to your critical damage." },
		cm = { "Crit Dmg", "A critical strike deals this much of a spell's damage." },
		dmg = { "Damage", "Every spell you cast deals this much more damage. It grows with your level, gear, talents, jewelry and buffs." },
		cd = { "Haste", "Your spells come back this much sooner." },
		echo = { "Echo", "The chance a spell strikes twice. Past 100%, every spell strikes twice and the rest is the chance of a third." },
		hp = { "Health", "The most health you can have." },
		reg = { "Regen", "Health you regain every second." },
		lch = { "Lifesteal", "Heals you for this much of all the damage you deal." },
		arm = { "Armor", "Damage you take is reduced by this much (60% at most)." },
		heal = { "Kill Heal", "Every kill heals you for this much." },
		thn = { "Thorns", "This much of the melee damage you take is dealt back to the attacker." },
		liv = { "Lives", "Times you rise again instead of dying." },
		area = { "Area", "Your spells' areas and ranges are this much larger." },
		cnt = { "Targets", "Every spell that picks its targets picks this many more." },
		pick = { "Pickup", "Experience and gold fly to you from this far." },
		spd = { "Speed", "You run this much faster." },
		xp = { "Experience", "You gain this much more experience." },
		gold = { "Gold", "You find this much more gold." },
		luck = { "Luck", "Better odds of rarer upgrades when you level up." },
		bp = { "Buff Power", "Your damage, haste, shield and thorns buffs are this much stronger." },
		dots = { "DoT Stacks", "How many of each of your damage-over-time effects one enemy carries at once." },
		doth = { "DoT Haste", "Your damage-over-time effects tick this much faster." },
		big = { "Vs Elites", "More damage to elites and bosses." },
		exe = { "Execute", "More damage to enemies below 30% health." },
		cc = { "Vs Controlled", "More damage to rooted, stunned, slowed or fleeing enemies." },
		dotd = { "Vs Afflicted", "More damage to enemies carrying one of your damage-over-time effects." },
		shd = { "Shielded", "More damage while you hold an absorb shield." },
		auto = { "Melee", "Your melee swings deal this much more damage." },
		pet = { "Pet Damage", "Your pets deal this much more damage." },
		yd = "yd",
	},
	ruRU = {
		crit = { "Крит", "Шанс критического удара заклинания. Свыше 100% остаток прибавляется к критическому урону." },
		cm = { "Крит. урон", "Критический удар наносит столько от урона заклинания." },
		dmg = { "Урон", "Каждое ваше заклинание наносит на столько больше урона. Растет с уровнем, экипировкой, талантами, бижутерией и баффами." },
		cd = { "Ускорение", "Ваши заклинания восстанавливаются на столько быстрее." },
		echo = { "Эхо", "Шанс, что заклинание ударит дважды. Свыше 100% каждое бьет дважды, а остаток - шанс третьего удара." },
		hp = { "Здоровье", "Максимум здоровья, который у вас может быть." },
		reg = { "Реген", "Здоровье, которое вы восстанавливаете каждую секунду." },
		lch = { "Вампиризм", "Лечит вас на столько от всего нанесенного вами урона." },
		arm = { "Броня", "Получаемый урон снижается на столько (не больше 60%)." },
		heal = { "Лечение за убийство", "Каждое убийство лечит вас на столько." },
		thn = { "Шипы", "Столько получаемого вами урона в ближнем бою возвращается атакующему." },
		liv = { "Жизни", "Сколько раз вы встанете, вместо того чтобы умереть." },
		area = { "Область", "Области и дальность ваших заклинаний больше на столько." },
		cnt = { "Цели", "Каждое заклинание, выбирающее цели, выбирает на столько больше." },
		pick = { "Подбор", "Опыт и золото летят к вам с такого расстояния." },
		spd = { "Скорость", "Вы бегаете на столько быстрее." },
		xp = { "Опыт", "Вы получаете на столько больше опыта." },
		gold = { "Золото", "Вы находите на столько больше золота." },
		luck = { "Удача", "Выше шанс более редких улучшений при повышении уровня." },
		bp = { "Сила баффов", "Ваши баффы урона, ускорения, щита и шипов сильнее на столько." },
		dots = { "Стаки DoT", "Сколько стаков каждого вашего эффекта урона со временем несет один враг." },
		doth = { "Темп DoT", "Ваши эффекты урона со временем тикают на столько быстрее." },
		big = { "По элитам", "Больше урона по элитам и боссам." },
		exe = { "Добивание", "Больше урона по врагам со здоровьем ниже 30%." },
		cc = { "По контролю", "Больше урона по врагам под корнями, оглушением, замедлением или в бегстве." },
		dotd = { "По пораженным", "Больше урона по врагам с вашим эффектом урона со временем." },
		shd = { "Под щитом", "Больше урона, пока у вас есть щит." },
		auto = { "Ближний бой", "Ваши удары в ближнем бою наносят на столько больше урона." },
		pet = { "Урон питомцев", "Ваши питомцы наносят на столько больше урона." },
		yd = "м",
	},
}
X.TEXT = TEXT

local function Strings()
	local loc = H.Locale and H.Locale.code or "enUS"
	return TEXT[loc] or TEXT.enUS
end

function X.Label(key)
	local t = Strings()[key] or TEXT.enUS[key]
	return t and t[1] or key
end

function X.Tip(key)
	local t = Strings()[key] or TEXT.enUS[key]
	return t and t[2] or ""
end

-- Значение из слоя H.Stats; нет данных или ключа - 0, как у движка.
function X.Value(key)
	local s = H.Stats
	if s and s.Get then
		local v = s.Get(key)
		if type(v) == "number" then
			return v
		end
	end
	return 0
end

function X.HasData()
	local s = H.Stats
	return s ~= nil and s.Has ~= nil and s.Has() and true or false
end

local function ZeroOf(kind)
	if kind == "add" or kind == "haste" then
		return 1
	end
	return 0
end

function X.IsZero(key, v)
	local d = DEF[key]
	return d ~= nil and math.abs(v - ZeroOf(d.kind)) < 0.0005
end

local function Format(kind, v)
	if kind == "add" then
		return string.format("%+.0f%%", (v - 1) * 100)
	elseif kind == "haste" then
		return string.format("%+.0f%%", (1 - v) * 100)
	elseif kind == "spct" then
		return string.format("%+.0f%%", v * 100)
	elseif kind == "pct1" then
		return string.format("%.1f%%", v * 100)
	elseif kind == "pct0" then
		return string.format("%.0f%%", v * 100)
	elseif kind == "plus" then
		return string.format("+%d", v)
	elseif kind == "dec1" then
		return string.format("%.1f", v)
	elseif kind == "yd" then
		return string.format("%.0f %s", v, Strings().yd)
	end
	return string.format("%.0f", v)
end

function X.Text(key, v)
	local d = DEF[key]
	return Format(d and d.kind or "int", v)
end

-- Строка вклада надетой экипировки или "" (как AZS_Gear движка).
function X.GearText(key)
	local d = DEF[key]
	if not d or not d.gear then
		return ""
	end
	local g = X.Value(d.gear)
	if g == 0 then
		return ""
	end
	return B.T("char_worn")..": "..Format(d.gearKind or d.kind, g)
end

-- Бонус урона для заголовка окна: "+85%".
function X.Headline()
	return Format("add", X.Value("dmg"))
end

-- Строка раздела и ее ключи в порядке показа, только видимые строки. out - массив для ключей (очищается).
-- Возвращает число. hideZero - настройка модуля.
function X.VisibleRows(section, hideZero, out)
	H.Wipe(out)
	local rows = X.SECTIONS[section].rows
	for i = 1, table.getn(rows) do
		local key = rows[i]
		local d = DEF[key]
		local zero = X.IsZero(key, X.Value(key))
		if not zero or (not d.cond and not hideZero) then
			table.insert(out, key)
		end
	end
	return table.getn(out)
end
