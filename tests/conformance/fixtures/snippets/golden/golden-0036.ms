// conform: tags=diagnostics
// conform: phase=check
  -o, --output <path>  Executable path (default: ./program; ./program.exe on Windows)
  --json              Emit one versioned build result and artifact inventory
  --debug             Alias for --build-type Debug
// expect-error: MS1000 3:59-3:60 unexpected source character ';'; Manuscript ends a statement at the end of the line, so remove the semicolon
