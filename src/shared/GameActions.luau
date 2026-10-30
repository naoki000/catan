--[[
	GameActions: the single entry point that changes a game.

	    local ok, err = GameActions.perform(state, seat, action, ctx)

	  action = { type = "placeRoad", edge = 12 }   (plain table from the client)
	  ctx    = { rng = Rng, authority = "player" }

	Each handler validates EVERYTHING (via RuleEngine) before mutating, so a
	rejected action leaves the state untouched. Normal play always uses
	authority = "player". A future game-master / free-edit mode will add
	handlers that run with a different authority through this same function,
	so logging, versioning and victory checks stay in one place.
]]

local Board = require(script.Parent.Board)
local GameState = require(script.Parent.GameState)
local LongestRoad = require(script.Parent.LongestRoad)
local RuleConfig = require(script.Parent.RuleConfig)
local RuleEngine = require(script.Parent.RuleEngine)

local GameActions = {}
local handlers = {}

local R = RuleConfig.ResourceNames

local function name(state, seat: number): string
	return state.players[seat].name
end

local function pay(state, player, cost)
	for r, n in cost do
		player.resources[r] -= n
		state.bank[r] += n
	end
end

local function formatResources(map): string
	local parts = {}
	for _, r in RuleConfig.Resources do
		if (map[r] or 0) > 0 then
			table.insert(parts, R[r] .. "×" .. map[r])
		end
	end
	return #parts > 0 and table.concat(parts, " ") or "なし"
end
GameActions.formatResources = formatResources

-- Building ---------------------------------------------------------------------------

handlers.placeSettlement = function(state, seat, action)
	local vertex = action.vertex
	local ok, reason = RuleEngine.canPlaceSettlement(state, seat, vertex)
	if not ok then
		return false, reason
	end
	local player = state.players[seat]

	if state.phase == "setup" then
		state.vertexOwner[vertex] = seat
		state.vertexBuilding[vertex] = 1
		player.pieces.settlement -= 1
		state.turn.setupVertex = vertex
		state.turnPhase = "setupRoad"

		-- The settlement placed in the final setup round collects starting resources
		local isLastRound = state.setupStep > #state.setupQueue - #state.order
		if isLastRound then
			local topology = Board.getTopology(state.layout.radius)
			local gained = {}
			for _, t in topology.vertices[vertex].tiles do
				local resource = RuleConfig.TerrainResource[state.layout.terrain[t]]
				if resource and state.bank[resource] > 0 then
					state.bank[resource] -= 1
					player.resources[resource] += 1
					gained[resource] = (gained[resource] or 0) + 1
				end
			end
			GameState.addLog(
				state,
				string.format(
					"%s が開拓地を配置し、初期資源 %s を獲得",
					name(state, seat),
					formatResources(gained)
				),
				"build"
			)
		else
			GameState.addLog(state, name(state, seat) .. " が開拓地を配置", "build")
		end
	else
		pay(state, player, RuleEngine.cost(state, seat, "settlement"))
		state.vertexOwner[vertex] = seat
		state.vertexBuilding[vertex] = 1
		player.pieces.settlement -= 1
		GameState.addLog(state, name(state, seat) .. " が開拓地を建設", "build")
	end
	LongestRoad.update(state)
	return true
end

local function advanceSetup(state)
	state.setupStep += 1
	state.turn.setupVertex = 0
	if state.setupStep > #state.setupQueue then
		state.phase = "main"
		state.turnPhase = "roll"
		state.currentSeat = state.order[1]
		state.turn.number = 1
		GameState.addLog(
			state,
			"初期配置が完了しました。" .. name(state, state.currentSeat) .. " の手番です。",
			"turn"
		)
	else
		state.currentSeat = state.setupQueue[state.setupStep]
		state.turnPhase = "setupSettlement"
	end
end

handlers.placeRoad = function(state, seat, action)
	local edge = action.edge
	local ok, reason = RuleEngine.canPlaceRoad(state, seat, edge)
	if not ok then
		return false, reason
	end
	local player = state.players[seat]

	if state.phase == "setup" then
		state.edgeOwner[edge] = seat
		player.pieces.road -= 1
		GameState.addLog(state, name(state, seat) .. " が街道を配置", "build")
		advanceSetup(state)
	else
		if state.turn.freeRoads > 0 then
			state.turn.freeRoads -= 1
		else
			pay(state, player, RuleEngine.cost(state, seat, "road"))
		end
		state.edgeOwner[edge] = seat
		player.pieces.road -= 1
		GameState.addLog(state, name(state, seat) .. " が街道を建設", "build")
	end
	LongestRoad.update(state)
	return true
end

handlers.buildCity = function(state, seat, action)
	local vertex = action.vertex
	local ok, reason = RuleEngine.canBuildCity(state, seat, vertex)
	if not ok then
		return false, reason
	end
	local player = state.players[seat]
	pay(state, player, RuleEngine.cost(state, seat, "city"))
	state.vertexBuilding[vertex] = 2
	player.pieces.city -= 1
	player.pieces.settlement += 1
	GameState.addLog(state, name(state, seat) .. " が都市を建設", "build")
	return true
end

-- Dice & production -----------------------------------------------------------------

local function produce(state, total: number)
	local topology = Board.getTopology(state.layout.radius)
	-- demand[resource][seat] = amount
	local demand = {}
	for t, tile in topology.tiles do
		local resource = RuleConfig.TerrainResource[state.layout.terrain[t]]
		if resource and state.layout.numbers[t] == total and t ~= state.layout.robberTile then
			for _, v in tile.vertices do
				local owner = state.vertexOwner[v]
				if owner ~= 0 then
					local kind = state.vertexBuilding[v] == 2 and "city" or "settlement"
					local amount = RuleConfig.get(state.rules, owner, "production", kind)
					demand[resource] = demand[resource] or {}
					demand[resource][owner] = (demand[resource][owner] or 0) + amount
				end
			end
		end
	end

	local gains = {}
	for _, resource in RuleConfig.Resources do
		local wants = demand[resource]
		if wants then
			local needed, receivers = 0, 0
			for _, amount in wants do
				needed += amount
				receivers += 1
			end
			local available = state.bank[resource]
			for seat, amount in wants do
				local give = 0
				if needed <= available then
					give = amount
				elseif receivers == 1 then
					give = available -- a single player takes whatever is left
				end
				-- otherwise nobody receives this resource (bank shortage rule)
				if give > 0 then
					state.bank[resource] -= give
					state.players[seat].resources[resource] += give
					gains[seat] = gains[seat] or {}
					gains[seat][resource] = (gains[seat][resource] or 0) + give
				end
			end
			if needed > available and receivers > 1 then
				GameState.addLog(
					state,
					R[resource] .. " の在庫が足りないため配布されません",
					"produce"
				)
			end
		end
	end

	local any = false
	for _, seat in state.order do
		if gains[seat] then
			any = true
			GameState.addLog(
				state,
				string.format("  %s: %s", name(state, seat), formatResources(gains[seat])),
				"produce"
			)
		end
	end
	if not any then
		GameState.addLog(state, "  資源の産出はありません", "produce")
	end
	return gains
end
GameActions.produce = produce

handlers.rollDice = function(state, seat, _action, ctx)
	if state.phase ~= "main" or state.currentSeat ~= seat then
		return false, "あなたの手番ではありません"
	end
	if state.turnPhase ~= "roll" then
		return false, "今はサイコロを振れません"
	end
	local diceRule = RuleConfig.get(state.rules, seat, "dice")
	local dice, total = {}, 0
	for i = 1, diceRule.count do
		dice[i] = ctx.rng:nextInt(1, diceRule.sides)
		total += dice[i]
	end
	state.turn.dice = dice
	state.turn.diceTotal = total
	state.turn.rolled = true
	GameState.addLog(
		state,
		string.format(
			"%s がサイコロを振りました: %s = %d",
			name(state, seat),
			table.concat(dice, "+"),
			total
		),
		"dice"
	)

	if total == state.rules.robberRoll then
		local anyDiscard = false
		for _, p in state.players do
			local count = GameState.resourceCount(p)
			if count > RuleConfig.get(state.rules, p.seat, "discardLimit") then
				p.mustDiscard = math.floor(count / 2)
				anyDiscard = true
				GameState.addLog(
					state,
					string.format("  %s は %d 枚捨てる必要があります", p.name, p.mustDiscard),
					"robber"
				)
			end
		end
		state.turnPhase = anyDiscard and "discard" or "moveRobber"
	else
		produce(state, total)
		state.turnPhase = "main"
	end
	return true
end

handlers.discard = function(state, seat, action)
	local player = state.players[seat]
	if state.turnPhase ~= "discard" or player.mustDiscard <= 0 then
		return false, "捨てる必要はありません"
	end
	local cards, total = RuleEngine.cleanResourceMap(action.resources)
	if not cards then
		return false, "不正な指定です"
	end
	if total ~= player.mustDiscard then
		return false, string.format("ちょうど %d 枚選んでください", player.mustDiscard)
	end
	if not RuleEngine.hasResources(player, cards) then
		return false, "その資源を持っていません"
	end
	pay(state, player, cards)
	player.mustDiscard = 0
	GameState.addLog(state, string.format("%s が %d 枚捨てました", player.name, total), "robber")
	for _, p in state.players do
		if p.mustDiscard > 0 then
			return true
		end
	end
	state.turnPhase = "moveRobber"
	return true
end

local function finishRobber(state)
	state.stealCandidates = {}
	state.turnPhase = state.turn.rolled and "main" or "roll"
end

local function stealFrom(state, thief: number, victim: number, ctx)
	local pool = {}
	for _, r in RuleConfig.Resources do
		for _ = 1, state.players[victim].resources[r] do
			table.insert(pool, r)
		end
	end
	if #pool == 0 then
		return
	end
	local r = pool[ctx.rng:nextInt(1, #pool)]
	state.players[victim].resources[r] -= 1
	state.players[thief].resources[r] += 1
	-- Which card was taken is private: the public log omits the resource
	GameState.addLog(
		state,
		string.format("%s が %s から資源を1枚奪いました", name(state, thief), name(state, victim)),
		"robber"
	)
end

handlers.moveRobber = function(state, seat, action, ctx)
	local ok, reason = RuleEngine.canMoveRobber(state, seat, action.tile)
	if not ok then
		return false, reason
	end
	state.layout.robberTile = action.tile
	local terrain = RuleConfig.TerrainNames[state.layout.terrain[action.tile]]
	GameState.addLog(state, string.format("%s が盗賊を %s に移動", name(state, seat), terrain), "robber")
	local candidates = RuleEngine.stealCandidates(state, seat, action.tile)
	if #candidates == 0 then
		finishRobber(state)
	elseif #candidates == 1 then
		stealFrom(state, seat, candidates[1], ctx)
		finishRobber(state)
	else
		state.stealCandidates = candidates
		state.turnPhase = "steal"
	end
	return true
end

handlers.steal = function(state, seat, action, ctx)
	if state.currentSeat ~= seat or state.turnPhase ~= "steal" then
		return false, "今は資源を奪えません"
	end
	if not table.find(state.stealCandidates, action.target) then
		return false, "そのプレイヤーからは奪えません"
	end
	stealFrom(state, seat, action.target, ctx)
	finishRobber(state)
	return true
end

-- Development cards --------------------------------------------------------------------

handlers.buyDevCard = function(state, seat)
	local ok, reason = RuleEngine.requireMainTurn(state, seat)
	if not ok then
		return false, reason
	end
	local player = state.players[seat]
	if #state.devDeck == 0 then
		return false, "発展カードが残っていません"
	end
	local cost = RuleEngine.cost(state, seat, "devCard")
	if not RuleEngine.hasResources(player, cost) then
		return false, "資源が足りません"
	end
	pay(state, player, cost)
	local card = table.remove(state.devDeck)
	player.newDevCards[card] += 1
	GameState.addLog(state, name(state, seat) .. " が発展カードを購入", "dev")
	return true
end

handlers.playDevCard = function(state, seat, action)
	local card = action.card
	if state.phase ~= "main" or state.currentSeat ~= seat then
		return false, "あなたの手番ではありません"
	end
	if state.turnPhase ~= "roll" and state.turnPhase ~= "main" then
		return false, "今は発展カードを使えません"
	end
	if state.turn.devCardPlayed then
		return false, "発展カードは1ターンに1枚までです"
	end
	local player = state.players[seat]
	if type(card) ~= "string" or player.devCards[card] == nil or card == "victoryPoint" then
		return false, "そのカードは使えません"
	end
	if player.devCards[card] <= 0 then
		if (player.newDevCards[card] or 0) > 0 then
			return false, "購入したターンには使えません"
		end
		return false, "そのカードを持っていません"
	end

	-- Validate card-specific input before changing anything
	if card == "roadBuilding" then
		if player.pieces.road <= 0 then
			return false, "街道が残っていません"
		end
	elseif card == "yearOfPlenty" then
		local picks = action.resources
		local count = RuleConfig.get(state.rules, seat, "yearOfPlentyPicks")
		if type(picks) ~= "table" or #picks ~= count then
			return false, string.format("資源を %d つ選んでください", count)
		end
		local need = {}
		for i = 1, count do
			local r = picks[i]
			if not RuleEngine.isResource(r) then
				return false, "不正な資源です"
			end
			need[r] = (need[r] or 0) + 1
		end
		for r, n in need do
			if state.bank[r] < n then
				return false, R[r] .. " の在庫が足りません"
			end
		end
	elseif card == "monopoly" then
		if not RuleEngine.isResource(action.resource) then
			return false, "資源を選んでください"
		end
	end

	player.devCards[card] -= 1
	state.turn.devCardPlayed = true
	local cardName = RuleConfig.DevCardNames[card]

	if card == "knight" then
		player.knightsPlayed += 1
		GameState.addLog(state, name(state, seat) .. " が「" .. cardName .. "」を使用", "dev")
		if LongestRoad.updateLargestArmy(state, seat) then
			GameState.addLog(state, name(state, seat) .. " が最大騎士力を獲得", "award")
		end
		state.turnPhase = "moveRobber"
	elseif card == "roadBuilding" then
		state.turn.freeRoads = math.min(RuleConfig.get(state.rules, seat, "roadBuildingRoads"), player.pieces.road)
		GameState.addLog(
			state,
			string.format(
				"%s が「%s」を使用（街道 %d 本）",
				name(state, seat),
				cardName,
				state.turn.freeRoads
			),
			"dev"
		)
	elseif card == "yearOfPlenty" then
		local got = {}
		for i = 1, RuleConfig.get(state.rules, seat, "yearOfPlentyPicks") do
			local r = action.resources[i]
			state.bank[r] -= 1
			player.resources[r] += 1
			got[r] = (got[r] or 0) + 1
		end
		GameState.addLog(
			state,
			string.format("%s が「%s」で %s を獲得", name(state, seat), cardName, formatResources(got)),
			"dev"
		)
	elseif card == "monopoly" then
		local r = action.resource
		local taken = 0
		for _, other in state.players do
			if other.seat ~= seat then
				taken += other.resources[r]
				player.resources[r] += other.resources[r]
				other.resources[r] = 0
			end
		end
		GameState.addLog(
			state,
			string.format("%s が「%s」で %s を %d 枚獲得", name(state, seat), cardName, R[r], taken),
			"dev"
		)
	end
	return true
end

-- Trading ---------------------------------------------------------------------------------

handlers.bankTrade = function(state, seat, action)
	local ok, reason = RuleEngine.requireMainTurn(state, seat)
	if not ok then
		return false, reason
	end
	local give, get = action.give, action.get
	if not RuleEngine.isResource(give) or not RuleEngine.isResource(get) or give == get then
		return false, "不正な交換です"
	end
	local player = state.players[seat]
	local ratio = RuleEngine.tradeRatio(state, seat, give)
	if player.resources[give] < ratio then
		return false, string.format("%s が %d 枚必要です", R[give], ratio)
	end
	if state.bank[get] < 1 then
		return false, R[get] .. " の在庫がありません"
	end
	player.resources[give] -= ratio
	state.bank[give] += ratio
	player.resources[get] += 1
	state.bank[get] -= 1
	GameState.addLog(
		state,
		string.format("%s が銀行と交換: %s×%d → %s×1", name(state, seat), R[give], ratio, R[get]),
		"trade"
	)
	return true
end

handlers.proposeTrade = function(state, seat, action)
	local ok, reason = RuleEngine.requireMainTurn(state, seat)
	if not ok then
		return false, reason
	end
	local give, giveTotal = RuleEngine.cleanResourceMap(action.give)
	local want, wantTotal = RuleEngine.cleanResourceMap(action.want)
	if not give or not want or giveTotal == 0 or wantTotal == 0 then
		return false, "出す資源と欲しい資源を選んでください"
	end
	for r in give do
		if want[r] then
			return false, "同じ資源を出して受け取ることはできません"
		end
	end
	if not RuleEngine.hasResources(state.players[seat], give) then
		return false, "出す資源が足りません"
	end
	state.tradeSeq += 1
	state.trade = { id = state.tradeSeq, from = seat, give = give, want = want, declined = {} }
	GameState.addLog(
		state,
		string.format(
			"%s が取引を提案: 出す %s / 欲しい %s",
			name(state, seat),
			formatResources(give),
			formatResources(want)
		),
		"trade"
	)
	return true
end

handlers.respondTrade = function(state, seat, action)
	local trade = state.trade
	if not trade or trade.id ~= action.tradeId then
		return false, "その取引は終了しています"
	end
	if trade.from == seat then
		return false, "自分の提案には応答できません"
	end
	if action.accept == true then
		local responder, proposer = state.players[seat], state.players[trade.from]
		if not RuleEngine.hasResources(responder, trade.want) then
			return false, "必要な資源が足りません"
		end
		if not RuleEngine.hasResources(proposer, trade.give) then
			return false, "提案者の資源が足りなくなりました"
		end
		for r, n in trade.give do
			proposer.resources[r] -= n
			responder.resources[r] += n
		end
		for r, n in trade.want do
			responder.resources[r] -= n
			proposer.resources[r] += n
		end
		state.trade = nil
		GameState.addLog(state, string.format("取引成立: %s ⇄ %s", proposer.name, responder.name), "trade")
	else
		trade.declined[tostring(seat)] = true
		GameState.addLog(state, name(state, seat) .. " が取引を断りました", "trade")
		for _, p in state.players do
			if p.seat ~= trade.from and not trade.declined[tostring(p.seat)] then
				return true
			end
		end
		state.trade = nil
		GameState.addLog(state, "全員が断ったため取引は終了しました", "trade")
	end
	return true
end

handlers.cancelTrade = function(state, seat)
	if not state.trade or state.trade.from ~= seat then
		return false, "取り消せる取引がありません"
	end
	state.trade = nil
	GameState.addLog(state, name(state, seat) .. " が取引を取り消しました", "trade")
	return true
end

-- Turn ------------------------------------------------------------------------------------

handlers.endTurn = function(state, seat)
	local ok, reason = RuleEngine.requireMainTurn(state, seat)
	if not ok then
		return false, reason
	end
	local player = state.players[seat]
	for card, n in player.newDevCards do
		player.devCards[card] += n
		player.newDevCards[card] = 0
	end
	state.trade = nil
	local index = table.find(state.order, seat) or 0
	state.currentSeat = state.order[index % #state.order + 1]
	state.turnPhase = "roll"
	state.turn.number += 1
	state.turn.rolled = false
	state.turn.devCardPlayed = false
	state.turn.dice = {}
	state.turn.diceTotal = 0
	state.turn.freeRoads = 0
	GameState.addLog(state, name(state, state.currentSeat) .. " の手番です", "turn")
	return true
end

-- Entry point ---------------------------------------------------------------------------

local function checkVictory(state)
	if state.phase ~= "main" then
		return
	end
	local seat = state.currentSeat
	local target = RuleConfig.get(state.rules, seat, "victoryPointsToWin")
	if GameState.totalPoints(state, seat) >= target then
		state.phase = "finished"
		state.winner = seat
		state.trade = nil
		GameState.addLog(
			state,
			string.format(
				"🏆 %s が %d 点で勝利しました！",
				name(state, seat),
				GameState.totalPoints(state, seat)
			),
			"win"
		)
	end
end

GameActions.ActionTypes = {}
for actionType in handlers do
	GameActions.ActionTypes[actionType] = true
end

function GameActions.perform(state, seat: number, action, ctx): (boolean, string?)
	if type(action) ~= "table" or type(action.type) ~= "string" then
		return false, "不正な操作です"
	end
	local handler = handlers[action.type]
	if not handler then
		return false, "不明な操作です"
	end
	if state.phase == "finished" then
		return false, "ゲームは終了しています"
	end
	if not state.players[seat] then
		return false, "プレイヤーが見つかりません"
	end
	local ok, err = handler(state, seat, action, ctx)
	if ok then
		state.version += 1
		checkVictory(state)
		return true
	end
	return false, err
end

return GameActions
