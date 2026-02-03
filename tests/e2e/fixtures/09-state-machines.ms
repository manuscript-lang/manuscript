// @test: State Machines

// === Traffic light ===
fn traffic_next(state: string): string
  match state
    "red" => "green"
    "green" => "yellow"
    "yellow" => "red"
    _ => "red"

var light = "red"
// @expect: red
print(light)
light = traffic_next(light)
// @expect: green
print(light)
light = traffic_next(light)
// @expect: yellow
print(light)
light = traffic_next(light)
// @expect: red
print(light)

// === Order state ===
fn can_transition(current: string, next: string): bool
  match current
    "pending" => next == "confirmed" or next == "cancelled"
    "confirmed" => next == "shipped"
    "shipped" => next == "delivered"
    _ => false

fn do_transition(current: string, next: string): map
  if can_transition(current, next)
    {state: next, ok: true}
  else
    {state: current, ok: false}

var order = "pending"
let r1 = do_transition(order, "confirmed")
order = r1.state
// @expect: confirmed true
print(order, r1.ok)

let r2 = do_transition(order, "pending")
// @expect: confirmed false
print(r2.state, r2.ok)

let r3 = do_transition(order, "shipped")
order = r3.state
// @expect: shipped true
print(order, r3.ok)

// === Counter state ===
fn counter_op(value: number, op: string): number
  match op
    "inc" => value + 1
    "dec" => value - 1
    "reset" => 0
    _ => value

var counter = 0
counter = counter_op(counter, "inc")
counter = counter_op(counter, "inc")
counter = counter_op(counter, "inc")
// @expect: 3
print(counter)
counter = counter_op(counter, "dec")
// @expect: 2
print(counter)
counter = counter_op(counter, "reset")
// @expect: 0
print(counter)

// === Vending machine ===
fn vending_insert(balance: number, amount: number): map
  {balance: balance + amount, message: "inserted " + to_str(amount)}

fn vending_buy(balance: number, price: number): map
  if balance >= price
    {balance: balance - price, message: "bought item"}
  else
    {balance: balance, message: "not enough"}

fn vending_refund(balance: number): map
  {balance: 0, message: "refunded " + to_str(balance)}

var vm = 0
let a1 = vending_insert(vm, 100)
vm = a1.balance
// @expect: inserted 100
print(a1.message)
// @expect: 100
print(vm)

let a2 = vending_buy(vm, 50)
vm = a2.balance
// @expect: bought item
print(a2.message)
// @expect: 50
print(vm)

let a3 = vending_buy(vm, 100)
// @expect: not enough
print(a3.message)
