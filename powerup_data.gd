extends Node

# ── Power-up categories ───────────────────────────────────────────────────────
enum Category { PLAYER, TOWER, TRADEOFF, CURSED }

# ── Power-up pool ─────────────────────────────────────────────────────────────
# Each entry: [id, name, category, effect_line, cost_line, color_hex]
const POOL: Array = [
	# ── Player buffs ──────────────────────────────────────────────────────────
	["goldylox",    "GoldyLox",      Category.PLAYER,   "Auto-collect gold within 2 hexes",                     "",                                           "4488ff"],
	["fury",        "FURY",          Category.PLAYER,   "Kills grant 1.5x speed for 0.8s",                      "",                                           "4488ff"],
	["lightfoot",   "Lightfoot",     Category.PLAYER,   "First pit fall per wave negated",                       "",                                           "4488ff"],
	["t_radar",     "T-Radar",       Category.PLAYER,   "Treasure Nodes visible from 6 hexes",                  "",                                           "4488ff"],
	["recycler",    "Recycler",      Category.PLAYER,   "Enemy Towers drop +15 bonus gold",                     "",                                           "4488ff"],
	["phoenix_egg", "Phoenix Egg",   Category.PLAYER,   "One-time death negation",                              "",                                           "4488ff"],
	["armor",       "Armor",         Category.PLAYER,   "10% damage resistance",                                "",                                           "4488ff"],
	# ── Tower buffs ───────────────────────────────────────────────────────────
	["cryo_rounds", "Cryo Rounds",   Category.TOWER,    "Turret bullets slow on hit 0.5s",                       "",                                           "44cc88"],
	["chain_shot",  "Chain Shot",    Category.TOWER,    "Kill shots continue to next enemy",                     "",                                           "44cc88"],
	["fortify",     "Fortify",       Category.TOWER,    "All nodes gain +50% max HP",                            "",                                           "44cc88"],
	["rapid_reload","Rapid Reload",  Category.TOWER,    "Turret fire rate +25%",                                 "",                                           "44cc88"],
	["ghost_turret","Ghost Turret",  Category.TOWER,    "Place one free Turret anywhere",                        "",                                           "44cc88"],
	# ── Tradeoff ──────────────────────────────────────────────────────────────
	["overclock",   "Overclock",     Category.TRADEOFF, "+40% move speed",                                       "Artifact aggro +8 hexes",                    "ffaa22"],
	["iron_skin",   "Iron Skin",     Category.TRADEOFF, "+3 HP",                                                 "-20% move speed",                            "ffaa22"],
	["fools_gold",  "Fool's Gold",   Category.TRADEOFF, "Gold rewards doubled",                                  "Free upgrade drops removed",                 "ffaa22"],
	["berserker",   "Berserker",     Category.TRADEOFF, "+50% speed below 50% HP",                               "Max HP -2",                                  "ffaa22"],
	["exposed",     "Exposed",       Category.TRADEOFF, "Fire rate +50%",                                        "Your shots can hit your own nodes",          "ffaa22"],
	["glass_cannon","Glass Cannon",  Category.TRADEOFF, "Damage output x2",                                      "Max HP reduced to 3 total",                  "ffaa22"],
	# ── Cursed ────────────────────────────────────────────────────────────────
	["death_pact",  "Death Pact",    Category.CURSED,   "Death: all on-screen enemies take 30 dmg",             "Wave cooldown -90s per death",               "ff3333"],
	["blood_price", "Blood Price",   Category.CURSED,   "+50 gold per wave",                                     "Max HP -1 per wave from wave 6",             "ff3333"],
	["enemy_pact",  "Enemy Pact",    Category.CURSED,   "Enemies have -30% HP",                                  "Enemies move +30% faster",                  "ff3333"],
	["void_carry",  "Void Carry",    Category.CURSED,   "Artifacts don't trigger enemy aggro",                   "Artifact loot locked to 5g/10g only",        "ff3333"],
	["fcr_mod",     "FCR Mod",       Category.CURSED,   "High top speed, slow accel/decel",                      "Momentum is your master now",                "ff3333"],
	["copycat",     "Copycat",       Category.CURSED,   "All active power-ups duplicated",                       "All tradeoff costs doubled",                 "ff3333"],
]

func get_offer(active_ids: Array, source: String) -> Array:
	# Returns 3 random power-ups appropriate for source, excluding already active
	var available: Array = []
	for pu in POOL:
		if pu[0] in active_ids:
			continue
		# Boss and cursed source offers cursed tier; normal waves exclude cursed
		if source == "wave" and pu[2] == Category.CURSED:
			continue
		available.append(pu)
	available.shuffle()
	return available.slice(0, mini(3, available.size()))
