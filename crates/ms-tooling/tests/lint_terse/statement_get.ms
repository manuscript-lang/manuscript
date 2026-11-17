fn work() Void!: ok()

fn main() Void:
    work().get(none)
    work().get()

fn closer() Void:
    handles := [work()]
    handles[0].get(none)

type Box:
    n: Int

fn Box.close() Void!: ok()

fn shut(box: Box) Void:
    box.close().get(none)
