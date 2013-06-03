# Ripped from https://github.com/redis/redis-rb's lib/redis/errors.rb file

class Redis
  # Base error for all redis-rb errors.
  class BaseError < RuntimeError
  end

  # Raised by the client when command execution returns an error reply.
  class CommandError < Redis::BaseError
  end

  # Base error for connection related errors.
  class BaseConnectionError < Redis::BaseError
  end

  # Raised when connection to a Redis server cannot be made.
  class CannotConnectError < Redis::BaseConnectionError
  end

  # Raised when connection to a Redis server is lost.
  class ConnectionError < Redis::BaseConnectionError
  end

  # Raised when performing I/O times out.
  class TimeoutError < Redis::BaseConnectionError
  end

  # Raised when the connection was inherited by a child process.
  class InheritedError < Redis::BaseConnectionError
  end
end