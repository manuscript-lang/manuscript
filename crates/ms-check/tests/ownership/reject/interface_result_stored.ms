interface Named:
    fn names() ref List[String]

type Box:
    items: List[String]

impl Named for Box:
    fn names() ref List[String]:
        return self.items

fn keep(n: Named) List[List[String]]:
    var saved: List[List[String]] = []
    saved.append(n.names())  # error: borrows its result from `n`
    return saved
