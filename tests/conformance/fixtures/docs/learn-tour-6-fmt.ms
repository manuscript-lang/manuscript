# conform: tags=formatter,interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:106
def greeting(name: String = "world") -> String:
    return f"Hello, {name}!"

def line_total(price: Int, quantity: Int) -> Int:
    return price * quantity

let welcome = greeting("Sam")
let default_welcome = greeting()  # "Hello, world!"
let subtotal = line_total(12, 3)
