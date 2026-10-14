//go:build !linux && !windows

package debugger

import "fmt"

func scriptProcessSupported() error {
	return fmt.Errorf("script debugging requires identity-bound process interruption on Linux or Windows; use interactive ms debug on this platform")
}

func openScriptProcess(int) (scriptProcess, error) { return nil, scriptProcessSupported() }
