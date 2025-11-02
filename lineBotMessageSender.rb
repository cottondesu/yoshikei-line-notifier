require 'line/bot'
require 'dotenv/load'
require 'logger'

class LineBotMessageSender
  MESSAGE_TYPE_TEXT = 'text'.freeze

  def initialize(client: nil, logger: nil)
    @logger = logger || begin
      logger = Logger.new($stdout)
      logger.level = Logger::INFO
      logger
    end
    @client = client || default_client
  end

  def send_message(user_id, text)
    send_with_handling { @client.push_message(user_id, build_text_message(text)) }
  end

  def send_multicast_message(user_ids, text)
    send_with_handling { @client.multicast(user_ids, build_text_message(text)) }
  end

  private

  def default_client
    Line::Bot::Client.new do |config|
      begin
        config.channel_secret = ENV.fetch('LINE_CHANNEL_SECRET')
        config.channel_token = ENV.fetch('LINE_CHANNEL_TOKEN')
      rescue KeyError => e
        @logger.error("環境変数が設定されていません: #{e.message}")
        raise
      end
    end
  end

  def build_text_message(text)
    {
      type: MESSAGE_TYPE_TEXT,
      text: text
    }
  end

  def send_with_handling
    response = yield
    log_response(response)
    response
  rescue => e
    handle_error(e)
    nil
  end

  def log_response(response)
    if response.code.to_i >= 400
      @logger.error("レスポンスエラー: #{response.code} #{response.body}")
    else
      @logger.info("メッセージ送信成功: #{response.body}")
    end
  end

  def handle_error(e)
    @logger.error("エラーが発生しました: #{e.message}")
    @logger.debug(e.backtrace.join("\n")) if @logger.level == Logger::DEBUG
  end
end
