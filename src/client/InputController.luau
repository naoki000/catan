--[[
	InputController: turns taps on the board into selections.

	The current selection mode decides which markers are shown:
	  "settlement" -> legal vertices      "road"   -> legal edges
	  "city"       -> own settlements     "robber" -> legal tiles
	Legal spots come from the shared RuleEngine run on the local view, so the
	highlights always match what the server will accept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RuleEngine = require(ReplicatedStorage.Shared.RuleEngine)
local BoardRenderer = require(script.Parent.BoardRenderer)
local CameraController = require(script.Parent.CameraController)

local InputController = {}

local mode = nil
local view = nil
local selectCallback = nil

local MODE_KIND = { settlement = "vertex", city = "vertex", road = "edge", robber = "tile" }

local function legalIds(m: string)
	local seat = view and view.mySeat or 0
	if not view or seat == 0 then
		return {}
	end
	if m == "settlement" then
		return RuleEngine.legalSettlementVertices(view, seat)
	elseif m == "road" then
		return RuleEngine.legalRoadEdges(view, seat)
	elseif m == "city" then
		return RuleEngine.legalCityVertices(view, seat)
	elseif m == "robber" then
		return RuleEngine.legalRobberTiles(view, seat)
	end
	return {}
end

local function refresh()
	if mode and view then
		BoardRenderer.showMarkers(view, MODE_KIND[mode], legalIds(mode))
	else
		BoardRenderer.clearMarkers()
	end
end

local function raycastMarker(screenPos: Vector2): BasePart?
	local camera = Workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { BoardRenderer.getMarkersFolder() }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return hit and hit.Instance :: BasePart or nil
end

function InputController.init()
	CameraController.onTap(function(pos)
		if not mode then
			return
		end
		local marker = raycastMarker(pos)
		if marker and selectCallback then
			selectCallback(mode, marker:GetAttribute("Id"))
		end
	end)
	CameraController.onHover(function(pos)
		if mode then
			BoardRenderer.setHover(raycastMarker(pos))
		end
	end)
end

function InputController.setView(newView)
	view = newView
	refresh()
end

function InputController.setMode(newMode: string?)
	mode = newMode
	refresh()
end

function InputController.getMode(): string?
	return mode
end

-- Number of legal targets for a mode (used to enable/disable buttons)
function InputController.countLegal(m: string): number
	return #legalIds(m)
end

function InputController.onSelect(callback: (string, number) -> ())
	selectCallback = callback
end

return InputController
