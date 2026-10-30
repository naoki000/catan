# HEXLAND（ヘックスランド開拓記）

Roblox 上で 3〜4 人がオンライン対戦できる、六角形の島を開拓するボードゲームです。
資源を集めて街道・開拓地・都市を建て、先に 10 点を取ったプレイヤーが勝ちます。

- 言語：Luau／同期：Rojo／ツール管理：Rokit
- ゲームロジックは Roblox API に依存しない純 Luau（`src/shared`）で、PC 上で Lune を使ってユニットテストできます
- 対戦サーバーは Roblox 標準機能のみ（予約サーバー＋MemoryStore）。外部ホスティングは使いません

> 本作は特定の市販ボードゲームの公式素材（画像・ロゴ・カードデザイン・説明文）を使用していません。名称・UI・ルール説明文はすべて独自に作成しています。

## ディレクトリ構成

```
default.project.json   Rojo プロジェクト（DataModel への配置）
rokit.toml             ツールのバージョン固定（rojo / stylua / selene / luau-lsp / lune）
src/shared/            ReplicatedStorage.Shared … ルール・盤面・状態（サーバー/クライアント共通）
  RuleConfig.luau        ルール値（サイコロ・コスト・駒数・点数など）
  Board.luau             盤面トポロジ（タイル/交点/辺の整数ID・隣接）と盤面生成
  GameState.luau         ゲーム状態（純データ）
  RuleEngine.luau        操作の合法性判定（状態を変更しない）
  GameActions.luau       操作の適用（唯一の状態変更窓口）
  LongestRoad.luau       最長交易路・最大騎士力
  StateView.luau         プレイヤー別の公開ビュー（他人の手札を隠す）
  AutoPlayer.luau        切断中プレイヤーの自動処理・テスト用ボット
  MatchRoom.luau         対戦部屋（待機室＋ゲーム）。Roblox API 非依存
  Protocol.luau          通信名・部屋コード・プレイヤーカラー
src/server/            ServerScriptService.Server
  init.server.luau       起動処理
  Network.luau           RemoteEvent 作成・レート制限・振り分け
  RoomService.luau       部屋の作成/参加/退出/再接続、テレポート
  RoomDirectory.luau     MemoryStore 上の部屋台帳（部屋コード⇔予約サーバーID）
  Config.luau            Place ID などの設定
src/client/            StarterPlayerScripts.Client
  init.client.luau       起動処理
  Store.luau             サーバーから受け取った状態
  BoardRenderer.luau     3D 盤面の生成・描画
  CameraController.luau  見下ろしカメラ（ドラッグ移動・ホイール/ピンチ拡大）
  InputController.luau   交点/辺/地形の選択とハイライト
  UI/                    ホーム・ロビー・ゲーム画面（ScreenGui をコードで生成）
tests/                 Lune ユニットテスト（tests/run.luau が実行器）
scripts/check.ps1      ビルド・整形・Lint・型チェック・テストを一括実行
docs/                  設計・カスタマイズ計画・テスト・公開手順
```

盤面・UI はすべてコードで生成するため、Roblox Studio 側で手作業のオブジェクト管理は不要です（.rbxl はビルド成果物で Git 管理外）。

## 1. 開発環境のセットアップ（Windows）

1. **Roblox Studio** をインストール：https://create.roblox.com/ → 「Studio をダウンロード」
2. **Rokit**（ツール管理）をインストール
   ```powershell
   gh release download --repo rojo-rbx/rokit --pattern "*windows-x86_64.zip" --dir $env:TEMP\rokit
   Expand-Archive $env:TEMP\rokit\*.zip -DestinationPath $env:TEMP\rokit -Force
   & $env:TEMP\rokit\rokit.exe self-install
   ```
   新しいターミナルを開き、リポジトリ直下で `rokit install` を実行すると `rokit.toml` のツール（rojo, stylua, selene, luau-lsp, lune）が入ります。
3. **VS Code 拡張機能**（`.vscode/extensions.json` で推奨表示されます）
   - Luau Language Server（JohnnyMorganz.luau-lsp）
   - StyLua（JohnnyMorganz.stylua）… 保存時に自動整形
   - Selene（Kampfkarren.selene-vscode）
   - Rojo（evaera.vscode-rojo）
   - GitHub Copilot
4. **Rojo の Studio プラグイン**をインストール：`rojo plugin install`
   （または Studio の「プラグイン」→ Rojo を検索してインストール）

## 2. VS Code ↔ Roblox Studio の同期

1. VS Code でこのフォルダを開き、ターミナルで `rojo serve`
2. Roblox Studio で「新規」→「Baseplate」を開く（どのテンプレートでも可）
3. Studio の「プラグイン」タブ → **Rojo** → **Connect**（localhost:34872）
4. 以後 VS Code でファイルを保存すると Studio に即反映されます

同期を使わずにビルドする場合：`rojo build default.project.json -o build/Hexland.rbxl` で作った place ファイルを Studio で開きます。

## 3. ローカルでのテスト

### PC 上のチェック（Studio 不要）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check.ps1
```
Rojo ビルド → StyLua → Selene → luau-lsp 型チェック → Lune ユニットテストを順に実行します。
ユニットテストのみ：`lune run tests/run`（名前で絞り込み：`lune run tests/run -- Robber`）

### Roblox Studio（Server & Clients）

Studio 内では Teleport が使えないため、サーバーは自動的に **local モード**（部屋を同じサーバー内で管理）で動きます。

1. Studio 上部「テスト」タブ → 「クライアントとサーバー」でプレイヤー数を **3** または **4** にして「開始」
2. Player1 のウィンドウ：「ゲーム開始」→「部屋を作成」→ 表示された 6 文字の部屋コードを確認
3. Player2〜4 のウィンドウ：「ゲーム開始」→ 部屋コードを入力 →「部屋に参加」→「準備完了」
4. Player1 で「ゲーム開始」
5. 光っている交点・辺をクリックして初期配置 → サイコロ → 建設・取引 → ターン終了…

詳しいテスト項目は [docs/testing.md](docs/testing.md) を参照してください。

## 4. Roblox への公開

[docs/publishing.md](docs/publishing.md) に、ロビー用 Place と対戦用 Place の作成、`src/server/Config.luau` への Place ID 設定、公開設定（年齢・質問票）の手順をまとめています。

## 5. 設計とカスタマイズ

- 設計の概要：[docs/architecture.md](docs/architecture.md)
- 将来のルール変更に向けた変更箇所：[docs/customization-plan.md](docs/customization-plan.md)

## ライセンス・素材

すべてのコード・テキストは本リポジトリで新規作成したものです。外部の画像・音声・フォント素材は使用していません（Roblox 標準フォントと標準パーツのみ）。
