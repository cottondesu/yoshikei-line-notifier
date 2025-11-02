require_relative 'yoshikeiLogin'
require_relative 'lineBotMessageSender'

# Yoshikeiにログインする処理を呼び出し、必要なデータを取得
login = YoshikeiLogin.new
login_data = nil
retry_count = 0
max_retries = 3

begin
  login_data = login.perform_login
  raise "Login failed" unless login_data
rescue => e
  retry_count += 1
  if retry_count < max_retries
    puts "Login attempt #{retry_count} failed: #{e.message}. Retrying in #{10 * retry_count} seconds..."
    sleep(10 * retry_count) # エクスポネンシャルバックオフ方式
    retry
  else
    puts "Login failed after #{max_retries} attempts: #{e.message}."
    exit(1) # 明示的な異常終了
  end
end

if login_data
  # LINEにメッセージを送信する処理を呼び出す
  begin
    # 現在の環境変数からユーザーIDを取得
    user_ids = [ENV.fetch('LINE_USER_ID_1'), ENV.fetch('LINE_USER_ID_2')]

    if user_ids.empty?
      puts "送信先のユーザーIDが設定されていません。"
      exit(1)
    end

    logger = Logger.new($stdout)
    logger.level = Logger::INFO
    line_bot = LineBotMessageSender.new(logger: logger)
    line_bot.send_multicast_message(user_ids, login_data)
  rescue KeyError => e
    puts "環境変数が設定されていません: #{e.message}"
    exit(1)
  end
end
