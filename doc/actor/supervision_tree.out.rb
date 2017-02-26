
class Master < Concurrent::Actor::RestartingContext
  def initialize
    # create listener a supervised child of master
    @listener = Listener.spawn(name: 'listener1', supervise: true)
  end

  def on_message(msg)
    command, *args = msg
    case command
    when :listener
      @listener
    when :reset, :terminated, :resumed, :paused
      log(DEBUG) { " got #{msg} from #{envelope.sender}"}
    else
      pass
    end
  end

  # TODO this should be a part of a behaviour, it ensures that children are restarted/paused etc. when theirs parents are
  def on_event(event)
    event_name, _ = event
    case event_name
    when :resetting, :restarting
      @listener << :terminate!
    when Exception, :paused
      @listener << :pause!
    when :resumed
      @listener << :resume!
    end
  end
end 

class Listener < Concurrent::Actor::RestartingContext
  def initialize
    @number = (rand() * 100).to_i
  end

  def on_message(msg)
    case msg
    when :number
      @number
    else
      pass
    end
  end

end 

master   = Master.spawn(name: 'master', supervise: true)
    # => #<Concurrent::Actor::Reference:0x7fbedc05e5e0 /master (Master)>
listener = master.ask!(:listener)
    # => #<Concurrent::Actor::Reference:0x7fbedd86b840 /master/listener1 (Listener)>
listener.ask!(:number)                             # => 39
# crash the listener which is supervised by master, it's restarted automatically reporting a different number
listener.tell(:crash)
    # => #<Concurrent::Actor::Reference:0x7fbedd86b840 /master/listener1 (Listener)>
listener.ask!(:number)                             # => 73

master << :crash
    # => #<Concurrent::Actor::Reference:0x7fbedc05e5e0 /master (Master)>

sleep 0.1                                          # => 0

# ask for listener again, old one is terminated with master and replaced with new one
listener.ask!(:terminated?)                        # => true
listener = master.ask!(:listener)
    # => #<Concurrent::Actor::Reference:0x7fbedb929090 /master/listener1 (Listener)>
listener.ask!(:number)                             # => 72

master.ask!(:terminate!)                           # => true

sleep 0.1                                          # => 0
