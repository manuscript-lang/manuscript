def core(line: String) -> String:
    return line.trim()

def use_it(line: String) -> Int:
    let t = core(line)
    return t.length()
