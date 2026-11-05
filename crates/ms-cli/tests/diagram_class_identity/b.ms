export type Item:
    count: Int

export type BBox:
    item: Item

export fn b_box() BBox:
    return BBox(Item(2))
