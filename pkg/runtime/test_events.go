package msruntime

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
)

type testReporter struct {
	file   *os.File
	failed bool
}

func openTestReporter() (*testReporter, error) {
	path := os.Getenv(nativeabi.TestEventsEnv)
	if path == "" {
		return nil, nil
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return nil, fmt.Errorf("cannot record structured test results: %w", err)
	}
	return &testReporter{file: file}, nil
}

func (r *testReporter) emit(event nativeabi.TestEvent) {
	if r == nil || r.failed {
		return
	}
	if err := json.NewEncoder(r.file).Encode(event); err != nil {
		r.failed = true
		fmt.Fprintf(os.Stderr, "cannot record structured test results: %v\n", err)
	}
}

func (r *testReporter) close() {
	if r != nil {
		if err := r.file.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "cannot close structured test results: %v\n", err)
		}
	}
}
