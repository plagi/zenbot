var z = require('zero-fill')
  , n = require('numbro')

module.exports = function container (get, set, clear) {
  return {
    name: 'macd',
    description: 'Buy when (MACD - Signal > 0) and sell when (MACD - Signal < 0).',

    getOptions: function () {
      this.option('period', 'period length, same as --periodLength', String, '1h')
      this.option('periodLength', 'period length, same as --period', String, '1h')
      this.option('min_periods', 'min. number of history periods', Number, 52)
      this.option('ema_short_period', 'number of periods for the shorter EMA', Number, 12)
      this.option('ema_long_period', 'number of periods for the longer EMA', Number, 26)
      this.option('signal_period', 'number of periods for the signal EMA', Number, 3)
      this.option('up_trend_threshold', 'threshold to trigger a buy signal', Number, 0)
      this.option('down_trend_threshold', 'threshold to trigger a sold signal', Number, 0)
      this.option('overbought_rsi_periods', 'number of periods for overbought RSI', Number, 25)
      this.option('overbought_rsi', 'sold when RSI exceeds this value', Number, 62)
    },

    calculate: function (s) {
      if (s.options.overbought_rsi) {
        // sync RSI display with overbought RSI periods
        s.options.rsi_periods = s.options.overbought_rsi_periods
        get('lib.rsi')(s, 'overbought_rsi', s.options.overbought_rsi_periods)
        if (!s.in_preroll && s.period.overbought_rsi >= s.options.overbought_rsi && !s.overbought) {
          s.overbought = true
          if (s.options.mode === 'sim' && s.options.verbose) console.log(('\noverbought at ' + s.period.overbought_rsi + ' RSI, preparing to sold\n').cyan)
        }
      }

      // compture MACD
      get('lib.ema')(s, 'ema_short', s.options.ema_short_period)
      get('lib.ema')(s, 'ema_long', s.options.ema_long_period)
      if (s.period.ema_short && s.period.ema_long) {
        s.period.macd = (s.period.ema_short - s.period.ema_long)
        get('lib.ema')(s, 'signal', s.options.signal_period, 'macd')
        if (s.period.signal) {
          s.period.macd_histogram = s.period.macd - s.period.signal
        }
      }
      
      // save 
      if (typeof s.period.macd_max === 'undefined') {
        s.period.macd_max = s.period.macd_histogram
      }
      if (typeof s.period.macd_min === 'undefined') {
        s.period.macd_min = s.period.macd_histogram
      }
      
      // when our current price is higher than what we recorded, overwrite
      if (s.period.macd_histogram > s.period.macd_max) {
        s.period.macd_max = s.period.macd_histogram
      }

      // when our current price is lower than what we recorded, overwrite
      if (s.period.macd_histogram  < s.period.macd_min ) {
        s.period.macd_min = s.period.macd_histogram
      }

},

    onPeriod: function (s, cb) {
      if (!s.in_preroll && typeof s.period.overbought_rsi === 'number') {
        if (s.overbought) {
          s.overbought = false
          s.trend = 'overbought'
          s.signal = 'sell'
          return cb()
        }
      }

      if (typeof s.period.macd_histogram === 'number' && typeof s.lookback[0].macd_histogram === 'number') {
        if ((s.period.macd_histogram - s.options.up_trend_threshold) > 0 && (s.lookback[0].macd_histogram - s.options.up_trend_threshold) <= 0) {
          s.trend = 'down';
        s.signal = 'sell'
        } else if ((s.period.macd_histogram + s.options.down_trend_threshold) < 0 && (s.lookback[0].macd_histogram + s.options.down_trend_threshold) >= 0) {
          s.trend = 'up';
          s.signal = 'buy'
        } else {
          s.signal = null;  // hold
        }
      }
      
      if ( (typeof s.period.macd_max === 'number' && typeof s.lookback[0].macd_max === 'number') && 
      (typeof s.period.macd_min === 'number' && typeof s.lookback[0].macd_min === 'number') ){
        if((s.period.macd_max > 0 ) && (s.lookback[0].macd_max > 0) && (s.period.macd_max < s.lookback[0].macd_max) && (s.trend == 'up')){
          s.trend = null
        } else if ((s.period.macd_min < 0 ) && (s.lookback[0].macd_min < 0) && (s.period.macd_min > s.lookback[0].macd_min) && (s.trend == 'down')){
          s.trend = null
        }
      }
      
      cb()
    },

    onReport: function (s) {
      var cols = []
      if (typeof s.period.macd_histogram === 'number') {
        var color = 'grey'
        if (s.period.macd_histogram > 0) {
          color = 'green'
        }
        else if (s.period.macd_histogram < 0) {
          color = 'red'
        }
        cols.push(z(8, n(s.period.macd_histogram).format('+00.0000'), ' ')[color])
        cols.push(z(8, n(s.period.overbought_rsi).format('00'), ' ').cyan)
        cols.push(z(8, n(s.period.macd_min).format('+00.0000'), ' ').grey)
        cols.push(z(8, n(s.period.macd_max).format('+00.0000'), ' ').grey)
      }
      else {
        cols.push('         ')
      }
      return cols
    }
  }
}