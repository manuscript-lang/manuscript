package main

import (
	"fmt"
	"os"
	"strings"
)

func patchDelve() error {
	const path = "vendor/github.com/go-delve/delve/service/debugger/debugger.go"
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	const before = `func go11DecodeErrorCheck(err error) error {
	if !errors.Is(err, dwarf.DecodeError{}) {
		return err
	}

	gover, ok := goversion.Installed()
	if !ok || !gover.AfterOrEqual(goversion.GoVersion{Major: 1, Minor: 11, Rev: -1}) || goversion.VersionAfterOrEqual(runtime.Version(), 1, 11) {
		return err
	}

	return errors.New("executables built by Go 1.11 or later need Delve built by Go 1.11 or later")
}
`
	const after = `func go11DecodeErrorCheck(err error) error {
	// Manuscript embeds Go 1.25+: the pre-Go-1.11 compatibility probe is
	// obsolete and must not execute an external go command on malformed DWARF.
	return err
}
`
	source := string(data)
	if strings.Contains(source, after) {
		return patchDelveTerminal("")
	}
	if strings.Count(source, before) != 1 {
		return fmt.Errorf("Delve compatibility probe changed; review the no-external-Go patch")
	}
	if err := os.WriteFile(path, []byte(strings.Replace(source, before, after, 1)), 0644); err != nil {
		return err
	}
	return patchDelveTerminal("")
}
