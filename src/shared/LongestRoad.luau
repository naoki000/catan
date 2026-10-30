--[[
	LongestRoad: longest continuous road per player, and award holders.

	A path may branch, may loop, uses each road segment at most once, and
	cannot continue THROUGH a vertex occupied by another player's building
	(it may end there).
]]

local Board = require(script.Parent.Board)
local RuleConfig = require(script.Parent.RuleConfig)

local LongestRoad = {}

function LongestRoad.compute(state, seat: number): number
	local topology = Board.getTopology(state.layout.radius)
	local edgeOwner, vertexOwner = state.edgeOwner, state.vertexOwner
	local used = {}
	local best = 0

	local function blocked(v: number): boolean
		local owner = vertexOwner[v]
		return owner ~= 0 and owner ~= seat
	end

	local function dfs(v: number, length: number)
		if length > best then
			best = length
		end
		if length > 0 and blocked(v) then
			return
		end
		for _, e in topology.vertices[v].edges do
			if edgeOwner[e] == seat and not used[e] then
				used[e] = true
				local ev = topology.edges[e].vertices
				dfs(ev[1] == v and ev[2] or ev[1], length + 1)
				used[e] = false
			end
		end
	end

	local started = {}
	for e, owner in edgeOwner do
		if owner == seat then
			for _, v in topology.edges[e].vertices do
				if not started[v] then
					started[v] = true
					dfs(v, 0)
				end
			end
		end
	end
	return best
end

-- Recompute every player's length and move the award if needed.
function LongestRoad.update(state)
	local holder = state.longestRoadHolder
	local maxLength = 0
	for seat, p in state.players do
		p.longestRoad = LongestRoad.compute(state, seat)
		if p.longestRoad > maxLength then
			maxLength = p.longestRoad
		end
	end
	local minimum = state.rules.longestRoadMin

	local newHolder = holder
	if holder ~= 0 and state.players[holder].longestRoad == maxLength and maxLength >= minimum then
		newHolder = holder -- holder keeps it on ties
	elseif maxLength < minimum then
		newHolder = 0
	else
		local leaders = {}
		for seat, p in state.players do
			if p.longestRoad == maxLength then
				table.insert(leaders, seat)
			end
		end
		-- A unique leader takes it; a tie after the holder was overtaken/broken leaves it unclaimed
		newHolder = #leaders == 1 and leaders[1] or 0
	end

	if newHolder ~= holder then
		if holder ~= 0 then
			state.players[holder].hasLongestRoad = false
		end
		if newHolder ~= 0 then
			state.players[newHolder].hasLongestRoad = true
		end
		state.longestRoadHolder = newHolder
		return true
	end
	return false
end

function LongestRoad.updateLargestArmy(state, seat: number): boolean
	local holder = state.largestArmyHolder
	local knights = state.players[seat].knightsPlayed
	if holder == seat or knights < RuleConfig.get(state.rules, seat, "largestArmyMin") then
		return false
	end
	if holder == 0 or knights > state.players[holder].knightsPlayed then
		if holder ~= 0 then
			state.players[holder].hasLargestArmy = false
		end
		state.players[seat].hasLargestArmy = true
		state.largestArmyHolder = seat
		return true
	end
	return false
end

return LongestRoad
