module ThriftHttp
  # A truly trivial pub/sub implementation for instrumentation. Note, NOT
  # threadsafe; make sure all subscribers are added before publishing anything.
  module PubSub
    # Add listeners to be run in the order of subscription
    def subscribe(subscriber)
      subscribers << subscriber
    end

    private

    # If a subscriber raises an exception, any future ones won't run: this is
    # not considered a bug. Don't raise.
    def publish(event, *args)
      # freeze to prevent any subscriber changes after usage
      subscribers.freeze.each { |l| l.send(event, *args) if l.respond_to?(event) }
    end

    def subscribers
      @subscribers ||= []
    end
  end
end
