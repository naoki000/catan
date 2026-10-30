--[[
	MatchRoom: one match room (waiting room + game), independent of Roblox APIs.

	The server creates one MatchRoom per room code and injects `hooks` that do
	the actual networking. Because it is pure Luau it is unit-tested in Lune.

	Identity is always the Roblox UserId supplied by the server (never by the
	client). A UserId that already has a seat can always come back (reconnect);
	new UserIds can only join while the room is still in the lobby.

	hooks = {
		sendRoom = function(userId, snapshot) end,
		sendGame = function(userId, view) end,
		notice = function(userId, kind, text) end,
		now = function(): number end,
		rng = Rng,
		onStatusChanged = function(room) end, -- optional
		autoPlayDelay = 20,                   -- optional (seconds)
	}
]]

local AutoPlayer = require(script.Parent.AutoPlayer)
local GameActions = require(script.Parent.GameActions)
local GameState = require(script.Parent.GameState)
local Protocol = require(script.Parent.Protocol)
local RuleConfig = require(script.Parent.RuleConfig)
local StateView = require(script.Parent.StateView)

local MatchRoom = {}
MatchRoom.__index = MatchRoom

function MatchRoom.new(code: string, hooks, rules)
	local self = setmetatable({}, MatchRoom)
	self.code = code
	self.hooks = hooks
	self.rules = rules or RuleConfig.create()
	self.status = "lobby" -- "lobby" | "playing" | "finished"
	self.members = {} -- [tostring(userId)] = member
	self.joinOrder = {} -- userIds
	self.hostUserId = 0
	self.game = nil
	self.seatByUser = {} -- [tostring(userId)] = seat
	self.disconnectedAt = {} -- [tostring(userId)] = time
	return self
end

local function key(userId: number): string
	return tostring(userId)
end

function MatchRoom:memberCount(): number
	return #self.joinOrder
end

function MatchRoom:connectedCount(): number
	local n = 0
	for _, m in self.members do
		if m.connected then
			n += 1
		end
	end
	return n
end

function MatchRoom:isMember(userId: number): boolean
	return self.members[key(userId)] ~= nil
end

function MatchRoom:snapshot()
	local members = {}
	for _, userId in self.joinOrder do
		local m = self.members[key(userId)]
		table.insert(members, {
			userId = m.userId,
			name = m.name,
			colorIndex = m.colorIndex,
			ready = m.ready,
			connected = m.connected,
			isHost = m.userId == self.hostUserId,
		})
	end
	return {
		code = self.code,
		status = self.status,
		hostUserId = self.hostUserId,
		members = members,
		minPlayers = self.rules.minPlayers,
		maxPlayers = self.rules.maxPlayers,
	}
end

function MatchRoom:broadcast()
	local snapshot = self:snapshot()
	for _, userId in self.joinOrder do
		local m = self.members[key(userId)]
		if m.connected then
			self:sendTo(userId, snapshot)
		end
	end
end

function MatchRoom:sendTo(userId: number, snapshot)
	self.hooks.sendRoom(userId, snapshot or self:snapshot())
	if self.game then
		local seat = self.seatByUser[key(userId)]
		self.hooks.sendGame(userId, StateView.forSeat(self.game, seat or 0))
	else
		self.hooks.sendGame(userId, nil)
	end
end

function MatchRoom:sync(userId: number)
	-- Disconnected members must rejoin (join) first so broadcasts include them again
	local m = self.members[key(userId)]
	if m and m.connected then
		self:sendTo(userId)
	end
end

function MatchRoom:setStatus(status: string)
	if self.status ~= status then
		self.status = status
		if self.hooks.onStatusChanged then
			self.hooks.onStatusChanged(self)
		end
	end
end

local function nextFreeColor(self): number
	local used = {}
	for _, m in self.members do
		used[m.colorIndex] = true
	end
	for i = 1, #Protocol.PlayerColors do
		if not used[i] then
			return i
		end
	end
	return 1
end

function MatchRoom:pickHost()
	local current = self.members[key(self.hostUserId)]
	if current and current.connected then
		return
	end
	for _, userId in self.joinOrder do
		local m = self.members[key(userId)]
		if m.connected then
			self.hostUserId = userId
			return
		end
	end
	if not current then
		self.hostUserId = self.joinOrder[1] or 0
	end
end

-- Join or rejoin. Returns ok, error.
function MatchRoom:join(userId: number, name: string): (boolean, string?)
	local existing = self.members[key(userId)]
	if existing then
		existing.connected = true
		existing.name = name
		self.disconnectedAt[key(userId)] = nil
		if self.game then
			local seat = self.seatByUser[key(userId)]
			if seat then
				self.game.players[seat].connected = true
			end
		end
		self:pickHost()
		self:broadcast()
		return true
	end
	if self.status ~= "lobby" then
		return false, "このゲームはすでに開始しています"
	end
	if self:memberCount() >= self.rules.maxPlayers then
		return false, "この部屋は満員です"
	end
	self.members[key(userId)] = {
		userId = userId,
		name = name,
		colorIndex = nextFreeColor(self),
		ready = false,
		connected = true,
	}
	table.insert(self.joinOrder, userId)
	if self.hostUserId == 0 then
		self.hostUserId = userId
	end
	self:pickHost()
	self:broadcast()
	return true
end

-- The player's connection ended (left the server / closed the game).
function MatchRoom:disconnect(userId: number)
	local m = self.members[key(userId)]
	if not m then
		return
	end
	if self.status == "lobby" then
		self:remove(userId)
		return
	end
	m.connected = false
	self.disconnectedAt[key(userId)] = self.hooks.now()
	local seat = self.seatByUser[key(userId)]
	if self.game and seat then
		self.game.players[seat].connected = false
	end
	self:pickHost()
	self:broadcast()
end

-- Voluntary leave. In the lobby the seat is freed; during a game it behaves
-- like a disconnect so the player can still come back.
function MatchRoom:leave(userId: number)
	self:disconnect(userId)
end

function MatchRoom:remove(userId: number)
	if not self.members[key(userId)] then
		return
	end
	self.members[key(userId)] = nil
	local index = table.find(self.joinOrder, userId)
	if index then
		table.remove(self.joinOrder, index)
	end
	if self.hostUserId == userId then
		self.hostUserId = 0
	end
	self:pickHost()
	self:broadcast()
end

function MatchRoom:setReady(userId: number, ready: any): (boolean, string?)
	local m = self.members[key(userId)]
	if not m or self.status ~= "lobby" then
		return false, "今は変更できません"
	end
	m.ready = ready == true
	self:broadcast()
	return true
end

function MatchRoom:canStart(): (boolean, string?)
	if self.status ~= "lobby" then
		return false, "ゲームはすでに開始しています"
	end
	local count = self:memberCount()
	if count < self.rules.minPlayers then
		return false, string.format("%d 人以上必要です", self.rules.minPlayers)
	end
	if count > self.rules.maxPlayers then
		return false, string.format("最大 %d 人までです", self.rules.maxPlayers)
	end
	for _, m in self.members do
		if not m.connected then
			return false, m.name .. " が接続していません"
		end
		if m.userId ~= self.hostUserId and not m.ready then
			return false, "全員の準備完了を待っています"
		end
	end
	return true
end

function MatchRoom:start(userId: number): (boolean, string?)
	if userId ~= self.hostUserId then
		return false, "ゲームを開始できるのはホストだけです"
	end
	local ok, err = self:canStart()
	if not ok then
		return false, err
	end
	local seats = {}
	for i, uid in self.joinOrder do
		local m = self.members[key(uid)]
		seats[i] = { userId = uid, name = m.name, color = Protocol.PlayerColors[m.colorIndex].hex }
		self.seatByUser[key(uid)] = i
	end
	self.game = GameState.new(seats, self.rules, self.hooks.rng)
	self:setStatus("playing")
	self:broadcast()
	return true
end

function MatchRoom:seatOf(userId: number): number?
	return self.seatByUser[key(userId)]
end

-- Apply a game action requested by a player.
function MatchRoom:perform(userId: number, action): (boolean, string?)
	if not self.game then
		return false, "ゲームが開始されていません"
	end
	local seat = self.seatByUser[key(userId)]
	if not seat then
		return false, "このゲームの参加者ではありません"
	end
	local ok, err = GameActions.perform(self.game, seat, action, { rng = self.hooks.rng, authority = "player" })
	if not ok then
		return false, err
	end
	if self.game.phase == "finished" then
		self:setStatus("finished")
	end
	self:broadcast()
	return true
end

-- Called periodically: plays required actions for players who stay disconnected.
function MatchRoom:tick(): number
	if not self.game or self.game.phase == "finished" then
		return 0
	end
	local delay = self.hooks.autoPlayDelay or 20
	local now = self.hooks.now()
	local performed = 0
	for _ = 1, 20 do
		local acted = false
		for userKey, since in self.disconnectedAt do
			local seat = self.seatByUser[userKey]
			if seat and now - since >= delay then
				local action = AutoPlayer.requiredAction(self.game, seat)
				if action then
					local ok =
						GameActions.perform(self.game, seat, action, { rng = self.hooks.rng, authority = "auto" })
					if ok then
						performed += 1
						acted = true
						if action.type == "endTurn" or action.type == "discard" then
							GameState.addLog(
								self.game,
								"（"
									.. self.game.players[seat].name
									.. " は切断中のため自動処理されました）",
								"info"
							)
						end
					end
				end
			end
		end
		if not acted or self.game.phase == "finished" then
			break
		end
	end
	if performed > 0 then
		if self.game.phase == "finished" then
			self:setStatus("finished")
		end
		self:broadcast()
	end
	return performed
end

function MatchRoom:isEmpty(): boolean
	return self:connectedCount() == 0
end

return MatchRoom
