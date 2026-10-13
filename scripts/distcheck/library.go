package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func libraryFixture(directory string) (string, error) {
	root := filepath.Join(directory, "library")
	for name, text := range map[string]string{
		"ms.toml":             "# library\n[project]\nname = \"library\"\nsource = \"src\"\n",
		"src/value.ms":        "export fn value() -> Int: return 3\n",
		"src/unimported.ms":   "import panic from \"@std/faults.ms\"\nexport fn other() -> Int: return 4\ntest \"source\":\n    if other() != 4: return panic(\"bad other\")\n",
		"tests/value_test.ms": "import value from \"../src/value.ms\"\nimport panic from \"@std/faults.ms\"\ntest \"separate\":\n    if value() != 3: return panic(\"bad value\")\n",
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return "", err
		}
		if err := os.WriteFile(path, []byte(text), 0644); err != nil {
			return "", err
		}
	}
	return filepath.Join(root, "ms.toml"), nil
}

func checkLibrarySource(cli, manifest string, run func(string, ...string) (string, error)) error {
	for _, command := range []string{"check", "lint", "doc"} {
		data, err := run(cli, command, manifest)
		if err != nil {
			return err
		}
		if command == "doc" && (!strings.Contains(data, "fn value()") || !strings.Contains(data, "fn other()")) {
			return fmt.Errorf("packaged library docs omit exports: %s", data)
		}
	}
	return nil
}

func checkLibraryNative(cli, manifest string, run func(string, ...string) (string, error)) error {
	if _, err := run(cli, "lock", manifest); err != nil {
		return err
	}
	data, err := run(cli, "test", manifest)
	if err != nil {
		return err
	}
	if !strings.Contains(data, "2 tests, 0 failed") {
		return fmt.Errorf("packaged library skipped tests: %s", data)
	}
	for _, command := range []string{"run", "build", "emit", "debug", "profile"} {
		_, err := run(cli, command, manifest)
		if err == nil || !strings.Contains(err.Error(), "ms.toml:2:1: resolution: library project has no executable entry") || !strings.Contains(err.Error(), "add entry =") {
			return fmt.Errorf("packaged %s library rejection: %v", command, err)
		}
	}
	return nil
}
