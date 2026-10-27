from "@std/core.ms" import Closeable, TextError

type Journal:
    lines: Int

impl Closeable for Journal:
    var def close() -> Unit:
        let _ = self.lines

impl Journal:
    var def flush() -> Result[Unit, TextError]:
        return ok(())

export def forgets() -> Int:
    let journal = Journal(1)
    return journal.lines

export def flushes() -> Result[Int, TextError]:
    var journal = Journal(2)
    try journal.flush()
    return ok(journal.lines)
