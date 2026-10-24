interface Shows:
    fn view() String

type Item:
    name: String

impl Shows for Item:
    fn view() ref String:  # error: the result kinds must agree
        return self.name
