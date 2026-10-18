package e2e_test

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

const fileFixtureSource = `import {TestHooks, expect_equal, fail, skip} from "@std/testing.ms"
import stdout from "@std/io.ms"
import panic from "@std/faults.ms"
fn println(message: String) Unit:
    let written = stdout().write("{message}\n".to_bytes()).get()

type State:
    value: Int
fn make_fixture() State:
    println("factory")
    return State(0)
impl TestHooks for State:
    fn before_all() Unit:
        println("before_all")
    fn before_each() Unit:
        self.value = self.value + 1
        println("before_each")
    fn after_each() Unit:
        println("after_each")
    fn after_all() Unit:
        println("after_all {self.value}")
test "first":
    try expect_equal(fixture.value, 1)
test "second":
    try expect_equal(fixture.value, 2)
`

type fixtureReport struct {
	Completed      bool
	Reason, Stdout string
	Tests          []struct{ Name, Status, Failure string }
	Summary        struct {
		Selected, Passed, Failed, Skipped int
		NotRun                            int `json:"not_run"`
	}
	FixtureErrors []struct{ File, Phase, Failure string } `json:"fixture_errors"`
}

func TestCLITestFileFixtureLifecycle(t *testing.T) {
	cases := []struct {
		name, source                   string
		args                           []string
		status                         int
		passed, failed, skipped, unrun int
		phase                          string
		want                           []string
	}{
		{name: "success", source: fileFixtureSource, passed: 2, want: []string{"factory", "before_all", "after_all 2"}},
		{name: "repeat", source: strings.ReplaceAll(fileFixtureSource, "try expect_equal(fixture.value, 1)", "try expect_equal(fixture.value > 0, true)"), args: []string{"--filter=first", "--repeat=2"}, passed: 2, want: []string{"after_all 2"}},
		{name: "selection", source: strings.ReplaceAll(fileFixtureSource, "try expect_equal(fixture.value, 2)", "try expect_equal(fixture.value, 1)"), args: []string{"--filter=second"}, passed: 1, want: []string{"after_all 1"}},
		{name: "failfast", source: strings.ReplaceAll(fileFixtureSource, "try expect_equal(fixture.value, 1)", "try fail(\"broken\")"), args: []string{"--fail-fast"}, status: 1, failed: 1, unrun: 1, want: []string{"after_each", "after_all 1"}},
		{name: "skip", source: strings.ReplaceAll(fileFixtureSource, "try expect_equal(fixture.value, 1)", "skip(\"unavailable\")"), passed: 1, skipped: 1, want: []string{"after_each", "after_all 2"}},
		{name: "factory fails", source: strings.ReplaceAll(fileFixtureSource, "return State(0)", "return panic(\"setup failed\")"), status: 1, unrun: 2, phase: "make_fixture", want: []string{"setup failed"}},
		{name: "before all fails", source: strings.ReplaceAll(fileFixtureSource, "println(\"before_all\")", "panic(\"before failed\")"), status: 1, unrun: 2, phase: "before_all", want: []string{"after_all 0"}},
		{name: "after all fails", source: strings.ReplaceAll(fileFixtureSource, "println(\"after_all {self.value}\")", "panic(\"teardown failed\")"), status: 1, passed: 2, phase: "after_all", want: []string{"teardown failed"}},
		{name: "before each fails", source: strings.ReplaceAll(fileFixtureSource, "println(\"before_each\")", "panic(\"before each failed\")"), status: 1, failed: 2, want: []string{"after_each", "after_all 2"}},
		{name: "after each cannot skip", source: strings.ReplaceAll(fileFixtureSource, "println(\"after_each\")", "skip(\"teardown skipped\")"), status: 1, failed: 2, want: []string{"after_each cannot skip", "after_all 2"}},
		{name: "after each fails", source: strings.ReplaceAll(fileFixtureSource, "println(\"after_each\")", "panic(\"after each failed\")"), status: 1, failed: 2, want: []string{"after_all 2"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			file := filepath.Join(t.TempDir(), "test.ms")
			if err := os.WriteFile(file, []byte(tc.source), 0600); err != nil {
				t.Fatal(err)
			}
			status, output, stderr := cliStreams(t, append([]string{"test", file, "--json"}, tc.args...)...)
			var doc fixtureReport
			if err := json.Unmarshal(output, &doc); err != nil {
				t.Fatalf("%v %d %s %s", err, status, output, stderr)
			}
			if status != tc.status || !doc.Completed || doc.Summary.Passed != tc.passed || doc.Summary.Failed != tc.failed || doc.Summary.Skipped != tc.skipped || doc.Summary.NotRun != tc.unrun {
				t.Fatalf("status %d: %s %s", status, output, stderr)
			}
			if tc.phase != "" && (len(doc.FixtureErrors) != 1 || doc.FixtureErrors[0].Phase != tc.phase) {
				t.Fatalf("fixture errors: %s", output)
			}
			for _, want := range tc.want {
				if !strings.Contains(doc.Stdout, want) {
					t.Fatalf("missing %q: %s", want, output)
				}
			}
			if strings.Count(doc.Stdout, "factory\n") != 1 {
				t.Fatalf("factory not called once: %s", output)
			}
		})
	}
}

func TestCLITestFileFixtureListAndDefaultHooks(t *testing.T) {
	source := `import {TestHooks, expect_equal} from "@std/testing.ms"
import stdout from "@std/io.ms"
fn println(message: String) Unit:
    let written = stdout().write("{message}\n".to_bytes()).get()

type State:
    value: Int
fn make_fixture() State:
    println("FACTORY")
    return State(7)
impl TestHooks for State:
test "one":
    let hooks = TestHooks(value: fixture)
    hooks.before_all()
    try expect_equal(fixture.value, 7)
`
	file := filepath.Join(t.TempDir(), "test.ms")
	os.WriteFile(file, []byte(source), 0600)
	for _, args := range [][]string{{"--list"}, {"--filter=absent"}, {}} {
		status, out, stderr := cliStreams(t, append([]string{"test", file, "--json"}, args...)...)
		var doc fixtureReport
		if json.Unmarshal(out, &doc) != nil || !doc.Completed {
			t.Fatalf("%d %s %s", status, out, stderr)
		}
		if len(args) > 0 && strings.Contains(doc.Stdout, "FACTORY") {
			t.Fatalf("unexpected fixture initialization: %s", out)
		}
		if len(args) == 0 && (status != 0 || doc.Summary.Passed != 1) {
			t.Fatalf("%d %s %s", status, out, stderr)
		}
	}
}

func TestCLITestSharedRESTServer(t *testing.T) {
	source := `import {TestHooks, expect_equal, expect_ok} from "@std/testing.ms"
import {HttpServer, HttpRequest, HttpResponse, HttpMethod, headers} from "@std/http.ms"
import network from "@std/net.ms"
type ApiFixture:
    server: HttpServer
fn handle(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "shared".to_bytes())
fn make_fixture() ApiFixture:
    return ApiFixture(server: network().serve(address: "127.0.0.1:0", handler: handle).get())
impl TestHooks for ApiFixture:
    fn after_all() Unit:
        self.server.close()
test "first request":
    let response = try expect_ok(network().request(method: HttpMethod.Get, url: "http://{fixture.server.address()}/", headers: headers(), body: "".to_bytes()))
    try expect_equal(response.metadata().status, 200)
test "second request uses same server":
    let response = try expect_ok(network().request(method: HttpMethod.Get, url: "http://{fixture.server.address()}/", headers: headers(), body: "".to_bytes()))
    try expect_equal(response.body, "shared".to_bytes())
`
	file := filepath.Join(t.TempDir(), "test.ms")
	if err := os.WriteFile(file, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	status, out, stderr := cliStreams(t, "test", file, "--json", "--timeout=5s")
	var doc fixtureReport
	if json.Unmarshal(out, &doc) != nil || status != 0 || !doc.Completed || doc.Summary.Passed != 2 {
		t.Fatalf("shared REST server: %d %s %s", status, out, stderr)
	}
}

func TestCLITestFixturesStayLocalToEachFile(t *testing.T) {
	root := t.TempDir()
	source := strings.ReplaceAll(fileFixtureSource, "try expect_equal(fixture.value, 1)", "try expect_equal(fixture.value > 0, true)")
	source = strings.ReplaceAll(source, "try expect_equal(fixture.value, 2)", "try expect_equal(fixture.value > 0, true)")
	a := strings.ReplaceAll(source, `println("factory")`, `println("factory A")`)
	b := strings.ReplaceAll(source, `println("factory")`, `println("factory B")`)
	a = "import helper from \"./other.ms\"\n" + a
	b = "export fn helper() Unit:\n    return\n" + b
	path := filepath.Join(root, "test.ms")
	if err := os.WriteFile(path, []byte(a), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "other.ms"), []byte(b), 0600); err != nil {
		t.Fatal(err)
	}
	status, out, stderr := cliStreams(t, "test", path, "--json", "--shuffle=19", "--repeat=2")
	var doc fixtureReport
	if json.Unmarshal(out, &doc) != nil || status != 0 || doc.Summary.Passed != 8 || strings.Count(doc.Stdout, "factory A\n") != 1 || strings.Count(doc.Stdout, "factory B\n") != 1 || strings.Count(doc.Stdout, "after_all 4\n") != 2 {
		t.Fatalf("file fixtures %d %s %s", status, out, stderr)
	}
}

func TestCLITestFixtureInterruptCleansUp(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("process interrupt forwarding is Unix-specific")
	}
	source := fileFixtureSource[:strings.Index(fileFixtureSource, `test "first":`)] + `test "interruptible":
    println("READY")
    while true:
        try expect_equal(1, 1)
test "later":
    try fail("must not run")
`
	path := filepath.Join(t.TempDir(), "test.ms")
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, "test", path, "--timeout=5s")
	pipe, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	command.Stderr = &stderr
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	ready := make(chan struct{}, 1)
	output := make(chan string, 1)
	go func() {
		scanner := bufio.NewScanner(pipe)
		var log strings.Builder
		for scanner.Scan() {
			line := scanner.Text()
			log.WriteString(line + "\n")
			if line == "READY" {
				ready <- struct{}{}
			}
		}
		output <- log.String()
	}()
	select {
	case <-ready:
	case log := <-output:
		command.Wait()
		t.Fatalf("test did not start: %s %s", log, stderr.String())
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	if err := command.Process.Signal(os.Interrupt); err != nil {
		t.Fatal(err)
	}
	var log string
	select {
	case log = <-output:
	case <-ctx.Done():
		t.Fatal("test runner did not unwind after interrupt")
	}
	err = command.Wait()
	if err == nil || !strings.Contains(log, "after_each") || !strings.Contains(log, "after_all 1") || strings.Contains(log, "RUN test.ms::later") {
		t.Fatalf("interrupt cleanup: %v %s %s", err, log, stderr.String())
	}
}

func TestCLITestWithoutFactoryDoesNotRunHooks(t *testing.T) {
	source := `import {TestHooks, expect_equal} from "@std/testing.ms"
import stdout from "@std/io.ms"
type UnusedFixture:
    value: Int
impl TestHooks for UnusedFixture:
    fn before_all() Unit:
        let written = stdout().write("UNUSED before_all".to_bytes()).get()
    fn before_each() Unit:
        let written = stdout().write("UNUSED before_each".to_bytes()).get()
    fn after_each() Unit:
        let written = stdout().write("UNUSED after_each".to_bytes()).get()
    fn after_all() Unit:
        let written = stdout().write("UNUSED after_all".to_bytes()).get()
test "plain test":
    try expect_equal(1 + 1, 2)
`
	file := filepath.Join(t.TempDir(), "test.ms")
	if err := os.WriteFile(file, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	status, output, stderr := cliStreams(t, "test", file, "--json")
	var doc fixtureReport
	if json.Unmarshal(output, &doc) != nil || status != 0 || !doc.Completed || doc.Summary.Passed != 1 || len(doc.FixtureErrors) != 0 || strings.Contains(doc.Stdout, "UNUSED") {
		t.Fatalf("no-factory file must run normally: %d %s %s", status, output, stderr)
	}
}
