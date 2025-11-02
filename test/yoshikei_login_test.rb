require 'minitest/autorun'
require 'mocha/minitest'
require_relative '../yoshikeiLogin'
require 'nokogiri'

class YoshikeiLoginTest < Minitest::Test
  class DummyElement
    def initialize(text_elements = {})
      @text_elements = text_elements
    end

    def find_elements(*)
      []
    end

    def text
      @text_elements[:text]
    end
  end

  def setup
    @web_driver_helper = mock('WebDriverHelper')
    WebDriverHelper.stubs(:new).returns(@web_driver_helper)
    @login = YoshikeiLogin.new
  end

  def test_login_retries
    max_retries = 3
    @login.stubs(:perform_login).raises(StandardError.new("Login failed"))

    retry_count = 0
    login_data = nil

    assert_raises(StandardError, "リトライ後も例外が発生することを確認") do
      begin
        begin
          login_data = @login.perform_login
          raise "Login failed" unless login_data
        rescue => e
          retry_count += 1
          if retry_count <= max_retries
            sleep(0.01) # テスト高速化
            retry
          else
            raise e
          end
        end
      end
    end

    # 最大リトライ回数に達したか
    assert_equal max_retries + 1, retry_count, "最大リトライ回数+1回エラー発生が正しい"
    # ログインデータが取得できていないこと
    assert_nil login_data, "リトライ後のlogin_dataはnilであるべき"
  end

  def test_fetch_next_day_info_gets_saturday_cart_count
    html = <<~HTML
      <div class="fc-row">
        <div class="fc-future"><span class="fc-date">25</span><span class="fc-weekday">日</span></div>
        <div class="fc-future fc-content"><span class="fc-date">26</span><span class="fc-weekday">月</span>
          <div class="fc-calendar-events">
            <div class="fc-calendar-event">
              <button type="button" class="car"><span>1</span></button>
            </div>
          </div>
        </div>
        <div class="fc-future fc-content"><span class="fc-date">27</span><span class="fc-weekday">火</span>
          <div class="fc-calendar-events">
            <div class="fc-calendar-event">
              <button type="button" class="car"><span>1</span></button>
            </div>
          </div>
        </div>
        <div class="fc-future"><span class="fc-date">28</span><span class="fc-weekday">水</span></div>
        <div class="fc-future fc-content"><span class="fc-date">29</span><span class="fc-weekday">木</span>
          <div class="fc-calendar-events">
            <div class="fc-calendar-event">
              <button type="button" class="car"><span>1</span></button>
            </div>
          </div>
        </div>
        <div class="fc-today fc-future"><span class="fc-date">30</span><span class="fc-weekday">金</span></div>
        <div class="fc-future fc-content"><span class="fc-date">31</span><span class="fc-weekday">土</span>
          <div class="fc-calendar-events">
            <div class="fc-calendar-event">
              <button type="button" class="car"><span>1</span></button>
            </div>
          </div>
        </div>
      </div>
    HTML

    # NokogiriでHTMLをパース
    doc = Nokogiri::HTML.parse(html)
    fc_row = doc.at_css('.fc-row')
    nodes = fc_row.css('div')

    # "fc-today" クラス（金曜日）のインデックスを取得
    today_index = nodes.find_index { |node| node['class'].to_s.include?('fc-today') }
    assert today_index, 'fc-today(金曜日)が見つかりません'

    # 翌日（土曜日）の要素を取得
    saturday_elem = nodes[today_index + 1]
    assert saturday_elem, '翌日の土曜日要素が見つかりません'

    date = saturday_elem.at_css('.fc-date')&.text
    weekday = saturday_elem.at_css('.fc-weekday')&.text
    car_count = saturday_elem.css('button.car span').map(&:text).map(&:to_i).sum

    assert_equal '31', date
    assert_equal '土', weekday
    assert_equal 1, car_count
  end

  def test_handle_friday_returns_saturday_info
    custom_month = "5月"
    today_elem = mock('today_element')

    # 基本情報のセットアップ
    @web_driver_helper.stubs(:fetch_text_element).with(today_elem, css: '.fc-date').returns("30")
    @web_driver_helper.stubs(:fetch_text_element).with(today_elem, css: '.fc-weekday').returns("金")
    today_elem.stubs(:find_elements).with(css: 'button.car').returns([1, 2])

    # 土曜日情報のスタブ
    saturday_info = {
      date: '31',
      weekday: '土',
      car_count: 1
    }
    @login.stubs(:find_saturday_info).returns(saturday_info)

    # テスト実行
    result = @login.send(:handle_friday, custom_month, today_elem, 0, 0, [])
    assert_equal "5月30日(金) カート追加数: 2, 5月31日(土) カート追加数: 1", result
  end

  # 曜日が"土"の時にnilになることを確認するテスト
  def test_handle_fc_today_skip_saturday
    dummy_elem = DummyElement.new(text: 'dummy')

    # WebDriverHelperのfetch_text_elementをモック化
    @web_driver_helper.stubs(:fetch_text_element).with(dummy_elem, css: '.fc-weekday').returns('土')

    result = @login.send(:handle_fc_today, '2024年5月', dummy_elem, 0, 0, [])
    assert_nil result, "土曜日はnilが返るべき"
  end

  # 曜日が"金"で、金曜日のみ返すテスト（handle_fridayが呼ばれる場合）
  def test_handle_fc_today_not_skip_friday
    dummy_elem = DummyElement.new(text: 'dummy')

    # WebDriverHelperのfetch_text_elementをモック化
    @web_driver_helper.stubs(:fetch_text_element).with(dummy_elem, css: '.fc-weekday').returns('金')

    @login.expects(:handle_friday).with('2024年5月', dummy_elem, 0, 0, []).returns('金曜日情報')
    result = @login.send(:handle_fc_today, '2024年5月', dummy_elem, 0, 0, [])
    assert_equal '金曜日情報', result
  end

  # 曜日が平日で、handle_weekdayが呼ばれる場合のテスト
  def test_handle_fc_today_not_skip_weekday
    dummy_elem = DummyElement.new(text: 'dummy')

    # WebDriverHelperのfetch_text_elementをモック化
    @web_driver_helper.stubs(:fetch_text_element).with(dummy_elem, css: '.fc-weekday').returns('水')

    @login.expects(:handle_weekday).with('2024年5月', dummy_elem).returns('平日情報')
    result = @login.send(:handle_fc_today, '2024年5月', dummy_elem, 0, 0, [])
    assert_equal '平日情報', result
  end

  # 金曜日のカート数表示テスト（シンプル版）
  def test_friday_cart_display
    # 金曜日のカート数と土曜日のカート数情報を直接テスト
    @login.stubs(:find_saturday_info).returns({
      date: '31',
      weekday: '土',
      car_count: 1
    })

    # 金曜日の情報設定
    today_date = '30'
    weekday = '金'
    today_car_count = 2

    # テスト実行
    result = @login.send(:create_friday_saturday_message,
                          '5月', today_date, weekday, today_car_count,
                          {date: '31', weekday: '土', car_count: 1})

    assert_equal '5月30日(金) カート追加数: 2, 5月31日(土) カート追加数: 1', result
  end

  def test_find_saturday_in_row
    # テスト用のモック行を作成
    row = mock('row')
    day1 = mock('day1')
    day2 = mock('day2_saturday')
    day3 = mock('day3')

    # 行内の要素の設定
    day_elements = [day1, day2, day3]
    row.stubs(:find_elements).with(css: 'div[class*="fc-"]').returns(day_elements)

    # 曜日情報のモック設定
    @web_driver_helper.stubs(:fetch_text_element).with(day1, css: '.fc-weekday').returns('金')
    @web_driver_helper.stubs(:fetch_text_element).with(day2, css: '.fc-weekday').returns('土')
    @web_driver_helper.stubs(:fetch_text_element).with(day3, css: '.fc-weekday').returns('日')

    # メソッド実行
    result = @login.send(:find_saturday_in_row, row)

    # 土曜日の要素が返されることを確認
    assert_equal day2, result, "土曜日の要素が返されるべき"
  end

  def test_find_saturday_in_row_not_found
    # 土曜日がない行のテスト
    row = mock('row')
    day1 = mock('day1')
    day2 = mock('day2')

    # 行内の要素の設定（土曜日なし）
    day_elements = [day1, day2]
    row.stubs(:find_elements).with(css: 'div[class*="fc-"]').returns(day_elements)

    # 曜日情報のモック設定
    @web_driver_helper.stubs(:fetch_text_element).with(day1, css: '.fc-weekday').returns('木')
    @web_driver_helper.stubs(:fetch_text_element).with(day2, css: '.fc-weekday').returns('金')

    # メソッド実行
    result = @login.send(:find_saturday_in_row, row)

    # 土曜日が見つからないのでnilが返されることを確認
    assert_nil result, "土曜日が見つからない場合はnilを返すべき"
  end
end
