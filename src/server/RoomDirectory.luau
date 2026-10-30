--[[
	RoomDirectory: cross-server room registry in MemoryStoreService.

	Keys in one HashMap:
	  room:<CODE>      -> { code, reservedServerId, hostUserId, allowed = {userIds}, status, maxPlayers, createdAt }
	  srv:<serverId>   -> CODE      (lets the reserved match server find its room)
	  user:<userId>    -> CODE      (lets a player rejoin their current game)

	status: "open" (waiting room, joinable) | "started" | "finished" | "closed"

	All writes that depend on the current value use UpdateAsync so two lobby
	servers can never over-fill a room or reuse a code.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")

local Config = require(script.Parent.Config)

local RoomDirectory = {}

local map = nil
local function getMap()
	if not map then
		map = MemoryStoreService:GetHashMap("HexlandRooms_v1")
	end
	return map
end

local function withRetry(fn)
	local lastErr
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(0.4 * attempt)
	end
	warn("[Hexland] MemoryStore error: " .. tostring(lastErr))
	return false, lastErr
end

-- Create a new room record. Fails if the code already exists.
function RoomDirectory.create(record): boolean
	local created = false
	local ok = withRetry(function()
		created = false
		getMap():UpdateAsync("room:" .. record.code, function(old)
			if old ~= nil then
				return nil -- code taken, cancel
			end
			created = true
			return record
		end, Config.ROOM_TTL_SECONDS)
	end)
	return ok and created
end

function RoomDirectory.get(code: string)
	local ok, value = withRetry(function()
		return getMap():GetAsync("room:" .. code)
	end)
	return ok and value or nil
end

--[[
	Add a user to the allowed list of an open room.
	Returns record or nil, reason. Users already in the list always succeed
	(that is a rejoin), even after the game started.
]]
function RoomDirectory.addMember(code: string, userId: number)
	local reason = "部屋が見つかりません"
	local result = nil
	withRetry(function()
		result = getMap():UpdateAsync("room:" .. code, function(old)
			if old == nil then
				reason = "部屋が見つかりません"
				return nil
			end
			if table.find(old.allowed, userId) then
				return old
			end
			if old.status ~= "open" then
				reason = "このゲームはすでに開始しています"
				return nil
			end
			if #old.allowed >= old.maxPlayers then
				reason = "この部屋は満員です"
				return nil
			end
			table.insert(old.allowed, userId)
			return old
		end, Config.ROOM_TTL_SECONDS)
	end)
	if result then
		return result
	end
	return nil, reason
end

function RoomDirectory.removeMember(code: string, userId: number)
	withRetry(function()
		getMap():UpdateAsync("room:" .. code, function(old)
			if old == nil then
				return nil
			end
			local index = table.find(old.allowed, userId)
			if not index then
				return nil
			end
			table.remove(old.allowed, index)
			return old
		end, Config.ROOM_TTL_SECONDS)
	end)
end

function RoomDirectory.setStatus(code: string, status: string)
	withRetry(function()
		getMap():UpdateAsync("room:" .. code, function(old)
			if old == nil then
				return nil
			end
			old.status = status
			return old
		end, Config.ROOM_TTL_SECONDS)
	end)
end

function RoomDirectory.setServerRoom(serverId: string, code: string)
	withRetry(function()
		getMap():SetAsync("srv:" .. serverId, code, Config.ROOM_TTL_SECONDS)
	end)
end

function RoomDirectory.getServerRoom(serverId: string): string?
	local ok, value = withRetry(function()
		return getMap():GetAsync("srv:" .. serverId)
	end)
	return ok and value or nil
end

function RoomDirectory.setUserRoom(userId: number, code: string)
	withRetry(function()
		getMap():SetAsync("user:" .. userId, code, Config.ROOM_TTL_SECONDS)
	end)
end

function RoomDirectory.getUserRoom(userId: number): string?
	local ok, value = withRetry(function()
		return getMap():GetAsync("user:" .. userId)
	end)
	return ok and value or nil
end

function RoomDirectory.clearUserRoom(userId: number, code: string?)
	withRetry(function()
		getMap():UpdateAsync("user:" .. userId, function(old)
			if old == nil or (code and old ~= code) then
				return nil
			end
			return "" -- empty string = no current room
		end, 60)
	end)
end

return RoomDirectory
