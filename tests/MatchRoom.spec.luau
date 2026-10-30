local AutoPlayer = require(Shared.AutoPlayer)
local GameState = require(Shared.GameState)
local MatchRoom = require(Shared.MatchRoom)
local Rng = require(Shared.Rng)

-- Fake network: records the last message each user received
local function makeRoom(seed)
	local clock = 0
	local inbox = {}
	local hooks = {
		sendRoom = function(userId, snapshot)
			inbox[userId] = inbox[userId] or {}
			inbox[userId].room = snapshot
			inbox[userId].roomCount = (inbox[userId].roomCount or 0) + 1
		end,
		sendGame = function(userId, view)
			inbox[userId] = inbox[userId] or {}
			inbox[userId].game = view
		end,
		notice = function() end,
		now = function()
			return clock
		end,
		rng = Rng.fromSeed(seed or 1),
		autoPlayDelay = 20,
	}
	local room = MatchRoom.new("ABC234", hooks)
	return room, inbox, function(dt)
		clock += dt
	end
end

local function fill(room, n)
	for i = 1, n do
		expect.ok(room:join(i, "U" .. i))
	end
end

test("Room: join, colors, ready, host-only start with 3-4 players", function()
	local room, inbox = makeRoom()
	fill(room, 2)
	expect.eq(room.hostUserId, 1)
	expect.eq(inbox[2].room.members[2].colorIndex, 2)
	expect.fails(room:start(1), "3")
	expect.ok(room:join(3, "U3"))
	expect.fails(room:start(2), "ホスト")
	expect.fails(room:start(1), "準備")
	expect.ok(room:setReady(2, true))
	expect.ok(room:setReady(3, true))
	expect.ok(room:start(1))
	expect.eq(room.status, "playing")
	for i = 1, 3 do
		expect.eq(inbox[i].game.phase, "setup")
		expect.eq(inbox[i].game.mySeat, i)
	end
	-- every client sees the same board
	expect.eq(inbox[1].game.layout.robberTile, inbox[3].game.layout.robberTile)
	for t = 1, 19 do
		expect.eq(inbox[1].game.layout.terrain[t], inbox[2].game.layout.terrain[t])
	end
	-- nobody new can join after the start; a 5th player can never join
	expect.fails(room:join(9, "late"), "開始")
end)

test("Room: max 4 players, leaving in the lobby frees the seat and moves the host", function()
	local room = makeRoom()
	fill(room, 4)
	expect.fails(room:join(5, "U5"), "満員")
	room:leave(1)
	expect.eq(room:memberCount(), 3)
	expect.eq(room.hostUserId, 2)
	expect.ok(room:join(5, "U5"))
	expect.eq(room.members["5"].colorIndex, 1, "freed color is reused")
end)

test("Room: private hands per player, actions only by the seat owner", function()
	local room, inbox = makeRoom(3)
	fill(room, 3)
	room:setReady(2, true)
	room:setReady(3, true)
	expect.ok(room:start(1))
	local game = room.game
	local current = game.players[game.currentSeat].userId
	local other = current % 3 + 1
	expect.fails(room:perform(other, { type = "placeSettlement", vertex = 1 }), "手番")
	expect.fails(room:perform(77, { type = "placeSettlement", vertex = 1 }), "参加者")
	-- finish setup through the room API
	while game.phase == "setup" do
		local seat = game.currentSeat
		expect.ok(room:perform(game.players[seat].userId, AutoPlayer.requiredAction(game, seat)))
	end
	for uid = 1, 3 do
		local view = inbox[uid].game
		for seat, p in view.players do
			if seat == view.mySeat then
				expect.truthy(p.resources ~= nil)
			else
				expect.eq(p.resources, nil, "other hand hidden")
				expect.eq(p.resourceCount, GameState.resourceCount(game.players[seat]))
			end
		end
		expect.eq(view.devDeck, nil)
	end
end)

test("Room: disconnect, auto-play after timeout, reconnect resyncs", function()
	local room, inbox, advance = makeRoom(5)
	fill(room, 3)
	room:setReady(2, true)
	room:setReady(3, true)
	expect.ok(room:start(1))
	local game = room.game
	local firstSeat = game.currentSeat
	local firstUser = game.players[firstSeat].userId
	room:disconnect(firstUser)
	expect.falsy(game.players[firstSeat].connected)
	expect.eq(room.status, "playing")
	if room.hostUserId == firstUser then
		error("host should move to a connected player")
	end
	advance(5)
	expect.eq(room:tick(), 0, "waits before auto-play")
	advance(20)
	expect.truthy(room:tick() > 0, "auto-play placed setup pieces")
	expect.truthy(game.currentSeat ~= firstSeat or game.setupStep > 1)
	-- reconnect
	inbox[firstUser].game = nil
	room:sync(firstUser)
	expect.eq(inbox[firstUser].game, nil, "sync does not leak state to a disconnected member")
	expect.ok(room:join(firstUser, "U" .. firstUser))
	expect.truthy(game.players[firstSeat].connected)
	expect.eq(inbox[firstUser].game.mySeat, firstSeat)
	expect.eq(inbox[firstUser].game.version, game.version)
end)

test("Room: a full 4-player game played through the room reaches a winner", function()
	local room, inbox = makeRoom(11)
	fill(room, 4)
	for i = 2, 4 do
		room:setReady(i, true)
	end
	expect.ok(room:start(1))
	local game = room.game
	local steps = 0
	while game.phase ~= "finished" do
		steps += 1
		assert(steps < 30000, "did not finish")
		local acted = false
		for seat, p in game.players do
			local action = AutoPlayer.buildAction(game, seat) or AutoPlayer.requiredAction(game, seat)
			if action then
				local ok, err = room:perform(p.userId, action)
				assert(ok, err)
				acted = true
				break
			end
		end
		assert(acted, "nobody could act in phase " .. game.turnPhase)
	end
	expect.eq(room.status, "finished")
	for uid = 1, 4 do
		expect.eq(inbox[uid].game.phase, "finished")
		expect.eq(inbox[uid].game.winner, game.winner)
	end
	expect.fails(room:perform(1, { type = "endTurn" }), "終了")
end)
