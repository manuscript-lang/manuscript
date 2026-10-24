interface Shows:
    def view() -> String

type Item:
    name: String

impl Shows for Item:
    def view() -> ref String:  # error: the result kinds must agree
        return self.name
