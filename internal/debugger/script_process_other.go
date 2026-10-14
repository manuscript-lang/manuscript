//go:build !linux && !windows && !darwin

package debugger

import "fmt"

func scriptProcessSupported() error {
	return fmt.Errorf("script debugging requires identity-bound process interruption on Linux, Windows, or macOS; use interactive ms debug on this platform")
}

func openScriptProcess(int) (scriptProcess, error) { return nil, scriptProcessSupported() }
