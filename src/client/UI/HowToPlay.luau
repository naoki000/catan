--[[
	HowToPlay: short rules summary written for this game (original text).
]]

local Kit = require(script.Parent.Kit)

local HowToPlay = {}

local TEXT = [[
<b>目的</b>
島に開拓地や都市を建てて、先に <b>10点</b> を集めた人の勝ちです。

<b>点数</b>
開拓地 1点 / 都市 2点 / 最長交易路 2点（5本以上つながった街道で最長）/ 最大騎士力 2点（騎士3枚以上で最多）/ 勝利点カード 1点

<b>初期配置</b>
順番に開拓地と街道を1つずつ置き、2巡目は逆順に置きます。2つ目の開拓地のまわりの地形から資源を1枚ずつもらえます。開拓地どうしは隣の交点に置けません。

<b>手番</b>
1. サイコロを振る：出目と同じ数字の地形に接する開拓地は1枚、都市は2枚の資源をもらえます（盗賊のいる地形は産出しません）。
2. 取引：銀行と4:1（港があれば3:1や2:1）で交換、または他のプレイヤーに取引を提案できます。
3. 建設：街道（木材・レンガ）、開拓地（木材・レンガ・羊毛・小麦）、都市（小麦2・鉱石3）、発展カード（羊毛・小麦・鉱石）。
4. ターン終了。

<b>7が出たら</b>
資源を8枚以上持っている人は半分（切り捨て）を捨てます。手番の人は盗賊を別の地形に移し、そこに建物を持つ人から資源を1枚奪います。

<b>発展カード</b>
騎士（盗賊を移動）/ 街道建設（街道2本を無料で）/ 発見（好きな資源2枚）/ 独占（全員から1種類の資源を集める）/ 勝利点（1点・非公開）。
買ったターンには使えず、使えるのは1ターンに1枚までです。

<b>操作</b>
ドラッグで盤面を移動、ホイールまたはピンチで拡大縮小。光っている場所をクリック（タップ）して配置します。
]]

function HowToPlay.open(gui: Instance)
	local overlay, content = Kit.modal(gui, "遊び方", 0.6, 0.8)
	local scroll = Kit.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		LayoutOrder = 1,
		Parent = content,
	})
	Kit.new("TextLabel", {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = Kit.Colors.text,
		Text = TEXT,
		Parent = scroll,
	})
	Kit.button("閉じる", function()
		overlay:Destroy()
	end, { LayoutOrder = 2, Size = UDim2.new(0.5, 0, 0, 40) }).Parent =
		content
	Kit.raise(overlay, 60)
end

return HowToPlay
