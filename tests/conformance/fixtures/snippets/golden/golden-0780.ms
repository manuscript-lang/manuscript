// conform: tags=diagnostics
// conform: phase=check
﻿fn value() Void {
    return
}
// expect-error: MS1000 3:1 unexpected source character '\\u{feff}'; non-ASCII characters are only allowed inside text and comments, and identifiers are ASCII
// expect-error: MS1000 5:1-5:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
