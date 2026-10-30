--[[
	RuleConfig: every tunable rule value in one place.

	A game stores its own copy in `state.rules` (plain data, safe to replicate).
	Engine code must read values through this module instead of hard-coding
	numbers, so that future custom rules only need to change the config.

	Per-player overrides (future feature) live in rules.playerOverrides[tostring(seat)]
	and are resolved by RuleConfig.get(rules, seat, ...). Only the keys that are
	actually read through RuleConfig.get support overrides; see docs/customization-plan.md.
]]

local RuleConfig = {}

RuleConfig.Resources = { "lumber", "brick", "wool", "grain", "ore" }

RuleConfig.ResourceNames = {
	lumber = "木材",
	brick = "レンガ",
	wool = "羊毛",
	grain = "小麦",
	ore = "鉱石",
}

-- Terrain -> produced resource (desert produces nothing)
RuleConfig.TerrainResource = {
	forest = "lumber",
	hills = "brick",
	pasture = "wool",
	fields = "grain",
	mountains = "ore",
	desert = nil,
}

RuleConfig.TerrainNames = {
	forest = "森",
	hills = "丘陵",
	pasture = "牧草地",
	fields = "畑",
	mountains = "山",
	desert = "砂漠",
}

RuleConfig.DevCardTypes = { "knight", "roadBuilding", "yearOfPlenty", "monopoly", "victoryPoint" }

RuleConfig.DevCardNames = {
	knight = "騎士",
	roadBuilding = "街道建設",
	yearOfPlenty = "発見",
	monopoly = "独占",
	victoryPoint = "勝利点",
}

RuleConfig.Default = {
	minPlayers = 3,
	maxPlayers = 4,
	victoryPointsToWin = 10,

	dice = { count = 2, sides = 6 },
	robberRoll = 7,
	-- Players holding MORE than this many resource cards discard half (rounded down)
	discardLimit = 7,

	buildingCosts = {
		road = { lumber = 1, brick = 1 },
		settlement = { lumber = 1, brick = 1, wool = 1, grain = 1 },
		city = { grain = 2, ore = 3 },
		devCard = { wool = 1, grain = 1, ore = 1 },
	},
	-- Pieces each player owns at the start
	pieceLimits = { road = 15, settlement = 5, city = 4 },
	-- Resources produced per building on a matching roll
	production = { settlement = 1, city = 2 },
	points = { settlement = 1, city = 2, longestRoad = 2, largestArmy = 2, victoryPointCard = 1 },
	longestRoadMin = 5,
	largestArmyMin = 3,

	tradeRatios = { bank = 4, genericPort = 3, specificPort = 2 },
	-- Cards of each resource in the bank
	bankResourceCount = 19,

	devCardDeck = { knight = 14, victoryPoint = 5, roadBuilding = 2, yearOfPlenty = 2, monopoly = 2 },
	roadBuildingRoads = 2,
	yearOfPlentyPicks = 2,

	-- Board composition (standard 19-tile island)
	boardRadius = 2,
	terrainCounts = { forest = 4, hills = 3, pasture = 4, fields = 4, mountains = 3, desert = 1 },
	numberTokens = { 2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12 },
	-- 4 generic 3:1 ports + one 2:1 port per resource
	ports = { "generic", "generic", "generic", "generic", "lumber", "brick", "wool", "grain", "ore" },
	-- Gaps (in coastal edges) between consecutive ports around the island
	portSpacing = { 3, 3, 4, 3, 3, 4, 3, 3, 4 },
	avoidAdjacentRedNumbers = true,

	-- Future: per-player overrides, e.g. { ["2"] = { pieceLimits = { road = 20 } } }
	playerOverrides = {},
}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function deepMerge(target, source)
	for k, v in source do
		if type(v) == "table" and type(target[k]) == "table" and #v == 0 and next(v) ~= nil then
			deepMerge(target[k], v)
		else
			target[k] = deepCopy(v)
		end
	end
	return target
end

RuleConfig.deepCopy = deepCopy

-- Create a fresh rules table (standard rules with optional overrides).
function RuleConfig.create(overrides: any?)
	local rules = deepCopy(RuleConfig.Default)
	if overrides then
		deepMerge(rules, overrides)
	end
	return rules
end

--[[
	Read a rule value, honouring a per-player override when present.
	  RuleConfig.get(rules, seat, "pieceLimits", "road")
	  RuleConfig.get(rules, seat, "buildingCosts", "city")
]]
function RuleConfig.get(rules, seat: number?, ...: string)
	local path = { ... }
	if seat and rules.playerOverrides then
		local node = rules.playerOverrides[tostring(seat)]
		for _, key in path do
			if type(node) ~= "table" then
				node = nil
				break
			end
			node = node[key]
		end
		if node ~= nil then
			return node
		end
	end
	local node = rules
	for _, key in path do
		node = node[key]
		if node == nil then
			return nil
		end
	end
	return node
end

return RuleConfig
