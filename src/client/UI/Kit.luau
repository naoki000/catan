--[[
	Kit: tiny helpers for building ScreenGui layouts in code.
	All sizes use Scale where possible so the UI works on PC and phones.
]]

local Kit = {}

Kit.Colors = {
	background = Color3.fromRGB(24, 32, 44),
	panel = Color3.fromRGB(34, 45, 60),
	panelLight = Color3.fromRGB(52, 66, 86),
	accent = Color3.fromRGB(240, 186, 70),
	accentDark = Color3.fromRGB(190, 140, 40),
	good = Color3.fromRGB(80, 170, 100),
	bad = Color3.fromRGB(200, 80, 70),
	text = Color3.fromRGB(240, 240, 235),
	muted = Color3.fromRGB(160, 170, 185),
	disabled = Color3.fromRGB(80, 88, 100),
}

Kit.ResourceIcons = { lumber = "🌲", brick = "🧱", wool = "🐑", grain = "🌾", ore = "⛰️" }
Kit.ResourceColors = {
	lumber = Color3.fromRGB(47, 122, 58),
	brick = Color3.fromRGB(190, 96, 58),
	wool = Color3.fromRGB(130, 185, 80),
	grain = Color3.fromRGB(225, 185, 60),
	ore = Color3.fromRGB(120, 120, 135),
}

function Kit.new(className: string, props, children)
	local inst = Instance.new(className)
	for k, v in props or {} do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.corner(radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function Kit.padding(px: number)
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function Kit.list(direction, padding: number?, align)
	return Kit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
end

function Kit.frame(props, children)
	local defaults = { BackgroundColor3 = Kit.Colors.panel, BorderSizePixel = 0 }
	for k, v in props or {} do
		defaults[k] = v
	end
	local f = Kit.new("Frame", defaults, children)
	Kit.corner(10).Parent = f
	return f
end

function Kit.label(text: string, props)
	local defaults = {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Kit.Colors.text,
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		Size = UDim2.new(1, 0, 0, 24),
		TextWrapped = true,
	}
	for k, v in props or {} do
		if k ~= "MaxTextSize" then
			defaults[k] = v
		end
	end
	local label = Kit.new("TextLabel", defaults)
	Kit.new(
		"UITextSizeConstraint",
		{ MaxTextSize = (props and props.MaxTextSize) or 22, MinTextSize = 9, Parent = label }
	)
	return label
end

function Kit.button(text: string, onClick: () -> (), props)
	local defaults = {
		Text = text,
		BackgroundColor3 = Kit.Colors.accent,
		TextColor3 = Color3.fromRGB(30, 30, 30),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 40),
		BorderSizePixel = 0,
	}
	for k, v in props or {} do
		if k ~= "MaxTextSize" then
			defaults[k] = v
		end
	end
	local button = Kit.new("TextButton", defaults)
	Kit.corner(8).Parent = button
	Kit.padding(4).Parent = button
	Kit.new(
		"UITextSizeConstraint",
		{ MaxTextSize = (props and props.MaxTextSize) or 20, MinTextSize = 8, Parent = button }
	)
	button.Activated:Connect(function()
		if button.Active then
			onClick()
		end
	end)
	return button
end

function Kit.setEnabled(button: TextButton, on: boolean, color: Color3?)
	button.Active = on
	button.AutoButtonColor = on
	button.BackgroundColor3 = on and (color or Kit.Colors.accent) or Kit.Colors.disabled
	button.TextColor3 = on and Color3.fromRGB(30, 30, 30) or Color3.fromRGB(170, 170, 170)
end

-- Centered modal dialog. Returns (overlay, contentFrame).
function Kit.modal(parent: Instance, title: string, widthScale: number?, heightScale: number?)
	local overlay = Kit.new("Frame", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 50,
		Active = true,
		Parent = parent,
	})
	local box = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(widthScale or 0.42, heightScale or 0.6),
		ZIndex = 51,
		Parent = overlay,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(300, 220), MaxSize = Vector2.new(640, 640), Parent = box })
	Kit.padding(12).Parent = box
	local content =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 52, Parent = box })
	Kit.list(Enum.FillDirection.Vertical, 8).Parent = content
	local heading = Kit.label(
		title,
		{ Size = UDim2.new(1, 0, 0, 30), Font = Enum.Font.GothamBold, MaxTextSize = 26, LayoutOrder = 0 }
	)
	heading.Parent = content
	for _, d in overlay:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 52)
		end
	end
	return overlay, content
end

-- Make every descendant render above the modal overlay (call after adding children)
function Kit.raise(root: Instance, z: number)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
end

return Kit
