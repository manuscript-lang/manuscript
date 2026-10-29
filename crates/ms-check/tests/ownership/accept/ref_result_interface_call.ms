interface Names:
    fn names() ref List[String]

type Holder:
    source: Names

impl Holder:
    fn listed() ref List[String]:
        return self.source.names()
