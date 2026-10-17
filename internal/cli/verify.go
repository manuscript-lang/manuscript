package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

type verifyResult struct {
	Format int          `json:"format"`
	Target string       `json:"target"`
	OK     bool         `json:"ok"`
	Steps  []verifyStep `json:"steps"`
}

// verifyStep embeds the step command's own --json document unchanged.
type verifyStep struct {
	Name       string          `json:"name"`
	Status     string          `json:"status"`
	ExitCode   int             `json:"exit_code"`
	DurationNS int64           `json:"duration_ns"`
	Reason     string          `json:"reason,omitempty"`
	Error      string          `json:"error,omitempty"`
	Result     json.RawMessage `json:"result,omitempty"`
}

// runVerify runs check, fmt --check, lint, and test on one target and reports
// every step in one document. Lint and test need a program that checks, so
// they are skipped when check fails; fmt always runs.
func runVerify(args []string) int {
	structured, skipTest, positional := false, false, false
	var targets []string
	for _, arg := range args {
		switch {
		case !positional && arg == "--":
			positional = true
		case !positional && arg == "--json":
			structured = true
		case !positional && arg == "--no-test":
			skipTest = true
		case !positional && strings.HasPrefix(arg, "-"):
			fmt.Fprintf(os.Stderr, "unknown option %s for ms verify; run 'ms help verify' for its options\n", arg)
			return 2
		default:
			targets = append(targets, arg)
		}
	}
	if len(targets) > 1 {
		fmt.Fprintln(os.Stderr, "ms verify takes one target; pass a .ms file, directory, or ms.toml")
		return 2
	}
	target := "ms.toml"
	if len(targets) == 1 {
		target = targets[0]
	}
	if target == "" {
		fmt.Fprintln(os.Stderr, "ms verify: the target is empty; pass a .ms file, directory, or ms.toml")
		return 2
	}
	resolved, err := resolveInput("verify", target)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	target = resolved
	result := verifyResult{Format: 1, Target: target, OK: true, Steps: []verifyStep{}}
	record := func(step verifyStep) {
		if step.Status != "passed" {
			result.OK = false
		}
		result.Steps = append(result.Steps, step)
		if !structured {
			fmt.Printf("%-6s %s\n", step.Name, step.Status)
		}
	}
	skip := func(name, reason string) {
		record(verifyStep{Name: name, Status: "skipped", Reason: reason})
	}
	check := runVerifyStep("check", []string{"check", target, "--json"})
	record(check)
	record(runVerifyStep("fmt", []string{"fmt", target, "--check", "--json"}))
	switch {
	case check.Status != "passed":
		skip("lint", "check failed")
	default:
		record(runVerifyStep("lint", []string{"lint", target, "--json"}))
	}
	switch {
	case skipTest:
		skip("test", "--no-test")
	case check.Status != "passed":
		skip("test", "check failed")
	default:
		record(runVerifyStep("test", []string{"test", target, "--json"}))
	}
	status := 0
	if !result.OK {
		status = 1
	}
	if structured {
		return emitJSON(result, status)
	}
	for _, step := range result.Steps {
		if step.Status == "failed" {
			printVerifyFindings(step)
			fmt.Fprintf(os.Stderr, "%s failed; run ms %s %s for details (or ms verify %s --json for every step)\n", step.Name, step.Name, target, target)
		}
	}
	return status
}

// runVerifyStep runs one command in process with stdout and stderr captured.
func runVerifyStep(name string, args []string) verifyStep {
	step := verifyStep{Name: name, Status: "failed"}
	out, err := os.CreateTemp("", "manuscript-verify-out-")
	if err != nil {
		step.ExitCode, step.Error = 1, err.Error()
		return step
	}
	defer os.Remove(out.Name())
	defer out.Close()
	errs, err := os.CreateTemp("", "manuscript-verify-err-")
	if err != nil {
		step.ExitCode, step.Error = 1, err.Error()
		return step
	}
	defer os.Remove(errs.Name())
	defer errs.Close()
	stdout, stderr := os.Stdout, os.Stderr
	os.Stdout, os.Stderr = out, errs
	start := time.Now()
	step.ExitCode = Run(args)
	step.DurationNS = time.Since(start).Nanoseconds()
	os.Stdout, os.Stderr = stdout, stderr
	output, _ := os.ReadFile(out.Name())
	if json.Valid(output) {
		step.Result = json.RawMessage(strings.TrimSpace(string(output)))
	}
	if step.ExitCode == 0 {
		step.Status = "passed"
		return step
	}
	if step.Result == nil {
		message, _ := os.ReadFile(errs.Name())
		step.Error = strings.TrimSpace(string(message))
	}
	return step
}

// verifyFindingLimit bounds the findings printed per failed step so the text
// summary stays short; --json carries every one.
const verifyFindingLimit = 8

// printVerifyFindings prints the leading findings of a failed step so the text
// summary names the problem instead of only pointing at another command.
func printVerifyFindings(step verifyStep) {
	var findings []string
	if step.Error != "" {
		findings = append(findings, step.Error)
	}
	var result struct {
		Diagnostics []struct {
			Message  string `json:"message"`
			Position struct {
				File   string `json:"file"`
				Line   int    `json:"line"`
				Column int    `json:"column"`
			} `json:"position"`
		} `json:"diagnostics"`
		Tests []struct {
			Name    string `json:"name"`
			Status  string `json:"status"`
			Failure string `json:"failure"`
		} `json:"tests"`
	}
	if json.Unmarshal(step.Result, &result) == nil {
		for _, d := range result.Diagnostics {
			findings = append(findings, fmt.Sprintf("%s:%d:%d: %s", d.Position.File, d.Position.Line, d.Position.Column, d.Message))
		}
		for _, t := range result.Tests {
			if t.Status == "failed" {
				findings = append(findings, fmt.Sprintf("%s: %s", t.Name, strings.SplitN(t.Failure, "\n", 2)[0]))
			}
		}
	}
	for i, finding := range findings {
		if i == verifyFindingLimit {
			fmt.Fprintf(os.Stderr, "  ... %d more\n", len(findings)-i)
			break
		}
		fmt.Fprintf(os.Stderr, "  %s\n", finding)
	}
}
