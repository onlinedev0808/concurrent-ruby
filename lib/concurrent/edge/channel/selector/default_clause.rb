require 'concurrent/maybe'

module Concurrent
  module Edge
    class Channel
      class Selector

        class DefaultClause

          def initialize(block)
            @block = block
          end

          def execute
            Concurrent::Maybe.just(@block.call)
          end
        end
      end
    end
  end
end
