package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func checkNativeResults(cli, directory string, environment []string) error {
	run := func(arguments ...string) (int, []byte, string, error) {
		return runResultCommand(cli, directory, environment, arguments...)
	}
	status, version, stderr, err := run("--version")
	if err != nil || status != 0 || stderr != "" {
		return fmt.Errorf("version flag: %v, %d, %s", err, status, stderr)
	}
	status, alias, stderr, err := run("version")
	if err != nil || status != 0 || stderr != "" || !bytes.Equal(alias, version) {
		return fmt.Errorf("version alias: %v, %d, %s", err, status, stderr)
	}
	status, alias, stderr, err = run("version", "extra")
	if err != nil || status != 2 || len(alias) != 0 || stderr == "" {
		return fmt.Errorf("version usage: %v, %d, %s, %s", err, status, alias, stderr)
	}
	source := filepath.Join(directory, "native-results=a=b.ms")
	code := `import arguments from "@std/cli.ms"
import {stdout, stderr} from "@std/io.ms"
export fn main() Int:
    let args = arguments()
    let _out = stdout().write(data: "out={args[0].get()}\n".to_bytes())
    let _err = stderr().write(data: "stderr\n".to_bytes())
    return 7
`
	if err := os.WriteFile(source, []byte(code), 0600); err != nil {
		return err
	}
	type result struct {
		Format         int
		Command        string
		Completed      bool
		ExitCode       int `json:"exit_code"`
		Reason, Stdout string
		Artifacts      []struct{ Kind, Path, State string }
		Diagnostics    []json.RawMessage
	}
	build := filepath.Join(directory, "native-result-program")
	status, output, stderr, err := run("build", source, "--json", "--output="+build)
	var document result
	if err != nil || status != 0 || stderr != "" || json.Unmarshal(output, &document) != nil || document.Format != 1 || document.Command != "build" || !document.Completed || document.ExitCode != 0 || len(document.Artifacts) != 2 || document.Artifacts[0].State != "verified" || document.Artifacts[1].State != "verified" || len(document.Diagnostics) != 0 {
		return fmt.Errorf("build JSON: %v, %d, %s, %s", err, status, output, stderr)
	}
	capture := filepath.Join(directory, "native-capture=a=b")
	status, output, stderr, err = run("profile", source, "--json", "--out-dir="+capture, "--", "--out-dir=application-value")
	document = result{}
	if err != nil || status != 7 || stderr != "stderr\n" || json.Unmarshal(output, &document) != nil || document.Command != "profile" || !document.Completed || document.ExitCode != 7 || document.Reason != "program_exit" || document.Stdout != "out=--out-dir=application-value\n" || len(document.Artifacts) != 6 || len(document.Diagnostics) != 0 {
		return fmt.Errorf("profile JSON/forwarding: %v, %d, %s, %s", err, status, output, stderr)
	}
	for _, artifact := range document.Artifacts {
		if info, err := os.Stat(artifact.Path); err != nil || !info.Mode().IsRegular() || info.Size() == 0 {
			return fmt.Errorf("missing profile artifact: %+v, %v", artifact, err)
		}
	}
	partial := filepath.Join(directory, "native-partial")
	metadata := partial + ".ms-build.json"
	if err := os.Mkdir(metadata, 0700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(metadata, "keep"), []byte("keep"), 0600); err != nil {
		return err
	}
	status, output, stderr, err = run("build", source, "--json", "--output="+partial)
	document = result{}
	if err != nil || status != 1 || stderr == "" || json.Unmarshal(output, &document) != nil || document.Completed || document.Reason != "build_error" || len(document.Diagnostics) != 1 || len(document.Artifacts) != 2 || document.Artifacts[0].State != "written" || document.Artifacts[1].State != "unavailable" {
		return fmt.Errorf("partial artifact JSON: %v, %d, %s, %s", err, status, output, stderr)
	}
	return nil
}
