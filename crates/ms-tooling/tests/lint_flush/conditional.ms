from "@std/core.ms" import Closeable, TextError

type Journal:
    lines: Int

impl Closeable for Journal:
    var def close() -> Unit:
        let _ = self.lines

impl Journal:
    var def flush() -> Result[Unit, TextError]:
        return ok(())

type Holder:
    journal: Journal

def take(j: Journal) -> Holder:
    return Holder(j)

export def kept_on_one_path(c: Bool) -> Int:
    let journal = Journal(1)
    if c:
        return take(journal).journal.lines
    return 0

export def moved_on_every_path(c: Bool) -> Int:
    let journal = Journal(2)
    if c:
        return take(journal).journal.lines
    return take(journal).journal.lines

export def moved_in_both_branches(c: Bool) -> Int:
    let journal = Journal(3)
    if c:
        return take(journal).journal.lines
    else:
        return take(journal).journal.lines
