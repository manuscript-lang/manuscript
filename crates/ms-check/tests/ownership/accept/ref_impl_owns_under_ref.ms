interface Shows:
    def view() -> ref String

type Item:
    name: String

impl Shows for Item:
    def view() -> String:
        return self.name.clone()
