# 設計概要

## レイヤー構成

| 層 | モジュール | 役割 | Roblox API |
|---|---|---|---|
| RuleConfig | `src/shared/RuleConfig.luau` | すべてのルール値。ゲームごとに `state.rules` へコピー | 不使用 |
| Board | `src/shared/Board.luau` | タイル・交点・辺の整数ID、隣接、海岸線、盤面生成 | 不使用 |
| GameState | `src/shared/GameState.luau` | ゲーム状態（純データ）、点数計算 | 不使用 |
| RuleEngine | `src/shared/RuleEngine.luau` | 合法性判定（状態を変更しない） | 不使用 |
| GameActions | `src/shared/GameActions.luau` | 操作の適用。状態を変える唯一の入口 | 不使用 |
| StateView | `src/shared/StateView.luau` | プレイヤー別の非公開情報フィルタ | 不使用 |
| MatchRoom | `src/shared/MatchRoom.luau` | 部屋（待機・開始・再接続・自動処理） | 不使用（フック注入） |
| Network | `src/server/Network.luau` | RemoteEvent・レート制限 | 使用 |
| RoomService | `src/server/RoomService.luau` | 部屋の作成/参加、テレポート、モード切替 | 使用 |
| RoomDirectory | `src/server/RoomDirectory.luau` | MemoryStore の部屋台帳 | 使用 |
| UI | `src/client/**` | 盤面描画・カメラ・入力・画面 | 使用 |

ルールに関わる処理はすべて `src/shared` にあり、UI からは RuleEngine（判定）を呼ぶだけです。
クライアントは操作要求を送るだけで、状態を書き換えるのはサーバーの `GameActions.perform` のみです。

## 盤面の座標とID

- タイル：axial 座標 (q, r)、pointy-top。半径 2 で 19 枚
- 交点：整数格子で一意に識別。タイル中心 = (2q + r, 3r)、角 = 中心 + {(0,-2),(1,-1),(1,1),(0,2),(-1,1),(-1,-1)}
  - 浮動小数点比較を使わずに、隣り合うタイルの角が同じ交点 ID になります
- 辺：両端の交点 ID のペアで一意
- 交点 54・辺 72・海岸辺 30（ユニットテストで検証）

## 通信

```
Client                               Server
  Request:FireServer(kind, payload) ──▶ Network（レート制限・pcall）
                                         └▶ RoomService ─▶ MatchRoom ─▶ GameActions.perform
  RoomState  ◀── 部屋情報（メンバー・準備状況）
  GameState  ◀── StateView.forSeat(state, seat)（各プレイヤー専用）
  Notice     ◀── エラー/お知らせ
```

- 正本はサーバーの `GameState`。クライアントから届くのは「何をしたいか」（例 `{type="placeRoad", edge=12}`）だけで、資源数・建設可否・点数は一切受け取りません
- すべてのアクションは RuleEngine で検証してから適用。不正値（負数・小数・未知の資源名・範囲外ID・`__index` などのキー）は拒否し、状態は変化しません
- 他プレイヤーの資源は枚数のみ、発展カードは枚数のみ、山札は残り枚数のみ送信します。盗賊で奪った資源の種類もログには出しません

## 部屋とサーバー

| モード | 条件 | 動作 |
|---|---|---|
| local | Studio 実行時、または `Config.MATCH_PLACE_ID == 0` | 同じサーバー内で複数の部屋を管理 |
| lobby | 公開後のスタート Place | 部屋コード発行、MemoryStore に登録、予約サーバーへテレポート |
| match | 公開後の対戦 Place（予約サーバー） | その部屋の参加許可リストにいる UserId だけ入室 |

- 予約サーバーは非推奨 API（`ReserveServer` / `ReserveServerAsync` / `ReservedServerAccessCode` / `ShouldReserveServer`）を使わず、
  `HttpService:GenerateGUID(false)` で生成した ID を `TeleportOptions.ReservedServerId` に設定する現行方式です
- MemoryStore（HashMap `HexlandRooms_v1`）：
  - `room:<CODE>` … 予約サーバーID、ホスト、参加許可 UserId、状態（open/started/finished/closed）
  - `srv:<予約サーバーID>` … 部屋コード（対戦サーバーが自分の部屋を特定）
  - `user:<UserId>` … 参加中の部屋コード（「前のゲームに戻る」）
- 参加許可リストへの追加は `UpdateAsync` で行い、別のロビーサーバーから同時に参加しても定員超過しません
- 対戦開始後は新規参加不可（許可リストにいる人の再接続のみ可）

## 切断・再接続

- 切断は `PlayerRemoving` で検知し、ゲーム中は席を保持（`connected=false`）
- 同じ UserId で戻ると同じ席に復帰し、状態を再送信（Roblox は同一アカウントの同一サーバー重複参加を許さないため重複は発生しません）
- ホストが抜けた場合は接続中の次のメンバーがホストになります（ゲーム中はホスト権限は不要）
- 切断中のプレイヤーに必要な操作（初期配置・サイコロ・資源を捨てる・盗賊・取引への応答・ターン終了）は `Config.AUTO_PLAY_DELAY`（20 秒）後にサーバーが自動処理し、ゲームが止まりません
- サーバー終了後の復元は対象外（MemoryStore 上の部屋は `closed` になります）
