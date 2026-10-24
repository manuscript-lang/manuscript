def f() -> Int:
    var xs = [1]
    let show = lambda () -> Int: xs.length()
    xs.append(2)  # error: while `show` borrows it
    return show()
