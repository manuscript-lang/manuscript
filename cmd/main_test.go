package main

import "testing"

func Test_programExecution(t *testing.T) {
	rt, _ := ExecuteProgram("1 + 2")
	if rt != "3" {
		t.Fatalf("Failed")
	}
}
