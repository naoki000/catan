--[[
	Server entry point (Script "Server" in ServerScriptService).
	All game rules live in ReplicatedStorage.Shared; this script only wires up
	networking and room management.
]]

local Network = require(script.Network)
local RoomService = require(script.RoomService)

Network.init()
RoomService.start()
