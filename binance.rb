# encoding: UTF-8
require 'sqlite3'
require 'httparty'
require 'open3'
require 'daemons'
require 'logger'
require "timeout"

WORKING_DIRECTORY = Dir.pwd

# Daemons.run_proc('cointrader_runner.rb') do
  TIMEOUT = 2*60*60
  API_URL = 'https://api.binance.com/api/v1/ticker/24hr'
  MIN_VOLUME = 500
  ACTION_LOGGER = Logger.new(WORKING_DIRECTORY + '/actions.csv')
  TARGET_COIN = "BTC"
  PAPER = ''#'--paper'
  
  def get_coin_data
    response = HTTParty.get(API_URL,:verify => false)
    coindata = response.parsed_response
  end

  def rename_coin(coin, pair = 'BTC')
    if coin.end_with?(pair)
      coin_name = coin.split(pair).first
      pair_name = "#{coin_name}-#{pair}"
    end
  end

  def sell(coin)
    puts ">> Selling #{coin}"
    system "zenbot sell --order_adjust_time 20000  binance.#{coin}"
  end
  
  loop do
    # system "rm ./simulations/*.html"

    results = {}
    first_data = get_coin_data
    first_data.select {|coin| coin['symbol'].end_with?(TARGET_COIN )}.each do |coin|
      pair = rename_coin(coin['symbol'], TARGET_COIN )
      puts pair
      puts "value: #{coin["quoteVolume"]} > 500 #{calc = coin["quoteVolume"].to_f > MIN_VOLUME} "
      begin
        if calc
          system "zenbot backfill  binance.#{pair} --days 2"
          result = %x[zenbot sim binance.#{pair} --days 1 --max_sell_loss_pct=25]
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
      rescue Exception => e
        puts "Error in coin #{pair}: #{e.inspect}"
      end
    end
  
    puts results
    puts "WINNER: #{winner = results.sort {|a,b| b.last["end_balance"].to_f <=> a.last["end_balance"].to_f}.first}"
    ACTION_LOGGER.debug results.to_s
    coin = winner.first
    begin
      Timeout.timeout(TIMEOUT) do
          system "zenbot trade binance.#{coin} #{PAPER}"
      end
    rescue Timeout::Error
      puts ">> Timeout trading #{coin}"
      system "pkill -f binance"
    ensure
      sell(coin)
    end

  end
# end