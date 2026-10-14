//go:build !darwin

package debugger

import "github.com/go-delve/delve/service/rpccommon"

func bindScriptProcess(_ *rpccommon.ServerImpl, pid int) (scriptProcess, error) {
	return openScriptProcess(pid)
}

func scriptInterruptsInspection() bool { return false }
