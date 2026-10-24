interface Shows:
    def view() -> ref String

type Item:
    name: String

impl Shows for Item:
    def view() -> String:  # error: the result kinds must agree
        return self.name.clone()
