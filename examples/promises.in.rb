# Adds factory methods like: future, event, delay, schedule, zip, ...
# otherwise they can be called on Promises module
include Concurrent::Promises::FactoryMethods #


### Simple asynchronous task

future = future(0.1) { |duration| sleep duration; :result } # evaluation starts immediately
future.completed?
# block until evaluated
future.value
future.completed?


### Failing asynchronous task

future = future { raise 'Boom' }
future.value
future.value! rescue $!
future.reason
# re-raising
raise future rescue $!


### Direct creation of completed futures

succeeded_future(Object.new)
failed_future(StandardError.new("boom"))

### Chaining of futures

head    = succeeded_future 1 #
branch1 = head.then(&:succ) #
branch2 = head.then(&:succ).then(&:succ) #
branch1.zip(branch2).value!
# zip is aliased as &
(branch1 & branch2).then { |a, b| a + b }.value!
(branch1 & branch2).then(&:+).value!
# or a class method zip from FactoryMethods can be used to zip multiple futures
zip(branch1, branch2, branch1).then { |*values| values.reduce &:+ }.value!
# pick only first completed
any(branch1, branch2).value!
(branch1 | branch2).value!


### Arguments

# any supplied arguments are passed to the block, promises ensure that they are visible to the block

future('3') { |s| s.to_i }.then(2) { |a, b| a + b }.value
succeeded_future(1).then(2, &:+).value
succeeded_future(1).chain(2) { |success, value, reason, arg| value + arg }.value


### Error handling

succeeded_future(Object.new).then(&:succ).then(&:succ).rescue { |e| e.class }.value # error propagates
succeeded_future(Object.new).then(&:succ).rescue { 1 }.then(&:succ).value # rescued and replaced with 1
succeeded_future(1).then(&:succ).rescue { |e| e.message }.then(&:succ).value # no error, rescue not applied

failing_zip = succeeded_future(1) & failed_future(StandardError.new('boom'))
failing_zip.result
failing_zip.then { |v| 'never happens' }.result
failing_zip.rescue { |a, b| (a || b).message }.value
failing_zip.chain { |success, values, reasons| [success, values.compact, reasons.compactß] }.value


### Delay

# will not evaluate until asked by #value or other method requiring completion
future = delay { 'lazy' }
sleep 0.1 #
future.completed?
future.value

# propagates trough chain allowing whole or partial lazy chains

head    = delay { 1 }
branch1 = head.then(&:succ)
branch2 = head.delay.then(&:succ)
join    = branch1 & branch2

sleep 0.1 # nothing will complete
[head, branch1, branch2, join].map(&:completed?)

branch1.value
sleep 0.1 # forces only head to complete, branch 2 stays incomplete
[head, branch1, branch2, join].map(&:completed?)

join.value
[head, branch1, branch2, join].map(&:completed?)


### Flatting

# waits for inner future, only the last call to value blocks thread
future { future { 1+1 } }.flat.value

# more complicated example
future { future { future { 1 + 1 } } }.
    flat(1).
    then { |f| f.then(&:succ) }.
    flat(1).value


### Schedule

# it'll be executed after 0.1 seconds
scheduled = schedule(0.1) { 1 }

scheduled.completed?
scheduled.value # available after 0.1sec

# and in chain
scheduled = delay { 1 }.schedule(0.1).then(&:succ)
# will not be scheduled until value is requested
sleep 0.1 #
scheduled.value # returns after another 0.1sec


### Completable Future and Event

future = completable_future
event  = completable_event()

# These threads will be blocked until the future and event is completed
t1     = Thread.new { future.value } #
t2     = Thread.new { event.wait } #

future.success 1
future.success 1 rescue $!
future.try_success 2
event.complete

# The threads can be joined now
[t1, t2].each &:join #


### Callbacks

queue  = Queue.new
future = delay { 1 + 1 }

future.on_success { queue << 1 } # evaluated asynchronously
future.on_success! { queue << 2 } # evaluated on completing thread

queue.empty?
future.value
queue.pop
queue.pop


### Thread-pools

# Factory methods are taking names of the global executors
# (ot instances of custom executors)

# executed on :fast executor, only short and non-blocking tasks can go there
future_on(:fast) { 2 }.
    # executed on executor for blocking and long operations
    then_on(:io) { File.read __FILE__ }.
    wait


### Interoperability with actors

actor = Concurrent::Actor::Utils::AdHoc.spawn :square do
  -> v { v ** 2 }
end


future { 2 }.
    then_ask(actor).
    then { |v| v + 2 }.
    value

actor.ask(2).then(&:succ).value


### Interoperability with channels

ch1 = Concurrent::Channel.new
ch2 = Concurrent::Channel.new

result = select(ch1, ch2)
ch1.put 1
result.value!


future { 1+1 }.
    then_put(ch1)
result = future { '%02d' }.
    then_select(ch1, ch2).
    then { |format, (value, channel)| format format, value }
result.value!


### Common use-cases Examples

# simple background processing
future { do_stuff }

# parallel background processing
jobs = 10.times.map { |i| future { i } } #
zip(*jobs).value


# periodic task
def schedule_job(interval, &job)
  # schedule the first execution and chain restart og the job
  Concurrent.schedule(interval, &job).chain do |success, continue, reason|
    if success
      schedule_job(interval, &job) if continue
    else
      # handle error
      p reason
      # retry
      schedule_job(interval, &job)
    end
  end
end

queue = Queue.new
count = 0

schedule_job 0.05 do
  queue.push count
  count += 1
  # to continue scheduling return true, false will end the task
  if count < 4
    # to continue scheduling return true
    true
  else
    queue.push nil
    # to end the task return false
    false
  end
end

# read the queue
arr, v = [], nil; arr << v while (v = queue.pop) #
arr

# How to limit processing where there are limited resources?
# By creating an actor managing the resource
DB = Concurrent::Actor::Utils::AdHoc.spawn :db do
  data = Array.new(10) { |i| '*' * i }
  lambda do |message|
    # pretending that this queries a DB
    data[message]
  end
end

concurrent_jobs = 11.times.map do |v|

  succeeded_future(v).
      # ask the DB with the `v`, only one at the time, rest is parallel
      then_ask(DB).
      # get size of the string, fails for 11
      then(&:size).
      rescue { |reason| reason.message } # translate error to value (exception, message)
end #

zip(*concurrent_jobs).value!


# In reality there is often a pool though:
data      = Array.new(10) { |i| '*' * i }
pool_size = 5

DB_POOL = Concurrent::Actor::Utils::Pool.spawn!('DB-pool', pool_size) do |index|
  # DB connection constructor
  Concurrent::Actor::Utils::AdHoc.spawn(name: "worker-#{index}", args: [data]) do |data|
    lambda do |message|
      # pretending that this queries a DB
      data[message]
    end
  end
end

concurrent_jobs = 11.times.map do |v|

  succeeded_future(v).
      # ask the DB_POOL with the `v`, only 5 at the time, rest is parallel
      then_ask(DB_POOL).
      then(&:size).
      rescue { |reason| reason.message }
end #

zip(*concurrent_jobs).value!
