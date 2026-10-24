interface Shows:
    fn view() ref String

type Item:
    name: String

impl Shows for Item:
    fn view() String:  # error: the result kinds must agree
        return self.name.clone()
