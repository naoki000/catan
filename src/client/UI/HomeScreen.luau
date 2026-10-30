--[[
	HomeScreen: title, create room, join by code, return to a previous game,
	and the how-to-play dialog.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Store = require(script.Parent.Parent.Store)
local HowToPlay = require(script.Parent.HowToPlay)
local Kit = require(script.Parent.Kit)

local HomeScreen = {}

function HomeScreen.create(gui: ScreenGui)
	local root = Kit.new("Frame", {
		Name = "Home",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.Colors.background,
		Parent = gui,
	})
	Kit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(28, 70, 110), Color3.fromRGB(18, 26, 38)),
		Rotation = 90,
		Parent = root,
	})

	local column = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.8),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(280, 300), MaxSize = Vector2.new(460, 640), Parent = column })
	Kit.list(Enum.FillDirection.Vertical, 10).Parent = column

	Kit.label("HEXLAND", {
		Size = UDim2.new(1, 0, 0, 64),
		Font = Enum.Font.GothamBlack,
		TextColor3 = Kit.Colors.accent,
		MaxTextSize = 60,
		LayoutOrder = 1,
		Parent = column,
	})
	Kit.label("ヘックスランド開拓記 ― 島を開拓して10点を目指そう", {
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Kit.Colors.muted,
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = column,
	})

	local menu = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 330),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Visible = false,
		Parent = column,
	})
	Kit.list(Enum.FillDirection.Vertical, 10).Parent = menu

	local startButton
	startButton = Kit.button("ゲーム開始", function()
		startButton.Visible = false
		menu.Visible = true
	end, { Size = UDim2.new(0.8, 0, 0, 54), LayoutOrder = 4, MaxTextSize = 26, Parent = column })

	Kit.button("部屋を作成", function()
		Store.request("createRoom")
	end, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 46), Parent = menu })

	local joinRow =
		Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = 2, Parent = menu })
	Kit.list(Enum.FillDirection.Horizontal, 8).Parent = joinRow
	local codeBox = Kit.new("TextBox", {
		Size = UDim2.new(0.6, -4, 1, 0),
		PlaceholderText = "部屋コード（6文字）",
		Text = "",
		ClearTextOnFocus = false,
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		BackgroundColor3 = Color3.fromRGB(245, 245, 240),
		TextColor3 = Color3.fromRGB(20, 20, 20),
		Parent = joinRow,
	})
	Kit.corner(8).Parent = codeBox
	Kit.padding(6).Parent = codeBox
	Kit.new("UITextSizeConstraint", { MaxTextSize = 24, Parent = codeBox })
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned = string.upper(string.sub(string.gsub(codeBox.Text, "[^%w]", ""), 1, Protocol.CODE_LENGTH))
		if cleaned ~= codeBox.Text then
			codeBox.Text = cleaned
		end
	end)
	Kit.button("部屋に参加", function()
		local code = Protocol.normalizeCode(codeBox.Text)
		if not code then
			HomeScreen.toast("部屋コードは英数字6文字です")
			return
		end
		Store.request("joinRoom", { code = code })
	end, { Size = UDim2.new(0.4, -4, 1, 0), BackgroundColor3 = Kit.Colors.good, Parent = joinRow })

	local rejoinButton = Kit.button("前のゲームに戻る", function()
		Store.request("rejoin")
	end, {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Color3.fromRGB(120, 170, 230),
		Visible = false,
		Parent = menu,
	})

	Kit.label(
		"3〜4人で遊べます。部屋を作成したら、部屋コードを友達に伝えてください。",
		{
			LayoutOrder = 5,
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Kit.Colors.muted,
			MaxTextSize = 15,
			Parent = menu,
		}
	)

	Kit.button("遊び方", function()
		HowToPlay.open(gui)
	end, {
		LayoutOrder = 5,
		Size = UDim2.new(0.8, 0, 0, 40),
		BackgroundColor3 = Kit.Colors.panelLight,
		TextColor3 = Kit.Colors.text,
		Parent = column,
	})

	local function update()
		rejoinButton.Visible = Store.rejoinCode ~= nil
		if Store.rejoinCode then
			rejoinButton.Text = "前のゲームに戻る（" .. Store.rejoinCode .. "）"
		end
	end
	Store.subscribe(function(field)
		if field == "rejoinCode" then
			update()
		end
	end)
	update()

	return root
end

-- Replaced by the app with the shared toast function
function HomeScreen.toast(_text: string) end

return HomeScreen
