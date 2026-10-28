type Box:
    name: String

impl Box:
    fn label() ref Optional[String]:
        return some(self.name)

export fn main() Int:
    return Box(name: "a").label().get("").length()
