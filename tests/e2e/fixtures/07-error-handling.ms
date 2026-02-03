// @test: Error Handling - Try/catch

// === Basic try/catch ===
fn safe_divide(a: number, b: number): string
  try
    if b == 0 then throw "division by zero"
    return "result: " + to_str(a / b)
  catch e
    return "error: " + to_str(e)

// @expect: error: division by zero
print(safe_divide(10, 0))
// @expect: result: 5
print(safe_divide(10, 2))

// === Nested try/catch ===
fn nested_try(): string
  var result = "start"
  try
    result = result + ", outer"
    try
      throw "inner"
    catch e
      result = result + ", caught inner"
    result = result + ", done"
  catch e
    result = result + ", caught outer"
  return result

// @expect: start, outer, caught inner, done
print(nested_try())

// === Error propagation ===
fn level1(): string
  throw "error from level1"

fn level2(): string
  try
    return level1()
  catch e
    throw to_str(e) + " -> level2"

fn level3(): string
  try
    return level2()
  catch e
    return to_str(e)

// @expect: error from level1 -> level2
print(level3())

// === Fallback pattern ===
fn get_value(key: string): string?
  if key == "missing" then return null
  return "value: " + key

fn get_or_default(key: string, default_val: string): string
  let val = get_value(key)
  if val == null then return default_val
  val ?? default_val

// @expect: default
print(get_or_default("missing", "default"))
// @expect: value: found
print(get_or_default("found", "default"))

// === Validation ===
fn validate(n: number): string
  if n < 0 then throw "must be non-negative"
  if n > 100 then throw "must be <= 100"
  return "valid: " + to_str(n)

fn check(n: number): string
  try
    return validate(n)
  catch e
    return to_str(e)

// @expect: must be non-negative
print(check(-5))
// @expect: valid: 50
print(check(50))
// @expect: must be <= 100
print(check(150))
