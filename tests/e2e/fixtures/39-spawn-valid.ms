// @test: Spawn Valid Patterns - comprehensive spawn usage

fn work(n: number): number
  n * 2

fn greet(name: string): string
  "Hello, " + name

// ============================================
// BASIC PATTERNS
// ============================================

// === Assign and consume with race ===
let task1 = spawn work(5)
race([task1])
// @expect: basic
print("basic")

// === Store multiple in list and race ===
let tasks = [spawn work(1), spawn work(2), spawn work(3)]
race(tasks)
// @expect: list
print("list")

// === Pass directly to function ===
fn accept_promise(p: Promise[number])
  race([p])

accept_promise(spawn work(25))
// @expect: direct pass
print("direct pass")

// === Consume spawn inside function ===
fn spawn_and_consume(): number
  let task = spawn work(100)
  race([task])

spawn_and_consume()
// @expect: consume in fn
print("consume in fn")

// === Store in map and race ===
let task_map = { "x": spawn work(1), "y": spawn work(2) }
race(values(task_map))  // values() gets the promises, not keys()
// @expect: map
print("map")

// ============================================
// FLOW TRACKING
// ============================================

// === Reassignment transfers tracking ===
let original = spawn work(10)
let alias = original  // tracking transfers
race([alias])
// @expect: reassign
print("reassign")

// === Chain of reassignments ===
let a = spawn work(20)
let b = a
let c = b
race([c])  // consume at end
// @expect: chain
print("chain")

// === Conditional spawn ===
let cond = true
let maybe = if cond then spawn work(1) else spawn work(2)
race([maybe])
// @expect: conditional
print("conditional")

// ============================================
// CALL STACK PROPAGATION
// ============================================

// === Return from function (caller consumes) ===
fn create_task(): Promise[number]
  let t = spawn work(42)
  t

let returned = create_task()
race([returned])
// @expect: returned
print("returned")

// === Deep call stack (3 layers) ===
fn layer3(): Promise[number]
  let s = spawn work(1)
  s

fn layer2(): Promise[number]
  let inner = layer3()
  inner

fn layer1(): Promise[number]
  let wrapped = layer2()
  wrapped

let deep = layer1()
race([deep])
// @expect: deep
print("deep")

// === Return list of spawns ===
fn create_task_list(): list[Promise[number]]
  let t1 = spawn work(10)
  let t2 = spawn work(20)
  [t1, t2]

let task_list = create_task_list()
race(task_list)
// @expect: list return
print("list return")

// === Return map of spawns ===
fn create_task_map(): map[string, Promise[number]]
  let x = spawn work(100)
  let y = spawn work(200)
  { "x": x, "y": y }

let returned_map = create_task_map()
race(values(returned_map))
// @expect: map return
print("map return")

// === Conditional in deep stack ===
fn maybe_spawn(flag: bool): Promise[number]
  let t = if flag then spawn work(1) else spawn work(2)
  t

fn wrap_maybe(flag: bool): Promise[number]
  let m = maybe_spawn(flag)
  m

let cond_deep = wrap_maybe(true)
race([cond_deep])
// @expect: conditional deep
print("conditional deep")

// === Factory with processor ===
fn spawn_factory(): Promise[number]
  let s = spawn work(42)
  s

fn process_spawn(p: Promise[number]): Promise[number]
  p

fn chain_process(): Promise[number]
  let s = spawn_factory()
  let p = process_spawn(s)
  p

let chained = chain_process()
race([chained])
// @expect: factory
print("factory")

// ============================================
// OBJECT PROPERTY TRACKING
// ============================================

// === Type with Promise property ===
type TaskHolder
  task: Promise[number]

let holder = TaskHolder(spawn work(42))
race([holder.task])
// @expect: type prop
print("type prop")

// === Spawn in type property, consumed via member access ===
fn create_holder(): TaskHolder
  let t = spawn work(99)
  TaskHolder(t)

let holder2 = create_holder()
race([holder2.task])
// @expect: holder access
print("holder access")

// === Deep nesting - spawn multiple levels deep ===
type Inner
  task: Promise[number]

type Outer
  inner: Inner

let nested_obj = Outer(Inner(spawn work(1)))
race([nested_obj.inner.task])
// @expect: deep nested
print("deep nested")

// === List of spawns inside object ===
type ListHolder
  tasks: list[Promise[number]]

let list_holder = ListHolder([spawn work(2), spawn work(3)])
race(list_holder.tasks)
// @expect: list in obj
print("list in obj")

// === Spawn through function returning object with Promise property ===
fn create_inner(): Inner
  Inner(spawn work(4))

fn create_outer(): Outer
  Outer(create_inner())

let deep_obj = create_outer()
race([deep_obj.inner.task])
// @expect: deep fn return
print("deep fn return")

// ============================================
// ASYNC BEHAVIOR
// ============================================

fn slow_task(): string
  sleep(50)
  "slow"

fn fast_task(): string
  "fast"

// @expect: before
print("before")

let slow = spawn slow_task()
// @expect: after slow
print("after slow")

let fast = spawn fast_task()
// @expect: after fast
print("after fast")

// race returns first to complete
let all_tasks = [slow, fast]
let winner = race(all_tasks)
// @expect: fast
print(winner)

// @expect: done
print("done")
