class_name TeamDatabase
extends Object

# ============================================================
#  TeamDatabase.gd — STREET 3 ELITE  (World Cup Expansion)
#  32-team static database. All team colours, groups, ratings.
# ============================================================

const TEAMS: Array[Dictionary] = [
	# Group A
	{"id":"ARG","name":"Argentina",   "alt":"The Albiceleste",  "rating":92,"color_home":Color(0.46,0.70,0.90),"color_away":Color(0.0,0.0,0.0),"group":"A"},
	{"id":"FRA","name":"France",      "alt":"Les Bleus",        "rating":90,"color_home":Color(0.0,0.12,0.53), "color_away":Color(1.0,1.0,1.0),"group":"A"},
	{"id":"ENG","name":"England",     "alt":"Three Lions",      "rating":88,"color_home":Color(1.0,1.0,1.0),   "color_away":Color(0.67,0.0,0.0),"group":"A"},
	{"id":"SEN","name":"Senegal",     "alt":"Lions of Teranga", "rating":80,"color_home":Color(0.0,0.53,0.22), "color_away":Color(1.0,0.84,0.0),"group":"A"},
	# Group B
	{"id":"BRA","name":"Brazil",      "alt":"Seleção",          "rating":91,"color_home":Color(0.99,0.85,0.0), "color_away":Color(0.0,0.39,0.0),"group":"B"},
	{"id":"POR","name":"Portugal",    "alt":"A Seleção",        "rating":87,"color_home":Color(0.69,0.0,0.07), "color_away":Color(0.0,0.0,0.0),"group":"B"},
	{"id":"ESP","name":"Spain",       "alt":"La Roja",          "rating":89,"color_home":Color(0.78,0.0,0.04), "color_away":Color(0.0,0.20,0.60),"group":"B"},
	{"id":"MAR","name":"Morocco",     "alt":"Atlas Lions",      "rating":82,"color_home":Color(0.78,0.0,0.04), "color_away":Color(0.0,0.40,0.20),"group":"B"},
	# Group C
	{"id":"GER","name":"Germany",     "alt":"Die Mannschaft",   "rating":86,"color_home":Color(1.0,1.0,1.0),   "color_away":Color(0.0,0.0,0.0),"group":"C"},
	{"id":"NED","name":"Netherlands", "alt":"Oranje",           "rating":85,"color_home":Color(1.0,0.44,0.0),  "color_away":Color(0.0,0.0,0.50),"group":"C"},
	{"id":"BEL","name":"Belgium",     "alt":"Red Devils",       "rating":84,"color_home":Color(0.78,0.04,0.04),"color_away":Color(0.0,0.22,0.66),"group":"C"},
	{"id":"NGA","name":"Nigeria",     "alt":"Super Eagles",     "rating":79,"color_home":Color(0.12,0.53,0.17),"color_away":Color(1.0,1.0,1.0),"group":"C"},
	# Group D
	{"id":"ITA","name":"Italy",       "alt":"Gli Azzurri",      "rating":85,"color_home":Color(0.0,0.22,0.66), "color_away":Color(1.0,1.0,1.0),"group":"D"},
	{"id":"KOR","name":"South Korea", "alt":"Taegeuk",          "rating":81,"color_home":Color(0.78,0.0,0.04), "color_away":Color(0.0,0.0,0.55),"group":"D"},
	{"id":"JPN","name":"Japan",       "alt":"Samurai Blue",     "rating":80,"color_home":Color(0.0,0.11,0.53), "color_away":Color(1.0,1.0,1.0),"group":"D"},
	{"id":"EGY","name":"Egypt",       "alt":"Pharaohs",         "rating":78,"color_home":Color(0.78,0.04,0.04),"color_away":Color(1.0,1.0,1.0),"group":"D"},
	# Group E
	{"id":"URU","name":"Uruguay",     "alt":"La Celeste",       "rating":83,"color_home":Color(0.35,0.67,0.87),"color_away":Color(0.0,0.0,0.0),"group":"E"},
	{"id":"COL","name":"Colombia",    "alt":"Los Cafeteros",    "rating":82,"color_home":Color(0.99,0.85,0.0), "color_away":Color(0.0,0.40,0.20),"group":"E"},
	{"id":"MEX","name":"Mexico",      "alt":"El Tri",           "rating":79,"color_home":Color(0.0,0.45,0.20), "color_away":Color(0.68,0.04,0.04),"group":"E"},
	{"id":"ALG","name":"Algeria",     "alt":"Desert Warriors",  "rating":78,"color_home":Color(0.78,0.04,0.04),"color_away":Color(0.0,0.0,0.0),"group":"E"},
	# Group F
	{"id":"CRO","name":"Croatia",     "alt":"Vatreni",          "rating":84,"color_home":Color(0.78,0.04,0.04),"color_away":Color(0.0,0.22,0.66),"group":"F"},
	{"id":"DEN","name":"Denmark",     "alt":"Danish Dynamite",  "rating":82,"color_home":Color(0.78,0.04,0.04),"color_away":Color(1.0,1.0,1.0),"group":"F"},
	{"id":"SWI","name":"Switzerland", "alt":"Nati",             "rating":81,"color_home":Color(0.78,0.04,0.04),"color_away":Color(1.0,1.0,1.0),"group":"F"},
	{"id":"CMR","name":"Cameroon",    "alt":"Indomitable Lions","rating":77,"color_home":Color(0.0,0.50,0.15), "color_away":Color(0.78,0.04,0.04),"group":"F"},
	# Group G
	{"id":"POL","name":"Poland",      "alt":"Biało-czerwoni",   "rating":80,"color_home":Color(1.0,1.0,1.0),   "color_away":Color(0.78,0.04,0.04),"group":"G"},
	{"id":"AUS","name":"Australia",   "alt":"Socceroos",        "rating":76,"color_home":Color(0.99,0.85,0.0), "color_away":Color(0.0,0.22,0.66),"group":"G"},
	{"id":"ECU","name":"Ecuador",     "alt":"La Tri",           "rating":77,"color_home":Color(0.99,0.85,0.0), "color_away":Color(0.0,0.22,0.66),"group":"G"},
	{"id":"GHA","name":"Ghana",       "alt":"Black Stars",      "rating":75,"color_home":Color(0.0,0.0,0.0),   "color_away":Color(1.0,1.0,1.0),"group":"G"},
	# Group H
	{"id":"USA","name":"USA",         "alt":"Stars & Stripes",  "rating":79,"color_home":Color(1.0,1.0,1.0),   "color_away":Color(0.0,0.22,0.66),"group":"H"},
	{"id":"MXB","name":"Mexico B",    "alt":"El Tri B",         "rating":77,"color_home":Color(0.0,0.45,0.20), "color_away":Color(0.68,0.04,0.04),"group":"H"},
	{"id":"SAU","name":"Saudi Arabia","alt":"Green Falcons",    "rating":74,"color_home":Color(0.0,0.45,0.10), "color_away":Color(1.0,1.0,1.0),"group":"H"},
	{"id":"TUN","name":"Tunisia",     "alt":"Eagles of Carthage","rating":74,"color_home":Color(0.78,0.04,0.04),"color_away":Color(1.0,1.0,1.0),"group":"H"},
]

const FLAGS: Dictionary = {
	"ARG":"🇦🇷","FRA":"🇫🇷","ENG":"🏴󠁧󠁢󠁥󠁮󠁧󠁿","BRA":"🇧🇷","ESP":"🇪🇸",
	"GER":"🇩🇪","ITA":"🇮🇹","POR":"🇵🇹","NED":"🇳🇱","BEL":"🇧🇪",
	"KOR":"🇰🇷","JPN":"🇯🇵","SEN":"🇸🇳","MAR":"🇲🇦","NGA":"🇳🇬",
	"EGY":"🇪🇬","CRO":"🇭🇷","URU":"🇺🇾","COL":"🇨🇴","MEX":"🇲🇽",
	"USA":"🇺🇸","SAU":"🇸🇦","ALG":"🇩🇿","DEN":"🇩🇰","SWI":"🇨🇭",
	"CMR":"🇨🇲","GHA":"🇬🇭","AUS":"🇦🇺","ECU":"🇪🇨","TUN":"🇹🇳",
	"POL":"🇵🇱","MXB":"🇲🇽",
}

static func get_team_by_id(team_id: String) -> Dictionary:
	for t in TEAMS:
		if t["id"] == team_id:
			return t
	return {}

static func get_flag(team_id: String) -> String:
	return FLAGS.get(team_id, "🏳")

static func get_teams_sorted_by_rating() -> Array:
	var sorted := TEAMS.duplicate()
	sorted.sort_custom(func(a, b): return a["rating"] > b["rating"])
	return sorted

## Returns indices into PlayerDatabase.PLAYERS for this team's squad (up to 6).
static func get_squad_indices(team_id: String) -> Array[int]:
	var result: Array[int] = []
	for i in range(PlayerDatabase.PLAYERS.size()):
		var p: Array = PlayerDatabase.PLAYERS[i] as Array
		if p[2] == team_id:
			result.append(i)
		if result.size() >= 6:
			break
	return result
