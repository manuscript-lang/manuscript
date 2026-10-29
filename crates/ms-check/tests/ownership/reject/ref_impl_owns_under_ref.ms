interface Shows:
    fn view() ref String

type Item:
    name: String

impl Shows for Item:
    fn view() String:  # error: the operation lends, so this method must return `ref`
        return self.name.clone()
