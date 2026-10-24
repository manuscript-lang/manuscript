interface Shows:
    fn view() ref String

type Item:
    name: String

impl Shows for Item:
    fn view() String:
        return self.name.clone()
