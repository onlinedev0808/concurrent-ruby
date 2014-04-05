require 'spec_helper'
require_relative 'actor_ref_shared'

module Concurrent

  describe SimpleActorRef do

    after(:each) do
      subject.shutdown
      sleep(0.1)
    end

    subject do
      shared_actor_test_class.spawn
    end

    it_should_behave_like :actor_ref

    context 'supervision' do

      it 'does not start a new thread on construction' do
        Thread.should_not_receive(:new).with(any_args)
        subject = shared_actor_test_class.spawn
      end

      it 'starts a new thread on the first post' do
        thread = Thread.new{ nil }
        Thread.should_receive(:new).once.with(no_args).and_return(thread)
        subject << :foo
      end

      it 'does not start a new thread after the first post' do
        subject << :foo
        sleep(0.1)
        expected = Thread.list.length
        5.times{ subject << :foo }
        Thread.list.length.should eq expected
      end

      it 'starts a new thread when the prior thread has died' do
        subject << :foo
        sleep(0.1)

        subject << :terminate
        sleep(0.1)

        thread = Thread.new{ nil }
        Thread.should_receive(:new).once.with(no_args).and_return(thread)
        subject << :foo
      end

      it 'does not restart the thread after shutdown' do
        thread = Thread.new{ nil }
        Thread.should_receive(:new).once.with(no_args).and_return(thread)
        subject << :foo
        sleep(0.1)

        subject.shutdown
        sleep(0.1)

        subject << :foo
      end

      it 'calls #on_start when the thread is first started' do
        actor = subject.instance_variable_get(:@actor)
        actor.should_receive(:on_start).once.with(no_args)
        subject << :foo
      end

      it 'calls #on_restart when the thread is restarted' do
        actor = subject.instance_variable_get(:@actor)
        actor.should_receive(:on_restart).once.with(no_args)
        subject << :terminate
        sleep(0.1)
        subject << :foo
      end
    end

    context '#shutdown' do

      it 'calls #on_shutdown when shutdown' do
        actor = subject.instance_variable_get(:@actor)
        actor.should_receive(:on_shutdown).once.with(no_args)
        subject << :foo
        sleep(0.1)

        subject.shutdown
      end
    end
  end
end
