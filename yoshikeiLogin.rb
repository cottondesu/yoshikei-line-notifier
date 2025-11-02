# frozen_string_literal: true
require 'selenium-webdriver'
require 'webdrivers'
require 'dotenv/load'

class WebDriverHelper
  CHROME_OPTIONS = %w[--headless --disable-gpu --no-sandbox --disable-dev-shm-usage].freeze

  def with_driver(&block)
    options = Selenium::WebDriver::Chrome::Options.new
    CHROME_OPTIONS.each { |opt| options.add_argument(opt) }
    Selenium::WebDriver::Chrome::Service.driver_path = ENV.fetch('CHROMEDRIVER_PATH')
    options.binary = ENV.fetch('GOOGLE_CHROME_BIN')
    driver = Selenium::WebDriver.for :chrome, options: options

    yield(driver)
  ensure
    driver&.quit
  end

  def fill_field(driver, by, field_name, value)
    field = driver.find_element(by, field_name)
    field.clear
    field.send_keys(value)
  rescue Selenium::WebDriver::Error::NoSuchElementError => e
    raise "フィールドが見つかりません (#{field_name}): #{e.message}"
  end

  def click_button(driver, selector)
    button = driver.find_element(:css, selector)
    button.click
  rescue Selenium::WebDriver::Error::NoSuchElementError => e
    raise "ボタンが見つかりません (#{selector}): #{e.message}"
  end

  def wait_for_page_load(driver)
    Selenium::WebDriver::Wait.new(timeout: 30).until do
      driver.execute_script("return document.readyState") == "complete"
    end
  end

  def element_present?(driver, by, identifier)
    element = driver.find_element(by, identifier)
    element.displayed?
  rescue Selenium::WebDriver::Error::NoSuchElementError
    false
  end

  def fetch_text_element(parent_elem, selector)
    by, value = selector.first
    element = parent_elem.find_element(by, value)

    # まず通常の text で取得を試行
    text_result = element.text.strip

    # 空の場合（非表示要素など）は textContent で取得
    if text_result.empty?
      text_result = element.attribute('textContent').to_s.strip
      puts "[デバッグ] 非表示要素のため textContent で取得: '#{text_result}'"
    end

    text_result
  rescue Selenium::WebDriver::Error::NoSuchElementError => e
    puts "[デバッグ] 指定セレクタ #{selector.inspect} で要素が見つかりません: #{e.message}"
    ""
  rescue => e
    puts "[デバッグ] 予期しないエラー: #{e.class}: #{e.message}"
    ""
  end
end

class YoshikeiLogin
  def initialize
    @web_driver_helper = WebDriverHelper.new
  end

  def perform_login
    @web_driver_helper.with_driver do |driver|
      login_to_yoshikei(driver)
      fetch_today_text(driver)
    rescue Selenium::WebDriver::Error::TimeoutError => e
      puts "待機によるタイムアウトが発生しました: #{e.message}"
    rescue Selenium::WebDriver::Error::NoSuchElementError => e
      puts "指定された要素が見つかりません: #{e.message}"
    rescue => e
      puts "エラーが発生しました: #{e.message}"
    end
  end

  private

  def login_to_yoshikei(driver)
    driver.navigate.to ENV['LOGIN_URL']

    # 明示的な待機を設定
    wait = Selenium::WebDriver::Wait.new(timeout: 30)
    wait.until { driver.execute_script("return document.readyState") == "complete" }

    # 要素が利用可能になるまで待機と表示チェック
    wait.until { @web_driver_helper.element_present?(driver, :name, 'login_cd') }
    wait.until { @web_driver_helper.element_present?(driver, :name, 'login_pwd') }

    # 入力フィールドにデータを入力
    @web_driver_helper.fill_field(driver, :name, 'login_cd', ENV['YOSHIKEI_USERNAME'])
    @web_driver_helper.fill_field(driver, :name, 'login_pwd', ENV['YOSHIKEI_PASSWORD'])

    # ボタンが表示され、クリック可能になるまで待機
    wait.until { @web_driver_helper.element_present?(driver, :css, '.btn-column-wrap .main-- button') }
    @web_driver_helper.click_button(driver, '.btn-column-wrap .main-- button')
  end

  def fetch_today_text(driver)
    @web_driver_helper.wait_for_page_load(driver)

    custom_month = @web_driver_helper.fetch_text_element(driver, id: 'custom-month')
    fc_rows = driver.find_element(class: 'fc-body').find_elements(class: 'fc-row')

    fc_rows.each_with_index do |row, row_index|
      row.find_elements(class: 'fc-today').each_with_index do |fc_today_elem, elem_index|
        result = handle_fc_today(custom_month, fc_today_elem, row_index, elem_index, fc_rows)
        return result if result
      end
    end
    ''

  rescue Selenium::WebDriver::Error::NoSuchElementError => e
    puts "カレンダー要素が見つかりません: #{e.message}"
    ''
  end

  def handle_fc_today(custom_month, fc_today_elem, row_index, elem_index, fc_rows)
    weekday = @web_driver_helper.fetch_text_element(fc_today_elem, css: '.fc-weekday')
    return nil if %w[土 日].include?(weekday) # 土曜・日曜の場合はスキップ

    if weekday == '金'
      handle_friday(custom_month, fc_today_elem, row_index, elem_index, fc_rows)
    else
      handle_weekday(custom_month, fc_today_elem)
    end
  end



  def handle_friday(custom_month, fc_today_elem, row_index, elem_index, fc_rows)
    # 金曜日の情報取得
    weekday = @web_driver_helper.fetch_text_element(fc_today_elem, css: '.fc-weekday')
    today_fc_date = @web_driver_helper.fetch_text_element(fc_today_elem, css: '.fc-date')
    today_car_count = fc_today_elem.find_elements(css: 'button.car').size

    puts "[デバッグ] 金曜日情報 - 日付: #{today_fc_date}, 曜日: #{weekday}, カート数: #{today_car_count}"

    # 土曜日の要素と情報を取得
    saturday_info = find_saturday_info(fc_rows, row_index, elem_index)

    # メッセージ作成
    create_friday_saturday_message(custom_month, today_fc_date, weekday, today_car_count, saturday_info)
  end

  def find_saturday_info(fc_rows, row_index, elem_index)
    return {} unless fc_rows && fc_rows[row_index]

    begin
      # 現在の行で土曜日を探す
      saturday_elem = find_saturday_in_row(fc_rows[row_index])

      # 見つからなければ次の行を確認
      if !saturday_elem && row_index + 1 < fc_rows.size
        puts "[デバッグ] 現在の行に土曜日なし、次の行を確認"
        saturday_elem = find_saturday_in_row(fc_rows[row_index + 1])
      end

      # 土曜日情報を返す
      if saturday_elem
        saturday_weekday = @web_driver_helper.fetch_text_element(saturday_elem, css: '.fc-weekday')
        saturday_date = @web_driver_helper.fetch_text_element(saturday_elem, css: '.fc-date')
        saturday_car_count = saturday_elem.find_elements(css: 'button.car').size
        puts "[デバッグ] 土曜日情報 - 日付: #{saturday_date}, 曜日: #{saturday_weekday}, カート数: #{saturday_car_count}"

        return {
          date: saturday_date,
          weekday: saturday_weekday,
          car_count: saturday_car_count
        }
      end
    rescue => e
      puts "[デバッグ] 土曜日要素の取得でエラー: #{e.message}"
    end

    # 土曜日が見つからなかった場合
    puts "[デバッグ] 土曜日が見つかりませんでした"
    {}
  end

  def find_saturday_in_row(row)
    day_elements = row.find_elements(css: 'div[class*="fc-"]')
    puts "[デバッグ] 行内の要素数: #{day_elements.size}"

    day_elements.each_with_index do |elem, idx|
      elem_weekday = @web_driver_helper.fetch_text_element(elem, css: '.fc-weekday')
      if elem_weekday == '土'
        puts "[デバッグ] 土曜日を発見: インデックス#{idx}"
        return elem
      end
    end
    nil
  end

  def create_friday_saturday_message(custom_month, today_date, weekday, today_car_count, saturday_info)
    # デフォルト値の設定
    today_car_count ||= 0
    saturday_car_count = saturday_info[:car_count] || 0

    puts "[デバッグ] カート数確認 - 金曜日: #{today_car_count}, 土曜日: #{saturday_car_count}"

    # 両方とも0の場合は空文字を返す
    if today_car_count == 0 && saturday_car_count == 0
      puts "[デバッグ] 金曜日・土曜日ともにカート数0のため、空文字を返します"
      return ''
    end

    results = []

    # 金曜日の情報（カート数が0より大きい場合のみ）
    if today_car_count > 0
      results << "#{custom_month}#{today_date}日(#{weekday}) カート追加数: #{today_car_count}"
    end

    # 土曜日の情報があれば追加（カート数が0より大きい場合のみ）
    if saturday_info[:date] && saturday_car_count > 0
      results << "#{custom_month}#{saturday_info[:date]}日(#{saturday_info[:weekday]}) カート追加数: #{saturday_car_count}"
    end

    result_text = results.join(', ')
    puts "[デバッグ] 金曜日処理の最終結果: '#{result_text}'"

    result_text
  end

  def handle_weekday(custom_month, fc_today_elem)
    weekday = @web_driver_helper.fetch_text_element(fc_today_elem, css: '.fc-weekday')
    car_buttons = fc_today_elem.find_elements(css: 'button.car')
    return nil if car_buttons.empty?

    fc_date = @web_driver_helper.fetch_text_element(fc_today_elem, css: '.fc-date')
    car_button_text = car_buttons.first.find_element(tag_name: 'span').text
    "#{custom_month}#{fc_date}日(#{weekday}) カート追加数: #{car_button_text}"
  end

  def fetch_next_day_info(fc_rows, row_index, elem_index)
    next_day_elem = find_next_day(fc_rows, row_index, elem_index)
    return nil unless next_day_elem

    next_day_date = @web_driver_helper.fetch_text_element(next_day_elem, css: '.fc-date')
    next_day_car_count = next_day_elem.find_elements(css: 'button.car').size
    [next_day_date, next_day_car_count]
  end

  def find_next_day(fc_rows, row_index, elem_index)
    next_day_row = fc_rows[row_index + 1] if row_index + 1 < fc_rows.size
    next_day_elements = next_day_row&.find_elements(css: '.fc-day') || []
    next_day_elements[elem_index] if elem_index < next_day_elements.size
  end
end
