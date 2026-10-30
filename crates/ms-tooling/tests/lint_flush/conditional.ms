import Closeable, TextError from "@std/core.ms"

type Journal:
    lines: Int

impl Closeable for Journal:
    var fn close() Unit:
        let _ = self.lines

impl Journal:
    var fn flush() Result[Unit, TextError]:
        return ok(unit)

type Holder:
    journal: Journal

fn take(j: Journal) Holder:
    return Holder(j)

export fn kept_on_one_path(c: Bool) Int:
    let journal = Journal(1)
    if c:
        return take(journal).journal.lines

    return 0

export fn moved_on_every_path(c: Bool) Int:
    let journal = Journal(2)
    if c:
        return take(journal).journal.lines

    return take(journal).journal.lines

export fn moved_in_both_branches(c: Bool) Int:
    let journal = Journal(3)

    if c:
        return take(journal).journal.lines
    else:
        return take(journal).journal.lines
