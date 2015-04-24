require 'concurrent/ivar'

module Concurrent
  module Channel

    Probe = IVar

    def self.select(*channels)
      probe = Probe.new
      channels.each { |channel| channel.select(probe) }
      result = probe.value
      channels.each { |channel| channel.remove_probe(probe) }
      result
    end
  end
end
