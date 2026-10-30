--[[
	GameState: the authoritative game data (pure tables, no Instances).

	The whole state is plain data so it can be serialised (DataStore / tests)
	and filtered per player by StateView before being sent to clients.

	Arrays never contain nil holes (0 means "none") so they replicate safely
	through RemoteEvents.

	Seats are 1..N in join order. `state.order` is the turn order (seats).
]]

local Board = require(script.Parent.Board)
local RuleConfig = require(script.Parent.RuleConfig)
local Rng = require(script.Parent.Rng)

local GameState = {}

GameState.MAX_LOG = 60

function GameState.emptyResources()
	local r = {}
	for _, name in RuleConfig.Resources do
		r[name] = 0
	end
	return r
end

function GameState.emptyDevCards()
	local d = {}
	for _, name in RuleConfig.DevCardTypes do
		d[name] = 0
	end
	return d
end

--[[
	seats: array of { userId: number, name: string, color: string }
	rules: table from RuleConfig.create()
	rng:   Rng
]]
function GameState.new(seats, rules, rng)
	assert(#seats >= 1, "need at least one seat")
	local topology = Board.getTopology(rules.boardRadius)
	local layout = Board.generateLayout(rules, rng)

	local players = {}
	for i, s in seats do
		players[i] = {
			seat = i,
			userId = s.userId,
			name = s.name,
			color = s.color,
			resources = GameState.emptyResources(),
			devCards = GameState.emptyDevCards(), -- playable
			newDevCards = GameState.emptyDevCards(), -- bought this turn
			knightsPlayed = 0,
			pieces = {
				road = RuleConfig.get(rules, i, "pieceLimits", "road"),
				settlement = RuleConfig.get(rules, i, "pieceLimits", "settlement"),
				city = RuleConfig.get(rules, i, "pieceLimits", "city"),
			},
			mustDiscard = 0,
			longestRoad = 0,
			hasLongestRoad = false,
			hasLargestArmy = false,
			connected = true,
		}
	end

	local order = {}
	for i = 1, #seats do
		order[i] = i
	end
	Rng.shuffle(rng, order)

	-- Snake order for the initial placement: 1..N, N..1, ...
	local setupQueue = {}
	for round = 1, rules.setupRounds or 2 do
		if round % 2 == 1 then
			for i = 1, #order do
				table.insert(setupQueue, order[i])
			end
		else
			for i = #order, 1, -1 do
				table.insert(setupQueue, order[i])
			end
		end
	end

	local devDeck = {}
	for _, card in RuleConfig.DevCardTypes do
		for _ = 1, rules.devCardDeck[card] or 0 do
			table.insert(devDeck, card)
		end
	end
	Rng.shuffle(rng, devDeck)

	local bank = {}
	for _, name in RuleConfig.Resources do
		bank[name] = rules.bankResourceCount
	end

	local vertexOwner, vertexBuilding, edgeOwner = {}, {}, {}
	for i = 1, #topology.vertices do
		vertexOwner[i] = 0
		vertexBuilding[i] = 0 -- 0 none, 1 settlement, 2 city
	end
	for i = 1, #topology.edges do
		edgeOwner[i] = 0
	end

	local state = {
		version = 1,
		rules = rules,
		layout = layout,
		players = players,
		order = order,
		bank = bank,
		devDeck = devDeck,
		vertexOwner = vertexOwner,
		vertexBuilding = vertexBuilding,
		edgeOwner = edgeOwner,

		phase = "setup", -- "setup" | "main" | "finished"
		-- setupSettlement | setupRoad | roll | discard | moveRobber | steal | main
		turnPhase = "setupSettlement",
		setupQueue = setupQueue,
		setupStep = 1,
		currentSeat = setupQueue[1],
		turn = {
			number = 0,
			rolled = false,
			devCardPlayed = false,
			dice = {},
			diceTotal = 0,
			freeRoads = 0,
			setupVertex = 0,
		},
		stealCandidates = {},
		trade = nil,
		tradeSeq = 0,
		longestRoadHolder = 0,
		largestArmyHolder = 0,
		winner = 0,
		log = {},
		logSeq = 0,
	}
	GameState.addLog(state, "ゲーム開始！ 初期配置を行います。")
	return state
end

function GameState.addLog(state, text: string, kind: string?)
	state.logSeq += 1
	table.insert(state.log, { seq = state.logSeq, text = text, kind = kind or "info" })
	while #state.log > GameState.MAX_LOG do
		table.remove(state.log, 1)
	end
end

function GameState.topology(state)
	return Board.getTopology(state.layout.radius)
end

function GameState.player(state, seat: number)
	return state.players[seat]
end

-- Total resource cards. Works on full state and on filtered client views.
function GameState.resourceCount(player): number
	if player.resources then
		local n = 0
		for _, v in player.resources do
			n += v
		end
		return n
	end
	return player.resourceCount or 0
end

function GameState.countDevCards(cards): number
	local n = 0
	for _, v in cards do
		n += v
	end
	return n
end

-- Points visible to everyone (excludes hidden victory point cards)
function GameState.publicPoints(state, seat: number): number
	local rules = state.rules
	local points = 0
	for v = 1, #state.vertexOwner do
		if state.vertexOwner[v] == seat then
			if state.vertexBuilding[v] == 2 then
				points += RuleConfig.get(rules, seat, "points", "city")
			elseif state.vertexBuilding[v] == 1 then
				points += RuleConfig.get(rules, seat, "points", "settlement")
			end
		end
	end
	if state.longestRoadHolder == seat then
		points += RuleConfig.get(rules, seat, "points", "longestRoad")
	end
	if state.largestArmyHolder == seat then
		points += RuleConfig.get(rules, seat, "points", "largestArmy")
	end
	return points
end

-- Points including hidden victory point cards (server-side only)
function GameState.totalPoints(state, seat: number): number
	local p = state.players[seat]
	local cards = (p.devCards.victoryPoint or 0) + (p.newDevCards.victoryPoint or 0)
	return GameState.publicPoints(state, seat) + cards * RuleConfig.get(state.rules, seat, "points", "victoryPointCard")
end

return GameState
