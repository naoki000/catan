--[[
	StateView: the filtered copy of the game state that one player may see.

	Hidden from other players:
	  * resource cards by type (only the total count is shown)
	  * development cards (only the count), including victory point cards
	  * the order of the development card deck (only its size)
	After the game ends all hands are revealed.
]]

local GameState = require(script.Parent.GameState)
local RuleConfig = require(script.Parent.RuleConfig)

local StateView = {}

local copy = RuleConfig.deepCopy

function StateView.forSeat(state, seat: number?)
	local finished = state.phase == "finished"
	local players = {}
	for i, p in state.players do
		local view = {
			seat = p.seat,
			userId = p.userId,
			name = p.name,
			color = p.color,
			pieces = copy(p.pieces),
			knightsPlayed = p.knightsPlayed,
			mustDiscard = p.mustDiscard,
			longestRoad = p.longestRoad,
			hasLongestRoad = p.hasLongestRoad,
			hasLargestArmy = p.hasLargestArmy,
			connected = p.connected,
			resourceCount = GameState.resourceCount(p),
			devCardCount = GameState.countDevCards(p.devCards) + GameState.countDevCards(p.newDevCards),
			points = GameState.publicPoints(state, i),
		}
		if i == seat or finished then
			view.resources = copy(p.resources)
			view.devCards = copy(p.devCards)
			view.newDevCards = copy(p.newDevCards)
			view.points = GameState.totalPoints(state, i)
		end
		players[i] = view
	end

	return {
		version = state.version,
		mySeat = seat or 0,
		rules = copy(state.rules),
		layout = copy(state.layout),
		players = players,
		order = copy(state.order),
		bank = copy(state.bank),
		devDeckCount = #state.devDeck,
		vertexOwner = copy(state.vertexOwner),
		vertexBuilding = copy(state.vertexBuilding),
		edgeOwner = copy(state.edgeOwner),
		phase = state.phase,
		turnPhase = state.turnPhase,
		setupStep = state.setupStep,
		setupQueue = copy(state.setupQueue),
		currentSeat = state.currentSeat,
		turn = copy(state.turn),
		stealCandidates = copy(state.stealCandidates),
		trade = state.trade and copy(state.trade) or nil,
		longestRoadHolder = state.longestRoadHolder,
		largestArmyHolder = state.largestArmyHolder,
		winner = state.winner,
		log = copy(state.log),
	}
end

return StateView
