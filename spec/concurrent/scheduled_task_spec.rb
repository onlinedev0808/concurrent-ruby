require 'timecop'
require_relative 'obligation_shared'
require_relative 'observable_shared'

module Concurrent

  describe ScheduledTask do
    context 'behavior' do

      # obligation

      let!(:fulfilled_value) { 10 }
      let!(:rejected_reason) { StandardError.new('mojo jojo') }

      let(:pending_subject) do
        ScheduledTask.new(1){ fulfilled_value }.execute
      end

      let(:fulfilled_subject) do
        latch = Concurrent::CountDownLatch.new(1)
        task = ScheduledTask.new(0.1){ latch.count_down; fulfilled_value }.execute
        latch.wait(1)
        sleep(0.1)
        task
      end

      let(:rejected_subject) do
        latch = Concurrent::CountDownLatch.new(1)
        task = ScheduledTask.new(0.1){ latch.count_down; raise rejected_reason }.execute
        latch.wait(1)
        sleep(0.1)
        task
      end

      it_should_behave_like :obligation

      # dereferenceable

      specify{ expect(ScheduledTask.ancestors).to include(Dereferenceable) }

      # observable

      subject{ ScheduledTask.new(0.1){ nil } }

      def trigger_observable(observable)
        observable.execute
        sleep(0.2)
      end

      it_should_behave_like :observable
    end

    context '#initialize' do

      it 'accepts a number of seconds (from now) as the schedule time' do
        expected = 60
        Timecop.freeze do
          now = Time.now
          task = ScheduledTask.new(expected){ nil }.execute
          expect(task.delay).to be_within(0.1).of(expected)
        end
      end

      it 'accepts a Time object as the schedule time' do
        warn 'deprecated syntax'
        expected = 60 * 10
        schedule = Time.now + expected
        task = ScheduledTask.new(schedule){ nil }.execute
        expect(task.delay).to be_within(0.1).of(expected)
      end

      it 'raises an exception when seconds is less than zero' do
        expect {
          ScheduledTask.new(-1){ nil }
        }.to raise_error(ArgumentError)
      end

      it 'raises an exception when schedule time is in the past' do
        expect {
          ScheduledTask.new(Time.now - 60){ nil }
        }.to raise_error(ArgumentError)
      end

      it 'raises an exception when no block given' do
        expect {
          ScheduledTask.new(1)
        }.to raise_error(ArgumentError)
      end

      it 'sets the initial state to :unscheduled' do
        task = ScheduledTask.new(1){ nil }
        expect(task).to be_unscheduled
      end
    end

    context 'instance #execute' do

      it 'does nothing unless the state is :unscheduled' do
        expect(Concurrent).not_to receive(:timer).with(any_args)
        task = ScheduledTask.new(1){ nil }
        task.instance_variable_set(:@state, :pending)
        task.execute
        task.instance_variable_set(:@state, :rejected)
        task.execute
        task.instance_variable_set(:@state, :fulfilled)
        task.execute
      end

      it 'allows setting the execution interval to 0' do
        expect { 1000.times { ScheduledTask.execute(0) { } } }.not_to raise_error
      end

      it 'sets the sate to :pending' do
        task = ScheduledTask.new(1){ nil }
        task.execute
        expect(task).to be_pending
      end

      it 'returns self' do
        task = ScheduledTask.new(1){ nil }
        expect(task.execute).to eq task
      end
    end

    context 'class #execute' do

      it 'creates a new ScheduledTask' do
        task = ScheduledTask.execute(1){ nil }
        expect(task).to be_a(ScheduledTask)
      end

      it 'passes the block to the new ScheduledTask' do
        @expected = false
        task = ScheduledTask.execute(0.1){ @expected = true }
        task.value(1)
        expect(@expected).to be_truthy
      end

      it 'calls #execute on the new ScheduledTask' do
        task = ScheduledTask.new(0.1){ nil }
        allow(ScheduledTask).to receive(:new).with(any_args).and_return(task)
        expect(task).to receive(:execute).with(no_args)
        ScheduledTask.execute(0.1){ nil }
      end
    end

    context '#cancel' do

      it 'returns false if the task has already been performed' do
        task = ScheduledTask.new(0.1){ 42 }.execute
        task.value(1)
        expect(task.cancel).to be_falsey
      end

      it 'returns false if the task is already in progress' do
        latch = Concurrent::CountDownLatch.new(1)
        task = ScheduledTask.new(0.1) {
          latch.count_down
          sleep(1)
        }.execute
        latch.wait(1)
        expect(task.cancel).to be_falsey
      end

      it 'cancels the task if it has not yet scheduled' do
        latch = Concurrent::CountDownLatch.new(1)
        task = ScheduledTask.new(0.1){ latch.count_down }
        task.cancel
        task.execute
        expect(latch.wait(0.3)).to be_falsey
      end


      it 'cancels the task if it has not yet started' do
        latch = Concurrent::CountDownLatch.new(1)
        task = ScheduledTask.new(0.3){ latch.count_down }.execute
        sleep(0.1)
        task.cancel
        expect(latch.wait(0.5)).to be_falsey
      end

      it 'returns true on success' do
        task = ScheduledTask.new(10){ nil }.execute
        sleep(0.1)
        expect(task.cancel).to be_truthy
      end

      it 'sets the state to :cancelled when cancelled' do
        task = ScheduledTask.new(10){ 42 }.execute
        sleep(0.1)
        task.cancel
        expect(task).to be_cancelled
      end
    end

    context 'execution' do

      it 'sets the state to :in_progress when the task is running' do
        latch = Concurrent::CountDownLatch.new(1)
        task = ScheduledTask.new(0.1) {
          latch.count_down
          sleep(1)
        }.execute
        latch.wait(1)
        expect(task).to be_in_progress
      end
    end

    context 'observation' do

      let(:clazz) do
        Class.new do
          attr_reader :value
          attr_reader :reason
          attr_reader :count
          attr_reader :latch
          def initialize
            @latch = Concurrent::CountDownLatch.new(1)
          end
          def update(time, value, reason)
            @count = @count.to_i + 1
            @value = value
            @reason = reason
            @latch.count_down
          end
        end
      end

      let(:observer) { clazz.new }

      it 'returns true for an observer added while :unscheduled' do
        task = ScheduledTask.new(0.1){ 42 }
        expect(task.add_observer(observer)).to be_truthy
      end

      it 'returns true for an observer added while :pending' do
        task = ScheduledTask.new(0.1){ 42 }.execute
        expect(task.add_observer(observer)).to be_truthy
      end

      it 'returns true for an observer added while :in_progress' do
        task = ScheduledTask.new(0.1){ sleep(1); 42 }.execute
        sleep(0.2)
        expect(task.add_observer(observer)).to be_truthy
      end

      it 'notifies all observers on fulfillment' do
        task = ScheduledTask.new(0.1){ 42 }.execute
        task.add_observer(observer)
        observer.latch.wait(1)
        expect(observer.value).to eq(42)
        expect(observer.reason).to be_nil
      end

      it 'notifies all observers on rejection' do
        task = ScheduledTask.new(0.1){ raise StandardError }.execute
        task.add_observer(observer)
        observer.latch.wait(1)
        expect(observer.value).to be_nil
        expect(observer.reason).to be_a(StandardError)
      end
    end
  end
end
