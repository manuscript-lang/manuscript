// conform: tags=diagnostics
// conform: phase=check
	needRefresh       bool
}

// WaitForInput joins prompt readers. The caller must first interrupt its owned
// input and call Close; borrowed input is never closed by liner.
func (s *commonState) WaitForInput() { s.inputReaders.Wait() }

// TabStyle is used to select how tab completions are displayed.
type TabStyle int
// expect-error: MS1000 4:1-4:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
// expect-error: MS1000 8:1-8:5 'func' is not a Manuscript declaration keyword; declare a function as 'fn name(a Int) Int { ... }' with the result type after the parameters
// expect-fix: 8:1-8:5 "fn"
// expect-error: MS1000 11:15-11:18 expected '{', found name 'int'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
