module EventedSpec
  module SpecHelper

    # Represents example running inside some type of event loop
    class EventedExample

      # Create new evented example
      def initialize(opts, example_group_instance, &block)
        @opts, @example_group_instance, @block = opts, example_group_instance, block
      end

      # Sets timeout for currently running example
      #
      def timeout(spec_timeout)
        EM.cancel_timer(@spec_timer) if @spec_timer
        @spec_timer = EM.add_timer(spec_timeout) do
          @spec_exception = SpecTimeoutExceededError.new "Example timed out"
          done
        end
      end

      # Breaks the event loop and finishes the spec.
      #
      # This is under-implemented (generic) method that only implements optional delay.
      # It should be given a block that does actual work of finishing up the event loop
      # and cleaning any remaining artifacts.
      #
      # Please redefine it inside descendant class and call super.
      #
      def done(delay=nil, &block)
        if delay
          EM.add_timer delay, &block
        else
          block.call
        end
      end

      # Runs hooks of specified type (hopefully, inside the event loop)
      #
      def run_em_hooks(type)
        @example_group_instance.class.em_hooks[type].each do |hook|
          @example_group_instance.instance_eval(&hook) #_with_rescue(&hook)
        end
      end

      # Runs given block inside EM event loop.
      # Double-round exception handler needed because some of the exceptions bubble
      # outside of event loop due to asynchronous nature of evented examples
      #
      def run_em_loop
        begin
          EM.run do
            run_em_hooks :em_before

            @spec_exception = nil
            timeout(@opts[:spec_timeout]) if @opts[:spec_timeout]
            begin
              yield
            rescue Exception => @spec_exception
              # p "Inside loop, caught #{@spec_exception.class.name}: #{@spec_exception}"
              done # We need to properly terminate the event loop
            end
          end
        rescue Exception => @spec_exception
          # p "Outside loop, caught #{@spec_exception.class.name}: #{@spec_exception}"
          run_em_hooks :em_after # Event loop broken, but we still need to run em_after hooks
        ensure
          finish_example
        end
      end

      # Stops EM event loop. It is called from #done
      #
      def finish_em_loop
        run_em_hooks :em_after
        EM.stop_event_loop if EM.reactor_running?
      end

      # Called from #run_event_loop when event loop is stopped,
      # but before the example returns.
      # Descendant classes may redefine to clean up type-specific state.
      #
      def finish_example
        raise @spec_exception if @spec_exception
      end

    end # class EventedExample


    # Represents spec running inside EM.run loop
    class EMExample < EventedExample

      # Run @block inside the EM.run event loop
      def run
        run_em_loop do
          @example_group_instance.instance_eval(&@block)
        end
      end

      # Breaks the EM event loop and finishes the spec.
      # Done yields to any given block first, then stops EM event loop.
      #
      def done(delay = nil)
        super(delay) do
          yield if block_given?
          EM.next_tick do
            finish_em_loop
          end
        end
      end # done
    end # class EMExample < EventedExample


    # Represents spec running inside AMQP.start loop
    class AMQPExample < EventedExample

      # Run @block inside the AMQP.start loop
      def run
        run_em_loop do
          AMQP.start_connection(@opts) do
            run_em_hooks :amqp_before
            @example_group_instance.instance_eval(&@block)
          end
        end
      end

      # Breaks the event loop and finishes the spec. It yields to any given block first,
      # then stops AMQP, EM event loop and cleans up AMQP state.
      #
      def done(delay = nil)
        super(delay) do
          yield if block_given?
          EM.next_tick do
            run_em_hooks :amqp_after
            if AMQP.conn && !AMQP.closing?
              AMQP.stop_connection do
                # Cannot call finish_em_loop before connection is marked as closed
                # This callback is called before that happens.
                EM.next_tick { finish_em_loop }
              end
            else
              # Need this branch because if AMQP couldn't connect,
              # the callback would never trigger
              AMQP.cleanup_state
              EM.next_tick { finish_em_loop }
            end
          end
        end
      end

      # Called from run_event_loop when event loop is finished, before any exceptions
      # is raised or example returns. We ensure AMQP state cleanup here.
      def finish_example
        AMQP.cleanup_state
        super
      end

    end # class AMQPExample < EventedExample
  end # module SpecHelper
end # module AMQP
