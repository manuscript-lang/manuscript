import {terminal, TerminalError} from "@std/terminal.ms"
import panic from "@std/faults.ms"

test "redirected streams report no terminal and refuse raw mode":
    let capabilities = terminal().capabilities()
    if capabilities.raw_mode: return
    if capabilities.colors != 0 and not capabilities.output_is_terminal:
        return panic("colors without a terminal")
    if capabilities.resize_events: return panic("resize events without raw mode")

    let raw = terminal().raw_mode(alternate_screen: false)

    if let active = raw:
        active.close()
        return panic("raw mode on redirected input")

    if raw.unwrap_error() != TerminalError.NotTerminal: return panic("wrong error")
