local AutoPlayer = require(Shared.AutoPlayer)
local Board = require(Shared.Board)
local GameActions = require(Shared.GameActions)
local GameState = require(Shared.GameState)
local LongestRoad = require(Shared.LongestRoad)
local RuleConfig = require(Shared.RuleConfig)
local RuleEngine = require(Shared.RuleEngine)
local Rng = require(Shared.Rng)
local StateView = require(Shared.StateView)

local RESOURCES = RuleConfig.Resources

local function seats(n)
	local list = {}
	for i = 1, n do
		list[i] = { userId = 1000 + i, name = "P" .. i, color = "c" .. i }
	end
	return list
end

local function newGame(n, seed)
	local rng = Rng.fromSeed(seed or 7)
	local state = GameState.new(seats(n or 3), RuleConfig.create(), rng)
	return state, { rng = rng, authority = "player" }
end

-- Fixed dice: returns the queued values in order
local function fixedRng(values)
	local i = 0
	return {
		nextInt = function(_, min, max)
			i += 1
			local v = values[i] or min
			assert(v >= min and v <= max, "fixed rng value out of range")
			return v
		end,
	}
end

local function act(state, seat, action, ctx)
	return GameActions.perform(state, seat, action, ctx)
end

local function finishSetup(state, ctx)
	local guard = 0
	while state.phase == "setup" do
		guard += 1
		assert(guard < 100, "setup did not finish")
		local seat = state.currentSeat
		local action = AutoPlayer.requiredAction(state, seat)
		local ok, err = act(state, seat, action, ctx)
		assert(ok, err)
	end
end

local function totalCards(state)
	local total = 0
	for _, r in RESOURCES do
		total += state.bank[r]
		for _, p in state.players do
			total += p.resources[r]
		end
	end
	return total
end

local function give(player, map)
	for r, n in map do
		player.resources[r] += n
	end
end

local function clearHand(state, player)
	for _, r in RESOURCES do
		state.bank[r] += player.resources[r]
		player.resources[r] = 0
	end
end

-- Setup ---------------------------------------------------------------------------------

test("Setup: snake order, 2 settlements + 2 roads each, starting resources from 2nd settlement", function()
	for _, n in { 3, 4 } do
		local state, ctx = newGame(n, n * 11)
		local expected = {}
		for i = 1, n do
			table.insert(expected, state.order[i])
		end
		for i = n, 1, -1 do
			table.insert(expected, state.order[i])
		end
		for i, s in expected do
			expect.eq(state.setupQueue[i], s, "setup queue")
		end
		finishSetup(state, ctx)
		expect.eq(state.phase, "main")
		expect.eq(state.turnPhase, "roll")
		expect.eq(state.currentSeat, state.order[1])
		for _, p in state.players do
			expect.eq(p.pieces.settlement, 3)
			expect.eq(p.pieces.road, 13)
			local count = GameState.resourceCount(p)
			expect.truthy(count >= 0 and count <= 3, "starting resources")
		end
		expect.eq(totalCards(state), 95, "cards conserved")
	end
end)

test("Setup: only the current player may act, road must touch the new settlement, distance rule", function()
	local state, ctx = newGame(3, 3)
	local seat = state.currentSeat
	local other = seat % 3 + 1
	local topology = Board.getTopology(2)
	expect.fails(act(state, other, { type = "placeSettlement", vertex = 1 }, ctx), "手番")
	expect.fails(act(state, seat, { type = "placeRoad", edge = 1 }, ctx), "開拓地")
	expect.fails(act(state, seat, { type = "rollDice" }, ctx))
	expect.ok(act(state, seat, { type = "placeSettlement", vertex = 10 }, ctx))
	expect.fails(act(state, seat, { type = "placeSettlement", vertex = 30 }, ctx), "街道")
	-- a road not touching vertex 10
	local farEdge
	for e, edge in topology.edges do
		if edge.vertices[1] ~= 10 and edge.vertices[2] ~= 10 then
			farEdge = e
			break
		end
	end
	expect.fails(act(state, seat, { type = "placeRoad", edge = farEdge }, ctx), "接続")
	expect.ok(act(state, seat, { type = "placeRoad", edge = topology.vertices[10].edges[1] }, ctx))
	-- next player cannot build next to vertex 10
	local nextSeat = state.currentSeat
	expect.fails(
		act(state, nextSeat, { type = "placeSettlement", vertex = topology.vertices[10].neighbors[1] }, ctx),
		"距離"
	)
	expect.fails(act(state, nextSeat, { type = "placeSettlement", vertex = 10 }, ctx), "すでに")
end)

-- Dice & production ---------------------------------------------------------------------

test("Dice: production gives 1 per settlement, 2 per city, nothing under the robber", function()
	local state, ctx = newGame(3, 5)
	finishSetup(state, ctx)
	local topology = Board.getTopology(2)
	local seat = state.currentSeat
	-- pick a producing tile with a number and put our buildings on it
	local tileId
	for t = 1, #topology.tiles do
		if state.layout.numbers[t] ~= 0 and t ~= state.layout.robberTile then
			tileId = t
			break
		end
	end
	local number = state.layout.numbers[tileId]
	local resource = RuleConfig.TerrainResource[state.layout.terrain[tileId]]
	-- reset board ownership to a known configuration
	for v = 1, #state.vertexOwner do
		state.vertexOwner[v], state.vertexBuilding[v] = 0, 0
	end
	local verts = topology.tiles[tileId].vertices
	state.vertexOwner[verts[1]], state.vertexBuilding[verts[1]] = seat, 1
	state.vertexOwner[verts[4]], state.vertexBuilding[verts[4]] = seat, 2
	for _, p in state.players do
		clearHand(state, p)
	end
	local d1 = math.max(1, number - 6)
	ctx.rng = fixedRng({ d1, number - d1 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	expect.eq(state.turn.diceTotal, number)
	-- other tiles with the same number could also touch these vertices; count expected precisely
	local expectedGain = 0
	for _, v in { verts[1], verts[4] } do
		for _, t in topology.vertices[v].tiles do
			if
				state.layout.numbers[t] == number
				and RuleConfig.TerrainResource[state.layout.terrain[t]] == resource
				and t ~= state.layout.robberTile
			then
				expectedGain += state.vertexBuilding[v] == 2 and 2 or 1
			end
		end
	end
	expect.eq(state.players[seat].resources[resource], expectedGain)
	expect.truthy(expectedGain >= 3)

	-- Robber blocks the tile
	state.turnPhase, state.currentSeat = "roll", seat
	clearHand(state, state.players[seat])
	state.layout.robberTile = tileId
	ctx.rng = fixedRng({ d1, number - d1 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	local blockedGain = 0
	for _, v in { verts[1], verts[4] } do
		for _, t in topology.vertices[v].tiles do
			if
				t ~= tileId
				and state.layout.numbers[t] == number
				and RuleConfig.TerrainResource[state.layout.terrain[t]] == resource
			then
				blockedGain += state.vertexBuilding[v] == 2 and 2 or 1
			end
		end
	end
	expect.eq(state.players[seat].resources[resource], blockedGain, "robber tile produced")
	expect.eq(totalCards(state), 95)
end)

test("Dice: bank shortage gives nothing when several players need it", function()
	local state, ctx = newGame(3, 9)
	finishSetup(state, ctx)
	local topology = Board.getTopology(2)
	local tileId
	for t = 1, #topology.tiles do
		if state.layout.numbers[t] ~= 0 and t ~= state.layout.robberTile then
			tileId = t
			break
		end
	end
	local number = state.layout.numbers[tileId]
	local resource = RuleConfig.TerrainResource[state.layout.terrain[tileId]]
	for v = 1, #state.vertexOwner do
		state.vertexOwner[v], state.vertexBuilding[v] = 0, 0
	end
	local verts = topology.tiles[tileId].vertices
	state.vertexOwner[verts[1]], state.vertexBuilding[verts[1]] = 1, 2
	state.vertexOwner[verts[4]], state.vertexBuilding[verts[4]] = 2, 2
	-- move almost all of that resource out of the bank
	local holder = state.players[3]
	holder.resources[resource] += state.bank[resource] - 1
	state.bank[resource] = 1
	local before1, before2 = state.players[1].resources[resource], state.players[2].resources[resource]
	local d1 = math.max(1, number - 6)
	ctx.rng = fixedRng({ d1, number - d1 })
	expect.ok(act(state, state.currentSeat, { type = "rollDice" }, ctx))
	expect.eq(state.players[1].resources[resource], before1)
	expect.eq(state.players[2].resources[resource], before2)
	expect.eq(state.bank[resource], 1)
end)

-- Building ----------------------------------------------------------------------------------

test("Build: rejected without resources, accepted and paid with resources", function()
	local state, ctx = newGame(3, 21)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 3, 3 }) -- 6, avoid robber
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	clearHand(state, p)
	local road = nil
	for e = 1, #state.edgeOwner do
		if state.edgeOwner[e] == 0 and RuleEngine.edgeConnects(state, seat, e) then
			road = e
			break
		end
	end
	expect.fails(act(state, seat, { type = "placeRoad", edge = road }, ctx), "資源")
	expect.fails(act(state, seat, { type = "buyDevCard" }, ctx), "資源")
	local city
	for v = 1, #state.vertexOwner do
		if state.vertexOwner[v] == seat then
			city = v
		end
	end
	expect.fails(act(state, seat, { type = "buildCity", vertex = city }, ctx), "資源")

	state.bank.lumber -= 1
	state.bank.brick -= 1
	give(p, { lumber = 1, brick = 1 })
	expect.ok(act(state, seat, { type = "placeRoad", edge = road }, ctx))
	expect.eq(p.resources.lumber, 0)
	expect.eq(p.pieces.road, 12)
	expect.eq(state.edgeOwner[road], seat)

	state.bank.grain -= 2
	state.bank.ore -= 3
	give(p, { grain = 2, ore = 3 })
	expect.ok(act(state, seat, { type = "buildCity", vertex = city }, ctx))
	expect.eq(state.vertexBuilding[city], 2)
	expect.eq(p.pieces.city, 3)
	expect.eq(p.pieces.settlement, 4, "settlement returned to supply")
	expect.eq(GameState.publicPoints(state, seat), 3)
	expect.eq(totalCards(state), 95)
	-- cannot build a city on an opponent's or empty vertex
	expect.fails(act(state, seat, { type = "buildCity", vertex = city }, ctx))
end)

test("Build: settlement needs own connected road and respects the distance rule", function()
	local state, ctx = newGame(3, 23)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	state.bank.lumber -= 10
	state.bank.brick -= 10
	state.bank.wool -= 10
	state.bank.grain -= 10
	give(p, { lumber = 10, brick = 10, wool = 10, grain = 10 })
	-- an empty vertex far from our roads
	local far
	for v = 1, #state.vertexOwner do
		if
			state.vertexOwner[v] == 0
			and RuleEngine.distanceRuleOk(state, v)
			and not RuleEngine.vertexTouchesOwnRoad(state, seat, v)
		then
			far = v
			break
		end
	end
	expect.fails(act(state, seat, { type = "placeSettlement", vertex = far }, ctx), "街道")
	-- extend roads until a legal spot appears
	local legal = RuleEngine.legalSettlementVertices(state, seat)
	local guard = 0
	while #legal == 0 and guard < 6 do
		guard += 1
		local e = RuleEngine.legalRoadEdges(state, seat)[1]
		expect.ok(act(state, seat, { type = "placeRoad", edge = e }, ctx))
		legal = RuleEngine.legalSettlementVertices(state, seat)
	end
	expect.truthy(#legal > 0)
	expect.ok(act(state, seat, { type = "placeSettlement", vertex = legal[1] }, ctx))
	expect.eq(p.pieces.settlement, 2)
end)

test("Build: piece limits are enforced", function()
	local state, ctx = newGame(3, 25)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	p.pieces.road = 0
	give(p, { lumber = 1, brick = 1 })
	state.bank.lumber -= 1
	state.bank.brick -= 1
	local e
	for i = 1, #state.edgeOwner do
		if state.edgeOwner[i] == 0 and RuleEngine.edgeConnects(state, seat, i) then
			e = i
			break
		end
	end
	expect.fails(act(state, seat, { type = "placeRoad", edge = e }, ctx), "残って")
end)

-- Malicious input ----------------------------------------------------------------------------

test("Security: malformed actions are rejected and never change the state", function()
	local state, ctx = newGame(3, 31)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	local before = totalCards(state)
	local version = state.version
	local bad = {
		"nope",
		{},
		{ type = "giveMeResources" },
		{ type = "__index" },
		{ type = "placeRoad", edge = -1 },
		{ type = "placeRoad", edge = 1.5 },
		{ type = "placeRoad", edge = 0 / 0 },
		{ type = "placeRoad", edge = 9999 },
		{ type = "placeSettlement", vertex = "1" },
		{ type = "buildCity", vertex = {} },
		{ type = "bankTrade", give = "gold", get = "ore" },
		{ type = "bankTrade", give = "ore", get = "ore" },
		{ type = "proposeTrade", give = { ore = -5 }, want = { brick = 1 } },
		{ type = "proposeTrade", give = { ore = 1.5 }, want = { brick = 1 } },
		{ type = "proposeTrade", give = { gold = 1 }, want = { brick = 1 } },
		{ type = "proposeTrade", give = {}, want = { brick = 1 } },
		{ type = "discard", resources = { ore = -3 } },
		{ type = "playDevCard", card = "victoryPoint" },
		{ type = "playDevCard", card = "__index" },
		{ type = "playDevCard", card = "knight" },
		{ type = "moveRobber", tile = 3 },
		{ type = "steal", target = 2 },
		{ type = "respondTrade", tradeId = 1, accept = true },
	}
	for _, action in bad do
		local ok = act(state, seat, action, ctx)
		expect.falsy(ok, "accepted bad action " .. tostring(type(action) == "table" and action.type))
	end
	-- other players cannot act on someone else's turn
	local other = state.order[2]
	expect.fails(act(state, other, { type = "endTurn" }, ctx))
	expect.fails(act(state, other, { type = "buyDevCard" }, ctx))
	expect.fails(act(state, 99, { type = "endTurn" }, ctx))
	expect.eq(totalCards(state), before)
	expect.eq(state.version, version)
end)

-- Trade --------------------------------------------------------------------------------------

test("Trade: bank 4:1, port ratios, player trade accept/decline/cancel", function()
	local state, ctx = newGame(3, 41)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	for _, q in state.players do
		clearHand(state, q)
	end
	-- remove ports for a clean 4:1 test
	local savedPorts = state.layout.ports
	state.layout.ports = {}
	expect.eq(RuleEngine.tradeRatio(state, seat, "ore"), 4)
	state.bank.ore -= 4
	give(p, { ore = 4 })
	expect.ok(act(state, seat, { type = "bankTrade", give = "ore", get = "wool" }, ctx))
	expect.eq(p.resources.ore, 0)
	expect.eq(p.resources.wool, 1)
	expect.fails(act(state, seat, { type = "bankTrade", give = "ore", get = "wool" }, ctx))

	-- ports
	local generic = { kind = "generic", edge = 1, vertices = { 1, 2 } }
	local specific = { kind = "ore", edge = 2, vertices = { 3, 4 } }
	state.layout.ports = { generic, specific }
	local savedOwner = state.vertexOwner[1]
	state.vertexOwner[1] = seat
	expect.eq(RuleEngine.tradeRatio(state, seat, "brick"), 3)
	state.vertexOwner[3] = seat
	expect.eq(RuleEngine.tradeRatio(state, seat, "ore"), 2)
	expect.eq(RuleEngine.tradeRatio(state, seat, "brick"), 3)
	state.vertexOwner[1], state.vertexOwner[3] = savedOwner, 0
	state.layout.ports = savedPorts

	-- player trade
	local partner = state.order[2]
	local third = state.order[3]
	state.bank.brick -= 2
	give(state.players[partner], { brick = 2 })
	expect.fails(act(state, seat, { type = "proposeTrade", give = { wool = 2 }, want = { brick = 2 } }, ctx), "足り")
	expect.ok(act(state, seat, { type = "proposeTrade", give = { wool = 1 }, want = { brick = 2 } }, ctx))
	local id = state.trade.id
	expect.fails(act(state, seat, { type = "respondTrade", tradeId = id, accept = true }, ctx), "自分")
	expect.fails(act(state, third, { type = "respondTrade", tradeId = id, accept = true }, ctx), "足り")
	expect.ok(act(state, partner, { type = "respondTrade", tradeId = id, accept = true }, ctx))
	expect.eq(state.trade, nil)
	expect.eq(p.resources.brick, 2)
	expect.eq(p.resources.wool, 0)
	expect.eq(state.players[partner].resources.wool, 1)
	expect.eq(totalCards(state), 95)

	-- decline by everyone ends the offer; cancel works
	expect.ok(act(state, seat, { type = "proposeTrade", give = { brick = 1 }, want = { ore = 1 } }, ctx))
	id = state.trade.id
	expect.ok(act(state, partner, { type = "respondTrade", tradeId = id, accept = false }, ctx))
	expect.truthy(state.trade ~= nil)
	expect.ok(act(state, third, { type = "respondTrade", tradeId = id, accept = false }, ctx))
	expect.eq(state.trade, nil)
	expect.ok(act(state, seat, { type = "proposeTrade", give = { brick = 1 }, want = { ore = 1 } }, ctx))
	expect.fails(act(state, partner, { type = "cancelTrade" }, ctx))
	expect.ok(act(state, seat, { type = "cancelTrade" }, ctx))
	expect.eq(state.trade, nil)
end)

-- Robber -------------------------------------------------------------------------------------

test("Robber: 7 forces discards (more than 7 cards), robber moves, one card stolen", function()
	local state, ctx = newGame(3, 51)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local victim = state.order[2]
	local safe = state.order[3]
	for _, q in state.players do
		clearHand(state, q)
	end
	state.bank.ore -= 9
	give(state.players[victim], { ore = 9 }) -- must discard 4
	state.bank.wool -= 7
	give(state.players[safe], { wool = 7 }) -- exactly 7: no discard
	ctx.rng = fixedRng({ 3, 4, 1 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	expect.eq(state.turnPhase, "discard")
	expect.eq(state.players[victim].mustDiscard, 4)
	expect.eq(state.players[safe].mustDiscard, 0)
	expect.fails(act(state, seat, { type = "moveRobber", tile = 1 }, ctx))
	expect.fails(act(state, safe, { type = "discard", resources = { wool = 3 } }, ctx))
	expect.fails(act(state, victim, { type = "discard", resources = { ore = 3 } }, ctx), "4")
	expect.fails(act(state, victim, { type = "discard", resources = { wool = 4 } }, ctx))
	expect.ok(act(state, victim, { type = "discard", resources = { ore = 4 } }, ctx))
	expect.eq(state.turnPhase, "moveRobber")
	expect.fails(act(state, seat, { type = "moveRobber", tile = state.layout.robberTile }, ctx), "別")

	-- place the robber on a tile where the victim has a building
	local topology = Board.getTopology(2)
	local target
	for t, tile in topology.tiles do
		if t ~= state.layout.robberTile then
			local hasVictim, hasSelf = false, false
			for _, v in tile.vertices do
				if state.vertexOwner[v] == victim then
					hasVictim = true
				end
				if state.vertexOwner[v] ~= 0 and state.vertexOwner[v] ~= victim then
					hasSelf = true
				end
			end
			if hasVictim and not hasSelf then
				target = t
				break
			end
		end
	end
	expect.truthy(target, "found robber target")
	expect.ok(act(state, seat, { type = "moveRobber", tile = target }, ctx))
	expect.eq(state.layout.robberTile, target)
	expect.eq(state.turnPhase, "main")
	expect.eq(state.players[victim].resources.ore, 4)
	expect.eq(state.players[seat].resources.ore, 1)
	expect.eq(totalCards(state), 95)
end)

-- Development cards ------------------------------------------------------------------------

test("Dev cards: cannot play on the turn bought, one per turn, VP card never played", function()
	local state, ctx = newGame(3, 61)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	-- force the top of the deck to be a knight
	state.devDeck[#state.devDeck] = "knight"
	state.bank.wool -= 1
	state.bank.grain -= 1
	state.bank.ore -= 1
	give(p, { wool = 1, grain = 1, ore = 1 })
	local deckSize = #state.devDeck
	expect.ok(act(state, seat, { type = "buyDevCard" }, ctx))
	expect.eq(#state.devDeck, deckSize - 1)
	expect.eq(p.newDevCards.knight, 1)
	expect.fails(act(state, seat, { type = "playDevCard", card = "knight" }, ctx), "購入")
	-- opponents only see a count
	local view = StateView.forSeat(state, state.order[2])
	expect.eq(view.players[seat].resources, nil)
	expect.eq(view.players[seat].devCards, nil)
	expect.eq(view.players[seat].devCardCount, 1)
	expect.eq(view.devDeck, nil)
	expect.eq(view.devDeckCount, #state.devDeck)

	-- cycle back to our turn
	for _ = 1, 3 do
		local s = state.currentSeat
		if state.turnPhase == "roll" then
			ctx.rng = fixedRng({ 2, 2 })
			expect.ok(act(state, s, { type = "rollDice" }, ctx))
		end
		expect.ok(act(state, s, { type = "endTurn" }, ctx))
	end
	expect.eq(state.currentSeat, seat)
	expect.eq(p.devCards.knight, 1)
	p.devCards.monopoly = 1
	-- knight may be played before rolling
	expect.ok(act(state, seat, { type = "playDevCard", card = "knight" }, ctx))
	expect.eq(state.turnPhase, "moveRobber")
	local tile = RuleEngine.legalRobberTiles(state, seat)[1]
	ctx.rng = fixedRng({ 1 })
	expect.ok(act(state, seat, { type = "moveRobber", tile = tile }, ctx))
	if state.turnPhase == "steal" then
		expect.ok(act(state, seat, { type = "steal", target = state.stealCandidates[1] }, ctx))
	end
	expect.eq(state.turnPhase, "roll", "back to roll after pre-roll knight")
	expect.fails(act(state, seat, { type = "playDevCard", card = "monopoly", resource = "ore" }, ctx), "1枚")
	p.devCards.victoryPoint = 1
	state.turn.devCardPlayed = false
	expect.fails(act(state, seat, { type = "playDevCard", card = "victoryPoint" }, ctx))
end)

test("Dev cards: monopoly, year of plenty, road building", function()
	local state, ctx = newGame(3, 71)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	for _, q in state.players do
		clearHand(state, q)
	end
	local a, b = state.order[2], state.order[3]
	state.bank.ore -= 5
	give(state.players[a], { ore = 3 })
	give(state.players[b], { ore = 2 })
	p.devCards.monopoly = 1
	expect.fails(act(state, seat, { type = "playDevCard", card = "monopoly", resource = "gold" }, ctx))
	expect.ok(act(state, seat, { type = "playDevCard", card = "monopoly", resource = "ore" }, ctx))
	expect.eq(p.resources.ore, 5)
	expect.eq(state.players[a].resources.ore, 0)

	state.turn.devCardPlayed = false
	p.devCards.yearOfPlenty = 1
	expect.fails(act(state, seat, { type = "playDevCard", card = "yearOfPlenty", resources = { "wool" } }, ctx))
	expect.fails(act(state, seat, { type = "playDevCard", card = "yearOfPlenty", resources = { "wool", "gold" } }, ctx))
	expect.ok(act(state, seat, { type = "playDevCard", card = "yearOfPlenty", resources = { "wool", "wool" } }, ctx))
	expect.eq(p.resources.wool, 2)

	state.turn.devCardPlayed = false
	p.devCards.roadBuilding = 1
	local roadsBefore = p.pieces.road
	expect.ok(act(state, seat, { type = "playDevCard", card = "roadBuilding" }, ctx))
	expect.eq(state.turn.freeRoads, 2)
	for _ = 1, 2 do
		local e = RuleEngine.legalRoadEdges(state, seat)[1]
		expect.ok(act(state, seat, { type = "placeRoad", edge = e }, ctx))
	end
	expect.eq(p.pieces.road, roadsBefore - 2)
	expect.eq(p.resources.lumber, 0, "free roads cost nothing")
	expect.eq(totalCards(state), 95)
end)

-- Longest road & largest army ----------------------------------------------------------------

local function pathEdges(state, length)
	-- a simple path of `length` edges along the coast
	local topology = Board.getTopology(state.layout.radius)
	local list = {}
	for i = 1, length do
		list[i] = topology.coastalEdges[i]
	end
	return list
end

test("Longest road: needs 5, counts branches correctly, broken by an opponent settlement", function()
	local state = newGame(3, 81)
	for e = 1, #state.edgeOwner do
		state.edgeOwner[e] = 0
	end
	for v = 1, #state.vertexOwner do
		state.vertexOwner[v], state.vertexBuilding[v] = 0, 0
	end
	local topology = Board.getTopology(2)
	local path = pathEdges(state, 6)
	for i = 1, 4 do
		state.edgeOwner[path[i]] = 1
	end
	LongestRoad.update(state)
	expect.eq(state.players[1].longestRoad, 4)
	expect.eq(state.longestRoadHolder, 0)
	state.edgeOwner[path[5]] = 1
	LongestRoad.update(state)
	expect.eq(state.longestRoadHolder, 1)
	expect.eq(GameState.publicPoints(state, 1), 2)

	-- a branch does not add to the length
	local shared
	for _, v in topology.edges[path[3]].vertices do
		for _, v2 in topology.edges[path[4]].vertices do
			if v == v2 then
				shared = v
			end
		end
	end
	for _, e in topology.vertices[shared].edges do
		if state.edgeOwner[e] == 0 then
			state.edgeOwner[e] = 1
		end
	end
	LongestRoad.update(state)
	expect.eq(state.players[1].longestRoad, 5)

	-- player 2 builds a ring of 6 around the centre tile -> takes it
	local inner = {}
	for _, tile in topology.tiles do
		if tile.q == 0 and tile.r == 0 then
			for i = 1, 6 do
				inner[i] = tile.edges[i]
			end
		end
	end
	for i = 1, 6 do
		state.edgeOwner[inner[i]] = 2
	end
	LongestRoad.update(state)
	expect.eq(state.players[2].longestRoad, 6, "ring of 6")
	expect.eq(state.longestRoadHolder, 2)

	-- opponent settlement on the ring breaks it into a path of 6 still? place on a ring vertex
	local ringVertex = topology.tiles[topology.tileAt["0,0"]].vertices[1]
	state.vertexOwner[ringVertex], state.vertexBuilding[ringVertex] = 3, 1
	LongestRoad.update(state)
	expect.eq(state.players[2].longestRoad, 6, "a ring broken at one vertex is still a path of 6")
	local ringVertex2 = topology.tiles[topology.tileAt["0,0"]].vertices[4]
	state.vertexOwner[ringVertex2], state.vertexBuilding[ringVertex2] = 3, 1
	LongestRoad.update(state)
	expect.eq(state.players[2].longestRoad, 3, "split into two paths of 3")
	expect.eq(state.longestRoadHolder, 1, "award returns to the unique longest")
end)

test("Largest army: needs 3 knights, must strictly exceed the holder", function()
	local state = newGame(3, 91)
	state.players[1].knightsPlayed = 2
	expect.falsy(LongestRoad.updateLargestArmy(state, 1))
	state.players[1].knightsPlayed = 3
	expect.truthy(LongestRoad.updateLargestArmy(state, 1))
	expect.eq(state.largestArmyHolder, 1)
	state.players[2].knightsPlayed = 3
	expect.falsy(LongestRoad.updateLargestArmy(state, 2))
	state.players[2].knightsPlayed = 4
	expect.truthy(LongestRoad.updateLargestArmy(state, 2))
	expect.eq(state.largestArmyHolder, 2)
	expect.falsy(state.players[1].hasLargestArmy)
end)

-- Victory ------------------------------------------------------------------------------------

test("Victory: reaching 10 points on your turn ends the game; hidden VP cards count", function()
	local state, ctx = newGame(3, 101)
	finishSetup(state, ctx)
	local seat = state.currentSeat
	local p = state.players[seat]
	ctx.rng = fixedRng({ 2, 2 })
	expect.ok(act(state, seat, { type = "rollDice" }, ctx))
	-- 2 settlements (2) + 7 VP cards = 9
	p.devCards.victoryPoint = 7
	expect.eq(state.phase, "main")
	expect.eq(StateView.forSeat(state, state.order[2]).players[seat].points, 2, "VP cards hidden from others")
	state.devDeck[#state.devDeck] = "victoryPoint"
	state.bank.wool -= 1
	state.bank.grain -= 1
	state.bank.ore -= 1
	give(p, { wool = 1, grain = 1, ore = 1 })
	expect.ok(act(state, seat, { type = "buyDevCard" }, ctx))
	expect.eq(state.phase, "finished")
	expect.eq(state.winner, seat)
	expect.fails(act(state, seat, { type = "endTurn" }, ctx), "終了")
	local view = StateView.forSeat(state, state.order[2])
	expect.eq(view.players[seat].points, 10, "revealed at the end")
	expect.truthy(view.players[seat].devCards ~= nil)
end)

-- Full simulated games -------------------------------------------------------------------

local function simulate(n, seed)
	local state, ctx = newGame(n, seed)
	finishSetup(state, ctx)
	local steps = 0
	while state.phase == "main" do
		steps += 1
		assert(steps < 20000, "game did not finish")
		-- everyone with a pending obligation acts (discards, trade answers)
		for _, p in state.players do
			if p.seat ~= state.currentSeat then
				local a = AutoPlayer.requiredAction(state, p.seat)
				if a then
					local ok, err = act(state, p.seat, a, ctx)
					assert(ok, err)
				end
			end
		end
		local seat = state.currentSeat
		local p = state.players[seat]
		if state.turnPhase == "roll" and p.devCards.knight > 0 and not state.turn.devCardPlayed then
			assert(act(state, seat, { type = "playDevCard", card = "knight" }, ctx))
		elseif state.turnPhase == "main" then
			local build = AutoPlayer.buildAction(state, seat)
			if build then
				local ok, err = act(state, seat, build, ctx)
				assert(ok, err)
			else
				assert(act(state, seat, AutoPlayer.requiredAction(state, seat), ctx))
			end
		else
			local a = AutoPlayer.requiredAction(state, seat)
			if a then
				local ok, err = act(state, seat, a, ctx)
				assert(ok, err)
			end
		end
		-- invariants
		assert(totalCards(state) == 95, "resource cards not conserved")
		for _, q in state.players do
			for _, r in RESOURCES do
				assert(q.resources[r] >= 0, "negative resources")
			end
			assert(q.pieces.road >= 0 and q.pieces.settlement >= 0 and q.pieces.city >= 0, "negative pieces")
		end
	end
	return state
end

test("Simulation: 3- and 4-player games always reach a winner with consistent state", function()
	for _, n in { 3, 4 } do
		for seed = 1, 15 do
			local state = simulate(n, seed * 97 + n)
			expect.eq(state.phase, "finished")
			local w = state.winner
			expect.truthy(w >= 1 and w <= n)
			expect.truthy(GameState.totalPoints(state, w) >= 10)
			-- every player's view agrees on the result
			for seat = 1, n do
				local view = StateView.forSeat(state, seat)
				expect.eq(view.winner, w)
				expect.eq(view.phase, "finished")
			end
			-- longest road holder really has the longest road
			if state.longestRoadHolder ~= 0 then
				local h = state.players[state.longestRoadHolder].longestRoad
				expect.truthy(h >= 5)
				for _, p in state.players do
					expect.truthy(p.longestRoad <= h)
				end
			end
		end
	end
end)
