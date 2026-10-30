--[[
	BoardRenderer: builds the 3D board locally on each client from the
	replicated game view. Purely visual; it never decides legality.

	Layout: tiles are pointy-top hexagons built from three rotated blocks.
	The integer lattice from Shared.Board maps to studs with
	    X = x * sqrt(3)/2 * HEX_SIZE,  Z = y * HEX_SIZE / 2
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Board = require(ReplicatedStorage.Shared.Board)
local RuleConfig = require(ReplicatedStorage.Shared.RuleConfig)

local BoardRenderer = {}

BoardRenderer.HEX_SIZE = 4
local HEX = BoardRenderer.HEX_SIZE
local KX = math.sqrt(3) / 2 * HEX
local KY = HEX / 2
local TILE_HEIGHT = 1
local TOP = TILE_HEIGHT

local TERRAIN_COLORS = {
	forest = Color3.fromRGB(47, 122, 58),
	hills = Color3.fromRGB(190, 96, 58),
	pasture = Color3.fromRGB(150, 200, 90),
	fields = Color3.fromRGB(235, 196, 72),
	mountains = Color3.fromRGB(128, 128, 140),
	desert = Color3.fromRGB(222, 202, 150),
}
local TERRAIN_ICONS = {
	forest = "🌲",
	hills = "🧱",
	pasture = "🐑",
	fields = "🌾",
	mountains = "⛰️",
	desert = "🏜️",
}
local SEA_COLOR = Color3.fromRGB(46, 112, 170)
local MARKER_COLOR = Color3.fromRGB(255, 236, 90)
local HOVER_COLOR = Color3.fromRGB(255, 255, 255)

local root, tilesFolder, piecesFolder, markersFolder
local renderedLayoutKey = nil
local robberModel = nil
local tileCenters = {}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function billboard(parent: Instance, text: string, size: number, color: Color3, offset: Vector3?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(size, 0, size, 0)
	gui.LightInfluence = 0
	gui.StudsOffsetWorldSpace = offset or Vector3.new(0, 0.6, 0)
	gui.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	gui.Parent = parent
	return gui
end

function BoardRenderer.latticeToWorld(x: number, y: number, height: number?): Vector3
	return Vector3.new(x * KX, height or TOP, y * KY)
end

function BoardRenderer.vertexPosition(topology, vertexId: number): Vector3
	local v = topology.vertices[vertexId]
	return BoardRenderer.latticeToWorld(v.x, v.y)
end

function BoardRenderer.tileCenter(topology, tileId: number): Vector3
	local tile = topology.tiles[tileId]
	local x, y = Board.tileLattice(topology, tile)
	return BoardRenderer.latticeToWorld(x, y)
end

function BoardRenderer.init()
	root = Workspace:FindFirstChild("HexlandBoard") or Instance.new("Folder")
	root.Name = "HexlandBoard"
	root.Parent = Workspace
	tilesFolder = Instance.new("Folder")
	tilesFolder.Name = "Tiles"
	tilesFolder.Parent = root
	piecesFolder = Instance.new("Folder")
	piecesFolder.Name = "Pieces"
	piecesFolder.Parent = root
	markersFolder = Instance.new("Folder")
	markersFolder.Name = "Markers"
	markersFolder.Parent = root
end

function BoardRenderer.getMarkersFolder(): Folder
	return markersFolder
end

-- Approximate radius of the island in studs (used by the camera)
function BoardRenderer.boardRadius(): number
	return 3 * HEX * 1.8 + HEX * 2
end

local function buildHexTile(center: Vector3, color: Color3, parent: Instance, scale: number, height: number, material)
	local model = Instance.new("Model")
	for i = 0, 2 do
		part({
			Name = "Hex" .. i,
			Size = Vector3.new(math.sqrt(3) * HEX * scale, height, HEX * scale),
			CFrame = CFrame.new(center - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, math.rad(60 * i), 0),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	model.Parent = parent
	return model
end

local function rebuildLayout(view)
	tilesFolder:ClearAllChildren()
	tileCenters = {}
	local topology = Board.getTopology(view.layout.radius)
	local layout = view.layout

	-- Sea and a sandy coast ring
	local seaRadius = (view.layout.radius + 1.6) * math.sqrt(3) * HEX
	part({
		Name = "Sea",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, seaRadius * 2, seaRadius * 2),
		CFrame = CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = SEA_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = tilesFolder,
	})
	buildHexTile(
		Vector3.new(0, 0.05, 0),
		Color3.fromRGB(230, 214, 160),
		tilesFolder,
		(view.layout.radius * 2 + 1.25),
		0.3
	):PivotTo(CFrame.new(0, -0.1, 0) * CFrame.Angles(0, math.rad(30), 0))

	for id = 1, #topology.tiles do
		local center = BoardRenderer.tileCenter(topology, id)
		tileCenters[id] = center
		local terrain = layout.terrain[id]
		local model = buildHexTile(center, TERRAIN_COLORS[terrain], tilesFolder, 0.95, TILE_HEIGHT)
		model.Name = "Tile" .. id
		model:SetAttribute("TileId", id)

		local number = layout.numbers[id]
		if number ~= 0 then
			local chip = part({
				Name = "Number",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.15, 2.0, 2.0),
				CFrame = CFrame.new(center + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(250, 240, 215),
				Parent = model,
			})
			local red = number == 6 or number == 8
			local pips = string.rep("•", 6 - math.abs(7 - number))
			billboard(
				chip,
				tostring(number) .. "\n" .. pips,
				1.7,
				red and Color3.fromRGB(200, 30, 30) or Color3.fromRGB(30, 30, 30)
			)
		end
		billboard(model, TERRAIN_ICONS[terrain] or "", 1.0, Color3.new(1, 1, 1), Vector3.new(0, 0.5, -HEX * 0.55)).Adornee =
			model:FindFirstChild("Hex0")
	end

	-- Ports
	for _, port in layout.ports do
		local a = BoardRenderer.vertexPosition(topology, port.vertices[1])
		local b = BoardRenderer.vertexPosition(topology, port.vertices[2])
		local mid = (a + b) / 2
		local tileId = topology.edges[port.edge].tiles[1]
		local outward = (mid - tileCenters[tileId]) * Vector3.new(1, 0, 1)
		outward = outward.Magnitude > 0 and outward.Unit or Vector3.new(0, 0, 1)
		local dockPos = mid + outward * 1.8 - Vector3.new(0, 0.7, 0)
		local dock = part({
			Name = "Port",
			Size = Vector3.new(1.6, 0.4, 1.6),
			CFrame = CFrame.new(dockPos),
			Color = Color3.fromRGB(120, 84, 50),
			Material = Enum.Material.Wood,
			Parent = tilesFolder,
		})
		for _, v in { a, b } do
			local from = Vector3.new(v.X, dockPos.Y, v.Z)
			local length = (dockPos - from).Magnitude
			part({
				Name = "Plank",
				Size = Vector3.new(0.3, 0.2, length),
				CFrame = CFrame.lookAt((from + dockPos) / 2, dockPos),
				Color = Color3.fromRGB(150, 110, 70),
				Material = Enum.Material.Wood,
				Parent = tilesFolder,
			})
		end
		local text = port.kind == "generic" and "3:1" or ("2:1\n" .. RuleConfig.ResourceNames[port.kind])
		billboard(dock, text, 2.2, Color3.new(1, 1, 1), Vector3.new(0, 0.8, 0))
	end
end

local function layoutKey(view): string
	return table.concat(view.layout.terrain, ",") .. "|" .. table.concat(view.layout.numbers, ",")
end

local function colorOf(view, seat: number): Color3
	local p = view.players[seat]
	return p and Color3.fromHex(p.color) or Color3.new(1, 0, 1)
end

local function buildSettlement(position: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Settlement"
	part({
		Size = Vector3.new(1.3, 0.9, 1.3),
		CFrame = CFrame.new(position + Vector3.new(0, 0.45, 0)),
		Color = color,
		Parent = model,
	})
	local roof = Instance.new("WedgePart")
	roof.Anchored, roof.CanCollide, roof.CanQuery, roof.CastShadow = true, false, false, false
	roof.Size = Vector3.new(1.4, 0.6, 0.7)
	roof.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
	roof.CFrame = CFrame.new(position + Vector3.new(0, 1.2, 0.35))
	roof.Parent = model
	local roof2 = roof:Clone()
	roof2.CFrame = CFrame.new(position + Vector3.new(0, 1.2, -0.35)) * CFrame.Angles(0, math.pi, 0)
	roof2.Parent = model
	return model
end

local function buildCity(position: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "City"
	part({
		Size = Vector3.new(2.1, 1.0, 1.4),
		CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)),
		Color = color,
		Parent = model,
	})
	part({
		Size = Vector3.new(0.9, 1.9, 1.4),
		CFrame = CFrame.new(position + Vector3.new(-0.55, 0.95, 0)),
		Color = color:Lerp(Color3.new(0, 0, 0), 0.15),
		Parent = model,
	})
	return model
end

local function buildRoad(a: Vector3, b: Vector3, color: Color3)
	local dir = (b - a)
	local length = dir.Magnitude * 0.72
	return part({
		Name = "Road",
		Size = Vector3.new(0.55, 0.45, length),
		CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.22, 0), b + Vector3.new(0, 0.22, 0)),
		Color = color,
	})
end

local function buildRobber(): Model
	local model = Instance.new("Model")
	model.Name = "Robber"
	part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.8, 1.1, 1.1),
		CFrame = CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(40, 40, 46),
		Parent = model,
	})
	part({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = CFrame.new(0, 2.1, 0),
		Color = Color3.fromRGB(40, 40, 46),
		Parent = model,
	})
	model.PrimaryPart = model:FindFirstChild("Body") :: BasePart
	return model
end

function BoardRenderer.render(view)
	if not view then
		BoardRenderer.clear()
		return
	end
	local key = layoutKey(view)
	if key ~= renderedLayoutKey then
		rebuildLayout(view)
		renderedLayoutKey = key
	end
	local topology = Board.getTopology(view.layout.radius)

	piecesFolder:ClearAllChildren()
	for e, owner in view.edgeOwner do
		if owner ~= 0 then
			local ev = topology.edges[e].vertices
			local road = buildRoad(
				BoardRenderer.vertexPosition(topology, ev[1]),
				BoardRenderer.vertexPosition(topology, ev[2]),
				colorOf(view, owner)
			)
			road.Parent = piecesFolder
		end
	end
	for v, owner in view.vertexOwner do
		if owner ~= 0 then
			local pos = BoardRenderer.vertexPosition(topology, v)
			local model = view.vertexBuilding[v] == 2 and buildCity(pos, colorOf(view, owner))
				or buildSettlement(pos, colorOf(view, owner))
			model.Parent = piecesFolder
		end
	end

	if not robberModel or not robberModel.Parent then
		robberModel = buildRobber()
		robberModel.Parent = root
	end
	local center = tileCenters[view.layout.robberTile] or Vector3.zero
	robberModel:PivotTo(CFrame.new(center + Vector3.new(0, 0, HEX * 0.5)))
end

function BoardRenderer.clear()
	if tilesFolder then
		tilesFolder:ClearAllChildren()
		piecesFolder:ClearAllChildren()
		markersFolder:ClearAllChildren()
	end
	if robberModel then
		robberModel:Destroy()
		robberModel = nil
	end
	renderedLayoutKey = nil
end

-- Selection markers --------------------------------------------------------------------

function BoardRenderer.clearMarkers()
	markersFolder:ClearAllChildren()
end

-- kind: "vertex" | "edge" | "tile"
function BoardRenderer.showMarkers(view, kind: string, ids)
	markersFolder:ClearAllChildren()
	if not view then
		return
	end
	local topology = Board.getTopology(view.layout.radius)
	for _, id in ids do
		local marker
		if kind == "vertex" then
			marker = part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.5, 1.5, 1.5),
				CFrame = CFrame.new(BoardRenderer.vertexPosition(topology, id) + Vector3.new(0, 0.6, 0)),
			})
		elseif kind == "edge" then
			local ev = topology.edges[id].vertices
			local a = BoardRenderer.vertexPosition(topology, ev[1])
			local b = BoardRenderer.vertexPosition(topology, ev[2])
			marker = part({
				Size = Vector3.new(0.9, 0.4, (b - a).Magnitude * 0.6),
				CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.3, 0), b + Vector3.new(0, 0.3, 0)),
			})
		elseif kind == "tile" then
			marker = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, HEX * 1.3, HEX * 1.3),
				CFrame = CFrame.new(BoardRenderer.tileCenter(topology, id) + Vector3.new(0, 0.25, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
			})
		end
		if marker then
			marker.Name = kind .. id
			marker.Material = Enum.Material.Neon
			marker.Color = MARKER_COLOR
			marker.Transparency = kind == "tile" and 0.55 or 0.15
			marker.CanQuery = true
			marker:SetAttribute("Kind", kind)
			marker:SetAttribute("Id", id)
			marker.Parent = markersFolder
		end
	end
end

local hovered = nil
function BoardRenderer.setHover(marker: BasePart?)
	if hovered == marker then
		return
	end
	if hovered and hovered.Parent then
		hovered.Color = MARKER_COLOR
		hovered.Size = hovered.Size / 1.25
	end
	hovered = marker
	if marker then
		marker.Color = HOVER_COLOR
		marker.Size = marker.Size * 1.25
	end
end

return BoardRenderer
