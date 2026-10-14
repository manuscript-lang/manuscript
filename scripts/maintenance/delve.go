package main

import (
	"bytes"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

//go:embed delve-script.patch
var delveScriptPatch []byte

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
	if !strings.Contains(source, after) {
		if strings.Count(source, before) != 1 {
			return fmt.Errorf("Delve compatibility probe changed; review the no-external-Go patch")
		}
		if err := os.WriteFile(path, []byte(strings.Replace(source, before, after, 1)), 0644); err != nil {
			return err
		}
	}
	return applyDelveScriptPatch(".")
}

func applyDelveScriptPatch(directory string) error {
	apply := func(args ...string) error {
		cmd := exec.Command("git", append([]string{"apply"}, args...)...)
		cmd.Dir, cmd.Stdin = directory, bytes.NewReader(delveScriptPatch)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("%w: %s", err, output)
		}
		return nil
	}
	if err := apply("--check", "-"); err != nil {
		if reverse := apply("--reverse", "--check", "-"); reverse == nil {
			return nil
		}
		return fmt.Errorf("Delve scripted session patch changed; review pinned backend: %w", err)
	}
	return apply("-")
}
