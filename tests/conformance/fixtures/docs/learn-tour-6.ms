# conform: tags=diagnostics,interpolation,strings,tier-core
# conform: phase=check
# conform: origin=documentation/learn/tour.md:106
fn greeting(name: String = "world") String:
    return "Hello, {name}!"

fn line_total(price: Int, quantity: Int) Int:
    return price * quantity

let welcome = greeting("Sam")
let default_welcome = greeting()  # "Hello, world!"
let subtotal = line_total(12, 3)
