--[[
	GameScreen: in-game HUD.
	  right  : turn info, players (points, cards, awards), game log
	  bottom : my resources, dice, build / trade / dev card / end turn buttons
	  modals : discard, steal, trade (bank & player), incoming trade offer,
	           development cards, game over

	Every button only sends a request; the server validates it and the next
	state update redraws the HUD. Button enabling uses the shared RuleEngine.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)
local RuleConfig = require(ReplicatedStorage.Shared.RuleConfig)
local RuleEngine = require(ReplicatedStorage.Shared.RuleEngine)
local InputController = require(script.Parent.Parent.InputController)
local Store = require(script.Parent.Parent.Store)
local HowToPlay = require(script.Parent.HowToPlay)
local Kit = require(script.Parent.Kit)

local GameScreen = {
	refresh = function() end,
	openTrade = function() end,
	openDevCards = function() end,
}

local RESOURCES = RuleConfig.Resources
local R = RuleConfig.ResourceNames
local ICON = Kit.ResourceIcons
local DICE_FACES = { "⚀", "⚁", "⚂", "⚃", "⚄", "⚅" }

local PHASE_TEXT = {
	setupSettlement = "初期配置：開拓地",
	setupRoad = "初期配置：街道",
	roll = "サイコロ",
	discard = "資源を捨てる",
	moveRobber = "盗賊の移動",
	steal = "奪う相手を選ぶ",
	main = "建設・取引",
}

local function me(view)
	return view and view.players[view.mySeat]
end

local function isMyTurn(view): boolean
	return view ~= nil and view.mySeat ~= 0 and view.currentSeat == view.mySeat and view.phase ~= "finished"
end

local function formatMap(map): string
	local parts = {}
	for _, r in RESOURCES do
		if (map[r] or 0) > 0 then
			table.insert(parts, ICON[r] .. R[r] .. "×" .. map[r])
		end
	end
	return table.concat(parts, "  ")
end

-- Resource stepper row: [icon name] [-] n [+]
local function stepperRow(parent: Instance, resource: string, order: number, getMax: () -> number, onChange: () -> ())
	local value = 0
	local row = Kit.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent }
	)
	Kit.label(
		ICON[resource] .. " " .. R[resource],
		{ Size = UDim2.new(0.45, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 18, Parent = row }
	)
	local countLabel = Kit.label("0", {
		Position = UDim2.new(0.62, 0, 0, 0),
		Size = UDim2.new(0.14, 0, 1, 0),
		Font = Enum.Font.GothamBold,
		Parent = row,
	})
	local function set(v)
		value = math.clamp(v, 0, getMax())
		countLabel.Text = tostring(value)
		onChange()
	end
	Kit.button("−", function()
		set(value - 1)
	end, {
		Position = UDim2.new(0.48, 0, 0, 2),
		Size = UDim2.new(0.13, 0, 1, -4),
		BackgroundColor3 = Kit.Colors.panelLight,
		TextColor3 = Kit.Colors.text,
		Parent = row,
	})
	Kit.button("+", function()
		set(value + 1)
	end, {
		Position = UDim2.new(0.77, 0, 0, 2),
		Size = UDim2.new(0.13, 0, 1, -4),
		BackgroundColor3 = Kit.Colors.panelLight,
		TextColor3 = Kit.Colors.text,
		Parent = row,
	})
	return function()
		return value
	end, function()
		set(0)
	end
end

function GameScreen.create(gui: ScreenGui, toast: (string) -> ())
	local root = Kit.new(
		"Frame",
		{ Name = "Game", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui }
	)

	-- Right panel -------------------------------------------------------------------------
	local side = Kit.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0.25, 0, 1, -16),
		BackgroundTransparency = 0.08,
		Parent = root,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(200, 200), MaxSize = Vector2.new(340, 2000), Parent = side })
	Kit.padding(8).Parent = side
	local sideList = Kit.list(Enum.FillDirection.Vertical, 6)
	sideList.VerticalAlignment = Enum.VerticalAlignment.Top
	sideList.Parent = side

	local turnLabel = Kit.label(
		"",
		{ LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 26), Font = Enum.Font.GothamBold, MaxTextSize = 20, Parent = side }
	)
	local phaseLabel = Kit.label("", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Kit.Colors.accent,
		MaxTextSize = 16,
		Parent = side,
	})
	local playerList = Kit.new(
		"Frame",
		{ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 4 * 58), BackgroundTransparency = 1, Parent = side }
	)
	local playerListLayout = Kit.list(Enum.FillDirection.Vertical, 4)
	playerListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	playerListLayout.Parent = playerList

	Kit.label("ログ", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Kit.Colors.muted,
		MaxTextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = side,
	})
	local logFrame = Kit.new("ScrollingFrame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 1, -(26 + 20 + 4 * 58 + 18 + 44 + 6 * 6)),
		BackgroundColor3 = Color3.fromRGB(20, 26, 36),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		Parent = side,
	})
	Kit.corner(6).Parent = logFrame
	local logLayout = Kit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left)
	logLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	logLayout.Parent = logFrame
	Kit.padding(4).Parent = logFrame

	local sideButtons =
		Kit.new("Frame", { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Parent = side })
	Kit.list(Enum.FillDirection.Horizontal, 6).Parent = sideButtons
	Kit.button("遊び方", function()
		HowToPlay.open(gui)
	end, {
		Size = UDim2.new(0.5, -3, 1, 0),
		BackgroundColor3 = Kit.Colors.panelLight,
		TextColor3 = Kit.Colors.text,
		Parent = sideButtons,
	})
	Kit.button("退出", function()
		Store.request("leaveRoom")
	end, {
		Size = UDim2.new(0.5, -3, 1, 0),
		BackgroundColor3 = Kit.Colors.bad,
		TextColor3 = Kit.Colors.text,
		Parent = sideButtons,
	})

	-- Bottom bar --------------------------------------------------------------------------
	local bottom = Kit.frame({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8),
		Size = UDim2.new(0.75, -24, 0.24, 0),
		BackgroundTransparency = 0.08,
		Parent = root,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(320, 120), MaxSize = Vector2.new(2000, 210), Parent = bottom })
	Kit.padding(8).Parent = bottom

	local hint = Kit.label("", {
		Size = UDim2.new(1, 0, 0.2, 0),
		TextColor3 = Kit.Colors.accent,
		Font = Enum.Font.GothamBold,
		MaxTextSize = 18,
		Parent = bottom,
	})
	local tradeBanner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.22, 0, 0.2, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = bottom,
	})
	Kit.button("提案を取り消す", function()
		Store.action({ type = "cancelTrade" })
	end, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.Colors.bad,
		TextColor3 = Kit.Colors.text,
		Parent = tradeBanner,
	})

	local resourceRow = Kit.new("Frame", {
		Position = UDim2.new(0, 0, 0.24, 0),
		Size = UDim2.new(0.42, 0, 0.76, 0),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	Kit.list(Enum.FillDirection.Horizontal, 4).Parent = resourceRow
	local resourceCounts = {}
	for i, r in RESOURCES do
		local card = Kit.frame({
			Size = UDim2.new(0.2, -4, 1, 0),
			BackgroundColor3 = Kit.ResourceColors[r],
			LayoutOrder = i,
			Parent = resourceRow,
		})
		Kit.label(ICON[r], { Size = UDim2.new(1, 0, 0.42, 0), MaxTextSize = 30, Parent = card })
		resourceCounts[r] = Kit.label("0", {
			Position = UDim2.new(0, 0, 0.42, 0),
			Size = UDim2.new(1, 0, 0.36, 0),
			Font = Enum.Font.GothamBlack,
			MaxTextSize = 28,
			TextStrokeTransparency = 0.4,
			Parent = card,
		})
		Kit.label(R[r], {
			Position = UDim2.new(0, 0, 0.78, 0),
			Size = UDim2.new(1, 0, 0.22, 0),
			MaxTextSize = 13,
			TextStrokeTransparency = 0.6,
			Parent = card,
		})
	end

	local diceLabel = Kit.label("", {
		Position = UDim2.new(0.43, 0, 0.24, 0),
		Size = UDim2.new(0.12, 0, 0.76, 0),
		Font = Enum.Font.GothamBold,
		MaxTextSize = 34,
		Parent = bottom,
	})

	local actions = Kit.new("Frame", {
		Position = UDim2.new(0.56, 0, 0.24, 0),
		Size = UDim2.new(0.44, 0, 0.76, 0),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.25, -4, 0.5, -4),
		CellPadding = UDim2.new(0, 4, 0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = actions,
	})

	local modeButtons = {}
	local function toggleMode(mode: string)
		InputController.setMode(InputController.getMode() ~= mode and mode or nil)
		GameScreen.refresh()
	end

	local buttons = {}
	buttons.roll = Kit.button("🎲 サイコロ", function()
		Store.action({ type = "rollDice" })
	end, { LayoutOrder = 1, Parent = actions })
	buttons.road = Kit.button("街道", function()
		toggleMode("road")
	end, { LayoutOrder = 2, Parent = actions })
	buttons.settlement = Kit.button("開拓地", function()
		toggleMode("settlement")
	end, { LayoutOrder = 3, Parent = actions })
	buttons.city = Kit.button("都市", function()
		toggleMode("city")
	end, { LayoutOrder = 4, Parent = actions })
	buttons.buyDev = Kit.button("発展カード購入", function()
		Store.action({ type = "buyDevCard" })
	end, { LayoutOrder = 5, Parent = actions })
	buttons.dev = Kit.button("発展カード", function()
		GameScreen.openDevCards()
	end, { LayoutOrder = 6, Parent = actions })
	buttons.trade = Kit.button("取引", function()
		GameScreen.openTrade()
	end, { LayoutOrder = 7, Parent = actions })
	buttons.endTurn = Kit.button("ターン終了", function()
		InputController.setMode(nil)
		Store.action({ type = "endTurn" })
	end, { LayoutOrder = 8, Parent = actions })
	modeButtons.road, modeButtons.settlement, modeButtons.city = buttons.road, buttons.settlement, buttons.city

	-- Modals --------------------------------------------------------------------------------
	local modals = {} -- [name] = overlay
	local modalState = { incomingId = nil, tradeRefresh = nil }

	local function closeModal(name: string)
		if modals[name] then
			modals[name]:Destroy()
			modals[name] = nil
		end
	end

	-- Discard
	local function openDiscard(view)
		local overlay, content = Kit.modal(gui, "資源を捨てる", 0.4, 0.62)
		modals.discard = overlay
		local need = me(view).mustDiscard
		Kit.label(
			string.format("7が出ました。%d 枚選んで捨ててください。", need),
			{ LayoutOrder = 1, MaxTextSize = 16, Parent = content }
		)
		local getters = {}
		local confirm
		local function total()
			local n = 0
			for _, g in getters do
				n += g()
			end
			return n
		end
		local function changed()
			if confirm then
				Kit.setEnabled(confirm, total() == need)
				confirm.Text = string.format("捨てる（%d / %d）", total(), need)
			end
		end
		for i, r in RESOURCES do
			getters[r] = stepperRow(content, r, 1 + i, function()
				return me(Store.game).resources[r]
			end, changed)
		end
		confirm = Kit.button("捨てる", function()
			local cards = {}
			for r, g in getters do
				cards[r] = g()
			end
			Store.action({ type = "discard", resources = cards })
		end, { LayoutOrder = 10, Parent = content })
		changed()
	end

	-- Steal
	local function openSteal(view)
		local overlay, content = Kit.modal(gui, "資源を奪う相手を選んでください", 0.36, 0.45)
		modals.steal = overlay
		for i, seat in view.stealCandidates do
			local p = view.players[seat]
			Kit.button(string.format("%s（%d 枚）", p.name, p.resourceCount), function()
				Store.action({ type = "steal", target = seat })
			end, { LayoutOrder = i, BackgroundColor3 = Color3.fromHex(p.color), Parent = content })
		end
	end

	-- Incoming trade offer
	local function openIncoming(view)
		local trade = view.trade
		local from = view.players[trade.from]
		local overlay, content = Kit.modal(gui, from.name .. " からの取引提案", 0.4, 0.45)
		modals.incoming = overlay
		modalState.incomingId = trade.id
		Kit.label(
			"あなたがもらう： " .. formatMap(trade.give),
			{ LayoutOrder = 1, MaxTextSize = 18, Parent = content }
		)
		Kit.label(
			"あなたが渡す： " .. formatMap(trade.want),
			{ LayoutOrder = 2, MaxTextSize = 18, Parent = content }
		)
		local accept = Kit.button("承諾", function()
			Store.action({ type = "respondTrade", tradeId = trade.id, accept = true })
		end, { LayoutOrder = 3, BackgroundColor3 = Kit.Colors.good, Parent = content })
		Kit.setEnabled(accept, RuleEngine.hasResources(me(view), trade.want), Kit.Colors.good)
		if not RuleEngine.hasResources(me(view), trade.want) then
			accept.Text = "承諾（資源が足りません）"
		end
		Kit.button("断る", function()
			Store.action({ type = "respondTrade", tradeId = trade.id, accept = false })
		end, { LayoutOrder = 4, BackgroundColor3 = Kit.Colors.bad, TextColor3 = Kit.Colors.text, Parent = content })
	end

	-- Trade dialog (bank / players)
	function GameScreen.openTrade()
		closeModal("trade")
		local view = Store.game
		if not view then
			return
		end
		local overlay, content = Kit.modal(gui, "取引", 0.5, 0.82)
		modals.trade = overlay

		-- Bank / port
		Kit.label(
			"銀行・港と交換（出す資源 → もらう資源）",
			{ LayoutOrder = 1, TextColor3 = Kit.Colors.muted, MaxTextSize = 16, Parent = content }
		)
		local giveChoice, getChoice = nil, nil
		local giveButtons, getButtons = {}, {}
		local bankRow = Kit.new(
			"Frame",
			{ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = content }
		)
		Kit.list(Enum.FillDirection.Horizontal, 4).Parent = bankRow
		local getRow = Kit.new(
			"Frame",
			{ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = content }
		)
		Kit.list(Enum.FillDirection.Horizontal, 4).Parent = getRow
		local bankButton
		local function refreshBank()
			local v = Store.game
			if not v then
				return
			end
			for r, b in giveButtons do
				local ratio = RuleEngine.tradeRatio(v, v.mySeat, r)
				b.Text = string.format("%s %d:1", ICON[r], ratio)
				b.BackgroundColor3 = giveChoice == r and Kit.Colors.accent or Kit.Colors.panelLight
				b.TextColor3 = giveChoice == r and Color3.new(0, 0, 0) or Kit.Colors.text
			end
			for r, b in getButtons do
				b.BackgroundColor3 = getChoice == r and Kit.Colors.accent or Kit.Colors.panelLight
				b.TextColor3 = getChoice == r and Color3.new(0, 0, 0) or Kit.Colors.text
			end
			local ok = giveChoice
				and getChoice
				and giveChoice ~= getChoice
				and me(v).resources[giveChoice] >= RuleEngine.tradeRatio(v, v.mySeat, giveChoice)
				and RuleEngine.requireMainTurn(v, v.mySeat)
			Kit.setEnabled(bankButton, ok and true or false)
		end
		for i, r in RESOURCES do
			giveButtons[r] = Kit.button(ICON[r], function()
				giveChoice = r
				refreshBank()
			end, { LayoutOrder = i, Size = UDim2.new(0.2, -4, 1, 0), Parent = bankRow })
			getButtons[r] = Kit.button(ICON[r] .. R[r], function()
				getChoice = r
				refreshBank()
			end, { LayoutOrder = i, Size = UDim2.new(0.2, -4, 1, 0), Parent = getRow })
		end
		bankButton = Kit.button("銀行と交換", function()
			if giveChoice and getChoice then
				Store.action({ type = "bankTrade", give = giveChoice, get = getChoice })
			end
		end, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 38), Parent = content })
		refreshBank()

		-- Player trade
		Kit.label(
			"プレイヤーに提案（出す / 欲しい）",
			{ LayoutOrder = 5, TextColor3 = Kit.Colors.muted, MaxTextSize = 16, Parent = content }
		)
		local grid = Kit.new(
			"Frame",
			{ LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 5 * 34), BackgroundTransparency = 1, Parent = content }
		)
		local giveCol = Kit.new("Frame", { Size = UDim2.new(0.5, -4, 1, 0), BackgroundTransparency = 1, Parent = grid })
		local wantCol = Kit.new("Frame", {
			Position = UDim2.new(0.5, 4, 0, 0),
			Size = UDim2.new(0.5, -4, 1, 0),
			BackgroundTransparency = 1,
			Parent = grid,
		})
		Kit.list(Enum.FillDirection.Vertical, 0).Parent = giveCol
		Kit.list(Enum.FillDirection.Vertical, 0).Parent = wantCol
		local giveGet, wantGet = {}, {}
		local proposeButton
		local function refreshPropose()
			local v = Store.game
			if not proposeButton or not v then
				return
			end
			local g, w = 0, 0
			for _, f in giveGet do
				g += f()
			end
			for _, f in wantGet do
				w += f()
			end
			Kit.setEnabled(
				proposeButton,
				g > 0 and w > 0 and v.trade == nil and (RuleEngine.requireMainTurn(v, v.mySeat)) == true
			)
		end
		for i, r in RESOURCES do
			giveGet[r] = stepperRow(giveCol, r, i, function()
				local v = Store.game
				return v and me(v).resources[r] or 0
			end, refreshPropose)
			wantGet[r] = stepperRow(wantCol, r, i, function()
				return 19
			end, refreshPropose)
		end
		proposeButton = Kit.button("取引を提案", function()
			local give, want = {}, {}
			for r, f in giveGet do
				give[r] = f()
			end
			for r, f in wantGet do
				want[r] = f()
			end
			Store.action({ type = "proposeTrade", give = give, want = want })
			closeModal("trade")
		end, { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Kit.Colors.good, Parent = content })
		refreshPropose()
		Kit.button("閉じる", function()
			closeModal("trade")
		end, {
			LayoutOrder = 8,
			Size = UDim2.new(0.5, 0, 0, 34),
			BackgroundColor3 = Kit.Colors.panelLight,
			TextColor3 = Kit.Colors.text,
			Parent = content,
		})
		modalState.tradeRefresh = function()
			refreshBank()
			refreshPropose()
		end
	end

	-- Development cards
	function GameScreen.openDevCards()
		closeModal("dev")
		local view = Store.game
		if not view or not me(view).devCards then
			return
		end
		local overlay, content = Kit.modal(gui, "発展カード", 0.5, 0.8)
		modals.dev = overlay
		local p = me(view)
		local canPlay = isMyTurn(view)
			and (view.turnPhase == "roll" or view.turnPhase == "main")
			and not view.turn.devCardPlayed

		local choiceA, choiceB, monoChoice = "lumber", "lumber", "lumber"
		local function cycle(current)
			local i = table.find(RESOURCES, current) or 1
			return RESOURCES[i % #RESOURCES + 1]
		end

		for i, card in RuleConfig.DevCardTypes do
			local count, fresh = p.devCards[card] or 0, p.newDevCards[card] or 0
			if count + fresh > 0 then
				local row = Kit.frame({
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 46),
					BackgroundColor3 = Kit.Colors.panelLight,
					Parent = content,
				})
				Kit.padding(4).Parent = row
				local text = string.format("%s × %d", RuleConfig.DevCardNames[card], count)
				if fresh > 0 then
					text ..= string.format("（今回購入 %d）", fresh)
				end
				Kit.label(text, {
					Size = UDim2.new(0.42, 0, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxTextSize = 17,
					Parent = row,
				})
				if card ~= "victoryPoint" then
					local extra = nil
					if card == "yearOfPlenty" then
						local a, b
						a = Kit.button(ICON[choiceA], function()
							choiceA = cycle(choiceA)
							a.Text = ICON[choiceA]
						end, {
							Position = UDim2.new(0.43, 0, 0, 0),
							Size = UDim2.new(0.12, 0, 1, 0),
							BackgroundColor3 = Kit.Colors.panel,
							Parent = row,
						})
						b = Kit.button(ICON[choiceB], function()
							choiceB = cycle(choiceB)
							b.Text = ICON[choiceB]
						end, {
							Position = UDim2.new(0.56, 0, 0, 0),
							Size = UDim2.new(0.12, 0, 1, 0),
							BackgroundColor3 = Kit.Colors.panel,
							Parent = row,
						})
						extra = function()
							return { resources = { choiceA, choiceB } }
						end
					elseif card == "monopoly" then
						local m
						m = Kit.button(ICON[monoChoice] .. R[monoChoice], function()
							monoChoice = cycle(monoChoice)
							m.Text = ICON[monoChoice] .. R[monoChoice]
						end, {
							Position = UDim2.new(0.43, 0, 0, 0),
							Size = UDim2.new(0.25, 0, 1, 0),
							BackgroundColor3 = Kit.Colors.panel,
							Parent = row,
						})
						extra = function()
							return { resource = monoChoice }
						end
					end
					local use = Kit.button("使う", function()
						local action = { type = "playDevCard", card = card }
						if extra then
							for k, v in extra() do
								action[k] = v
							end
						end
						Store.action(action)
						closeModal("dev")
					end, {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, 0, 0, 0),
						Size = UDim2.new(0.28, 0, 1, 0),
						Parent = row,
					})
					Kit.setEnabled(use, canPlay and count > 0)
				end
			end
		end
		Kit.label(
			"買ったターンには使えません。使えるのは1ターンに1枚までです。勝利点カードは自動で加算されます。",
			{
				LayoutOrder = 20,
				Size = UDim2.new(1, 0, 0, 36),
				TextColor3 = Kit.Colors.muted,
				MaxTextSize = 14,
				Parent = content,
			}
		)
		Kit.button("閉じる", function()
			closeModal("dev")
		end, {
			LayoutOrder = 21,
			Size = UDim2.new(0.5, 0, 0, 36),
			BackgroundColor3 = Kit.Colors.panelLight,
			TextColor3 = Kit.Colors.text,
			Parent = content,
		})
	end

	local function openGameOver(view)
		local winner = view.players[view.winner]
		local overlay, content = Kit.modal(gui, "🏆 " .. winner.name .. " の勝利！", 0.42, 0.6)
		modals.gameover = overlay
		local order = table.clone(view.order)
		table.sort(order, function(a, b)
			return view.players[a].points > view.players[b].points
		end)
		for i, seat in order do
			local p = view.players[seat]
			Kit.label(
				string.format("%d位  %s  %d 点", i, p.name, p.points),
				{ LayoutOrder = i, MaxTextSize = 20, TextColor3 = Color3.fromHex(p.color), Parent = content }
			)
		end
		Kit.button("盤面を見る", function()
			overlay.Visible = false
		end, {
			LayoutOrder = 10,
			BackgroundColor3 = Kit.Colors.panelLight,
			TextColor3 = Kit.Colors.text,
			Parent = content,
		})
		Kit.button("ホームに戻る", function()
			Store.request("leaveRoom")
		end, { LayoutOrder = 11, Parent = content })
	end

	-- Update ---------------------------------------------------------------------------------
	local lastLogSeq = -1
	local lastDiceKey = nil

	local function updatePlayers(view)
		for _, child in playerList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, seat in view.order do
			local p = view.players[seat]
			local current = view.currentSeat == seat and view.phase ~= "finished"
			local row = Kit.frame({
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 54),
				BackgroundColor3 = current and Color3.fromRGB(70, 86, 110) or Kit.Colors.panelLight,
				Parent = playerList,
			})
			if current then
				Kit.new("UIStroke", { Color = Kit.Colors.accent, Thickness = 2, Parent = row })
			end
			Kit.new("Frame", {
				Size = UDim2.new(0, 6, 1, -8),
				Position = UDim2.new(0, 4, 0, 4),
				BackgroundColor3 = Color3.fromHex(p.color),
				BorderSizePixel = 0,
				Parent = row,
			})
			local nameText = (current and "▶ " or "")
				.. p.name
				.. (seat == view.mySeat and "（あなた）" or "")
				.. (p.connected and "" or "（切断中）")
			Kit.label(nameText, {
				Position = UDim2.new(0, 14, 0, 2),
				Size = UDim2.new(0.72, -14, 0.5, -2),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBold,
				MaxTextSize = 16,
				Parent = row,
			})
			Kit.label("⭐" .. p.points, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 2),
				Size = UDim2.new(0.28, 0, 0.5, -2),
				TextXAlignment = Enum.TextXAlignment.Right,
				Font = Enum.Font.GothamBlack,
				TextColor3 = Kit.Colors.accent,
				MaxTextSize = 18,
				Parent = row,
			})
			local badges = {}
			if p.hasLongestRoad then
				table.insert(badges, "🛣最長")
			end
			if p.hasLargestArmy then
				table.insert(badges, "⚔最大")
			end
			local stats = string.format(
				"🃏%d  📜%d  ⚔%d  🛣%d  %s",
				p.resourceCount,
				p.devCardCount,
				p.knightsPlayed,
				p.longestRoad,
				table.concat(badges, " ")
			)
			Kit.label(stats, {
				Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.new(1, -20, 0.5, -2),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Kit.Colors.muted,
				MaxTextSize = 14,
				Parent = row,
			})
		end
	end

	local function updateLog(view)
		local newest = view.log[#view.log]
		if not newest or newest.seq == lastLogSeq then
			return
		end
		lastLogSeq = newest.seq
		for _, child in logFrame:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local first = math.max(1, #view.log - 40)
		for i = first, #view.log do
			local entry = view.log[i]
			Kit.new("TextLabel", {
				LayoutOrder = i,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextColor3 = entry.kind == "win" and Kit.Colors.accent
					or entry.kind == "dice" and Color3.fromRGB(170, 210, 255)
					or Kit.Colors.text,
				Text = entry.text,
				Parent = logFrame,
			})
		end
		task.defer(function()
			logFrame.CanvasPosition =
				Vector2.new(0, math.max(0, logFrame.AbsoluteCanvasSize.Y - logFrame.AbsoluteWindowSize.Y))
		end)
	end

	local function autoMode(view)
		if not isMyTurn(view) then
			return nil
		end
		local phase = view.turnPhase
		if phase == "setupSettlement" then
			return "settlement"
		elseif phase == "setupRoad" then
			return "road"
		elseif phase == "moveRobber" then
			return "robber"
		elseif view.turn.freeRoads > 0 and (phase == "main" or phase == "roll") then
			return "road"
		end
		return false
	end

	local function hintText(view, mode)
		if view.phase == "finished" then
			return "ゲーム終了"
		end
		local myself = me(view)
		if myself and myself.mustDiscard > 0 then
			return string.format("資源を %d 枚捨ててください", myself.mustDiscard)
		end
		if not isMyTurn(view) then
			local current = view.players[view.currentSeat]
			if view.turnPhase == "discard" then
				return "他のプレイヤーが資源を捨てるのを待っています"
			end
			return current.name .. " の手番です（" .. (PHASE_TEXT[view.turnPhase] or "") .. "）"
		end
		if mode == "settlement" then
			return view.phase == "setup" and "光っている交点に開拓地を置いてください"
				or "開拓地を建てる交点を選んでください"
		elseif mode == "road" then
			if view.turn.freeRoads > 0 then
				return string.format(
					"無料の街道を置く辺を選んでください（残り %d 本）",
					view.turn.freeRoads
				)
			end
			return view.phase == "setup" and "開拓地につながる辺に街道を置いてください"
				or "街道を建てる辺を選んでください"
		elseif mode == "city" then
			return "都市にする開拓地を選んでください"
		elseif mode == "robber" then
			return "盗賊を移動する地形を選んでください"
		elseif view.turnPhase == "roll" then
			return "サイコロを振ってください"
		elseif view.turnPhase == "steal" then
			return "資源を奪う相手を選んでください"
		elseif view.turnPhase == "discard" then
			return "他のプレイヤーが資源を捨てるのを待っています"
		end
		return "建設・取引をして、終わったら「ターン終了」"
	end

	function GameScreen.refresh()
		local view = Store.game
		root.Visible = view ~= nil
		if not view then
			for name in modals do
				closeModal(name)
			end
			InputController.setMode(nil)
			lastLogSeq = -1
			return
		end
		local myself = me(view)
		local myTurn = isMyTurn(view)

		-- selection mode
		local forced = autoMode(view)
		local mode = InputController.getMode()
		if forced then
			mode = forced
		elseif forced == false then
			if mode == "robber" or (mode and InputController.countLegal(mode) == 0) then
				mode = nil
			end
		else
			mode = nil
		end
		if InputController.getMode() ~= mode then
			InputController.setMode(mode)
		end
		InputController.setView(view)

		turnLabel.Text = view.phase == "setup" and "初期配置"
			or view.phase == "finished" and "ゲーム終了"
			or ("ターン " .. view.turn.number)
		phaseLabel.Text = view.phase == "finished" and ""
			or (view.players[view.currentSeat].name .. "：" .. (PHASE_TEXT[view.turnPhase] or ""))
		hint.Text = hintText(view, mode)
		updatePlayers(view)
		updateLog(view)

		for _, r in RESOURCES do
			resourceCounts[r].Text = myself and myself.resources and tostring(myself.resources[r]) or "-"
		end
		local dice = view.turn.dice
		if #dice > 0 then
			local faces = {}
			for i, d in dice do
				faces[i] = DICE_FACES[d] or tostring(d)
			end
			diceLabel.Text = table.concat(faces, " ") .. "\n= " .. view.turn.diceTotal
			local key = view.turn.number .. ":" .. view.turn.diceTotal .. ":" .. view.currentSeat
			if key ~= lastDiceKey then
				lastDiceKey = key
				toast(string.format("🎲 %s の出目: %d", view.players[view.currentSeat].name, view.turn.diceTotal))
			end
		else
			diceLabel.Text = "🎲"
		end

		-- buttons
		local mainTurn = myTurn and view.phase == "main" and view.turnPhase == "main"
		Kit.setEnabled(buttons.roll, myTurn and view.phase == "main" and view.turnPhase == "roll")
		for name, b in modeButtons do
			local legal = mainTurn and InputController.countLegal(name) > 0
			Kit.setEnabled(b, legal, mode == name and Color3.fromRGB(255, 240, 150) or nil)
		end
		Kit.setEnabled(
			buttons.buyDev,
			mainTurn
				and view.devDeckCount > 0
				and RuleEngine.hasResources(myself, RuleEngine.cost(view, view.mySeat, "devCard"))
		)
		local devTotal = myself
				and myself.devCards
				and (GameState.countDevCards(myself.devCards) + GameState.countDevCards(myself.newDevCards))
			or 0
		Kit.setEnabled(buttons.dev, devTotal > 0, Color3.fromRGB(200, 170, 240))
		buttons.dev.Text = "発展カード（" .. devTotal .. "）"
		Kit.setEnabled(buttons.trade, mainTurn, Color3.fromRGB(140, 200, 240))
		Kit.setEnabled(buttons.endTurn, mainTurn, Color3.fromRGB(240, 140, 120))
		tradeBanner.Visible = view.trade ~= nil and view.trade.from == view.mySeat

		-- modals that follow the game state
		local needDiscard = myself and myself.mustDiscard > 0 and view.turnPhase == "discard"
		if needDiscard and not modals.discard then
			openDiscard(view)
		elseif not needDiscard then
			closeModal("discard")
		end
		local needSteal = myTurn and view.turnPhase == "steal"
		if needSteal and not modals.steal then
			openSteal(view)
		elseif not needSteal then
			closeModal("steal")
		end
		local trade = view.trade
		local incoming = trade and trade.from ~= view.mySeat and not trade.declined[tostring(view.mySeat)]
		if incoming and modalState.incomingId ~= trade.id then
			closeModal("incoming")
			openIncoming(view)
		elseif not incoming then
			closeModal("incoming")
			modalState.incomingId = nil
		end
		if modals.trade and not mainTurn then
			closeModal("trade")
		elseif modalState.tradeRefresh and modals.trade then
			modalState.tradeRefresh()
		end
		if view.phase == "finished" and not modals.gameover then
			openGameOver(view)
		end
	end

	Store.subscribe(function(field)
		if field == "game" then
			GameScreen.refresh()
		end
	end)

	InputController.onSelect(function(mode, id)
		if mode == "settlement" then
			Store.action({ type = "placeSettlement", vertex = id })
		elseif mode == "road" then
			Store.action({ type = "placeRoad", edge = id })
		elseif mode == "city" then
			Store.action({ type = "buildCity", vertex = id })
		elseif mode == "robber" then
			Store.action({ type = "moveRobber", tile = id })
		end
		-- leave manual build modes after one placement (the server state update re-evaluates)
		if mode == "city" or (mode == "settlement" and Store.game and Store.game.phase == "main") then
			InputController.setMode(nil)
		end
	end)

	return root
end

return GameScreen
