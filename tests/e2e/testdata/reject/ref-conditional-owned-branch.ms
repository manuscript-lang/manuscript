type Pair:
    left: String

impl Pair:
    fn pick(first: Bool) ref String: (if first: self.left else: "literal")
