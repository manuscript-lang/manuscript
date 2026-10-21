fn f() Int:
    var total = 0
    let bump = fn() Unit:
        total += 1  # error: cannot assign a captured binding
    bump()
    return total
