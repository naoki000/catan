--[[
	Client entry point (LocalScript "Client" in StarterPlayerScripts).
	Builds the UI in code, renders the board and forwards input to the server.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local BoardRenderer = require(script.BoardRenderer)
local CameraController = require(script.CameraController)
local InputController = require(script.InputController)
local Store = require(script.Store)
local GameScreen = require(script.UI.GameScreen)
local HomeScreen = require(script.UI.HomeScreen)
local Kit = require(script.UI.Kit)
local RoomScreen = require(script.UI.RoomScreen)

local player = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

Store.init()

local gui = Instance.new("ScreenGui")
gui.Name = "HexlandUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Toasts --------------------------------------------------------------------------------
local toastHolder = Kit.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.4, 0, 0, 8),
	Size = UDim2.new(0.5, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	ZIndex = 90,
	Parent = gui,
})
Kit.list(Enum.FillDirection.Vertical, 4).Parent = toastHolder

local function toast(text: string, isError: boolean?)
	local label = Kit.label(text, {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = isError and Kit.Colors.bad or Kit.Colors.panel,
		MaxTextSize = 17,
		ZIndex = 91,
		Parent = toastHolder,
	})
	Kit.corner(8).Parent = label
	task.delay(isError and 4 or 3, function()
		label:Destroy()
	end)
end
HomeScreen.toast = function(text)
	toast(text, true)
end

Store.onNotice(function(kind, text)
	toast(text, kind == "error")
end)

-- Screens ---------------------------------------------------------------------------------
local home = HomeScreen.create(gui)
RoomScreen.create(gui)
GameScreen.create(gui, function(text)
	toast(text)
end)

-- Board & camera -----------------------------------------------------------------------------
BoardRenderer.init()
CameraController.init()
InputController.init()

local fitted = false
local function updateScreens()
	local inGame = Store.game ~= nil
	home.Visible = Store.room == nil and not inGame
	if inGame then
		BoardRenderer.render(Store.game)
		CameraController.setEnabled(true)
		if not fitted then
			fitted = true
			CameraController.fit(BoardRenderer.boardRadius())
		end
	else
		BoardRenderer.clear()
		CameraController.setEnabled(false)
		fitted = false
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 60, 40), Vector3.zero)
	end
end

Store.subscribe(function(field)
	if field == "game" or field == "room" then
		updateScreens()
	end
end)
updateScreens()

-- Ask for the current state (covers reconnects inside the same server)
Store.request("sync")
