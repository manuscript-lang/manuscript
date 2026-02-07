// @test: Generators and Spawn Errors - spawn not consumed when mixed with generators
import { race } from "std/concurrency"

fn work(): number
  42

fn stream_ok(): Stream[number]
  yield 1
  yield 2

// @error: spawn result must be used
spawn work()

// @error: spawn result 'task' is never awaited
fn unawaited_spawn()
  let task = spawn work()
  print("done")
unawaited_spawn()

// @error: spawn result 'promise' is never awaited
fn gen_and_spawn()
  for x in stream_ok()
    print(x)
  let promise = spawn work()
  print("no race")
gen_and_spawn()

// @error: spawn result 'tasks' is never awaited
let tasks = [spawn work(), spawn work()]
print("list not consumed")
