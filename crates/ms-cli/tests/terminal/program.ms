import TerminalEvent, EraseRegion, raw_mode from "@std/cli/terminal.ms"
import ReadStream from "@std/io/io.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import stdout from "@std/io/io.ms"
import Duration, nanoseconds from "@std/time.ms"

fn describe(e: TerminalEvent) String:
    match e:
        Text(t): return "text:" + t
        Key(n, c, a, s): return "key:" + n + " ctrl={c} alt={a} shift={s}"
        Resize(c, r): return "resize:{c}x{r}"

fn next_event(var events: ReadStream[TerminalEvent], limit: Duration) TerminalEvent?!:
    return promise(fn: events.next()).with(
        options: PromiseOptions(timeout: limit)
    ).wait()

export fn main() Int:
    let raw = raw_mode(alternate_screen: false)

    if let t = raw:
        var term = t
        let _ = term.move_cursor(1, 2)
        let _ = term.show_cursor(false)
        let _ = term.erase(EraseRegion.LineEnd)
        if let size = term.size():
            let _ = stdout().write("size {size.columns}x{size.rows}\r\n")

        var events = term.events()
        var done = false

        while not done:
            let next = next_event(var events, nanoseconds(5000000000))

            if let maybe = next:
                if let e = maybe:
                    let _ = stdout().write(describe(e.clone()) + "\r\n")
                    done = describe(e) == "text:q"
                else:
                    done = true
            else:
                let _ = stdout().write("timeout\r\n")
                done = true

        term.close().get(none)
        return 0

    let _ = stdout().write("no raw mode\n")
    return 1
