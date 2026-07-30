# Amazon GameLift Streams サンプル（ブラウザでゲームをプレイ）

「ゲームを起動」ボタンを押すと、AWS 上で動くサンプルゲームが WebRTC でブラウザに
ストリーミングされ、その場で遊べる——という一式です。すべてあなたの手元（自分の PC）で
実行して、あなたの AWS アカウント内にリソースを作ります。

> なぜ手元で実行するのか：この一式を作った Cloud 実行環境からは AWS のエンドポイントへ
> 到達できず（ネットワーク制限）、私が直接デプロイできませんでした。そのため「あなたが
> コマンドを順に実行するだけで完成する」形にしてあります。

達成するテスト項目：
**「ゲームを起動」ボタンをクリックすると、ブラウザにゲームが表示され、遊ぶことができる。**

---

## 全体像

```
game/    … 軽量サンプルゲーム（SDL2製ブロック崩し / Ubuntu 22.04 ネイティブ）
infra/   … S3アップロード → Application作成 → Stream Group作成 のスクリプト
web/     … 「ゲームを起動」ボタン付きWebアプリ（Express + GameLift Streams Web SDK）
```

処理の流れ：

1. `game/` をビルド → アップロード用フォルダ `game/dist/` が出来る
2. `infra/` のスクリプトで dist を S3 に上げ、GameLift Streams の Application と
   Stream Group（GPUキャパシティ）を作る
3. 出力された `STREAM_GROUP_ID` と `APPLICATION_ID` を `web/.env` に書く
4. `web/` を起動し、ブラウザで「ゲームを起動」を押す → ストリーミング開始

---

## 前提条件

- **AWS アカウント**（GameLift Streams は東京 `ap-northeast-1` 対応）
- **AWS CLI v2**（`gameliftstreams` サービスを認識する新しめのもの）
- **Docker**（サンプルゲームを Ubuntu 22.04 でビルドするため）
- **Node.js 18 以上**（Web アプリ用）
- IAM 権限：`infra/iam-policy.sample.json` を参照（GameLift Streams と S3、STS）

> ⚠️ **重要（サービスクォータ）**
> 新規アカウントでは GameLift Streams の「ストリームキャパシティ」上限が **0** の
> ことがあります。その場合 Stream Group がキャパシティを確保できません。
> AWS コンソール → **Service Quotas → Amazon GameLift Streams** で、使用する
> ストリームクラス（例: `gen6n`）の上限引き上げを申請してください。反映まで
> 数分〜1日程度かかることがあります。

> 💰 **コスト注意**
> Stream Group の「常時オン（always-on）」キャパシティは GPU インスタンスを
> 起動しっぱなしにするため、**起動中は課金が続きます**。試し終わったら必ず
> `infra/90-cleanup.sh` を実行して削除してください。
>
> 既定では always-on=0 / on-demand=12 とし、アイドル中に課金されないように
> しています。代わりに初回のストリーム開始時はプロビジョニングで数分待ちます。

> 📐 **キャパシティは 12 の倍数**
> `gen6n_small` はホスト 1 台 = 12 ストリーム枠のため、キャパシティに 12 の
> 倍数以外を指定すると `ValidationException` になります。`config.env` の
> `ALWAYS_ON_CAPACITY` / `ON_DEMAND_CAPACITY` は 0 か 12 の倍数にしてください。

---

## 手順

### 0. AWS 認証情報の設定

`aws configure`（または一時的な STS 認証情報）で、この PC から AWS を操作できる
状態にしてください。確認：

```bash
aws sts get-caller-identity
```

### 1. サンプルゲームをビルド

```bash
cd game
./build.sh          # Docker で Ubuntu 22.04 上でビルドし game/dist/ を生成
```

`game/dist/` に `run-game.sh`（起動スクリプト）、`bin/breakout`、`libs/`（同梱ライブラリ）が
できます。この `run-game.sh` が GameLift Streams の「実行ファイルの起動パス」です。

> Docker を使わず自分の Ubuntu 22.04 でビルドする場合は
> `sudo apt install build-essential libsdl2-dev` の後 `./package_build.sh` でも可。

### 2. 設定を編集

`infra/config.env` を開き、`BUILD_BUCKET` を **世界で一意** な名前に変更します
（例: `glstreams-sample-tomoya-ap-northeast-1`）。リージョンやストリームクラスも
必要なら調整してください（既定: 東京 / `gen6n_small`）。

### 3. プロビジョニング（順に実行）

```bash
cd ../infra
./00-preflight.sh                 # 事前チェック
./10-upload-and-create-app.sh     # S3アップロード + Application作成（READYまで待機）
./20-create-stream-group.sh       # Stream Group作成（ACTIVEまで待機）
```

`20-...` の最後に `STREAM_GROUP_ID` と `APPLICATION_ID` が表示されます。
（これらは `infra/state.env` にも保存されます。）

### 4. Web アプリを設定して起動

```bash
cd ../web
cp .env.example .env
# .env を編集し、STREAM_GROUP_ID と APPLICATION_ID を貼り付け
```

**GameLift Streams Web SDK** は `web/public/gameliftstreams-1.2.0.js` として
すでに同梱済みです（v1.2.0 / UMD ビルド → `window.gameliftstreams`）。
そのまま次の「起動」に進めます。

新しいバージョンに差し替えたい場合は、
[Getting started ページの Resources 節](https://aws.amazon.com/gamelift/streams/getting-started/#Resources)
からバンドルをダウンロードするか、直接取得します：

```bash
cd web/public
curl -sSLO https://gameliftstreams-public-website-assets.s3.us-west-2.amazonaws.com/AmazonGameLiftStreamsWebSDK-v1.2.0.zip
# zip 内の gameliftstreams-<version>.js を web/public/ に展開し、
# index.html の <script src="gameliftstreams-1.2.0.js"> を実際の名前に合わせる
```

起動：

```bash
npm install
npm start
```

### 5. テスト

ブラウザで `http://localhost:8000` を開き、**「ゲームを起動」** をクリック。
数秒〜十数秒でブロック崩しが表示され、`←` `→` でパドル移動、`Space` でボール発射。
これでテスト項目（ボタン→ブラウザ表示→プレイ可能）を満たします。

### 6. 後片付け（課金停止）

```bash
cd ../infra
./90-cleanup.sh
```

---

## うまくいかないときは

- **Stream Group が ACTIVE にならない / ERROR** → サービスクォータ（上記）を確認し、
  ストリームクラスの上限引き上げを申請してから `20-...` を再実行。
- **「ゲームを起動」後に映像が出ない** → `web` を起動したターミナルのログと、
  ブラウザの開発者ツール（Console）を確認。`StartStreamSession` のエラー内容が出ます。
- **黒い画面のまま** → ゲームが起動していない可能性。GameLift Streams コンソールの
  「Test stream」でも同じ Application を試すと切り分けできます。ログ収集を有効化する
  場合は `create-application` に `--application-log-paths` / `--application-log-output-uri`
  を追加してください。
- **入力が効かない** → ストリーム画面を一度クリックしてから操作してください
  （ブラウザはユーザー操作後に入力を有効化します）。

---

## 参考

- Amazon GameLift Streams 開発者ガイド（最初のストリーム）:
  https://docs.aws.amazon.com/gameliftstreams/latest/developerguide/streaming-process.html
- バックエンドサービスとウェブクライアント（Web SDK）:
  https://docs.aws.amazon.com/gameliftstreams/latest/developerguide/sdk.html
- 対応リージョン:
  https://docs.aws.amazon.com/gameliftstreams/latest/developerguide/regions-quotas-rande.html
- Getting started（Web SDK バンドル入手先）:
  https://aws.amazon.com/gamelift/streams/getting-started/
