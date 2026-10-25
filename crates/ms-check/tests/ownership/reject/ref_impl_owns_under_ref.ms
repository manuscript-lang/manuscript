interface Shows:
    def view() -> ref String

type Item:
    name: String

impl Shows for Item:
    def view() -> String:  # error: the operation lends, so this method must return `ref`
        return self.name.clone()
