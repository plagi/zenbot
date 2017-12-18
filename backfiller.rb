# encoding: UTF-8
require 'sqlite3'
require 'httparty'
require 'open3'
require 'daemons'
require 'logger'
require "timeout"

WORKING_DIRECTORY = Dir.pwd

# Daemons.run_proc('cointrader_runner.rb') do
  TIMEOUT = 5*60
  API_URL = 'https://poloniex.com/public?command=returnTicker&period=60'
  MIN_VOLUME = 500.0
  ACTION_LOGGER = Logger.new(WORKING_DIRECTORY + '/actions.csv')

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

  def sell(coin)
    LOGGER.info ">> Selling #{coin}"
    system "zenbot sell --order_adjust_time 20000  poloniex.#{coin}"
  end

  loop do
    system "rm ./simulations/*.html"

    results = {}
    first_data = get_coin_data
    first_data.select {|coin| coin.include?('BTC_')}.each do |coin, value|
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
              results[pair]["vs_buy_hold%"] = (1 -  results[pair]["buy_hold"].to_f / results[pair]["end_balance"].to_f)*100.0
              buy_hold = true
            end
          end
        end
        puts results[pair]
      end
    end
  
    Timeout.timeout(TIMEOUT) do
      puts results
      puts "WINNER: #{winner = results.sort {|a,b| b.last["end_balance"].to_f <=> a.last["end_balance"].to_f}.first}"
      ACTION_LOGGER.debug results.to_s
      coin = winner.first
      system("zenbot trade poloniex.#{coin}")
    rescue Timeout::Error
      puts ">> Timeout trading #{coin}"
      sell(coin)
    end
  end
# end