--[[
	RoomService: creates / joins / leaves rooms and owns the MatchRoom objects.

	Modes (decided once at startup):
	  "local" - Studio, or MATCH_PLACE_ID not configured. Rooms live in this
	            server. Used for Studio "Server & Clients" testing.
	  "lobby" - Start place on Roblox. Rooms are registered in MemoryStore and
	            players are teleported to a reserved server of the match place
	            (TeleportOptions.ReservedServerId, a GUID generated here).
	  "match" - Reserved server of the match place. Hosts exactly one room and
	            only admits UserIds on that room's allowed list.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local MatchRoom = require(ReplicatedStorage.Shared.MatchRoom)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Rng = require(ReplicatedStorage.Shared.Rng)
local RuleConfig = require(ReplicatedStorage.Shared.RuleConfig)
local Config = require(script.Parent.Config)
local Network = require(script.Parent.Network)
local RoomDirectory = require(script.Parent.RoomDirectory)

local RoomService = {}

local mode = "local"
local rooms = {} -- [code] = MatchRoom
local userRoom = {} -- [userId] = code (local mode)
local emptySince = {} -- [code] = os.clock()
local matchRoom = nil -- match mode: the single room
local matchCode = nil
local random = Random.new()
local rng = Rng.fromRandom(random)

local function makeHooks()
	return {
		sendRoom = function(userId, snapshot)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				Network.sendRoom(player, snapshot)
			end
		end,
		sendGame = function(userId, view)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				Network.sendGame(player, view)
			end
		end,
		notice = function(userId, kind, text)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				Network.notice(player, kind, text)
			end
		end,
		now = os.clock,
		rng = rng,
		autoPlayDelay = Config.AUTO_PLAY_DELAY,
	}
end

local function generateCode(): string
	local chars = {}
	for i = 1, Protocol.CODE_LENGTH do
		local index = random:NextInteger(1, #Protocol.CODE_ALPHABET)
		chars[i] = string.sub(Protocol.CODE_ALPHABET, index, index)
	end
	return table.concat(chars)
end

local function displayName(player: Player): string
	return player.DisplayName ~= "" and player.DisplayName or player.Name
end

local function teleportToMatch(player: Player, reservedServerId: string): boolean
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = reservedServerId
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(Config.MATCH_PLACE_ID, { player }, options)
		end)
		if ok then
			return true
		end
		warn("[Hexland] teleport failed: " .. tostring(err))
		task.wait(attempt)
	end
	Network.notice(
		player,
		"error",
		"対戦サーバーへの移動に失敗しました。もう一度お試しください。"
	)
	return false
end

local function teleportToLobby(player: Player)
	if Config.LOBBY_PLACE_ID ~= 0 then
		local ok = pcall(function()
			TeleportService:TeleportAsync(Config.LOBBY_PLACE_ID, { player })
		end)
		if ok then
			return
		end
	end
	player:Kick("ロビーに戻るには、ゲームに入り直してください。")
end

-- Local mode ------------------------------------------------------------------------------

local function localLeave(player: Player)
	local code = userRoom[player.UserId]
	local room = code and rooms[code]
	if room then
		room:leave(player.UserId)
		if not room:isMember(player.UserId) then
			userRoom[player.UserId] = nil
		end
	end
	Network.sendRoom(player, nil)
	Network.sendGame(player, nil)
end

local localHandlers = {}

function localHandlers.createRoom(player: Player)
	localLeave(player)
	local code
	repeat
		code = generateCode()
	until rooms[code] == nil
	local room = MatchRoom.new(code, makeHooks(), RuleConfig.create())
	rooms[code] = room
	room:join(player.UserId, displayName(player))
	userRoom[player.UserId] = code
end

function localHandlers.joinRoom(player: Player, payload)
	local code = Protocol.normalizeCode(payload.code)
	local room = code and rooms[code]
	if not room then
		Network.notice(
			player,
			"error",
			"部屋が見つかりません。部屋コードを確認してください。"
		)
		return
	end
	if userRoom[player.UserId] ~= code then
		localLeave(player)
	end
	local ok, err = room:join(player.UserId, displayName(player))
	if not ok then
		Network.notice(player, "error", err)
		return
	end
	userRoom[player.UserId] = code
end

function localHandlers.rejoin(player: Player)
	local code = userRoom[player.UserId]
	local room = code and rooms[code]
	if room and room:isMember(player.UserId) then
		room:join(player.UserId, displayName(player))
	else
		Network.notice(player, "error", "戻れるゲームがありません")
	end
end

function localHandlers.leaveRoom(player: Player)
	localLeave(player)
	local code = userRoom[player.UserId]
	if code then
		Network.notice(player, "rejoinAvailable", code)
	end
end

-- Lobby mode -----------------------------------------------------------------------------

local lobbyHandlers = {}
local busy = {}

local function guarded(fn)
	return function(player: Player, payload)
		if busy[player] then
			return
		end
		busy[player] = true
		local ok, err = pcall(fn, player, payload)
		busy[player] = nil
		if not ok then
			error(err)
		end
	end
end

lobbyHandlers.createRoom = guarded(function(player: Player)
	local record
	for _ = 1, 10 do
		record = {
			code = generateCode(),
			reservedServerId = HttpService:GenerateGUID(false),
			hostUserId = player.UserId,
			allowed = { player.UserId },
			status = "open",
			maxPlayers = RuleConfig.Default.maxPlayers,
			createdAt = os.time(),
		}
		if RoomDirectory.create(record) then
			break
		end
		record = nil
	end
	if not record then
		Network.notice(
			player,
			"error",
			"部屋を作成できませんでした。しばらくしてからお試しください。"
		)
		return
	end
	RoomDirectory.setServerRoom(record.reservedServerId, record.code)
	RoomDirectory.setUserRoom(player.UserId, record.code)
	Network.notice(
		player,
		"info",
		"部屋 " .. record.code .. " を作成しました。対戦サーバーへ移動します…"
	)
	teleportToMatch(player, record.reservedServerId)
end)

lobbyHandlers.joinRoom = guarded(function(player: Player, payload)
	local code = Protocol.normalizeCode(payload.code)
	if not code then
		Network.notice(player, "error", "部屋コードは英数字6文字です")
		return
	end
	local record, reason = RoomDirectory.addMember(code, player.UserId)
	if not record then
		Network.notice(player, "error", reason)
		return
	end
	RoomDirectory.setUserRoom(player.UserId, code)
	Network.notice(player, "info", "部屋 " .. code .. " に参加します…")
	teleportToMatch(player, record.reservedServerId)
end)

lobbyHandlers.rejoin = guarded(function(player: Player)
	local code = RoomDirectory.getUserRoom(player.UserId)
	local record = code and code ~= "" and RoomDirectory.get(code)
	if not record or record.status == "closed" or not table.find(record.allowed, player.UserId) then
		Network.notice(player, "error", "戻れるゲームがありません")
		return
	end
	teleportToMatch(player, record.reservedServerId)
end)

lobbyHandlers.leaveRoom = function(player: Player)
	Network.sendRoom(player, nil)
end

local function announceRejoin(player: Player)
	task.spawn(function()
		local code = RoomDirectory.getUserRoom(player.UserId)
		if not code or code == "" then
			return
		end
		local record = RoomDirectory.get(code)
		if
			record
			and record.status ~= "closed"
			and record.status ~= "finished"
			and table.find(record.allowed, player.UserId)
		then
			Network.notice(player, "rejoinAvailable", code)
		end
	end)
end

-- Match mode -------------------------------------------------------------------------------

local matchHandlers = {}

local function loadMatchRoom()
	local serverId = game.PrivateServerId
	if serverId == "" or game.PrivateServerOwnerId ~= 0 then
		return false
	end
	local deadline = os.clock() + Config.ROOM_LOOKUP_TIMEOUT
	while os.clock() < deadline do
		matchCode = RoomDirectory.getServerRoom(serverId)
		if matchCode then
			break
		end
		task.wait(1)
	end
	if not matchCode then
		return false
	end
	local hooks = makeHooks()
	hooks.onStatusChanged = function(room)
		local status = room.status == "playing" and "started" or room.status
		task.spawn(RoomDirectory.setStatus, room.code, status)
	end
	matchRoom = MatchRoom.new(matchCode, hooks, RuleConfig.create())
	rooms[matchCode] = matchRoom
	return true
end

local function admitToMatch(player: Player)
	while matchRoom == nil and matchCode ~= false do
		task.wait(0.5)
	end
	if not matchRoom then
		player:Kick("対戦部屋が見つかりませんでした。ロビーから参加し直してください。")
		return
	end
	local record = RoomDirectory.get(matchCode)
	if not matchRoom:isMember(player.UserId) and (not record or not table.find(record.allowed, player.UserId)) then
		player:Kick(
			"この部屋への参加は許可されていません。部屋コードを入力して参加してください。"
		)
		return
	end
	local ok, err = matchRoom:join(player.UserId, displayName(player))
	if not ok then
		Network.notice(player, "error", err)
		task.wait(3)
		teleportToLobby(player)
	end
end

function matchHandlers.leaveRoom(player: Player)
	if not matchRoom then
		return
	end
	local wasLobby = matchRoom.status == "lobby"
	matchRoom:leave(player.UserId)
	if wasLobby then
		task.spawn(RoomDirectory.removeMember, matchCode, player.UserId)
		task.spawn(RoomDirectory.clearUserRoom, player.UserId, matchCode)
	end
	teleportToLobby(player)
end

function matchHandlers.rejoin(player: Player)
	if matchRoom then
		matchRoom:sync(player.UserId)
	end
end

function matchHandlers.createRoom(player: Player)
	Network.notice(player, "error", "先に今の部屋から退出してください")
end
matchHandlers.joinRoom = matchHandlers.createRoom

-- Shared handlers --------------------------------------------------------------------------

local function roomOf(player: Player)
	if mode == "match" then
		return matchRoom
	end
	local code = userRoom[player.UserId]
	return code and rooms[code] or nil
end

local function onSetReady(player: Player, payload)
	local room = roomOf(player)
	if room then
		local ok, err = room:setReady(player.UserId, payload.ready)
		if not ok then
			Network.notice(player, "error", err)
		end
	end
end

local function onStartGame(player: Player)
	local room = roomOf(player)
	if room then
		local ok, err = room:start(player.UserId)
		if not ok then
			Network.notice(player, "error", err)
		end
	end
end

local function onAction(player: Player, payload)
	local room = roomOf(player)
	if not room then
		Network.notice(player, "error", "部屋に参加していません")
		return
	end
	local ok, err = room:perform(player.UserId, payload)
	if not ok then
		Network.notice(player, "error", err or "その操作はできません")
		room:sync(player.UserId) -- resync so the client never shows a rejected state
	end
end

local function onSync(player: Player)
	local room = roomOf(player)
	if room then
		room:sync(player.UserId)
	end
end

-- Startup ------------------------------------------------------------------------------------

function RoomService.getMode(): string
	return mode
end

function RoomService.start()
	if RunService:IsStudio() or Config.MATCH_PLACE_ID == 0 then
		mode = "local"
	elseif game.PlaceId == Config.MATCH_PLACE_ID then
		mode = "match"
	else
		mode = "lobby"
	end
	ReplicatedStorage:SetAttribute(Protocol.PLACE_ROLE_ATTRIBUTE, mode)
	print("[Hexland] server mode: " .. mode)

	local handlers = mode == "local" and localHandlers or mode == "lobby" and lobbyHandlers or matchHandlers
	for kind, fn in handlers do
		Network.on(kind, fn)
	end
	Network.on("setReady", onSetReady)
	Network.on("startGame", onStartGame)
	Network.on("action", onAction)
	Network.on("sync", onSync)

	if mode == "match" then
		task.spawn(function()
			if not loadMatchRoom() then
				matchCode = false
			end
		end)
		Players.PlayerAdded:Connect(function(player)
			admitToMatch(player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(admitToMatch, player)
		end
		game:BindToClose(function()
			if matchCode then
				RoomDirectory.setStatus(matchCode, "closed")
			end
		end)
	elseif mode == "lobby" then
		Players.PlayerAdded:Connect(announceRejoin)
		for _, player in Players:GetPlayers() do
			announceRejoin(player)
		end
	else
		local function announceLocal(player: Player)
			local code = userRoom[player.UserId]
			local room = code and rooms[code]
			if room and room:isMember(player.UserId) then
				Network.notice(player, "rejoinAvailable", code)
			end
		end
		Players.PlayerAdded:Connect(announceLocal)
	end

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn("[Hexland] TeleportInitFailed", player.Name, result, message)
		Network.notice(player, "error", "移動に失敗しました: " .. tostring(message))
	end)

	Players.PlayerRemoving:Connect(function(player)
		local room = roomOf(player)
		if room then
			room:disconnect(player.UserId)
			if mode == "match" and room.status == "lobby" then
				task.spawn(RoomDirectory.removeMember, matchCode, player.UserId)
				task.spawn(RoomDirectory.clearUserRoom, player.UserId, matchCode)
			end
		end
		busy[player] = nil
	end)

	-- Auto-play for disconnected players and cleanup of abandoned local rooms
	task.spawn(function()
		while true do
			task.wait(1)
			for code, room in rooms do
				local ok, err = pcall(room.tick, room)
				if not ok then
					warn("[Hexland] tick error: " .. tostring(err))
				end
				if mode == "local" then
					if room:isEmpty() then
						emptySince[code] = emptySince[code] or os.clock()
						if os.clock() - emptySince[code] > 600 or room:memberCount() == 0 then
							rooms[code] = nil
							emptySince[code] = nil
						end
					else
						emptySince[code] = nil
					end
				end
			end
		end
	end)
end

return RoomService
