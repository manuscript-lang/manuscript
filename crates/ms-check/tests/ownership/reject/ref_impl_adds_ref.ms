interface Shows:
    def view() -> String

type Item:
    name: String

impl Shows for Item:
    def view() -> ref String:  # error: declare `ref` on the interface operation
        return self.name
