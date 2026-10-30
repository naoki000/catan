--[[
	AutoPlayer: picks a legal action for a seat.

	* requiredAction: the minimal action needed to keep the game moving when a
	  player is disconnected (place setup pieces, roll, discard, move robber,
	  decline trades, end turn). Used by the server after a timeout.
	* buildAction: a simple building strategy, used by simulations/tests.

	Works on the full server state (never sees other players' hidden cards
	beyond what the rules expose: counts via GameState.resourceCount).
]]

local Board = require(script.Parent.Board)
local GameState = require(script.Parent.GameState)
local RuleConfig = require(script.Parent.RuleConfig)
local RuleEngine = require(script.Parent.RuleEngine)

local AutoPlayer = {}

local function pips(n: number): number
	if n == 0 then
		return 0
	end
	return 6 - math.abs(7 - n)
end

local function vertexScore(state, v: number): number
	local topology = Board.getTopology(state.layout.radius)
	local score = 0
	for _, t in topology.vertices[v].tiles do
		if t ~= state.layout.robberTile then
			score += pips(state.layout.numbers[t])
		end
	end
	return score
end

local function bestBy(list, score)
	local best, bestScore = nil, -math.huge
	for _, item in list do
		local s = score(item)
		if s > bestScore then
			best, bestScore = item, s
		end
	end
	return best
end

local function discardChoice(player)
	local cards = {}
	local left = player.mustDiscard
	while left > 0 do
		local most, mostCount = nil, 0
		for _, r in RuleConfig.Resources do
			local have = player.resources[r] - (cards[r] or 0)
			if have > mostCount then
				most, mostCount = r, have
			end
		end
		if not most then
			break
		end
		cards[most] = (cards[most] or 0) + 1
		left -= 1
	end
	return cards
end

function AutoPlayer.requiredAction(state, seat: number)
	if state.phase == "finished" then
		return nil
	end
	local player = state.players[seat]

	if state.turnPhase == "discard" and player.mustDiscard > 0 then
		return { type = "discard", resources = discardChoice(player) }
	end
	if state.trade and state.trade.from ~= seat and not state.trade.declined[tostring(seat)] then
		return { type = "respondTrade", tradeId = state.trade.id, accept = false }
	end
	if state.currentSeat ~= seat then
		return nil
	end

	local phase = state.turnPhase
	if phase == "setupSettlement" then
		local v = bestBy(RuleEngine.legalSettlementVertices(state, seat), function(candidate)
			return vertexScore(state, candidate)
		end)
		return v and { type = "placeSettlement", vertex = v } or nil
	elseif phase == "setupRoad" then
		local e = RuleEngine.legalRoadEdges(state, seat)[1]
		return e and { type = "placeRoad", edge = e } or nil
	elseif phase == "roll" then
		return { type = "rollDice" }
	elseif phase == "moveRobber" then
		local topology = Board.getTopology(state.layout.radius)
		local t = bestBy(RuleEngine.legalRobberTiles(state, seat), function(tileId)
			local s = 0
			for _, v in topology.tiles[tileId].vertices do
				local owner = state.vertexOwner[v]
				if owner == seat then
					s -= 10
				elseif owner ~= 0 then
					s += pips(state.layout.numbers[tileId]) + GameState.resourceCount(state.players[owner])
				end
			end
			return s
		end)
		return t and { type = "moveRobber", tile = t } or nil
	elseif phase == "steal" then
		return { type = "steal", target = state.stealCandidates[1] }
	elseif phase == "main" then
		if state.trade and state.trade.from == seat then
			return { type = "cancelTrade" }
		end
		return { type = "endTurn" }
	end
	return nil
end

-- Next building/trading action for a simple bot, or nil when it is done for this turn.
function AutoPlayer.buildAction(state, seat: number)
	if state.phase ~= "main" or state.currentSeat ~= seat or state.turnPhase ~= "main" then
		return nil
	end
	local player = state.players[seat]

	local city = RuleEngine.legalCityVertices(state, seat)[1]
	if city then
		return { type = "buildCity", vertex = city }
	end
	local settlement = bestBy(RuleEngine.legalSettlementVertices(state, seat), function(v)
		return vertexScore(state, v)
	end)
	if settlement then
		return { type = "placeSettlement", vertex = settlement }
	end
	if #state.devDeck > 0 and RuleEngine.hasResources(player, RuleEngine.cost(state, seat, "devCard")) then
		return { type = "buyDevCard" }
	end
	if
		state.turn.freeRoads > 0
		or (player.pieces.settlement > 0 and RuleEngine.hasResources(player, RuleEngine.cost(state, seat, "road")))
	then
		local road = RuleEngine.legalRoadEdges(state, seat)[1]
		if road then
			return { type = "placeRoad", edge = road }
		end
	end
	-- Trade the most plentiful resource for the scarcest one
	local need = bestBy(RuleConfig.Resources, function(r)
		return -player.resources[r]
	end)
	for _, r in RuleConfig.Resources do
		if r ~= need and player.resources[r] >= RuleEngine.tradeRatio(state, seat, r) + 1 and state.bank[need] > 0 then
			return { type = "bankTrade", give = r, get = need }
		end
	end
	return nil
end

return AutoPlayer
