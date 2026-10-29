import Item from "owner.ms"
import local from "local.ms"

fn exercise(x: Item) Int:
    return x.owned() + local(x)
