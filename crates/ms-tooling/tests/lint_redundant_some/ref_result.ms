type Box:
    name: String

impl Box:
    def label() -> ref Optional[String]:
        return some(self.name)

export def main() -> Int:
    return Box(name: "a").label().get("").length()
