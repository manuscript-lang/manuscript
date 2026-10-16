//go:build unix

package msruntime

import (
	"syscall"
	"testing"
	"time"
)

func TestRunMainSignalExit(t *testing.T) {
	exit := RunMain(func(ctx *Execution) int {
		go func() { time.Sleep(20 * time.Millisecond); syscall.Kill(syscall.Getpid(), syscall.SIGINT) }()
		<-ctx.Context.Done()
		CheckCancelled(ctx)
		return 0
	}, nil)
	if exit != 130 {
		t.Fatalf("exit = %d", exit)
	}
	exit = RunMain(func(ctx *Execution) int {
		go func() { time.Sleep(20 * time.Millisecond); syscall.Kill(syscall.Getpid(), syscall.SIGTERM) }()
		<-ctx.Context.Done()
		return 0
	}, nil)
	if exit != 143 {
		t.Fatalf("exit = %d", exit)
	}
}
