type Words:
    current: String
    count: Int

impl Words:
    var fn next() ref String?:
        self.count += 1
        if self.count > 3:
            return none

        self.current = "w"
        return some(self.current)

fn total(var w: Words) Int:
    var n = 0

    while true:
        if let word = w.next():
            n += word.length()
        else:
            break

    return n
