# ヨシケイ ログイン通知システム

このプロジェクトは、ヨシケイのウェブサイトにログインし、カートの情報を取得して、LINEに通知するシステムです。

## 機能

- Seleniumを使用したヨシケイWebサイトへの自動ログイン
- カートに追加された商品の情報取得
- LINE Botを使用したメッセージ送信
- エラー時の自動リトライ機能

## セットアップ

1. 必要なGemをインストールします：

```bash
bundle install
```

2. 環境変数を設定します：

`.env.example`ファイルを`.env`としてコピーし、必要な情報を入力してください。

```bash
cp .env.example .env
# .envファイルを編集して必要な情報を入力
```

## 実行方法

```bash
ruby main.rb
```

## テスト

```bash
ruby -Ilib test/line_bot_message_sender_test.rb
```

## 環境変数の説明

- `YOSHIKEI_USERNAME`: ヨシケイのログインユーザー名
- `YOSHIKEI_PASSWORD`: ヨシケイのログインパスワード
- `LOGIN_URL`: ヨシケイのログインURL
- `LINE_CHANNEL_SECRET`: LINE Bot チャンネルシークレット
- `LINE_CHANNEL_TOKEN`: LINE Bot チャンネルトークン
- `LINE_USER_ID_1`, `LINE_USER_ID_2`: メッセージ送信先のLINEユーザーID
- `GOOGLE_CHROME_BIN`: Chrome実行ファイルのパス
- `CHROMEDRIVER_PATH`: ChromeDriverのパス
