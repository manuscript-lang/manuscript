interface Shows:
    fn view() String

type Item:
    name: String

impl Shows for Item:
    fn view() ref String:  # error: declare `ref` on the interface operation
        return self.name
