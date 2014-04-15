require 'spec_helper'
require_relative 'global_thread_pool_shared'

module Concurrent

  describe PerThreadExecutor do

    subject { PerThreadExecutor.new }

    it_should_behave_like :global_thread_pool

    context '#post' do

      it 'creates a new thread for a call without arguments' do
        thread = Thread.new{ nil }
        Thread.should_receive(:new).with(no_args()).and_return(thread)
        Concurrent.configuration.global_task_pool.should_not_receive(:post).with(any_args())
        subject.post{ nil }
      end

      it 'executes a call without arguments' do
        @expected = false
        subject.post{ @expected = true }
        sleep(0.1)
        @expected.should be_true
      end

      it 'creates a new thread for a call with arguments' do
        thread = Thread.new{ nil }
        Thread.should_receive(:new).with(1,2,3).and_return(thread)
        Concurrent.configuration.global_task_pool.should_not_receive(:post).with(any_args())
        subject.post(1,2,3){ nil }
      end

      it 'executes a call with one argument' do
        @expected = 0
        subject.post(1){|one| @expected = one }
        sleep(0.1)
        @expected.should == 1
      end

      it 'executes a call with multiple arguments' do
        @expected = nil
        subject.post(1,2,3,4,5){|*args| @expected = args }
        sleep(0.1)
        @expected.should eq [1,2,3,4,5]
      end

      it 'aliases #<<' do
        thread = Thread.new{ nil }
        Thread.should_receive(:new).with(no_args()).and_return(thread)
        Concurrent.configuration.global_task_pool.should_not_receive(:post).with(any_args())
        subject << proc{ nil }
      end
    end
  end
end
