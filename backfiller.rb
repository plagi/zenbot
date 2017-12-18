# encoding: UTF-8
require 'sqlite3'
require 'httparty'
require 'open3'
require 'daemons'
require 'logger'
require "timeout"

WORKING_DIRECTORY = Dir.pwd


  API_URL = 'https://poloniex.com/public?command=returnTicker&period=60'
  TIMEOUT = 50
  ACTION_TIMEOUT = {"buy" => 10, "sell" =>  150}
  MIN_VOLUME = 100
  LOGGER = Logger.new(WORKING_DIRECTORY + '/results.log')
  ACTION_LOGGER = Logger.new(WORKING_DIRECTORY + '/actions.csv')
  @old_coin = nil
  @old_coin_dips = nil
  @new_coin = nil
  @action = 'buy'
  
  @bad_coins = []#['REP-BTC', 'ZEC-BTC', 'BCN-BTC', 'CLAM-BTC', 'LSK-BTC', 'LBC-BTC', 'ARDR-BTC', 'DOGE-BTC', 'FCT-BTC', 'STEEM-BTC', 'GAME-BTC', 'GNT-BTC']

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

first_data = get_coin_data
first_data.each do |coin, value|
  puts coin, value
  puts "value: #{value["baseVolume"]} > 500 #{value["baseVolume"] > 500} "
  pair = rename_coin(coin)
  system "zenbot backfill  poloniex.#{pair} --days 2"
  system "zenbot sim poloniex.#{pair} --days 2"  
end
