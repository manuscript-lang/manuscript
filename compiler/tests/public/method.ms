type Secret:
    a: Int

export type Holder:
    n: Int

fn Holder.get() Secret:
    return Secret(a: 1)

fn main() Void:
    return
