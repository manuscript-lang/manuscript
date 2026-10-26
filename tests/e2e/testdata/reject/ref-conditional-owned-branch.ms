type Pair:
    left: String

impl Pair:
    def pick(first: Bool) -> ref String: self.left if first else "literal"
