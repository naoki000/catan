--[[
	Server configuration.

	After creating the experience on Roblox (see README):
	  * LOBBY_PLACE_ID = the start place (lobby)
	  * MATCH_PLACE_ID = the second place used for matches (reserved servers)
	While MATCH_PLACE_ID is 0, or when running in Studio, everything runs in
	"local" mode: rooms are hosted inside the current server, which is what you
	use for Studio "Server & Clients" testing.
]]

return {
	LOBBY_PLACE_ID = 0,
	MATCH_PLACE_ID = 0,

	-- Seconds a disconnected player's obligations wait before the server plays for them
	AUTO_PLAY_DELAY = 20,
	-- Request rate limit per player
	MAX_REQUESTS_PER_SECOND = 15,
	-- MemoryStore entries expire after this many seconds (refreshed on every update)
	ROOM_TTL_SECONDS = 6 * 60 * 60,
	-- Reserved match server waits this long for the room record before giving up
	ROOM_LOOKUP_TIMEOUT = 30,
}
