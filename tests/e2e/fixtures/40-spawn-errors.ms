// @test: Spawn Error Patterns - spawns must be properly consumed

fn work(): number
  42

// @error: spawn result must be used
spawn work()

// @error: spawn result 'task' is never awaited
fn unawaited_in_function()
  let task = spawn work()
  print("done")
unawaited_in_function()

// @error: spawn result 'tasks' is never awaited
let tasks = [spawn work(), spawn work()]
print("list not consumed")

// @error: spawn result 'task_map' is never awaited
let task_map = { "a": spawn work(), "b": spawn work() }
print("map not consumed")

// @error: spawn result 'keys_map' is never awaited
let keys_map = { "x": spawn work(), "y": spawn work() }
race(keys(keys_map))  // keys() returns strings, not promises
print("keys wrong")

// @error: spawn result 'alias' is never awaited
let original = spawn work()
let alias = original
print("alias not consumed")

// @error: spawn result 'inner' is never awaited
fn bad_function()
  let inner = spawn work()
  print("bad")
bad_function()

// @error: spawn result 'holder' is never awaited
type TaskHolder
  task: Promise[number]

let holder = TaskHolder(spawn work())
print("holder not consumed")
