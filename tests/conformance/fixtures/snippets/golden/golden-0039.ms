// conform: tags=diagnostics
// conform: phase=check
  --json              Emit one versioned result; stdout is captured, stderr stays live (no --watch)
  --filter <text>      Run only tests whose module::name contains text
  --timeout <duration> Fail a test that runs longer (default 60s; 0 disables)
  --test <full-name>   Select exact module::name (repeatable)
  --match <regex>      Include names matching a regular expression
  --exclude <regex>    Exclude names matching a regular expression
  --list              List selected tests without running them
  --fail-fast         Stop after the first failed test
  --repeat <count>     Run the selected tests count times
  --shuffle <seed>     Shuffle with a reproducible integer seed
  --cpu-profile <path> Write a CPU profile of selected tests
  --heap-profile <path> Write a heap profile
  --trace <path>       Write an execution trace
  --debug              Alias for --build-type Debug
  --watch              Rebuild and rerun after each saved source change
