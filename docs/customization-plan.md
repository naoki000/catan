# カスタマイズ計画（Phase 5 に向けた変更箇所）

Phase 1〜4 ではカスタマイズ機能は実装していません。ここでは将来の機能ごとに、現在の構造で「どこを変えればよいか」を記録します。

## 現在の仕組み

- すべてのルール値は `RuleConfig.Default` にあり、ゲーム開始時に `RuleConfig.create()` でコピーされ `state.rules` に保存されます
- 値の読み出しは `RuleConfig.get(rules, seat, ...)` を使います。`rules.playerOverrides["<seat>"]` に同じ構造で値を置くと、その席だけ上書きされます（ユニットテストで検証済み）
- 状態変更はすべて `GameActions.perform(state, seat, action, ctx)` を通ります。`ctx.authority` は現在 `"player"`（通常操作）と `"auto"`（切断時の自動処理）のみです

## RuleConfig.get（席ごとの上書き）に対応済みの値

| 値 | キー | 読んでいる場所 |
|---|---|---|
| 駒の上限 | `pieceLimits.road / settlement / city` | `GameState.new` |
| 建設コスト | `buildingCosts.*` | `RuleEngine.cost` |
| 資源生産量 | `production.settlement / city` | `GameActions.produce` |
| 点数 | `points.*`、`victoryPointsToWin` | `GameState.publicPoints/totalPoints`、勝利判定 |
| サイコロ | `dice.count / sides` | `GameActions` の `rollDice` |
| 捨て札の基準 | `discardLimit` | `rollDice` |
| 交換レート | `tradeRatios.*` | `RuleEngine.tradeRatio` |
| 発展カード効果 | `roadBuildingRoads`、`yearOfPlentyPicks` | `playDevCard` |
| 最大騎士力の基準 | `largestArmyMin` | `LongestRoad.updateLargestArmy` |

## ゲーム全体の値（席ごとの上書きは未対応）

`robberRoll`、`longestRoadMin`、`bankResourceCount`、`devCardDeck`、`terrainCounts`、`numberTokens`、`ports`、`portSpacing`、`boardRadius`、`setupRounds`、`minPlayers/maxPlayers`

## 将来機能ごとの変更箇所

| 機能 | 変更箇所 | メモ |
|---|---|---|
| サイコロを3個以上 | `rules.dice.count` を変更するだけで出目計算は対応済み | UI の出目表示（`GameScreen` の `DICE_FACES`）は個数に対応済み。数字チップ（2〜12）の範囲外になる点は盤面生成側で別途検討 |
| 出目判定方式の変更（例：合計ではなく各目） | `GameActions` の `rollDice` と `produce` | `produce(state, total)` を「出目→産出タイル集合」を返す関数に差し替える |
| 出目の手動指定 | `ctx.rng` を差し替える（`Rng` インターフェース） | GM 用アクション（例 `setDice`）を `authority="gm"` で追加 |
| 席ごとの街道上限 | `playerOverrides["2"].pieceLimits.road` | ゲーム中に変更する場合は `player.pieces` の差分調整アクションが必要 |
| 開拓地・都市の上限 | 同上 | |
| 建設コスト変更 | `buildingCosts`（席ごと可） | UI のボタン有効判定も `RuleEngine.cost` 経由なので自動追従 |
| 資源生産量 | `production`（席ごと可） | |
| 勝利点の変更 | `victoryPointsToWin`、`points.*`（席ごと可） | `HowToPlay` の説明文は固定文字列なので表示を差し替える |
| ターン順序 | `state.order`（配列） | 逆順・ランダム化などは `endTurn` の次手番決定部分を関数化する |
| 建設位置の制限変更 | `RuleEngine.distanceRuleOk` / `edgeConnects` / `vertexTouchesOwnRoad` | ルールフラグ（例 `rules.ignoreDistanceRule`）を追加して分岐 |
| ゲーム中のルール変更 | `state.rules` を更新する GM アクション | `StateView` が毎回 `rules` を送るため UI は自動反映 |
| ルール無視での建設・資源操作 | `GameActions` に `authority="gm"` 専用ハンドラを追加（例 `gmPlacePiece`, `gmSetResources`） | `perform` を必ず経由させ、ログ・バージョン更新・勝利判定を共通化。`MatchRoom:perform` で GM 権限（ホストなど）を確認 |
| GM が他人の駒を操作 | 同上（`seat` とは別に対象席を payload で受け取る） | |

## 現在コード内に残っている固定値

| 場所 | 内容 | 対応方針 |
|---|---|---|
| `RuleEngine.distanceRuleOk` | 距離ルール（隣接交点に建物不可） | ルールフラグ化 |
| `GameActions.placeSettlement` | 最終巡目の開拓地で初期資源を得る | `rules.setupResourcesRound` などに分離 |
| `GameActions.endTurn` | 次の手番は `order` の次 | 手番決定関数に分離 |
| `GameState.new` | 手番順をランダムに決定 | ルール値化 |
| `Protocol.PlayerColors` | 4 色 | 5 人以上対応時に追加 |
| `UI/HowToPlay.luau` | 説明文中の数値（10 点、コストなど） | `rules` から説明文を生成 |
| `UI/GameScreen.luau` の取引ステッパー | 欲しい資源の上限 19 | `rules.bankResourceCount` を参照 |
| `BoardRenderer` | 盤面サイズは `layout.radius` に追従、駒の形状は固定 | — |
