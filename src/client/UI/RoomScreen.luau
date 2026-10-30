--[[
	RoomScreen: waiting room before the game starts.
	Shows the room code, members with colors and ready state, and the
	ready / start / leave buttons. The server re-validates everything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Store = require(script.Parent.Parent.Store)
local Kit = require(script.Parent.Kit)

local RoomScreen = {}

function RoomScreen.create(gui: ScreenGui)
	local root = Kit.new("Frame", {
		Name = "Room",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.Colors.background,
		Visible = false,
		Parent = gui,
	})
	local panel = Kit.frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.45, 0.85),
		Parent = root,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(300, 360), MaxSize = Vector2.new(520, 680), Parent = panel })
	Kit.padding(16).Parent = panel
	Kit.list(Enum.FillDirection.Vertical, 10).Parent = panel

	Kit.label("部屋コード", { LayoutOrder = 1, TextColor3 = Kit.Colors.muted, MaxTextSize = 18, Parent = panel })
	local codeLabel = Kit.label("------", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 56),
		Font = Enum.Font.GothamBlack,
		TextColor3 = Kit.Colors.accent,
		MaxTextSize = 52,
		Parent = panel,
	})
	Kit.label(
		"このコードを友達に伝えて「部屋に参加」から入ってもらいます",
		{ LayoutOrder = 3, TextColor3 = Kit.Colors.muted, MaxTextSize = 14, Parent = panel }
	)

	local list = Kit.new(
		"Frame",
		{ LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 4 * 50), BackgroundTransparency = 1, Parent = panel }
	)
	Kit.list(Enum.FillDirection.Vertical, 6).Parent = list

	local status = Kit.label("", { LayoutOrder = 5, TextColor3 = Kit.Colors.muted, MaxTextSize = 16, Parent = panel })

	local readyButton = Kit.button("準備完了", function()
		local room = Store.room
		if not room then
			return
		end
		local me
		for _, m in room.members do
			if m.userId == Players.LocalPlayer.UserId then
				me = m
			end
		end
		Store.request("setReady", { ready = not (me and me.ready) })
	end, { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Kit.Colors.good, Parent = panel })

	local startButton = Kit.button("ゲーム開始", function()
		Store.request("startGame")
	end, { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 48), Parent = panel })

	Kit.button("退出", function()
		Store.request("leaveRoom")
	end, {
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Kit.Colors.bad,
		TextColor3 = Kit.Colors.text,
		Parent = panel,
	})

	local function update()
		local room = Store.room
		root.Visible = room ~= nil and Store.game == nil
		if not room then
			return
		end
		codeLabel.Text = room.code
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local myUserId = Players.LocalPlayer.UserId
		local isHost = room.hostUserId == myUserId
		local allReady = true
		local me = nil
		for i, m in room.members do
			if m.userId == myUserId then
				me = m
			end
			if not m.isHost and not m.ready then
				allReady = false
			end
			local row = Kit.frame({
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = Kit.Colors.panelLight,
				LayoutOrder = i,
				Parent = list,
			})
			local color = Protocol.PlayerColors[m.colorIndex]
			local swatch = Kit.new("Frame", {
				Size = UDim2.new(0, 28, 0, 28),
				Position = UDim2.new(0, 8, 0.5, -14),
				BackgroundColor3 = Color3.fromHex(color.hex),
				Parent = row,
			})
			Kit.corner(14).Parent = swatch
			local nameText = m.name
				.. (m.isHost and "  👑" or "")
				.. (m.userId == myUserId and "（あなた）" or "")
			Kit.label(nameText, {
				Position = UDim2.new(0, 46, 0, 0),
				Size = UDim2.new(0.62, -46, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 18,
				Parent = row,
			})
			local state = not m.connected and "切断中"
				or m.isHost and "ホスト"
				or m.ready and "✔ 準備完了"
				or "準備中…"
			Kit.label(state, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				Size = UDim2.new(0.38, 0, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = (m.ready or m.isHost) and Kit.Colors.good or Kit.Colors.muted,
				MaxTextSize = 16,
				Parent = row,
			})
		end
		local count = #room.members
		local enough = count >= room.minPlayers and count <= room.maxPlayers
		readyButton.Visible = not isHost
		readyButton.Text = (me and me.ready) and "準備を取り消す" or "準備完了"
		startButton.Visible = isHost
		Kit.setEnabled(startButton, enough and allReady)
		if not enough then
			status.Text = string.format(
				"%d / %d 人（%d〜%d人で開始できます）",
				count,
				room.maxPlayers,
				room.minPlayers,
				room.maxPlayers
			)
		elseif not allReady then
			status.Text = "全員の準備完了を待っています"
		else
			status.Text = isHost and "準備ができました。ゲームを開始してください"
				or "ホストの開始を待っています"
		end
	end

	Store.subscribe(function(field)
		if field == "room" or field == "game" then
			update()
		end
	end)
	update()
	return root
end

return RoomScreen
