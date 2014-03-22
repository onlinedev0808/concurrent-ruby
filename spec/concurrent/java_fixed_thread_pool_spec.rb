require 'spec_helper'

if jruby?

  require_relative 'fixed_thread_pool_shared'

  module Concurrent

    describe JavaFixedThreadPool do

      subject { described_class.new(5) }

      after(:each) do
        subject.kill
        sleep(0.1)
      end

      it_should_behave_like :fixed_thread_pool
    end
  end
end
