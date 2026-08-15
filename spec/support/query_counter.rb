# Counts the queries a block actually sends, so a spec can hold a page to a
# fixed number of them rather than to the shape of the code that builds them.
module QueryCounter
  # The connection's own bookkeeping — reading the schema, opening and closing
  # a transaction — is not work the page asked for, and the transactional
  # fixtures put a pair of them around every example.
  BOOKKEEPING = %w[SCHEMA TRANSACTION].freeze

  def count_queries
    counted = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      counted += 1 if counts?(event.payload)
    end

    yield

    counted
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  # A cached query is answered without going to the database, so counting it
  # would let a page hide an N+1 behind the query cache.
  def counts?(payload)
    BOOKKEEPING.exclude?(payload[:name]) && !payload[:cached]
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
