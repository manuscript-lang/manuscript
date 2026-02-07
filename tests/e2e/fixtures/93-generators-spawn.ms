// @test: Generators and Spawn - generators, spawn, and combined usage
import { race, resolve, sleep } from "std/concurrency"

// ============================================
// GENERATOR BASICS
// ============================================

fn count_up(n: number): Stream[number]
  for i in 0..n
    yield i

var out = []
for x in count_up(3)
  out.push(x)
// @expect: [0, 1, 2]
print(out)

fn double_stream(n: number): Stream[number]
  for i in 0..n
    yield i * 2

var doubled = []
for v in double_stream(4)
  doubled.push(v)
// @expect: [0, 2, 4, 6]
print(doubled)

// ============================================
// GENERATOR + SPAWN
// ============================================

fn sum_from_gen(): number
  var s = 0
  for x in count_up(5)
    s = s + x
  s

let task_sum = spawn sum_from_gen()
race([task_sum])
// @expect: spawn gen sum
print("spawn gen sum")

fn collect_stream(): list[number]
  var acc: list[number] = []
  for x in double_stream(3)
    acc.push(x)
  acc

let task_collect = spawn collect_stream()
let result = race([task_collect])
// @expect: [0, 2, 4]
print(result)

// === Spawn function that returns generator; pull values from resolved stream ===

fn make_stream(): Stream[number]
  yield 10
  yield 20
  yield 30

let stream_promise = spawn make_stream()
let stream = race([stream_promise])
var from_spawned_gen: list[number] = []
for x in stream
  from_spawned_gen.push(x)
// @expect: [10, 20, 30]
print(from_spawned_gen)

// === Iterate without race: use resolve(single promise) ===
fn make_stream2(): Stream[number]
  yield 100
  yield 200

let p = spawn make_stream2()
let s = resolve(p)
var out2: list[number] = []
for x in s
  out2.push(x)
// @expect: [100, 200]
print(out2)

// ============================================
// RACE WITH GENERATOR-BACKED TASKS
// ============================================

fn slow_stream_sum(): number
  sleep(30)
  var s = 0
  for x in count_up(2)
    s = s + x
  s

fn fast_stream_sum(): number
  var s = 0
  for x in count_up(10)
    s = s + x
  s

// @expect: race start
print("race start")

let slow_task = spawn slow_stream_sum()
let fast_task = spawn fast_stream_sum()
let winner = race([slow_task, fast_task])
// @expect: 45
print(winner)

// ============================================
// GENERATOR IN NESTED CALLS
// ============================================

fn gen_ints(n: number): Stream[number]
  for i in 0..n
    yield i + 1

fn sum_gen_via_helper(n: number): number
  var t = 0
  for x in gen_ints(n)
    t = t + x
  t

let nested = spawn sum_gen_via_helper(4)
let nested_result = race([nested])
// @expect: 10
print(nested_result)

// @expect: done
print("done")
