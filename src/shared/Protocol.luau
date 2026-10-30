--[[
	Protocol: names and constants shared by server and client.

	Client -> server: Remotes.Request:FireServer(kind, payload)
	  kind = "createRoom" | "joinRoom" | "rejoin" | "leaveRoom" | "setReady"
	       | "startGame" | "action" | "sync"
	Server -> client:
	  Remotes.RoomState:FireClient(player, roomSnapshot | nil)
	  Remotes.GameState:FireClient(player, StateView | nil)
	  Remotes.Notice:FireClient(player, { kind = "error" | "info", text = string })
]]

local Protocol = {}

Protocol.REMOTES_FOLDER = "HexlandRemotes"
Protocol.Remotes = { "Request", "RoomState", "GameState", "Notice" }

Protocol.RequestKinds = {
	createRoom = true,
	joinRoom = true,
	rejoin = true,
	leaveRoom = true,
	setReady = true,
	startGame = true,
	action = true,
	sync = true,
}

-- Room codes avoid easily confused characters (0/O, 1/I/L)
Protocol.CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
Protocol.CODE_LENGTH = 6

Protocol.PlayerColors = {
	{ name = "赤", hex = "#d93f3f" },
	{ name = "青", hex = "#3f6fd9" },
	{ name = "白", hex = "#f2efe6" },
	{ name = "橙", hex = "#ee8a2a" },
}

-- Attribute set on ReplicatedStorage: "local" (Studio / single place), "lobby", "match"
Protocol.PLACE_ROLE_ATTRIBUTE = "HexlandPlaceRole"

function Protocol.normalizeCode(code: any): string?
	if type(code) ~= "string" then
		return nil
	end
	code = string.upper((string.gsub(code, "%s", "")))
	if #code ~= Protocol.CODE_LENGTH then
		return nil
	end
	for i = 1, #code do
		if not string.find(Protocol.CODE_ALPHABET, string.sub(code, i, i), 1, true) then
			return nil
		end
	end
	return code
end

return Protocol
