--[[
	Network: creates the RemoteEvents and routes client requests.

	Every request is rate limited and wrapped in pcall. Handlers receive the
	Player object provided by Roblox (never a client-supplied identity).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Config = require(script.Parent.Config)

local Network = {}

local remotes: { [string]: RemoteEvent } = {}
local handlers = {}
local buckets = {}

function Network.init()
	local folder = ReplicatedStorage:FindFirstChild(Protocol.REMOTES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Protocol.REMOTES_FOLDER
		folder.Parent = ReplicatedStorage
	end
	for _, name in Protocol.Remotes do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
	end

	remotes.Request.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
		if not Network.allow(player) then
			return
		end
		if type(kind) ~= "string" or not Protocol.RequestKinds[kind] then
			return
		end
		local handler = handlers[kind]
		if not handler then
			return
		end
		if payload ~= nil and type(payload) ~= "table" then
			payload = nil
		end
		local ok, err = pcall(handler, player, payload or {})
		if not ok then
			warn(string.format("[Hexland] %s from %s failed: %s", kind, player.Name, tostring(err)))
			Network.notice(player, "error", "サーバーエラーが発生しました")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

-- Token bucket rate limiter
function Network.allow(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	local capacity = Config.MAX_REQUESTS_PER_SECOND
	if not bucket then
		bucket = { tokens = capacity, last = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.last) * capacity)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Network.on(kind: string, handler: (Player, any) -> ())
	handlers[kind] = handler
end

function Network.sendRoom(player: Player, snapshot)
	remotes.RoomState:FireClient(player, snapshot)
end

function Network.sendGame(player: Player, view)
	remotes.GameState:FireClient(player, view)
end

function Network.notice(player: Player, kind: string, text: string)
	remotes.Notice:FireClient(player, { kind = kind, text = text })
end

return Network
