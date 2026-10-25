interface Names:
    def names() -> ref List[String]

type Holder:
    source: Names

impl Holder:
    def listed() -> ref List[String]:
        return self.source.names()
