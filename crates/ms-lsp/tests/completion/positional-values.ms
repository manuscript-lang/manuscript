fn take(value: Int, other: Int = 1) Int:
    return value + other

fn first(amount: Int) Int:
    return take(amount)

fn operand(amount: Int) Int:
    return take(1 + amount)

fn later(amount: Int) Int:
    return take(1, amount)

fn labeled(amount: Int) Int:
    return take(value: amount)

fn same_name(value: Int) Int:
    return take(value)

fn inline(amount: Int, callback: fn() Int) Int: return amount
