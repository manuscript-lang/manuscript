// @test: Channels - Communication between concurrent operations

// ============================================
// BASIC CHANNEL OPERATIONS
// ============================================

// === Simple send/receive with spawn ===
fn basic_channel_demo()
  let ch = Channel[string](1)
  let task = spawn ch.send("hello")
  race([task])
  let msg = ch.receive()
  // @expect: hello
  print(msg)

basic_channel_demo()

// === Buffered channel - doesn't block ===
fn buffered_channel_demo()
  let ch = Channel[number](3)
  ch.send(1)
  ch.send(2)
  ch.send(3)
  // @expect: 1
  print(ch.receive())
  // @expect: 2
  print(ch.receive())
  // @expect: 3
  print(ch.receive())

buffered_channel_demo()

// ============================================
// CHANNELS WITH TYPES
// ============================================

// === Channel of custom type ===
type Message
  id: number
  text: string

fn typed_channel_demo()
  let ch = Channel[Message](1)
  let msg = Message(1, "first message")
  ch.send(msg)
  let received = ch.receive()
  // @expect: first message
  print(received.text)
  // @expect: 1
  print(received.id)

typed_channel_demo()

// ============================================
// PRODUCER/CONSUMER WITH SPAWN
// ============================================

// === Single producer, single consumer ===
fn producer(ch: Channel[number], count: number)
  for i in 0..count
    ch.send(i)
  ch.close()

fn consumer(ch: Channel[number]): number
  var sum = 0
  for val in ch
    sum = sum + val
  sum

fn producer_consumer_demo()
  let ch = Channel[number](5)
  let task = spawn producer(ch, 5)
  let result = consumer(ch)
  race([task])
  // @expect: 10
  print(result)

producer_consumer_demo()

// ============================================
// CHANNEL CLOSE AND ITERATION
// ============================================

// === Check closed state ===
fn close_demo()
  let ch = Channel[number](1)
  // @expect: false
  print(ch.isClosed())
  ch.close()
  // @expect: true
  print(ch.isClosed())

close_demo()

// === Receive returns null on closed empty channel ===
fn receive_after_close_demo()
  let ch = Channel[string](1)
  ch.send("before")
  ch.close()
  // @expect: before
  print(ch.receive())
  // Receive on closed empty channel returns null
  let result = ch.receive()
  // @expect: true
  print(result == null)

receive_after_close_demo()

// ============================================
// CHANNEL WITH TYPE METHODS
// ============================================

type Worker
  name: string
  
  fn process(item: string): string
    "{name} processed: {item}"

fn type_method_channel_demo()
  let ch = Channel[string](5)
  let worker = Worker("Bot")
  
  ch.send("task1")
  ch.send("task2")
  ch.send("task3")
  ch.close()
  
  var count = 0
  for task in ch
    let result = worker.process(task)
    count = count + 1
    if count == 1
      // @expect: Bot processed: task1
      print(result)
  
  // @expect: 3
  print(count)

type_method_channel_demo()

// ============================================
// PIPELINE PATTERN
// ============================================

fn doubler(inp: Channel[number], out: Channel[number])
  for n in inp
    out.send(n * 2)
  out.close()

fn pipeline_demo()
  let input = Channel[number](5)
  let output = Channel[number](5)
  
  // Fill input
  for i in 1..4
    input.send(i)
  input.close()
  
  // Run pipeline
  let task = spawn doubler(input, output)
  race([task])
  
  var first = 0
  var second = 0
  var third = 0
  var idx = 0
  for n in output
    if idx == 0
      first = n
    if idx == 1
      second = n
    if idx == 2
      third = n
    idx = idx + 1
  
  // @expect: 2
  print(first)
  // @expect: 4
  print(second)
  // @expect: 6
  print(third)

pipeline_demo()

// ============================================
// CHANNEL ACCUMULATOR PATTERN
// ============================================

fn channel_accumulator_demo()
  let ch = Channel[number](5)
  
  ch.send(10)
  ch.send(20)
  ch.send(30)
  ch.close()
  
  var total = 0
  for val in ch
    total = total + val
  
  // @expect: 60
  print(total)

channel_accumulator_demo()

// ============================================
// CHANNELS WITH CONTEXT (MODULE SCOPE)
// ============================================

// Logger context with channel reporting
type IReporter extends Context
  fn init()
    super()
  fn report(msg: string)

type ChannelReporter extends IReporter
  ch: Channel[string]
  
  fn init(ch: Channel[string])
    super()
    ch = ch
  
  fn report(msg: string)
    ch.send(msg)

fn do_work(name: string) using (reporter: IReporter)
  reporter.report("started: " + name)
  reporter.report("completed: " + name)

// Context test at module scope
let ctx_ch = Channel[string](10)

with let reporter = ChannelReporter(ctx_ch)
  do_work("task1")
  do_work("task2")

ctx_ch.close()

var report_count = 0
var first_report = ""
for r in ctx_ch
  if report_count == 0
    first_report = r
  report_count = report_count + 1

// @expect: 4
print(report_count)
// @expect: started: task1
print(first_report)

// ============================================
// CONTEXT WITH SPAWN AND CHANNELS (MODULE SCOPE)
// ============================================

type ICounter extends Context
  fn init()
    super()
  fn increment(): number
  fn get(): number

type SafeCounter extends ICounter
  count: number = 0
  
  fn init(count: number = 0)
    super()
    count = count
  
  fn increment(): number
    count = count + 1
    count
  
  fn get(): number
    count

fn worker(id: number, ch: Channel[number]) using (counter: ICounter)
  let n = counter.increment()
  ch.send(n)

let worker_ch = Channel[number](5)

with let counter = SafeCounter()
  let t1 = spawn worker(1, worker_ch)
  let t2 = spawn worker(2, worker_ch)
  let t3 = spawn worker(3, worker_ch)
  race([t1, t2, t3])
  // @expect: 3
  print(counter.get())

worker_ch.close()

// ============================================
// EVENT BUS PATTERN WITH CONTEXT
// ============================================

type IEventBus extends Context
  fn init()
    super()
  fn publish(event: string)

type SimpleEventBus extends IEventBus
  ch: Channel[string]
  
  fn init(ch: Channel[string])
    super()
    ch = ch
  
  fn publish(event: string)
    ch.send(event)

fn event_publisher() using (bus: IEventBus)
  bus.publish("event1")
  bus.publish("event2")

let event_ch = Channel[string](10)

with let bus = SimpleEventBus(event_ch)
  event_publisher()

event_ch.close()

var event_count = 0
var first_event = ""
for e in event_ch
  if event_count == 0
    first_event = e
  event_count = event_count + 1

// @expect: 2
print(event_count)
// @expect: event1
print(first_event)
