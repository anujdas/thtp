module ThriftHttp
  # A truly trivial pub/sub implementation for instrumentation. Note, NOT
  # threadsafe; make sure all subscribers are added before publishing anything.
  module PubSub
    def self.included(base)
      base.extend ClassMethods
      base.send :init_subscribers
    end

    # methods to be extended onto the including class on module inclusion
    module ClassMethods
      # Add listeners to be run in the order of subscription
      def subscribe(subscriber)
        @subscribers << subscriber
      end

      # If a subscriber raises an exception, any future ones won't run: this is
      # not considered a bug. Don't raise.
      def publish(event, *args)
        # freeze to prevent any subscriber changes after usage
        @subscribers.freeze.each { |l| l.send(event, *args) if l.respond_to?(event) }
      end

      private

      # create an independent subscriber list for each subclass
      def inherited(subclass)
        super
        subclass.send :init_subscribers
      end

      # set up subscribers array just once per class
      def init_subscribers
        @subscribers = []
      end
    end
  end
end
