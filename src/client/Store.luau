--[[
	Store: client-side copy of what the server sent, plus a tiny pub/sub.
	The server is the only source of truth; the client never edits game data.

	fields:
	  role       "local" | "lobby" | "match"
	  room       room snapshot or nil
	  game       StateView or nil
	  rejoinCode code of a game the player can go back to, or nil
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Store = {
	role = "local",
	room = nil,
	game = nil,
	rejoinCode = nil,
}

local listeners = {}
local noticeListeners = {}
local remotes = nil

function Store.subscribe(fn: (string) -> ())
	table.insert(listeners, fn)
end

function Store.onNotice(fn: (string, string) -> ())
	table.insert(noticeListeners, fn)
end

local function emit(field: string)
	for _, fn in listeners do
		local ok, err = pcall(fn, field)
		if not ok then
			warn("[Hexland] UI update failed: " .. tostring(err))
		end
	end
end

function Store.set(field: string, value)
	Store[field] = value
	emit(field)
end

function Store.request(kind: string, payload)
	if remotes then
		remotes.Request:FireServer(kind, payload or {})
	end
end

function Store.action(action)
	Store.request("action", action)
end

function Store.init()
	remotes = ReplicatedStorage:WaitForChild(Protocol.REMOTES_FOLDER)
	for _, name in Protocol.Remotes do
		remotes:WaitForChild(name)
	end
	Store.role = ReplicatedStorage:GetAttribute(Protocol.PLACE_ROLE_ATTRIBUTE) or "local"
	ReplicatedStorage:GetAttributeChangedSignal(Protocol.PLACE_ROLE_ATTRIBUTE):Connect(function()
		Store.set("role", ReplicatedStorage:GetAttribute(Protocol.PLACE_ROLE_ATTRIBUTE))
	end)

	remotes.RoomState.OnClientEvent:Connect(function(snapshot)
		Store.set("room", snapshot)
	end)
	remotes.GameState.OnClientEvent:Connect(function(view)
		-- RemoteEvents to one client arrive in order, so the latest message is the latest state
		Store.set("game", view)
	end)
	remotes.Notice.OnClientEvent:Connect(function(notice)
		if type(notice) ~= "table" then
			return
		end
		if notice.kind == "rejoinAvailable" then
			Store.set("rejoinCode", notice.text)
			return
		end
		for _, fn in noticeListeners do
			fn(notice.kind, notice.text)
		end
	end)
end

return Store
