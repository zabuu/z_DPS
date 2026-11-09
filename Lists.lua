-- zDPS: static name lists. Plain name keys, no runtime scanning.
local Z = zDPS
local L = {}
Z.Lists = L

local function set(list, value)
  local t = {}
  for i = 1, table.getn(list) do t[list[i]] = value or true end
  return t
end

-- Dispel/cleanse casts counted as dispels (successful unless a DISPELFAILED line follows).
L.dispel = set({
  "Dispel Magic", "Cleanse", "Purify", "Cure Disease", "Abolish Disease", "Cure Poison",
  "Abolish Poison", "Purge", "Remove Curse", "Remove Lesser Curse", "Devour Magic",
  "Tranquilizing Shot", "Cleanse Spirit", "Mass Dispel",
})

-- Crowd control auras: keyed by aura name as it appears in "X is afflicted by Y."
L.cc = set({
  "Polymorph", "Polymorph: Pig", "Polymorph: Turtle", "Polymorph: Cow", "Polymorph: Sheep",
  "Fear", "Psychic Scream", "Howl of Terror", "Intimidating Shout", "Scare Beast",
  "Sap", "Blind", "Gouge", "Cheap Shot", "Kidney Shot",
  "Hibernate", "Entangling Roots", "Nature's Grasp",
  "Freezing Trap Effect", "Freezing Trap", "Wyvern Sting", "Scatter Shot",
  "Frost Nova", "Shackle Undead", "Banish", "Seduction", "Mind Control",
  "Hammer of Justice", "Repentance", "Turn Undead", "Turn Evil",
  "Concussion Blow", "Hex", "Enslave Demon", "Death Coil", "Bash", "Pounce",
  "Maim", "Rooted", "Earthbind", "Frost Shock", "Frostbite", "Fire Nova Totem",
})
-- CC that is applied by a cast whose log line is "X casts Y on Z" or "performs".
L.ccCast = set({
  "Polymorph", "Polymorph: Pig", "Polymorph: Turtle", "Polymorph: Cow", "Fear", "Sap", "Blind", "Gouge",
  "Hibernate", "Entangling Roots", "Wyvern Sting", "Scatter Shot", "Shackle Undead", "Banish",
  "Seduction", "Mind Control", "Hammer of Justice", "Repentance", "Turn Undead", "Scare Beast",
  "Cheap Shot", "Kidney Shot", "Concussion Blow", "Enslave Demon", "Death Coil", "Bash", "Pounce",
})

-- Consumables by category. Buff names as they appear in "X gains Y." ; potions by heal/power spell
-- name ; explosives by damage spell name.
L.consumable = {}
local function cat(name, list) for i = 1, table.getn(list) do L.consumable[list[i]] = name end end
cat("Flask", { "Flask of the Titans", "Flask of Supreme Power", "Flask of Distilled Wisdom",
  "Flask of Chromatic Resistance", "Flask of Petrification" })
cat("Elixir", { "Elixir of the Mongoose", "Elixir of Greater Agility", "Elixir of Agility", "Elixir of Fortitude",
  "Elixir of Superior Defense", "Elixir of Greater Defense", "Elixir of Giants", "Greater Arcane Elixir",
  "Arcane Elixir", "Elixir of Shadow Power", "Elixir of Frost Power", "Elixir of Firepower",
  "Elixir of Greater Firepower", "Elixir of Brute Force", "Elixir of the Sages", "Elixir of Giant Growth",
  "Elixir of Demonslaying", "Mageblood Potion", "Mageblood", "Gift of Arthas", "Elixir of Greater Intellect",
  "Elixir of Water Breathing", "Elixir of Detect Undead", "Elixir of Poison Resistance", "Elixir of Minor Agility",
  "Elixir of Lesser Agility", "Elixir of Defense", "Elixir of Ogre's Strength", "Elixir of Dream Vision",
  "Elixir of Greater Nature Power", "Elixir of Resistance", "Elixir of Lion's Strength", "Elixir of Wisdom",
  "Winterfall Firewater", "Rumsey Rum Black Label", "Rumsey Rum", "Gordok Green Grog", "Kreeg's Stout Beatdown",
  "Ground Scorpok Assay", "Cerebral Cortex Compound", "R.O.I.D.S.", "Lung Juice Cocktail", "Gizzard Gum",
  "Juju Power", "Juju Might", "Juju Ember", "Juju Chill", "Juju Flurry", "Juju Guile", "Juju Escape",
  "Spirit of Zanza", "Swiftness of Zanza", "Sheen of Zanza", "Dreamshard Elixir", "Dreamtonic", "Medivh's Merlot",
  "Danonzo's Tel'Abim Surprise", "Danonzo's Tel'Abim Medley", "Danonzo's Tel'Abim Delight" })
cat("Potion", { "Major Healing Potion", "Superior Healing Potion", "Greater Healing Potion", "Healing Potion",
  "Lesser Healing Potion", "Minor Healing Potion", "Major Mana Potion", "Superior Mana Potion",
  "Greater Mana Potion", "Mana Potion", "Lesser Mana Potion", "Minor Mana Potion", "Major Rejuvenation Potion",
  "Combat Mana Potion", "Combat Healing Potion", "Restore Mana", "Restore Health", "Healthstone", "Major Healthstone", "Greater Healthstone",
  "Minor Healthstone", "Lesser Healthstone", "Whipper Root Tuber", "Night Dragon's Breath", "Demonic Rune",
  "Dark Rune", "Major Troll's Blood Potion", "Greater Troll's Blood Potion", "Troll's Blood Potion",
  "Free Action Potion", "Living Action Potion", "Limited Invulnerability Potion", "Invulnerability",
  "Greater Fire Protection Potion", "Greater Frost Protection Potion", "Greater Nature Protection Potion",
  "Greater Shadow Protection Potion", "Greater Arcane Protection Potion", "Fire Protection", "Frost Protection",
  "Nature Protection", "Shadow Protection", "Arcane Protection", "Holy Protection", "Rage Potion", "Great Rage Potion",
  "Mighty Rage Potion", "Rage of Ages", "Swiftness Potion", "Elixir of Giant Growth", "Noggenfogger Elixir",
  "Restorative Potion", "Purification Potion", "Potion of Quickness", "Ghost Dye", "Wildvine Potion",
  "Shadow Oil", "Frost Oil", "Nordanaar Herbal Tea", "Tea with Sugar" })
cat("Food", { "Well Fed", "Increased Stamina", "Increased Agility", "Increased Intellect", "Increased Strength",
  "Increased Spirit", "Mana Regeneration", "Blessed Sunfruit", "Blessed Sunfruit Juice", "Spirit Regeneration",
  "Health Regeneration", "Grilled Squid", "Nightfin Soup", "Runn Tum Tuber Surprise", "Smoked Desert Dumplings",
  "Dirge's Kickin' Chimaerok Chops", "Sagefish Delight", "Hot Smoked Bass", "Spicy Chili Crab", "Rumsey Rum Dark",
  "Winter Veil Egg Nog", "Tender Wolf Steak", "Monster Omelet", "Spiced Wolf Meat", "Lean Wolf Steak", "Juicy Bear Burger",
  "Power Mushroom", "Heavy Kodo Stew", "Dragonbreath Chili", "Dragon's Breath", "Le Fishe Au Chocolat" })
cat("Scroll", { "Scroll of Agility", "Scroll of Agility II", "Scroll of Agility III", "Scroll of Agility IV",
  "Scroll of Strength", "Scroll of Strength II", "Scroll of Strength III", "Scroll of Strength IV",
  "Scroll of Protection", "Scroll of Protection II", "Scroll of Protection III", "Scroll of Protection IV",
  "Scroll of Stamina", "Scroll of Stamina II", "Scroll of Stamina III", "Scroll of Stamina IV",
  "Scroll of Intellect", "Scroll of Intellect II", "Scroll of Intellect III", "Scroll of Intellect IV",
  "Scroll of Spirit", "Scroll of Spirit II", "Scroll of Spirit III", "Scroll of Spirit IV",
  "Agility", "Strength", "Stamina", "Intellect", "Spirit", "Armor" })
cat("Explosive", { "Goblin Sapper Charge", "Goblin Sapper", "Dense Dynamite", "Solid Dynamite", "Big Iron Bomb",
  "Iron Grenade", "Thorium Grenade", "Hi-Explosive Bomb", "Goblin Land Mine", "Goblin Mortar", "Arcane Bomb",
  "Dark Iron Bomb", "The Big One", "Big Bronze Bomb", "Small Bronze Bomb", "Rough Copper Bomb", "Large Copper Bomb",
  "Coarse Dynamite", "Heavy Dynamite", "Ez-Thro Dynamite", "Ez-Thro Dynamite II", "Rough Dynamite",
  "Stratholme Holy Water", "Flash Bomb", "Fire Bomb", "Explosive Sheep", "Goblin Rocket Fuel" })
cat("Weapon", { "Brilliant Wizard Oil", "Brilliant Mana Oil", "Wizard Oil", "Lesser Wizard Oil", "Minor Wizard Oil",
  "Lesser Mana Oil", "Minor Mana Oil", "Blessed Wizard Oil", "Dense Sharpening Stone", "Elemental Sharpening Stone",
  "Consecrated Sharpening Stone", "Dense Weightstone", "Solid Sharpening Stone", "Solid Weightstone",
  "Sharpened", "Weighted", "Shadow Oil", "Frost Oil" })
cat("Other", { "Greater Stoneshield", "Greater Stoneshield Potion", "Lesser Stoneshield Potion", "Stoneshield",
  "Mighty Troll's Blood", "Thistle Tea", "Tea", "Crystal Force", "Crystal Ward", "Crystal Spire", "Infallible Mind",
  "Crystal Yield", "Crystal Charge", "Crystal Restore", "Oil of Immolation", "Fire Shield", "Lesser Stoneshield",
  "Bogling Root", "Goblin Jumper Cables", "Wind Fury", "Blackfathom Vitality" })
