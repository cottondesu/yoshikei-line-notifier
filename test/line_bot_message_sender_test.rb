require 'minitest/autorun'
require 'mocha/minitest'
require_relative '../lineBotMessageSender'

class LineBotMessageSenderTest < Minitest::Test
  def setup
    @client_mock = mock('client')
    @logger_mock = mock('logger')
    @logger_mock.stubs(:info)
    @logger_mock.stubs(:error)
    @logger_mock.stubs(:debug)
    @logger_mock.stubs(:level).returns(Logger::INFO)
    # モックオブジェクトは既に準備されているのでlevel=は呼ばれない
    @line_bot = LineBotMessageSender.new(client: @client_mock, logger: @logger_mock)
  end

  def test_send_message
    user_id = 'U1234567890'
    text = 'Hello, World!'
    message = { type: LineBotMessageSender::MESSAGE_TYPE_TEXT, text: text }

    @client_mock.expects(:push_message).with(user_id, message).returns(mock_response(success: true))
    @logger_mock.expects(:info).with(regexp_matches(/成功/))

    @line_bot.send_message(user_id, text)
  end

  def test_send_multicast_message
    user_ids = ['U1234567890', 'U0987654321']
    text = 'Hello, everyone!'
    message = { type: LineBotMessageSender::MESSAGE_TYPE_TEXT, text: text }

    @client_mock.expects(:multicast).with(user_ids, message).returns(mock_response(success: true))
    @logger_mock.expects(:info).with(regexp_matches(/成功/))

    @line_bot.send_multicast_message(user_ids, text)
  end

  def test_error_handling
    @client_mock.expects(:push_message).raises(StandardError.new('通信エラー'))
    @logger_mock.expects(:error).with(regexp_matches(/エラーが発生しました/))

    result = @line_bot.send_message('U1', 'msg')
    assert_nil result
  end

  private

  def mock_response(success:)
    response_mock = mock('response')
    response_mock.stubs(:code).returns(success ? 200 : 400)
    response_mock.stubs(:body).returns(success ? 'OK' : 'Error')
    response_mock
  end
end
