interface Names:
    def names() -> ref List[String]

type Holder:
    source: Names

impl Holder:
    def listed() -> ref List[String]:  # error: no `return` gives back part
        return self.source.names()
