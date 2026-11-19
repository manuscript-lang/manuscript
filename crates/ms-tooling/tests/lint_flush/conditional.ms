import Closeable from "@std/core.ms"

type Journal:
    lines: Int

fn move Journal.close() Void!:
    void self.lines
    return ok()

fn var Journal.flush() Result[Void, Error]:
    return ok()

type Holder:
    journal: Journal

fn take(move j: Journal) Holder:
    return Holder(j)

export fn kept_on_one_path(c: Bool) Int:
    journal := Journal(1)
    if c:
        return take(journal).journal.lines

    return 0

export fn moved_on_every_path(c: Bool) Int:
    journal := Journal(2)
    if c:
        return take(journal).journal.lines

    return take(journal).journal.lines

export fn moved_in_both_branches(c: Bool) Int:
    journal := Journal(3)

    if c:
        return take(journal).journal.lines
    else:
        return take(journal).journal.lines
