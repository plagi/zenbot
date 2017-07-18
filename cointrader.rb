# encoding: UTF-8
require 'sqlite3'
require 'httparty'
require 'open3'
require 'daemons'
require 'logger'

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

  @bad_coins = ['REP-BTC', 'ZEC-BTC', 'BCN-BTC', 'CLAM-BTC']

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
    puts ">> Buying #{coin}"
    start = Time.now
    price = 0
    command = Thread.new do
      system "zenbot buy --order_adjust_time 20000  poloniex.#{coin} --pct 10"
      # Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        # puts "stdout is:" + stdout.read
        # price = stdout.read.match(/at (\d*\.?\d+) BTC/i).try(:captures).try(:last)
        # puts price
        # puts "stderr is:" + stderr.read
      # end
    end
    command.join
    puts "#{coin} bought"
    finish = Time.now
    diff = finish - start
  end

  def sell(coin)
    puts ">> Selling #{coin}"
    start = Time.now
    price = 0
    command = Thread.new do
      system "zenbot sell --order_adjust_time 20000  poloniex.#{coin}"
      # Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
        # puts "stdout is:" + stdout.read
        # price = stdout.read.match(/at (\d*\.?\d+) BTC/i).try(:captures).try(:last)
        # puts price
        # puts "stderr is:" + stderr.read
      # end
    end
    command.join
    puts "#{coin} sold"
    finish = Time.now
    diff = finish - start
  end
  
  loop do
    begin
  
      db = SQLite3::Database.new ":memory:"
      db.results_as_hash = true
  
      db.execute "CREATE TABLE gains (key, pct, dips)"
  
      puts "Loading first data"
      first_data = get_coin_data
      first_data.each do |coin, value|
        # puts coin, value
        pair = rename_coin(coin)
        if pair #&& !@bad_coins.any?{|bad_pair| pair == bad_pair }
          pct = value['last']
          volume = value['baseVolume'].to_f
          if (volume > MIN_VOLUME)
            # puts "#{pair}: #{pct}"
            db.execute "INSERT INTO gains VALUES ('#{pair}', #{pct}, NULL);"
          end
        end
      end
  
      puts "Sleeping #{TIMEOUT}"
      sleep(TIMEOUT)
      
      puts "Loading second data"
      data = get_coin_data
      data.each do |coin, value|
        # puts coin, value
        pair = rename_coin(coin)
        if pair #&& !@bad_coins.any?{|bad_pair| pair == bad_pair }
          pct = value['last']
          volume = value['baseVolume'].to_f
          if (volume > MIN_VOLUME) 
            begin
              puts "#{pair}: #{pct} : #{[first_data[coin]['last'], (value['last'].to_f - first_data[coin]['last'].to_f), ((value['last'].to_f - first_data[coin]['last'].to_f)/first_data[coin]['last'].to_f)*100.0 ] * "\t"}"
            
              db.execute "UPDATE gains SET dips = #{pct} WHERE key = '#{pair}';"
            rescue SQLite3::Exception => e 
              puts "Exception occurred"
              puts e
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
          puts "Old coin still good: #{@old_coin} dips #{new_dips} - #{@old_coin_dips} = #{new_dips - @old_coin_dips}"
          @new_coin = @old_coin
          @old_coin_dips = new_dips
        else
          puts "New coin is better: #{@old_coin} dips #{new_dips} - #{@old_coin_dips} = #{new_dips - @old_coin_dips}"
        end
      end
    
      puts "Percent: #{pct.to_f * 100}"
      puts "Action: #{@action}"
      time = 0
    
      if (@old_coin != @new_coin)
          
        puts "Prev_coin != new_coin, #{@old_coin != @new_coin}"
        if !!@old_coin
          puts "Prev_coin present"
        
          # sell prev coin
          if @action == 'sell'
            time = sell(@old_coin)
            @old_coin_dips = 0
            if time > 4*60
              @bad_coins.push(@old_coin) 
              puts "Adding BAD coin: #{@old_coin}"
            end
          end
        else
          puts "Initial run"
        end
      
        puts "new coin: #{@new_coin}"
        # buy new coin
        if @action == 'buy'
          time = buy(@new_coin) 
          @old_coin_dips = new_dips
          puts "old dips: #{@old_coin_dips}"
          if time > 4*60
            @bad_coins.push(@new_coin) 
            puts "Adding BAD coin: #{@new_coin}"
          end
        end
      
        if @action == 'buy'
          @action = 'sell'
        else 
          @action = 'buy' 
        end
        
      else
        puts "Still good: #{@new_coin}, #{@old_coin}"
      end
    
      puts "BAD COINS: #{@bad_coins * ", "}"
    
    rescue SQLite3::Exception => e 
    
        puts "Exception occurred"
        puts e
    
    ensure
        db.close if db
    end
  end
end