type Box:
    items: List[Int]
    other: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

fn trimmed(line: String) ref String:
    return line.trim()

fn len(line: String) Int:
    let t = trimmed(line)
    return t.length()

fn grow(b: Box) Int:
    let xs = b.items
    return xs.length()
