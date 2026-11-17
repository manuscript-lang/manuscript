fn work() Void!: ok()

fn main() Void:
    work().get_or(none)
    work().get()

fn closer() Void:
    handles := [work()]
    handles[0].get_or(none)

type Box:
    n: Int

fn Box.close() Void!: ok()

fn shut(box: Box) Void:
    box.close().get_or(none)
