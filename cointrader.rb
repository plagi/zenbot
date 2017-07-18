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
  TIMEOUT = 50
  MIN_VOLUME = 100
  LOGGER = Logger.new(WORKING_DIRECTORY + '/results.log')
  @old_coin = nil
  @old_coin_dips = nil
  @new_coin = nil
  @action = 'buy'
  
  @bad_coins = ['REP-BTC', 'ZEC-BTC', 'BCN-BTC', 'CLAM-BTC', 'LSK-BTC', 'LBC-BTC', 'ARDR-BTC', 'DOGE-BTC', 'FCT-BTC', 'STEEM-BTC', 'GAME-BTC']

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
    LOGGER.info ">> Buying #{coin}"
    start = Time.now
    price = 0
    Timeout.timeout(10*60) do
      # command = Thread.new do
        system "zenbot buy --order_adjust_time 20000  poloniex.#{coin} --pct 10"
        # Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
          # LOGGER.info "stdout is:" + stdout.read
          # price = stdout.read.match(/at (\d*\.?\d+) BTC/i).try(:captures).try(:last)
          # LOGGER.info price
          # LOGGER.info "stderr is:" + stderr.read
        # end
      end
      # command.join
      LOGGER.info "#{coin} bought"
    rescue Timeout::Error
      LOGGER.info ">> Timeout buying #{coin}"
    end
    
    finish = Time.now
    diff = finish - start
  end

  def sell(coin)
    LOGGER.info ">> Selling #{coin}"
    start = Time.now
    price = 0
    Timeout.timeout(10*60) do
    # command = Thread.new do
      system "zenbot sell --order_adjust_time 20000  poloniex.#{coin}"
      # Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        # LOGGER.info "stdout is:" + stdout.read
        # price = stdout.read.match(/at (\d*\.?\d+) BTC/i).try(:captures).try(:last)
        # LOGGER.info price
        # LOGGER.info "stderr is:" + stderr.read
      # end
    # end
    # command.join
    LOGGER.info "#{coin} sold"
    rescue Timeout::Error
      LOGGER.info ">> Timeout selling #{coin}"
    end
    finish = Time.now
    diff = finish - start
  end
  
  loop do
    begin
  
      db = SQLite3::Database.new ":memory:"
      db.results_as_hash = true
  
      db.execute "CREATE TABLE gains (key, pct, dips)"
  
      LOGGER.info "Loading first data"
      first_data = get_coin_data
      first_data.each do |coin, value|
        # LOGGER.info coin, value
        pair = rename_coin(coin)
        if pair #&& !@bad_coins.any?{|bad_pair| pair == bad_pair }
          pct = value['last']
          volume = value['baseVolume'].to_f
          if (volume > MIN_VOLUME)
            # LOGGER.info "#{pair}: #{pct}"
            db.execute "INSERT INTO gains VALUES ('#{pair}', #{pct}, NULL);"
          end
        end
      end
  
      LOGGER.info "Sleeping #{TIMEOUT}"
      sleep(TIMEOUT)
      
      LOGGER.info "Loading second data"
      data = get_coin_data
      data.each do |coin, value|
        # LOGGER.info coin, value
        pair = rename_coin(coin)
        if pair #&& !@bad_coins.any?{|bad_pair| pair == bad_pair }
          pct = value['last']
          volume = value['baseVolume'].to_f
          if (volume > MIN_VOLUME) 
            begin
              LOGGER.info "#{pair}: #{pct} : #{[first_data[coin]['last'], (value['last'].to_f - first_data[coin]['last'].to_f), ((value['last'].to_f - first_data[coin]['last'].to_f)/first_data[coin]['last'].to_f)*100.0 ] * "\t"}"
            
              db.execute "UPDATE gains SET dips = #{pct} WHERE key = '#{pair}';"
            rescue SQLite3::Exception => e 
              LOGGER.info "Exception occurred"
              LOGGER.info e
            end
          end
        end
      end
  
      #get coin
      res = db.execute("SELECT key,( (dips-pct)/pct) as diff , dips FROM gains WHERE key not in (#{@bad_coins.map{|c| "'#{c}'"} * ", "}) ORDER BY diff DESC LIMIT 1;").first
      @old_coin = @new_coin
      @new_coin = res['key']
      new_dips = res['dips'].to_f
      pct = res['diff']
    
      if !!@old_coin && @old_coin_dips > 0.00000001
        new_dips = db.execute("SELECT key, dips FROM gains WHERE key='#{@old_coin}';").first['dips'].to_f
        if (new_dips - @old_coin_dips > 0.00000001)
          LOGGER.info "Old coin still good: #{@old_coin} dips #{new_dips} - #{@old_coin_dips} = #{new_dips - @old_coin_dips}"
          @new_coin = @old_coin
          @old_coin_dips = new_dips
        else
          LOGGER.info "New coin is better: #{@old_coin} dips #{new_dips} - #{@old_coin_dips} = #{new_dips - @old_coin_dips}"
        end
      end
    
      LOGGER.info "Percent: #{pct.to_f * 100}"
      LOGGER.info "Action: #{@action}"
      time = 0
    
      if (@old_coin != @new_coin)
          
        LOGGER.info "Prev_coin != new_coin, #{@old_coin != @new_coin}"
        if !!@old_coin
          LOGGER.info "Prev_coin present"
        
          # sell prev coin
          if @action == 'sell'
            time = sell(@old_coin)
            @old_coin_dips = 0
            if time > 4*60
              @bad_coins.push(@old_coin) 
              LOGGER.info "Adding BAD coin: #{@old_coin}"
            end
          end
        else
          LOGGER.info "Initial run"
        end
      
        LOGGER.info "new coin: #{@new_coin}"
        # buy new coin
        if @action == 'buy'
          time = buy(@new_coin) 
          @old_coin_dips = new_dips
          LOGGER.info "old dips: #{@old_coin_dips}"
          if time > 4*60
            @bad_coins.push(@new_coin) 
            LOGGER.info "Adding BAD coin: #{@new_coin}"
          end
        end
      
        if @action == 'buy'
          @action = 'sell'
        else 
          @action = 'buy' 
        end
        
      else
        LOGGER.info "Still good: #{@new_coin}, #{@old_coin}"
      end
    
      LOGGER.info "BAD COINS: #{@bad_coins * ", "}"
    
    rescue SQLite3::Exception => e 
    
        LOGGER.info "Exception occurred"
        LOGGER.info e
    
    ensure
        db.close if db
    end
  end
end