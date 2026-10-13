package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// These source-only fixtures run through the copied CLI under the same poisoned
// host-tool environment as the rest of the distribution gate.
func checkNumericFixtures(cli, directory string, run func(string, ...string) (string, error)) error {
	for _, fixture := range []struct {
		name  string
		tests int
	}{
		{"default-numbers.ms", 4}, {"wide-numbers.ms", 6}, {"wide-host-contracts.ms", 3},
	} {
		data, err := os.ReadFile(filepath.Join("tests", "e2e", "testdata", "accept", fixture.name))
		if err != nil {
			return err
		}
		source := filepath.Join(directory, fixture.name)
		if err := os.WriteFile(source, data, 0600); err != nil {
			return err
		}
		emitted := source + ".go"
		if _, err := run(cli, "emit", source, "--output="+emitted); err != nil {
			return err
		}
		output, err := os.ReadFile(emitted)
		if err != nil {
			return err
		}
		if strings.Contains(string(output), "github.com/manuscript-lang/manuscript/pkg/runtime") {
			return fmt.Errorf("%s retained an external runtime import", fixture.name)
		}
		transcript, err := run(cli, "test", source)
		if err != nil {
			return err
		}
		if !strings.Contains(transcript, fmt.Sprintf("%d tests, 0 failed", fixture.tests)) {
			return fmt.Errorf("copied numeric fixture %s: %s", fixture.name, transcript)
		}
	}
	return nil
}
