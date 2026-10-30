--[[
	RuleEngine: pure legality checks. Never mutates state.

	Every check returns (ok: boolean, reason: string?). The same functions run
	on the server (authoritative validation in GameActions) and on the client
	(highlighting legal spots), so the client can never show something the
	server would reject for a different reason.

	Client views (StateView) contain only the local player's resources; all
	checks that read resources only read the acting player's own hand.
]]

local Board = require(script.Parent.Board)
local GameState = require(script.Parent.GameState)
local RuleConfig = require(script.Parent.RuleConfig)

local RuleEngine = {}

local RESOURCE_SET = {}
for _, r in RuleConfig.Resources do
	RESOURCE_SET[r] = true
end

-- Input validation helpers ----------------------------------------------------

function RuleEngine.isInt(value, min: number, max: number): boolean
	return type(value) == "number" and value == value and math.floor(value) == value and value >= min and value <= max
end

function RuleEngine.isResource(value): boolean
	return type(value) == "string" and RESOURCE_SET[value] == true
end

-- A { resource = count } map with known resources and non-negative integer counts.
-- Returns a clean copy (zero entries removed) or nil.
function RuleEngine.cleanResourceMap(value)
	if type(value) ~= "table" then
		return nil
	end
	local clean, total = {}, 0
	for k, v in value do
		if not RuleEngine.isResource(k) or not RuleEngine.isInt(v, 0, 99) then
			return nil
		end
		if v > 0 then
			clean[k] = v
			total += v
		end
	end
	return clean, total
end

function RuleEngine.hasResources(player, cost): boolean
	if not player.resources then
		return false
	end
	for r, n in cost do
		if (player.resources[r] or 0) < n then
			return false
		end
	end
	return true
end

function RuleEngine.cost(state, seat: number, item: string)
	return RuleConfig.get(state.rules, seat, "buildingCosts", item)
end

-- Turn helpers ------------------------------------------------------------------

local function isCurrent(state, seat: number): boolean
	return state.currentSeat == seat and state.phase ~= "finished"
end

local function requireMainTurn(state, seat: number)
	if state.phase ~= "main" then
		return false, "今は実行できません"
	end
	if not isCurrent(state, seat) then
		return false, "あなたの手番ではありません"
	end
	if state.turnPhase ~= "main" then
		return false, "先にサイコロや盗賊の処理を終えてください"
	end
	return true
end
RuleEngine.requireMainTurn = requireMainTurn

-- Board queries ----------------------------------------------------------------

function RuleEngine.distanceRuleOk(state, vertex: number): boolean
	local topology = Board.getTopology(state.layout.radius)
	for _, n in topology.vertices[vertex].neighbors do
		if state.vertexOwner[n] ~= 0 then
			return false
		end
	end
	return true
end

function RuleEngine.vertexTouchesOwnRoad(state, seat: number, vertex: number): boolean
	local topology = Board.getTopology(state.layout.radius)
	for _, e in topology.vertices[vertex].edges do
		if state.edgeOwner[e] == seat then
			return true
		end
	end
	return false
end

-- Road connectivity: touches own building, or own road through a vertex not blocked by an opponent
function RuleEngine.edgeConnects(state, seat: number, edge: number): boolean
	local topology = Board.getTopology(state.layout.radius)
	for _, v in topology.edges[edge].vertices do
		local owner = state.vertexOwner[v]
		if owner == seat then
			return true
		end
		if owner == 0 then
			for _, e in topology.vertices[v].edges do
				if e ~= edge and state.edgeOwner[e] == seat then
					return true
				end
			end
		end
	end
	return false
end

-- Settlements --------------------------------------------------------------------

function RuleEngine.canPlaceSettlement(state, seat: number, vertex)
	local topology = Board.getTopology(state.layout.radius)
	if not RuleEngine.isInt(vertex, 1, #topology.vertices) then
		return false, "不正な場所です"
	end
	local player = state.players[seat]
	if not player then
		return false, "プレイヤーが見つかりません"
	end

	local isSetup = state.phase == "setup"
	if isSetup then
		if not isCurrent(state, seat) then
			return false, "あなたの手番ではありません"
		end
		if state.turnPhase ~= "setupSettlement" then
			return false, "次は街道を置いてください"
		end
	else
		local ok, reason = requireMainTurn(state, seat)
		if not ok then
			return false, reason
		end
	end

	if player.pieces.settlement <= 0 then
		return false, "開拓地が残っていません"
	end
	if state.vertexOwner[vertex] ~= 0 then
		return false, "すでに建物があります"
	end
	if not RuleEngine.distanceRuleOk(state, vertex) then
		return false, "隣の交点に建物があります（距離ルール）"
	end
	if not isSetup then
		if not RuleEngine.vertexTouchesOwnRoad(state, seat, vertex) then
			return false, "自分の街道につながっていません"
		end
		if not RuleEngine.hasResources(player, RuleEngine.cost(state, seat, "settlement")) then
			return false, "資源が足りません"
		end
	end
	return true
end

-- Roads ----------------------------------------------------------------------------

function RuleEngine.canPlaceRoad(state, seat: number, edge)
	local topology = Board.getTopology(state.layout.radius)
	if not RuleEngine.isInt(edge, 1, #topology.edges) then
		return false, "不正な場所です"
	end
	local player = state.players[seat]
	if not player then
		return false, "プレイヤーが見つかりません"
	end
	if not isCurrent(state, seat) then
		return false, "あなたの手番ではありません"
	end

	local isSetup = state.phase == "setup"
	local free = state.turn.freeRoads > 0
	if isSetup then
		if state.turnPhase ~= "setupRoad" then
			return false, "先に開拓地を置いてください"
		end
	elseif state.phase ~= "main" then
		return false, "今は実行できません"
	elseif free then
		if state.turnPhase ~= "main" and state.turnPhase ~= "roll" then
			return false, "今は街道を置けません"
		end
	elseif state.turnPhase ~= "main" then
		return false, "先にサイコロや盗賊の処理を終えてください"
	end

	if player.pieces.road <= 0 then
		return false, "街道が残っていません"
	end
	if state.edgeOwner[edge] ~= 0 then
		return false, "すでに街道があります"
	end

	if isSetup then
		local ev = topology.edges[edge].vertices
		if ev[1] ~= state.turn.setupVertex and ev[2] ~= state.turn.setupVertex then
			return false, "今置いた開拓地に接続してください"
		end
		return true
	end

	if not RuleEngine.edgeConnects(state, seat, edge) then
		return false, "自分の街道か建物につながっていません"
	end
	if not free and not RuleEngine.hasResources(player, RuleEngine.cost(state, seat, "road")) then
		return false, "資源が足りません"
	end
	return true
end

-- Cities ---------------------------------------------------------------------------

function RuleEngine.canBuildCity(state, seat: number, vertex)
	local topology = Board.getTopology(state.layout.radius)
	if not RuleEngine.isInt(vertex, 1, #topology.vertices) then
		return false, "不正な場所です"
	end
	local ok, reason = requireMainTurn(state, seat)
	if not ok then
		return false, reason
	end
	local player = state.players[seat]
	if state.vertexOwner[vertex] ~= seat or state.vertexBuilding[vertex] ~= 1 then
		return false, "自分の開拓地を選んでください"
	end
	if player.pieces.city <= 0 then
		return false, "都市が残っていません"
	end
	if not RuleEngine.hasResources(player, RuleEngine.cost(state, seat, "city")) then
		return false, "資源が足りません"
	end
	return true
end

-- Robber ---------------------------------------------------------------------------

function RuleEngine.canMoveRobber(state, seat: number, tile)
	local topology = Board.getTopology(state.layout.radius)
	if not isCurrent(state, seat) or state.turnPhase ~= "moveRobber" then
		return false, "今は盗賊を動かせません"
	end
	if not RuleEngine.isInt(tile, 1, #topology.tiles) then
		return false, "不正な地形です"
	end
	if tile == state.layout.robberTile then
		return false, "別の地形を選んでください"
	end
	return true
end

-- Seats (other than `seat`) with a building on `tile` and at least one resource card
function RuleEngine.stealCandidates(state, seat: number, tile: number)
	local topology = Board.getTopology(state.layout.radius)
	local found, list = {}, {}
	for _, v in topology.tiles[tile].vertices do
		local owner = state.vertexOwner[v]
		if owner ~= 0 and owner ~= seat and not found[owner] then
			found[owner] = true
			if GameState.resourceCount(state.players[owner]) > 0 then
				table.insert(list, owner)
			end
		end
	end
	table.sort(list)
	return list
end

-- Trading --------------------------------------------------------------------------

function RuleEngine.tradeRatio(state, seat: number, resource: string): number
	local ratios = RuleConfig.get(state.rules, seat, "tradeRatios")
	local best = ratios.bank
	for _, port in state.layout.ports do
		local owned = state.vertexOwner[port.vertices[1]] == seat or state.vertexOwner[port.vertices[2]] == seat
		if owned then
			if port.kind == resource then
				best = math.min(best, ratios.specificPort)
			elseif port.kind == "generic" then
				best = math.min(best, ratios.genericPort)
			end
		end
	end
	return best
end

-- Legal move lists (used for highlighting and by AutoPlayer) -------------------------

function RuleEngine.legalSettlementVertices(state, seat: number)
	local list = {}
	for v = 1, #state.vertexOwner do
		if RuleEngine.canPlaceSettlement(state, seat, v) then
			table.insert(list, v)
		end
	end
	return list
end

function RuleEngine.legalRoadEdges(state, seat: number)
	local list = {}
	for e = 1, #state.edgeOwner do
		if RuleEngine.canPlaceRoad(state, seat, e) then
			table.insert(list, e)
		end
	end
	return list
end

function RuleEngine.legalCityVertices(state, seat: number)
	local list = {}
	for v = 1, #state.vertexOwner do
		if RuleEngine.canBuildCity(state, seat, v) then
			table.insert(list, v)
		end
	end
	return list
end

function RuleEngine.legalRobberTiles(state, seat: number)
	local list = {}
	for t = 1, #state.layout.terrain do
		if RuleEngine.canMoveRobber(state, seat, t) then
			table.insert(list, t)
		end
	end
	return list
end

return RuleEngine
