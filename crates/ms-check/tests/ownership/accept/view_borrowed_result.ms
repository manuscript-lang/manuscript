fn core(line: String) String:
    return line.trim()

fn use_it(line: String) Int:
    t := core(line)
    return t.length()
