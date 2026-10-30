--[[
	Board: static hex-grid topology (tiles, vertices, edges and adjacency)
	plus random layout generation (terrain, number tokens, ports).

	Coordinates
	  * Tiles use axial coordinates (q, r), pointy-top orientation.
	  * Vertices are identified on an INTEGER lattice so identity never depends
	    on floating point comparison. With hex circumradius s, the lattice unit
	    is (sqrt(3)/2 * s) on X and (s/2) on Y:
	        tile centre  = (2q + r, 3r)
	        corner i     = centre + CORNERS[i]
	  * Edges are identified by their two vertex ids.

	Every tile, vertex and edge has a stable integer id (1..N). Topology is the
	same for every game of a given radius and is cached.
]]

local Rng = require(script.Parent.Rng)

local Board = {}

-- Pointy-top corners clockwise from the top (Y grows "down"/south)
local CORNERS = { { 0, -2 }, { 1, -1 }, { 1, 1 }, { 0, 2 }, { -1, 1 }, { -1, -1 } }
local AXIAL_DIRECTIONS = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }

local cache = {}

local function latticeKey(x: number, y: number): string
	return x .. "," .. y
end

--[[
	Topology for a hexagonal island of the given radius (2 => 19 tiles).
	Returns:
	  tiles[id]    = { id, q, r, vertices = {6 vertex ids}, edges = {6 edge ids}, neighbors = {tile ids} }
	  vertices[id] = { id, x, y, tiles = {...}, edges = {...}, neighbors = {vertex ids} }
	  edges[id]    = { id, vertices = {a, b}, tiles = {...} }
	  tileAt[q..","..r] = tile id
	  coastalEdges = edge ids in order around the island
]]
function Board.getTopology(radiusArg: number?)
	local radius: number = radiusArg or 2
	if cache[radius] then
		return cache[radius]
	end

	local tiles, vertices, edges = {}, {}, {}
	local tileAt, vertexAt, edgeAt = {}, {}, {}

	for q = -radius, radius do
		for r = math.max(-radius, -q - radius), math.min(radius, -q + radius) do
			local tile = { id = #tiles + 1, q = q, r = r, vertices = {}, edges = {}, neighbors = {} }
			tiles[tile.id] = tile
			tileAt[q .. "," .. r] = tile.id
		end
	end

	local function getVertex(x: number, y: number)
		local key = latticeKey(x, y)
		local id = vertexAt[key]
		if not id then
			id = #vertices + 1
			vertices[id] = { id = id, x = x, y = y, tiles = {}, edges = {}, neighbors = {} }
			vertexAt[key] = id
		end
		return id
	end

	local function getEdge(a: number, b: number)
		local lo, hi = math.min(a, b), math.max(a, b)
		local key = lo .. "-" .. hi
		local id = edgeAt[key]
		if not id then
			id = #edges + 1
			edges[id] = { id = id, vertices = { lo, hi }, tiles = {} }
			edgeAt[key] = id
			table.insert(vertices[lo].edges, id)
			table.insert(vertices[hi].edges, id)
			table.insert(vertices[lo].neighbors, hi)
			table.insert(vertices[hi].neighbors, lo)
		end
		return id
	end

	for _, tile in tiles do
		local cx, cy = 2 * tile.q + tile.r, 3 * tile.r
		for i, c in CORNERS do
			local vid = getVertex(cx + c[1], cy + c[2])
			tile.vertices[i] = vid
			table.insert(vertices[vid].tiles, tile.id)
		end
		for i = 1, 6 do
			local eid = getEdge(tile.vertices[i], tile.vertices[i % 6 + 1])
			tile.edges[i] = eid
			table.insert(edges[eid].tiles, tile.id)
		end
		for _, d in AXIAL_DIRECTIONS do
			local n = tileAt[(tile.q + d[1]) .. "," .. (tile.r + d[2])]
			if n then
				table.insert(tile.neighbors, n)
			end
		end
	end

	-- Coastal edges (touching exactly one tile), walked in order around the island
	local isCoastal = {}
	local coastalCount = 0
	for _, e in edges do
		if #e.tiles == 1 then
			isCoastal[e.id] = true
			coastalCount += 1
		end
	end
	local coastalEdges = {}
	local start
	for id in isCoastal do
		if not start or id < start then
			start = id
		end
	end
	local visited = {}
	local current, fromVertex = start, edges[start].vertices[1]
	while current and not visited[current] do
		visited[current] = true
		table.insert(coastalEdges, current)
		local e = edges[current]
		local nextVertex = e.vertices[1] == fromVertex and e.vertices[2] or e.vertices[1]
		local nextEdge
		for _, candidate in vertices[nextVertex].edges do
			if candidate ~= current and isCoastal[candidate] and not visited[candidate] then
				nextEdge = candidate
				break
			end
		end
		current, fromVertex = nextEdge, nextVertex
	end
	assert(#coastalEdges == coastalCount, "coastal walk failed")

	local topology = {
		radius = radius,
		tiles = tiles,
		vertices = vertices,
		edges = edges,
		tileAt = tileAt,
		coastalEdges = coastalEdges,
	}
	cache[radius] = topology
	return topology
end

-- Vertex position on the integer lattice (see header). Renderers convert to studs.
function Board.vertexLattice(topology, vertexId: number): (number, number)
	local v = topology.vertices[vertexId]
	return v.x, v.y
end

function Board.tileLattice(_topology, tile): (number, number)
	return 2 * tile.q + tile.r, 3 * tile.r
end

-- Edge shared by two vertices, or nil
function Board.edgeBetween(topology, a: number, b: number): number?
	for _, eid in topology.vertices[a].edges do
		local e = topology.edges[eid]
		if (e.vertices[1] == a and e.vertices[2] == b) or (e.vertices[1] == b and e.vertices[2] == a) then
			return eid
		end
	end
	return nil
end

local function isRed(n: number): boolean
	return n == 6 or n == 8
end

--[[
	Random layout for a new game:
	  terrain[tileId] = "forest" | ... | "desert"
	  numbers[tileId] = 2..12, or 0 for the desert
	  robberTile      = id of the desert tile
	  ports[i]        = { kind = "generic" | resource, edge = edgeId, vertices = {a, b} }
]]
function Board.generateLayout(rules, rng)
	local topology = Board.getTopology(rules.boardRadius)
	local tileCount = #topology.tiles

	local terrainPool = {}
	for _, terrain in { "forest", "hills", "pasture", "fields", "mountains", "desert" } do
		for _ = 1, rules.terrainCounts[terrain] or 0 do
			table.insert(terrainPool, terrain)
		end
	end
	assert(#terrainPool == tileCount, "terrainCounts must match the number of tiles")

	local terrain, numbers
	for _attempt = 1, 200 do
		terrain = Rng.shuffle(rng, table.clone(terrainPool))
		local tokens = Rng.shuffle(rng, table.clone(rules.numberTokens))
		numbers = {}
		local nextToken = 1
		for id = 1, tileCount do
			if terrain[id] == "desert" then
				numbers[id] = 0
			else
				numbers[id] = tokens[nextToken] or 0
				nextToken += 1
			end
		end

		local ok = true
		if rules.avoidAdjacentRedNumbers then
			for id, tile in topology.tiles do
				if isRed(numbers[id]) then
					for _, n in tile.neighbors do
						if isRed(numbers[n]) then
							ok = false
						end
					end
				end
			end
		end
		if ok then
			break
		end
	end

	local robberTile = 0
	for id = 1, tileCount do
		if terrain[id] == "desert" then
			robberTile = id
			break
		end
	end
	if robberTile == 0 then
		robberTile = 1
	end

	local ports = {}
	local kinds = Rng.shuffle(rng, table.clone(rules.ports))
	local position = 1
	for i, kind in kinds do
		local edgeId = topology.coastalEdges[((position - 1) % #topology.coastalEdges) + 1]
		local e = topology.edges[edgeId]
		ports[i] = { kind = kind, edge = edgeId, vertices = { e.vertices[1], e.vertices[2] } }
		position += rules.portSpacing[i] or 3
	end

	return {
		radius = topology.radius,
		terrain = terrain,
		numbers = numbers,
		robberTile = robberTile,
		ports = ports,
	}
end

return Board
