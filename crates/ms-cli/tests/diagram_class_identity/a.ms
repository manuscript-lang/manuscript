export type Item:
    name: String

export type ABox:
    item: Item

export fn a_box() ABox:
    return ABox(Item("a"))
