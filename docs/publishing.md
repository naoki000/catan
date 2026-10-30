# 公開手順（Roblox）

公式ドキュメント（2026年10月時点で確認）：
- 公開と Place：https://create.roblox.com/docs/production/publishing/publish-games-and-places
- テレポート：https://create.roblox.com/docs/projects/teleport
- 予約サーバー：https://create.roblox.com/docs/projects/teleport-private-servers

## 0. 事前条件（16歳以上の年齢確認済みユーザー向けに公開する場合）

- アカウントが良好な状態で、作成から 2 日以上経過している
- 顔による年齢推定または政府発行 ID で **年齢確認（age check）** を済ませている
- 公開時に表示される **Maturity & Compliance Questionnaire** の最初の質問（年齢制限コンテンツの有無）に回答する
  - 本作は年齢制限コンテンツを含まないため「No」→「Content May Vary」ラベルで、年齢確認済みの 16 歳以上に公開されます
- 全年齢公開（Roblox Kids / Select）はさらに追加条件（ID 認証・2FA・Premium 継続 または 1,000 Robux の返金可能な手数料・審査）があります。**有料条件を含むため、本手順では行いません**

## 1. ロビー Place（スタート Place）を公開

1. `rojo build default.project.json -o build/Hexland.rbxl`（または Rojo 同期中の Studio）
2. Studio で `build/Hexland.rbxl` を開く
3. **ファイル → Roblox に公開**（File > Publish）
   - 名前：`HEXLAND（ヘックスランド開拓記）`
   - 説明：例「六角形の島で資源を集め、街道・開拓地・都市を建てて10点を目指すオンライン対戦ゲーム。部屋コードで友達と3〜4人で遊べます。」
   - ジャンル：Strategy など
   - アイコン・サムネイル：自作画像（公式ボードゲームの画像やロゴは使用しない）
4. 公開後、Creator Dashboard でこの Place の **Place ID** を控える（= ロビー）

## 2. 対戦 Place を追加

1. 同じ `build/Hexland.rbxl` を Studio で開く
2. **ファイル → 名前を付けて Roblox に公開**（File > Publish As）→ 1 で作ったゲームを選択 → **新しい Place として追加**（Add as a new place）→ Create
3. Creator Dashboard → ゲーム → Configurations > Places で、追加した Place の **Place ID** を控える（= 対戦）

## 3. Place ID を設定して両方に再公開

1. `src/server/Config.luau` を編集
   ```lua
   LOBBY_PLACE_ID = <ロビーの Place ID>,
   MATCH_PLACE_ID = <対戦の Place ID>,
   ```
2. 再ビルドして、**ロビー Place と対戦 Place の両方に**上書き公開（File > Publish As → 各 Place を選んで Overwrite）
   - 同じビルドを両方に公開します。サーバーは `game.PlaceId` で自分の役割（lobby / match）を判断します

## 4. セキュリティ・アクセス設定

- Creator Dashboard → **Audience > Access Settings > Access Control for Places** を **Secure within universe only** に設定
  - 対戦 Place にはサーバーからのテレポートでしか入れなくなります（予約サーバー専用の Place に推奨される設定）
- Studio → File > Experience Settings > Security → **Enable Studio Access to API Services** は任意（Studio で MemoryStore を使う場合のみ。通常のローカルテストは local モードで不要）
- サードパーティテレポートは不要（無効のまま）

## 5. 公開範囲

1. 最初は **Playtest**（Early testers）で友達を招待してテスト（File > Invite early testers、最大 10 人）
2. 問題なければ File > Publish → 質問票に回答 → 公開
3. Creator Dashboard → Publish settings > Manage Audience → Public（Friends をオフにすると誰でも参加可）

部屋コードを知っている人だけが同じ対戦部屋に入れます。一般公開しても、他人の対戦部屋に勝手に入ることはできません（対戦サーバーが UserId の参加許可を検証）。

## 6. 公開後の対戦確認（Studio では確認できない項目）

TeleportService と予約サーバーは Studio 内では動作しないため、公開環境の Roblox クライアントで確認してください。
チェック項目は [testing.md](testing.md) の「公開環境で確認する項目」を参照してください。
