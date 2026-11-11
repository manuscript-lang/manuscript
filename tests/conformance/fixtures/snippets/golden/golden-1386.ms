// conform: tags=diagnostics
// conform: phase=check
)

type commonState struct {
	inputReaders      sync.WaitGroup
	terminalSupported bool
	outputRedirected  bool
	inputRedirected   bool
