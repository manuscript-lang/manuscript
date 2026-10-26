type Shelf:
    by_name: Map[String, String]
    dflt: String

impl Shelf:
    def lookup(k: String) -> ref String:
        return self.by_name.get_or(k, self.dflt)
