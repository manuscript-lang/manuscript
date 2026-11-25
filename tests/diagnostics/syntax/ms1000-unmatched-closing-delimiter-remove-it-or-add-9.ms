// conform: tags=diagnostics
// conform: phase=check
	needRefresh       bool
}

// TabStyle is used to select how tab completions are displayed.
type TabStyle int
// expect-error: MS1000 4:1-4:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
// expect-error: MS1000 7:15-7:18 expected '{', found name 'int'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
