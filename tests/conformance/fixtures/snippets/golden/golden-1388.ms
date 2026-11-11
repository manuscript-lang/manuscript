// conform: tags=diagnostics
// conform: phase=check
	needRefresh       bool
}

// WaitForInput joins prompt readers. The caller must first interrupt its owned
// input and call Close; borrowed input is never closed by liner.
func (s *commonState) WaitForInput() { s.inputReaders.Wait() }

// TabStyle is used to select how tab completions are displayed.
type TabStyle int

