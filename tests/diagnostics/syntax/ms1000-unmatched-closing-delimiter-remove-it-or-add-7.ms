// conform: tags=diagnostics
// conform: phase=check
)

type commonState struct {
	terminalSupported bool
	outputRedirected  bool
	inputRedirected   bool
// expect-error: MS1000 3:1-3:2 unmatched closing delimiter ')'; remove it or add the matching opener before it
// expect-error: MS1000 11:1 unterminated delimiter '{' opened at line 5:25; add the matching '}' before the end of the file
