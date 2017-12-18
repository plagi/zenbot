# encoding: UTF-8
require 'sqlite3'
require 'httparty'
require 'open3'
require 'daemons'
require 'logger'
require "timeout"

WORKING_DIRECTORY = Dir.pwd
API_URL = 'https://poloniex.com/public?command=returnTicker&period=60'
MIN_VOLUME = 500.0

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

system "rm ./simulations/*.html"

results = {}
  
first_data = get_coin_data
first_data.each do |coin, value|
  puts coin, value
  puts "value: #{value["baseVolume"]} > 500 #{calc = value["baseVolume"].to_f > MIN_VOLUME} "
  pair = rename_coin(coin)
  if calc
    result = %x[zenbot backfill  poloniex.#{pair} --days 2]
    puts result
    result = %x[zenbot sim poloniex.#{pair} --days 1]
    file = result.split("\n").last.split(" ").last
    results[pair] = {}
    buy_hold = false
    File.open(file).each do |line|
      if line.include?("end balance")
        results[pair]["end_balance"] = line.split(" ")[2].to_f
        results[pair]["end_balance%"] = line.scan(/\(([^)]+)\)/).flatten.first.to_f
      elsif line.include?("buy hold")
        if buy_hold == false
          results[pair]["buy_hold"] = line.split(" ")[2].to_f
          results[pair]["buy_hold%"] = line.scan(/\(([^)]+)\)/).flatten.first.to_f
          results[pair]["vs_buy_hold%"] = (1 - results[pair]["end_balance"].to_f / results[pair]["buy_hold"].to_f)*100.0
          buy_hold = true
        end
      end
    end
    puts results[pair]
  end
end

puts results
