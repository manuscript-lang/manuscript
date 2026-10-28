from "owner.ms" import Item
from "local.ms" import local

def exercise(x: Item) -> Int:
    return x.owned() + local(x)
