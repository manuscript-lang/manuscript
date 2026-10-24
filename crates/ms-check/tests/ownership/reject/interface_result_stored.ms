interface Named:
    def names() -> List[String]

type Box:
    items: List[String]

impl Named for Box:
    def names() -> List[String]:
        return self.items

def keep(n: Named) -> List[List[String]]:
    var saved: List[List[String]] = []
    saved.append(n.names())  # error: borrows its result from `n`
    return saved
