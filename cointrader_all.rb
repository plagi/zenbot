# encoding: UTF-8
require 'sqlite3'
require 'httparty'
require 'open3'
require 'daemons'
require 'logger'
require "timeout"

WORKING_DIRECTORY = Dir.pwd

Daemons.run_proc('cointrader_runner.rb') do
  API_URL = 'https://poloniex.com/public?command=returnTicker&period=60'
  MIN_VOLUME = 100
  LOGGER = Logger.new(WORKING_DIRECTORY + '/results.log')

  
  @bad_coins = []

  def get_coin_data
    response = HTTParty.get(API_URL)
    coindata = response.parsed_response
  end

  def rename_coin(coin, pair = 'BTC')
    if coin.include?('BTC_')
      coin_name = coin.split("_").last
      pair_name = "#{coin_name}-#{pair}"
    end
  end

  def buy(coin)
    LOGGER.info ">> Started trading #{coin}"
    command = Thread.new do
      system "zenbot trade --strategy rsi --period 5m poloniex.#{coin} --pct 10"
    end
  end

  def sell(coin)
    LOGGER.info ">> Selling #{coin}"
    command = Thread.new do
      system "zenbot sell --order_adjust_time 30000  poloniex.#{coin}"
    end
  end
  
  LOGGER.info "Loading coins data"
  first_data = get_coin_data
  first_data.each do |coin, value|

    pair = rename_coin(coin)
    if pair
      pct = value['last']
      volume = value['baseVolume'].to_f
      sleep(200)
      if (volume > MIN_VOLUME)
        buy(coin)
      end
    end
  end

end