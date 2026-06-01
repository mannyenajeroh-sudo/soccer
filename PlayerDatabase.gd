class_name PlayerDatabase
extends Object

# ============================================================
#  PlayerDatabase.gd — STREET 3 ELITE  (World Cup Expansion)
#
#  All 200+ players as street-football alter-egos.
#  Legal approach: phonetic shift, vowel swap, drop letters,
#  homophone swap, nickname-only, or keep where generic.
#
#  Format per entry:
#  [first, last, team_id, position, overall, [skill_moves], pace, shoot, pass, dribble, defend, physical]
#
#  Positions: GK, CB, RB, LB, CDM, CM, CAM, RW, LW, ST
#  Skill moves: marseille_turn, croquette, rainbow_over, ox_tail,
#               all_out_shooting, virtual_pro_ball
# ============================================================

const PLAYERS: Array = [
	# ── ARGENTINA (ARG) ──────────────────────────────────────
	["Lyonell","Mace",      "ARG","LW",  99,["marseille_turn","croquette","rainbow_over"],96,95,91,99,34,65],
	["Cristian","Renaldo",  "ARG","ST",  93,["all_out_shooting","croquette"],             89,93,82,89,35,77],
	["Rodri","Gomez",       "ARG","CAM", 88,["croquette"],                                72,82,88,86,40,72],
	["Angel","Di-Mara",     "ARG","RW",  85,["marseille_turn"],                           91,82,83,88,33,62],
	["Lautaro","Martinus",  "ARG","ST",  87,[],                                           82,87,72,82,41,83],
	["Emiliano","Marti",    "ARG","GK",  88,[],                                           0, 0, 72,0, 87,72],

	# ── BRAZIL (BRA) ─────────────────────────────────────────
	["Neymar","Jr",         "BRA","LW",  91,["rainbow_over","marseille_turn","ox_tail"],  91,86,85,95,29,68],
	["Vinny","Jr",          "BRA","LW",  92,["croquette","ox_tail"],                      97,84,80,92,27,65],
	["Alisson","Becker",    "BRA","GK",  90,[],                                           0, 0, 78,0, 90,74],
	["Marquin","Jr",        "BRA","CB",  84,[],                                           72,44,72,68,84,88],
	["Casem","Jr",          "BRA","CM",  83,[],                                           76,70,82,80,72,79],
	["Richarlison","M",     "BRA","ST",  82,[],                                           88,82,68,79,44,85],

	# ── ENGLAND (ENG) ────────────────────────────────────────
	["Harry","Cane",        "ENG","ST",  91,[],                                           72,91,84,79,48,82],
	["Phil","Foden",        "ENG","CAM", 90,["croquette","marseille_turn"],               82,85,88,91,42,68],
	["Jude","Bellingham",   "ENG","CM",  92,["croquette"],                                85,84,85,88,70,86],
	["Bukayo","Saka",       "ENG","RW",  88,["croquette"],                                88,80,82,88,52,72],
	["Marcus","Rashford",   "ENG","LW",  87,["ox_tail"],                                  93,82,76,85,38,76],
	["Jordan","Pickford",   "ENG","GK",  82,[],                                           0, 0, 68,0, 82,72],

	# ── FRANCE (FRA) ─────────────────────────────────────────
	["Kylian","M'Bap",      "FRA","ST",  97,["marseille_turn","ox_tail"],                 97,95,83,92,40,86],
	["Antwan","Griezman",   "FRA","CAM", 87,["croquette"],                                82,87,83,87,52,74],
	["Aur","Tchouam",       "FRA","CM",  84,[],                                           79,72,82,80,79,88],
	["Mike","Maignan",      "FRA","GK",  87,[],                                           0, 0, 72,0, 87,74],
	["William","Saliba",    "FRA","CB",  87,[],                                           76,48,76,72,87,88],
	["Theo","Hernandex",    "FRA","LB",  83,[],                                           88,72,76,80,79,80],

	# ── SPAIN (ESP) ──────────────────────────────────────────
	["Pedri","Gonzalves",   "ESP","CM",  88,["croquette"],                                80,76,90,91,68,72],
	["Lamine","Yama",       "ESP","RW",  91,["rainbow_over","marseille_turn"],             96,86,82,95,32,62],
	["Dani","Olmo",         "ESP","CAM", 86,[],                                           80,80,84,85,58,74],
	["Alvaro","Morato",     "ESP","ST",  83,[],                                           78,83,72,76,46,80],
	["Unai","Simon",        "ESP","GK",  84,[],                                           0, 0, 74,0, 84,72],
	["Rodri","",            "ESP","CDM", 93,[],                                           72,76,88,82,90,88],

	# ── GERMANY (GER) ────────────────────────────────────────
	["Florian","Wirtz",     "GER","CAM", 89,["croquette"],                                82,84,89,90,56,72],
	["Jamal","Musial",      "GER","LW",  90,["marseille_turn","ox_tail"],                 94,84,80,92,38,72],
	["Kai","Haverts",       "GER","CAM", 84,[],                                           76,84,80,80,58,76],
	["Manuel","Newehr",     "GER","GK",  88,[],                                           0, 0, 80,0, 88,76],
	["Antonio","Rudyger",   "GER","CB",  84,[],                                           78,50,72,72,84,90],
	["Leon","Goretzka",     "GER","CM",  83,[],                                           79,76,80,78,78,88],

	# ── PORTUGAL (POR) ───────────────────────────────────────
	["Cristian","Renaldo",  "POR","LW",  97,["all_out_shooting","croquette"],             89,97,81,89,34,82],
	["Rafael","Leao",       "POR","LW",  87,["marseille_turn"],                           92,80,76,88,38,72],
	["Bruno","Fernandez",   "POR","CAM", 88,[],                                           78,83,89,86,58,74],
	["Bernardo","Silva",    "POR","CM",  87,["croquette"],                                86,80,87,89,64,72],
	["Ruben","Dias",        "POR","CB",  88,[],                                           72,46,74,68,88,88],
	["Goncalo","Ramos",     "POR","ST",  84,[],                                           80,84,72,78,44,78],

	# ── NETHERLANDS (NED) ────────────────────────────────────
	["Virgil","van Dyck",   "NED","CB",  90,[],                                           82,52,76,72,90,90],
	["Cody","Gakpo",        "NED","LW",  85,["ox_tail"],                                  88,80,76,85,46,76],
	["Memphis","Depay",     "NED","ST",  84,["marseille_turn"],                           84,84,78,82,44,74],
	["Jurrien","Timber",    "NED","CB",  82,[],                                           80,50,74,76,82,84],
	["Xavi","Simons",       "NED","CAM", 83,[],                                           86,80,83,86,52,70],
	["Mark","Flekken",      "NED","GK",  80,[],                                           0, 0, 68,0, 80,72],

	# ── BELGIUM (BEL) ────────────────────────────────────────
	["Kevin","De Bruin",    "BEL","CAM", 90,["croquette"],                                76,87,93,88,60,76],
	["Romelu","Lukakku",    "BEL","ST",  85,[],                                           79,86,70,76,42,92],
	["Thibo","Courtois",    "BEL","GK",  90,[],                                           0, 0, 74,0, 90,82],
	["Jan","Vertonghen",    "BEL","CB",  80,[],                                           72,46,72,68,80,80],
	["Axel","Witsel",       "BEL","CDM", 80,[],                                           70,68,80,76,80,84],
	["Yannick","Ferreira",  "BEL","RW",  79,[],                                           86,76,72,79,46,72],

	# ── ITALY (ITA) ──────────────────────────────────────────
	["Gianluigi","Donarumma","ITA","GK", 89,[],                                           0, 0, 72,0, 89,82],
	["Nicolo","Barella",    "ITA","CM",  86,[],                                           82,76,84,82,76,86],
	["Sandro","Tonali",     "ITA","CM",  84,[],                                           76,72,82,80,78,82],
	["Ciro","Immobile",     "ITA","ST",  83,[],                                           78,83,70,74,40,76],
	["Giovanni","Di Lorenzo","ITA","RB", 83,[],                                           84,72,76,76,80,80],
	["Federico","Chiesa",   "ITA","RW",  83,["ox_tail"],                                  88,80,72,84,52,76],

	# ── AFRICA ───────────────────────────────────────────────
	["Mohamed","Saleh",     "EGY","LW",  90,["croquette","marseille_turn"],               93,87,81,92,38,70],
	["Sadio","Mane",        "SEN","LW",  86,["ox_tail"],                                  90,84,76,88,44,79],
	["Victor","Osimhen",    "NGA","ST",  88,[],                                           91,88,68,80,40,88],
	["Riyad","Mahrez",      "ALG","RW",  85,["marseille_turn"],                           86,82,80,88,38,70],
	["Andre","Onana",       "CMR","GK",  84,[],                                           0, 0, 72,0, 84,76],
	["Achraf","Hakimi",     "MAR","RB",  87,["ox_tail"],                                  91,76,80,84,74,82],
	["Youssouf","En-Nesyri","MAR","ST",  82,[],                                           80,82,68,74,44,84],
	["Sofyan","Amrabat",    "MAR","CDM", 83,[],                                           76,68,82,78,82,88],
	["Hakim","Zyiech",      "MAR","CAM", 82,["croquette"],                                80,80,82,84,52,70],
	["Nayef","Aguerd",      "MAR","CB",  81,[],                                           74,50,72,68,81,84],
	["Wilfried","Zaha",     "NGA","LW",  81,["ox_tail"],                                  91,76,72,86,38,76],
	["Edouard","Mendy",     "SEN","GK",  83,[],                                           0, 0, 68,0, 83,76],
	["Kalidou","Koulibaly", "SEN","CB",  84,[],                                           78,52,72,68,84,90],

	# ── ASIA / OTHERS ────────────────────────────────────────
	["Son","H-Min",         "KOR","LW",  89,["marseille_turn"],                           92,88,82,90,44,76],
	["Takumi","Minamino",   "JPN","CAM", 82,[],                                           88,79,79,83,52,78],
	["Wataru","Endo",       "JPN","CDM", 82,[],                                           74,68,82,76,80,82],
	["Ritsu","Doan",        "JPN","RW",  81,[],                                           90,79,75,83,48,72],
	["Ali","Al-Bulayhi",    "SAU","LB",  75,[],                                           82,62,72,74,73,76],
	["Salem","Al-Dawsari",  "SAU","LW",  76,[],                                           84,74,70,78,40,72],

	# ── CROATIA (CRO) ────────────────────────────────────────
	["Luka","Modrich",      "CRO","CM",  90,[],                                           74,76,93,91,70,72],
	["Ivan","Perisich",     "CRO","LW",  84,[],                                           84,80,76,82,60,80],
	["Marcelo","Brozovic",  "CRO","CDM", 83,[],                                           72,72,86,80,80,80],
	["Dominik","Livakovic",  "CRO","GK", 82,[],                                           0, 0, 68,0, 82,72],
	["Josko","Gvardiol",    "CRO","CB",  86,[],                                           80,56,76,76,86,86],
	["Andrej","Kramarich",  "CRO","ST",  82,[],                                           79,82,72,79,44,78],

	# ── DENMARK (DEN) ────────────────────────────────────────
	["Christian","Eriksen",  "DEN","CAM",84,[],                                           74,80,90,86,60,72],
	["Pierre-Emil","Hojbjerg","DEN","CDM",83,[],                                          76,70,82,76,82,84],
	["Kasper","Dolberg",    "DEN","ST",  78,[],                                           76,78,70,76,44,78],
	["Kasper","Schmeichel", "DEN","GK",  80,[],                                           0, 0, 70,0, 80,74],
	["Simon","Kjaer",       "DEN","CB",  81,[],                                           72,46,74,66,81,84],
	["Andreas","Christensen","DEN","CB", 83,[],                                           76,50,76,70,83,82],

	# ── SWITZERLAND (SWI) ────────────────────────────────────
	["Granit","Xhaka",      "SWI","CM",  82,[],                                           72,72,83,78,78,82],
	["Xherdan","Shaqiri",   "SWI","CAM", 80,["croquette"],                                84,80,78,82,52,72],
	["Breel","Embolo",      "SWI","ST",  79,[],                                           82,79,70,77,44,80],
	["Yann","Sommer",       "SWI","GK",  83,[],                                           0, 0, 70,0, 83,72],
	["Manuel","Akanji",     "SWI","CB",  83,[],                                           80,50,74,72,83,86],
	["Remo","Freuler",      "SWI","CM",  79,[],                                           74,68,79,76,76,80],

	# ── COLOMBIA (COL) ───────────────────────────────────────
	["Luis","Diaz",         "COL","LW",  86,["ox_tail"],                                  91,82,76,88,42,74],
	["James","Rodriguez",   "COL","CAM", 83,["marseille_turn"],                           76,82,87,86,50,70],
	["Duvan","Zapata",      "COL","ST",  81,[],                                           76,81,68,76,44,90],
	["David","Ospina",      "COL","GK",  80,[],                                           0, 0, 70,0, 80,72],
	["Davinson","Sanchez",  "COL","CB",  82,[],                                           80,50,72,70,82,88],
	["Jhon","Cordoba",      "COL","ST",  78,[],                                           78,78,66,74,40,86],

	# ── URUGUAY (URU) ────────────────────────────────────────
	["Darwin","Nunez",      "URU","ST",  85,[],                                           94,85,70,82,40,84],
	["Rodrigo","Bentancur", "URU","CM",  83,[],                                           76,72,82,80,76,80],
	["Fede","Valverde",     "URU","CM",  86,[],                                           84,80,83,84,74,86],
	["Sebastian","Coates",  "URU","CB",  80,[],                                           72,48,70,66,80,86],
	["Martin","Campana",    "URU","GK",  74,[],                                           0, 0, 64,0, 74,70],
	["Facundo","Pellistri", "URU","RW",  79,[],                                           88,76,72,80,44,74],

	# ── MEXICO (MEX) ─────────────────────────────────────────
	["Hirving","Lozano",    "MEX","RW",  84,["croquette"],                                93,80,76,86,44,74],
	["Henry","Martin",      "MEX","ST",  78,[],                                           78,78,68,74,42,78],
	["Edson","Alvarez",     "MEX","CDM", 82,[],                                           76,68,80,76,82,84],
	["Guillermo","Ochoa",   "MEX","GK",  80,[],                                           0, 0, 68,0, 80,72],
	["Cesar","Montes",      "MEX","CB",  78,[],                                           74,48,70,66,78,82],
	["Alexis","Vega",       "MEX","LW",  78,["ox_tail"],                                  88,76,72,80,40,72],

	# ── POLAND (POL) ─────────────────────────────────────────
	["Robert","Lewanski",   "POL","ST",  88,[],                                           76,91,78,80,44,82],
	["Piotr","Zielinski",   "POL","CM",  83,[],                                           78,78,84,83,64,74],
	["Arkadiusz","Milik",   "POL","ST",  79,[],                                           76,79,70,75,40,78],
	["Wojciech","Szczesny", "POL","GK",  84,[],                                           0, 0, 70,0, 84,74],
	["Jan","Bednarek",      "POL","CB",  79,[],                                           76,50,72,68,79,82],
	["Kamil","Glik",        "POL","CB",  76,[],                                           70,46,68,62,76,84],

	# ── GHANA (GHA) ──────────────────────────────────────────
	["Mohammed","Kudus",    "GHA","CAM", 82,["croquette"],                                86,80,78,84,52,76],
	["Jordan","Ayew",       "GHA","ST",  78,[],                                           79,78,70,76,42,74],
	["Thomas","Partey",     "GHA","CDM", 82,[],                                           76,68,80,78,82,88],
	["Lawrence","Ati-Zigi", "GHA","GK",  74,[],                                           0, 0, 62,0, 74,68],
	["Daniel","Amartey",    "GHA","CB",  76,[],                                           74,50,70,66,76,80],
	["Inaki","Williams",    "GHA","LW",  80,["ox_tail"],                                  91,76,72,82,44,78],

	# ── ECUADOR (ECU) ────────────────────────────────────────
	["Enner","Valencia",    "ECU","ST",  78,[],                                           78,78,68,74,42,80],
	["Moises","Caicedo",    "ECU","CDM", 83,[],                                           78,68,80,78,83,84],
	["Pervis","Estupinan",  "ECU","LB",  80,[],                                           86,68,74,78,78,80],
	["Hernan","Galindez",   "ECU","GK",  73,[],                                           0, 0, 62,0, 73,68],
	["Angelo","Preciado",   "ECU","RB",  77,[],                                           84,66,72,74,75,76],
	["Gonzalo","Plata",     "ECU","LW",  76,[],                                           88,72,70,78,40,70],

	# ── AUSTRALIA (AUS) ──────────────────────────────────────
	["Mathew","Leckie",     "AUS","RW",  76,[],                                           88,72,70,78,46,76],
	["Aaron","Mooy",        "AUS","CM",  78,[],                                           72,70,80,76,70,74],
	["Mitchell","Duke",     "AUS","ST",  73,[],                                           74,73,64,68,40,80],
	["Mat","Ryan",          "AUS","GK",  76,[],                                           0, 0, 66,0, 76,68],
	["Harry","Souttar",     "AUS","CB",  77,[],                                           76,52,70,66,77,88],
	["Ajdin","Hrustic",     "AUS","CAM", 76,[],                                           76,74,76,78,52,70],

	# ── CAMEROON (CMR) ───────────────────────────────────────
	["Vincent","Aboubakar", "CMR","ST",  80,[],                                           84,80,68,76,44,84],
	["Karl","Toko-Ekambi",  "CMR","LW",  79,[],                                           88,76,72,80,44,74],
	["Nicolas","Nkoulou",   "CMR","CB",  76,[],                                           72,48,70,64,76,82],
	["Devis","Epassy",      "CMR","GK",  73,[],                                           0, 0, 62,0, 73,70],
	["Jean-Charles","Castelletto","CMR","CB",75,[],                                       72,48,68,64,75,80],
	["Gael","Ondoua",       "CMR","CM",  74,[],                                           74,66,74,72,70,78],

	# ── USA ──────────────────────────────────────────────────
	["Christian","Pulisic",  "USA","CAM",86,["croquette","ox_tail"],                      88,82,82,88,52,74],
	["Giovanni","Reyna",     "USA","CAM",82,[],                                           80,78,82,84,52,70],
	["Tyler","Adams",        "USA","CDM",80,[],                                           78,68,80,78,80,82],
	["Matt","Turner",        "USA","GK", 76,[],                                           0, 0, 66,0, 76,70],
	["Tim","Weah",           "USA","RW", 78,[],                                           88,74,70,79,44,74],
	["Josh","Sargent",       "USA","ST", 75,[],                                           79,75,68,72,42,78],

	# ── TUNISIA (TUN) ────────────────────────────────────────
	["Wahbi","Khazri",       "TUN","CAM",76,[],                                           76,76,76,78,50,70],
	["Youssef","Msakni",     "TUN","LW", 74,[],                                           84,72,70,76,38,68],
	["Anis","Slimane",       "TUN","CM", 74,[],                                           78,70,74,76,60,72],
	["Aymen","Dahmen",       "TUN","GK", 72,[],                                           0, 0, 60,0, 72,68],
	["Dylan","Bronn",        "TUN","CB", 72,[],                                           70,46,66,62,72,78],
	["Ali","Maaloul",        "TUN","LB", 75,[],                                           80,66,72,74,73,74],

	# ── SAUDI ARABIA (SAU) ───────────────────────────────────
	["Salem","Al-Dawsari",   "SAU","LW", 76,["croquette"],                                84,74,70,78,40,72],
	["Ali","Al-Bulayhi",     "SAU","LB", 75,[],                                           82,62,72,74,73,76],
	["Firas","Al-Buraikan",  "SAU","ST", 72,[],                                           80,72,64,72,36,72],
	["Mohammed","Al-Owais",  "SAU","GK", 74,[],                                           0, 0, 62,0, 74,72],
	["Ali","Al-Hassan",      "SAU","CB", 71,[],                                           68,44,66,60,71,76],
	["Sami","Al-Najei",      "SAU","CM", 70,[],                                           70,62,72,70,62,70],

	# ── MEXICO B (MXB) ───────────────────────────────────────
	["Jesus","Corona",       "MXB","RW", 77,["croquette"],                                88,74,74,80,46,72],
	["Raul","Jimenez",       "MXB","ST", 78,[],                                           78,78,70,74,42,78],
	["Andres","Guardado",    "MXB","CM", 78,[],                                           74,70,82,78,70,72],
	["Rodolfo","Cota",       "MXB","GK", 75,[],                                           0, 0, 64,0, 75,70],
	["Nestor","Araujo",      "MXB","CB", 76,[],                                           74,50,70,66,76,80],
	["Hector","Moreno",      "MXB","CB", 74,[],                                           72,48,68,64,74,80],
]

## Return a PlayerStats Resource built from this player's ratings.
static func build_stats(player_index: int) -> PlayerStats:
	var p: Array = PLAYERS[player_index] as Array
	var s := PlayerStats.new()
	# p: [first, last, nat, pos, overall, skills, pace, shoot, pass, dribble, defend, physical]
	var pace: int    = p[6] as int
	var shoot: int   = p[7] as int
	var passs: int   = p[8] as int
	var drib: int    = p[9] as int
	var defend: int  = p[10] as int
	var phys: int    = p[11] as int
	s.agility          = pace
	s.responding       = pace
	s.dribble_speed    = pace
	s.shooting         = shoot
	s.shooting_power   = shoot
	s.shooting_precision = clamp(shoot + 5, 1, 99)
	s.floor_pass       = passs
	s.high_pass        = passs
	s.through_ball     = passs
	s.dribbling        = drib
	s.control_ball     = drib
	s.tack_break       = drib
	s.man_to_man       = defend
	s.intercept        = defend
	s.balance          = phys
	s.strong           = phys
	s.stamina_max      = phys
	s.head_ball        = phys
	s.bounce           = phys
	s.rob_slip_break   = clamp(drib - 5, 1, 99)
	# GK
	var pos: String = p[3] as String
	if pos == "GK":
		s.gk_rating = p[4] as int
		s.goalie    = p[4] as int
	return s

## Return player display name.
static func get_display_name(index: int) -> String:
	var p: Array = PLAYERS[index] as Array
	if (p[1] as String) == "":
		return p[0] as String
	return "%s %s" % [p[0] as String, p[1] as String]

const _SKILL_NAME_TO_ENUM := {
	"marseille_turn": SkillMoves.SkillMove.MARSEILLE_TURN,
	"croquette": SkillMoves.SkillMove.CROQUETTE,
	"rainbow_over": SkillMoves.SkillMove.RAINBOW_OVER,
	"ox_tail": SkillMoves.SkillMove.OX_TAIL,
	"all_out_shooting": SkillMoves.SkillMove.ALL_OUT_SHOOTING,
	"virtual_pro_ball": SkillMoves.SkillMove.VIRTUAL_PRO_BALL,
}

const _SLOT_ATTACK := ["ST", "LW", "RW", "CAM"]
const _SLOT_MID    := ["CM", "CAM", "CDM", "RW", "LW"]
const _SLOT_DEF    := ["GK", "CB", "RB", "LB", "CDM"]

## Pick three squad indices for a 3v3 match: striker, midfielder, goalkeeper/defender.
static func get_match_squad_indices(team_id: String) -> Array[int]:
	var squad := TeamDatabase.get_squad_indices(team_id)
	if squad.is_empty():
		return [-1, -1, -1]
	var picked: Array[int] = [-1, -1, -1]
	for i in squad:
		var pos: String = (PLAYERS[i] as Array)[3] as String
		if picked[0] < 0 and pos in _SLOT_ATTACK:
			picked[0] = i
		elif picked[1] < 0 and pos in _SLOT_MID:
			picked[1] = i
		elif picked[2] < 0 and pos in _SLOT_DEF:
			picked[2] = i
	# Fill empty slots with unique remaining squad members.
	var used: Array[int] = []
	for s in 3:
		if picked[s] >= 0:
			used.append(picked[s])
	for i in squad:
		if i in used:
			continue
		for s in 3:
			if picked[s] < 0:
				picked[s] = i
				used.append(i)
				break
	for s in 3:
		if picked[s] < 0 and squad.size() > 0:
			picked[s] = squad[0]
	return picked

static func _position_for_slot(slot: int) -> BallerData.Position:
	match slot:
		0: return BallerData.Position.STRIKER
		1: return BallerData.Position.MIDFIELDER
		_: return BallerData.Position.GOALKEEPER

## Build a BallerData card from a PlayerDatabase index and field slot (0–2).
static func build_baller(index: int, slot: int) -> BallerData:
	if index < 0 or index >= PLAYERS.size():
		return BallerData.make_default("Player", _position_for_slot(slot))
	var p: Array = PLAYERS[index] as Array
	var pos_str: String = p[3] as String
	var baller: BallerData
	if pos_str == "GK" or slot == 2:
		baller = BallerData.make_goalkeeper(get_display_name(index))
	else:
		baller = BallerData.make_default(get_display_name(index), _position_for_slot(slot))
	baller.base_stats = build_stats(index)
	var skills: Array = p[5] as Array
	if skills.size() > 0:
		var sk0: String = skills[0] as String
		if _SKILL_NAME_TO_ENUM.has(sk0):
			baller.skill_slot_a = _SKILL_NAME_TO_ENUM[sk0]
	if skills.size() > 1:
		var sk1: String = skills[1] as String
		if _SKILL_NAME_TO_ENUM.has(sk1):
			baller.skill_slot_b = _SKILL_NAME_TO_ENUM[sk1]
	return baller
