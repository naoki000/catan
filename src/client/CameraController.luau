--[[
	CameraController: top-down board camera.

	  Mouse: drag (left or right button) to pan, wheel to zoom
	  Touch: one-finger drag to pan, pinch to zoom
	A short press without movement is reported as a "tap" so the
	InputController can select vertices / edges / tiles.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local MIN_HEIGHT, MAX_HEIGHT = 22, 120
local DRAG_THRESHOLD = 8

local focus = Vector3.zero
local height = 70
local enabled = false
local limit = 30
local tapCallbacks = {}
local hoverCallbacks = {}

local function camera(): Camera
	return Workspace.CurrentCamera
end

local function apply()
	if not enabled then
		return
	end
	local cam = camera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 45
	cam.CFrame = CFrame.lookAt(focus + Vector3.new(0, height, 0), focus, Vector3.new(0, 0, -1))
end

local function worldPerPixel(): number
	local cam = camera()
	return 2 * height * math.tan(math.rad(cam.FieldOfView / 2)) / math.max(cam.ViewportSize.Y, 1)
end

function CameraController.pan(dx: number, dy: number)
	local k = worldPerPixel()
	focus -= Vector3.new(dx * k, 0, dy * k)
	focus = Vector3.new(math.clamp(focus.X, -limit, limit), 0, math.clamp(focus.Z, -limit, limit))
	apply()
end

function CameraController.zoom(factor: number)
	height = math.clamp(height * factor, MIN_HEIGHT, MAX_HEIGHT)
	apply()
end

-- Frame the whole board, leaving room for the side panel and bottom bar.
function CameraController.fit(boardRadius: number)
	limit = boardRadius
	local cam = camera()
	local viewport = cam.ViewportSize
	local usableY = math.max(viewport.Y * 0.68, 1)
	local usableX = math.max(viewport.X * 0.70, 1)
	local aspect = usableX / usableY
	local radius = boardRadius
	local needForY = radius / math.tan(math.rad(cam.FieldOfView / 2))
	local needForX = needForY / math.max(aspect, 0.01)
	height = math.clamp(math.max(needForY, needForX) * (viewport.Y / usableY), MIN_HEIGHT, MAX_HEIGHT)
	-- shift so the board sits in the area not covered by the UI (right panel, bottom bar)
	local k = worldPerPixel()
	focus = Vector3.new(viewport.X * 0.13 * k, 0, viewport.Y * 0.12 * k)
	apply()
end

function CameraController.onTap(callback: (Vector2, boolean) -> ())
	table.insert(tapCallbacks, callback)
end

function CameraController.onHover(callback: (Vector2) -> ())
	table.insert(hoverCallbacks, callback)
end

function CameraController.setEnabled(on: boolean)
	enabled = on
	if on then
		apply()
	end
end

function CameraController.init()
	local pointerDown = nil -- { start: Vector2, last: Vector2, dragging: boolean, isTouch: boolean, input }
	local activeTouches = 0
	local pinchStartHeight = height

	UserInputService.InputBegan:Connect(function(input, processed)
		if not enabled or processed then
			return
		end
		local t = input.UserInputType
		if
			t == Enum.UserInputType.MouseButton1
			or t == Enum.UserInputType.MouseButton2
			or t == Enum.UserInputType.Touch
		then
			if t == Enum.UserInputType.Touch then
				activeTouches += 1
				if activeTouches > 1 then
					pointerDown = nil
					return
				end
			end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			pointerDown = {
				start = pos,
				last = pos,
				dragging = false,
				isTouch = t == Enum.UserInputType.Touch,
				button = t,
				input = input,
			}
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if not enabled then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel and not processed then
			CameraController.zoom(input.Position.Z > 0 and 0.88 or 1.14)
			return
		end
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if pointerDown and (t == Enum.UserInputType.MouseMovement or pointerDown.input == input) then
				if not pointerDown.dragging and (pos - pointerDown.start).Magnitude > DRAG_THRESHOLD then
					pointerDown.dragging = true
				end
				if pointerDown.dragging then
					local delta = pos - pointerDown.last
					CameraController.pan(delta.X, delta.Y)
				end
				pointerDown.last = pos
			elseif t == Enum.UserInputType.MouseMovement then
				for _, cb in hoverCallbacks do
					cb(pos)
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			activeTouches = math.max(0, activeTouches - 1)
		end
		if
			pointerDown and (pointerDown.input == input or (t == pointerDown.button and t ~= Enum.UserInputType.Touch))
		then
			local down = pointerDown
			pointerDown = nil
			if not down.dragging and down.button ~= Enum.UserInputType.MouseButton2 then
				for _, cb in tapCallbacks do
					cb(down.start, down.isTouch)
				end
			end
		end
	end)

	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if not enabled or processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartHeight = height
			pointerDown = nil
		end
		height = math.clamp(pinchStartHeight / math.max(scale, 0.05), MIN_HEIGHT, MAX_HEIGHT)
		apply()
	end)

	camera():GetPropertyChangedSignal("ViewportSize"):Connect(apply)
end

return CameraController
