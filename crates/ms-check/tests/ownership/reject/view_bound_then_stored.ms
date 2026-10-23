fn f(line: String) List[String]:
    let t = line.trim_start()
    var saved: List[String] = []
    saved.append(t)  # error: cannot move `t` out
    return saved
