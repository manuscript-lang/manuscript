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

func TestRunMainEscalatesOnSecondStopRequest(t *testing.T) {
	reported := make(chan int, 1)
	restore := escalateExit
	escalateExit = func(code int) { reported <- code }
	t.Cleanup(func() { escalateExit = restore })
	release := make(chan struct{})
	finished := make(chan int, 1)
	go func() {
		finished <- RunMain(func(ctx *Execution) int {
			syscall.Kill(syscall.Getpid(), syscall.SIGINT)
			<-ctx.Context.Done()
			time.Sleep(50 * time.Millisecond)
			syscall.Kill(syscall.Getpid(), syscall.SIGTERM)
			<-release // cleanup that never ends on its own
			return 0
		}, nil)
	}()
	select {
	case code := <-reported:
		if code != 70 {
			t.Fatalf("escalated with %d", code)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("second stop request did not escalate")
	}
	close(release)
	<-finished
}

func TestRunMainEscalatesWhenGraceEnds(t *testing.T) {
	reported := make(chan int, 1)
	restore, grace := escalateExit, cleanupGrace
	escalateExit, cleanupGrace = func(code int) { reported <- code }, 50*time.Millisecond
	t.Cleanup(func() { escalateExit, cleanupGrace = restore, grace })
	release := make(chan struct{})
	finished := make(chan int, 1)
	go func() {
		finished <- RunMain(func(ctx *Execution) int {
			syscall.Kill(syscall.Getpid(), syscall.SIGTERM)
			<-release
			return 0
		}, nil)
	}()
	select {
	case <-reported:
	case <-time.After(5 * time.Second):
		t.Fatal("grace period did not escalate")
	}
	close(release)
	if exit := <-finished; exit != 143 {
		t.Fatalf("exit = %d", exit)
	}
}

func TestRunMainFinishingInsideGraceDoesNotEscalate(t *testing.T) {
	reported := make(chan int, 1)
	restore, grace := escalateExit, cleanupGrace
	escalateExit, cleanupGrace = func(code int) { reported <- code }, 200*time.Millisecond
	t.Cleanup(func() { escalateExit, cleanupGrace = restore, grace })
	exit := RunMain(func(ctx *Execution) int {
		syscall.Kill(syscall.Getpid(), syscall.SIGINT)
		<-ctx.Context.Done()
		time.Sleep(20 * time.Millisecond)
		CheckCancelled(ctx)
		return 0
	}, nil)
	time.Sleep(300 * time.Millisecond)
	if exit != 130 || len(reported) != 0 {
		t.Fatalf("exit = %d, escalations = %d", exit, len(reported))
	}
}
