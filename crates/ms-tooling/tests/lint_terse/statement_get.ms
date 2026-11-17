fn work() Void!: ok()

fn main() Void:
    void work()
    work().get()

fn closer() Void:
    handles := [work()]
    void handles[0]

type Box:
    n: Int

fn Box.close() Void!: ok()

fn shut(box: Box) Void:
    void box.close()
