require "redis"

class Redis::Client
  
  # Provides backwards compatibility with Redis gem 2.2.x
  if !defined?(Redis::BaseError)
    require 'redis-sentinel/redis_compat'
  end
  
  DEFAULT_FAILOVER_RECONNECT_WAIT_SECONDS = 0.1
  DEFAULT_MASTER_DISCOVERY_ATTEMPTS = 2
  
  def initialize_with_sentinel(options = { })
    @master_name                = fetch_option(options, :master_name)
    @master_password            = fetch_option(options, :master_password)
    @sentinels                  = fetch_option(options, :sentinels)
    @failover_reconnect_timeout = fetch_option(options, :failover_reconnect_timeout)
    @failover_reconnect_wait    = fetch_option(options, :failover_reconnect_wait) ||
                                  DEFAULT_FAILOVER_RECONNECT_WAIT_SECONDS
    @master_discovery_attempts  = fetch_option(options, :master_discover_attempts) ||
                                  DEFAULT_MASTER_DISCOVERY_ATTEMPTS
    
    initialize_without_sentinel(options)
  end

  alias initialize_without_sentinel initialize
  alias initialize initialize_with_sentinel

  def connect_with_sentinel
    if sentinel?
      auto_retry_with_timeout do
        discover_master
        connect_without_sentinel
      end
    else
      connect_without_sentinel
    end
  end

  alias connect_without_sentinel connect
  alias connect connect_with_sentinel

  def sentinel?
    @master_name && @sentinels
  end

  def auto_retry_with_timeout(&block)
    deadline = @failover_reconnect_timeout.to_i + Time.now.to_f
    begin
      with_timeout(@failover_reconnect_timeout.to_f) do
        block.call
      end
    rescue Redis::CannotConnectError, Errno::ECONNREFUSED
      raise if Time.now.to_f > deadline
      sleep @failover_reconnect_wait
      retry
    rescue Timeout::Error
      raise Redis::TimeoutError.new("Timeout connecting to sentinels")
    end
  end

  def try_next_sentinel
    @sentinels << @sentinels.shift
    if @logger && @logger.debug?
      @logger.debug "Trying next sentinel: #{@sentinels[0][:host]}:#{@sentinels[0][:port]}"
    end
    return @sentinels[0]
  end

  def discover_master
    attempts = 0
    while true
      if attempts > (@master_discovery_attempts * @sentinels.length)
        is_down = 1
        break
      end
      
      attempts += 1
      sentinel = redis_sentinels[@sentinels[0]]

      begin
        host, port = sentinel.sentinel("get-master-addr-by-name", @master_name)
        if !host && !port
          raise Redis::ConnectionError.new("No master named: #{@master_name}")
        end
        is_down, runid = sentinel.sentinel("is-master-down-by-addr", host, port)
        break
      rescue Redis::CannotConnectError, Errno::ECONNREFUSED
        try_next_sentinel
      end
    end

    if is_down.to_s == "1" || runid == '?'
      raise Redis::CannotConnectError.new("The master: #{@master_name} is currently not available.")
    else
      change_connection_compat!(:host => host, :port => port.to_i, :password => @master_password)
    end
  end

  private
  
  def change_connection_compat!(opts)
    if @options # Newer Redis Gem
      @options.merge!(opts)
    else
      self.host     = opts[:host]
      self.port     = opts[:port]
      self.password = opts[:password]
    end
  end

  def fetch_option(options, key)
    options.delete(key) || options.delete(key.to_s)
  end

  def redis_sentinels
    @redis_sentinels ||= Hash.new do |hash, config|
      hash[config] = Redis.new(config)
    end
  end
  
  protected
  
  begin
    require "system_timer"

    def with_timeout(seconds, &block)
      SystemTimer.timeout_after(seconds, &block)
    end

  rescue LoadError
    if ! defined?(RUBY_ENGINE)
      # MRI 1.8, all other interpreters define RUBY_ENGINE, JRuby and
      # Rubinius should have no issues with timeout.
      warn "WARNING: using the built-in Timeout class which is known to have issues when used for opening connections. Install the SystemTimer gem if you want to make sure the Redis client will not hang."
    end

    require "timeout"

    def with_timeout(seconds, &block)
      Timeout.timeout(seconds, &block)
    end
  end
  
end
