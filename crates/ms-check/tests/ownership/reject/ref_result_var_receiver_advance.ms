type Words:
    current: String
    count: Int

impl Words:
    var fn next() ref String?:
        self.count += 1
        self.current = "w"
        return self.current

fn f(var w: Words) Int:
    let first = w.next()
    let second = w.next()  # error: while `first` borrows it
    if let a = first:
        if let b = second:
            return a.length() + b.length()
    return 0
