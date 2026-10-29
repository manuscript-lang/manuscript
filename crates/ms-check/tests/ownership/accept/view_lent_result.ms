fn core(line: String) ref String:
    return line.trim()

fn use_it(line: String) Int:
    let t = core(line)
    return t.length()
