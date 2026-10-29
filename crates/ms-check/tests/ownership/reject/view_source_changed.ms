fn f() Int:
    var line = "  a "
    let t = line.trim()
    line = "b"  # error: cannot reassign `line` while `t` borrows it
    return t.length()
