package main

import (
	"fmt"
	"os"
	"path/filepath"
)

// Copies of this checker are cross-platform executable tripwires. They never
// stand in for a successful tool: any attempted invocation fails and is logged.
func poisonTools(directory, suffix string) (string, string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", "", err
	}
	data, err := os.ReadFile(executable)
	if err != nil {
		return "", "", err
	}
	root := filepath.Join(directory, "external tools")
	if err := os.MkdirAll(root, 0700); err != nil {
		return "", "", err
	}
	for _, name := range []string{"go", "gofmt", "goimports", "gopls", "dlv", "cache-tool"} {
		if err := os.WriteFile(filepath.Join(root, name+suffix), data, 0700); err != nil {
			return "", "", err
		}
	}
	return root, filepath.Join(directory, "external-tool-invoked"), nil
}

func assertNoExternalTool(marker string) error {
	if data, err := os.ReadFile(marker); !os.IsNotExist(err) {
		return fmt.Errorf("external tool invoked: %s (%v)", data, err)
	}
	return nil
}
