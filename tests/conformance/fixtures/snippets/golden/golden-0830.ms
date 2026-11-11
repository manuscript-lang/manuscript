// conform: tags=diagnostics
// conform: phase=check
type Counter:
    value: Int

fn advance(counter: Counter) Int:
    counter.value += 1
    return counter.value

fn work(counter: Counter) List[Int]:
    var value = 1
    return [
        value, counter.value, counter.value, advance(counter), value,
        match 2:
            number:
                value = number
                advance(counter)
            none: 0
        , value, counter.value, advance(counter)
    ]
