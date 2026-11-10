fn count(line: String) Int:
    t := line.trim()
    u := t.trim_end()
    if t == u:
        return u.length()

    return t.length() + 1

fn keep(line: String) List[String]:
    var saved: List[String] = []
    saved.append(line.trim().clone())

    t := line.trim_end()
    saved.append(t.clone())
    return saved
