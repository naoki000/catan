local Board = require(Shared.Board)
local RuleConfig = require(Shared.RuleConfig)
local Rng = require(Shared.Rng)

test("Board: standard island has 19 tiles, 54 vertices, 72 edges, 30 coastal edges", function()
	local t = Board.getTopology(2)
	expect.eq(#t.tiles, 19)
	expect.eq(#t.vertices, 54)
	expect.eq(#t.edges, 72)
	expect.eq(#t.coastalEdges, 30)
end)

test("Board: every vertex touches 2-3 edges and 1-3 tiles; every edge has 2 distinct vertices", function()
	local t = Board.getTopology(2)
	for _, v in t.vertices do
		expect.truthy(#v.edges >= 2 and #v.edges <= 3, "edges per vertex")
		expect.truthy(#v.tiles >= 1 and #v.tiles <= 3, "tiles per vertex")
		expect.eq(#v.neighbors, #v.edges)
	end
	for _, e in t.edges do
		expect.truthy(e.vertices[1] ~= e.vertices[2])
		expect.truthy(#e.tiles == 1 or #e.tiles == 2)
	end
end)

test("Board: adjacent tiles share exactly 2 vertices and 1 edge (integer identity)", function()
	local t = Board.getTopology(2)
	for _, tile in t.tiles do
		for _, n in tile.neighbors do
			local other = t.tiles[n]
			local shared = 0
			for _, a in tile.vertices do
				for _, b in other.vertices do
					if a == b then
						shared += 1
					end
				end
			end
			expect.eq(shared, 2, "shared vertices")
		end
		expect.truthy(#tile.neighbors >= 3 and #tile.neighbors <= 6)
	end
	expect.eq(#t.tiles[t.tileAt["0,0"]].neighbors, 6)
end)

test("Board: coastal walk is a connected loop", function()
	local t = Board.getTopology(2)
	for i, eid in t.coastalEdges do
		local nextId = t.coastalEdges[i % #t.coastalEdges + 1]
		local a, b = t.edges[eid], t.edges[nextId]
		local touches = false
		for _, v in a.vertices do
			if v == b.vertices[1] or v == b.vertices[2] then
				touches = true
			end
		end
		expect.truthy(touches, "consecutive coastal edges share a vertex")
	end
end)

test("Board: layout has correct terrain/number counts, robber on desert, 9 ports on distinct coast edges", function()
	local rules = RuleConfig.create()
	for seed = 1, 30 do
		local layout = Board.generateLayout(rules, Rng.fromSeed(seed))
		local counts, numberCount = {}, 0
		for id, terrain in layout.terrain do
			counts[terrain] = (counts[terrain] or 0) + 1
			if terrain == "desert" then
				expect.eq(layout.numbers[id], 0)
			else
				numberCount += 1
				expect.truthy(layout.numbers[id] >= 2 and layout.numbers[id] <= 12 and layout.numbers[id] ~= 7)
			end
		end
		for terrain, n in rules.terrainCounts do
			expect.eq(counts[terrain], n, terrain)
		end
		expect.eq(numberCount, 18)
		expect.eq(layout.terrain[layout.robberTile], "desert")
		expect.eq(#layout.ports, 9)
		local seen = {}
		local t = Board.getTopology(2)
		for _, port in layout.ports do
			expect.falsy(seen[port.edge], "duplicate port edge")
			seen[port.edge] = true
			expect.eq(#t.edges[port.edge].tiles, 1, "port on coast")
			-- no two ports share a vertex
			for _, other in layout.ports do
				if other ~= port then
					for _, v in port.vertices do
						expect.truthy(v ~= other.vertices[1] and v ~= other.vertices[2], "ports share a vertex")
					end
				end
			end
		end
	end
end)

test("Board: 6 and 8 are never adjacent", function()
	local rules = RuleConfig.create()
	local t = Board.getTopology(2)
	for seed = 100, 160 do
		local layout = Board.generateLayout(rules, Rng.fromSeed(seed))
		for id, tile in t.tiles do
			local n = layout.numbers[id]
			if n == 6 or n == 8 then
				for _, nb in tile.neighbors do
					local m = layout.numbers[nb]
					expect.truthy(m ~= 6 and m ~= 8, "adjacent red numbers")
				end
			end
		end
	end
end)

test("RuleConfig: defaults, overrides and per-player overrides", function()
	local rules = RuleConfig.create({ victoryPointsToWin = 12, pieceLimits = { road = 20 } })
	expect.eq(rules.victoryPointsToWin, 12)
	expect.eq(rules.pieceLimits.road, 20)
	expect.eq(rules.pieceLimits.city, 4, "untouched sibling keys survive")
	expect.eq(RuleConfig.Default.pieceLimits.road, 15, "defaults are not mutated")
	rules.playerOverrides["2"] = { pieceLimits = { road = 30 } }
	expect.eq(RuleConfig.get(rules, 2, "pieceLimits", "road"), 30)
	expect.eq(RuleConfig.get(rules, 1, "pieceLimits", "road"), 20)
	expect.eq(RuleConfig.get(rules, 2, "pieceLimits", "city"), 4)
end)
