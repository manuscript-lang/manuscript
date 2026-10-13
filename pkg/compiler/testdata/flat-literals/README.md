The source and executable Go oracle were frozen independently from main
`a6dcb33a4c3123a4dc7f9e805eaebcabcfa3a4f0` before large-literal lowering changed.
The Go file has SHA-256
`99fcf51f97e480a024a027bf46f6f360277cadb69e2a27e16e24d4056420d4a8`;
the source has SHA-256
`1a7760d20b88c04931518e954d5b3b0dbb28519603a0320d106592c9556af4bc`.

`TestLargeListLiteralAgainstBaseline` checks native behavior in Release and
Debug, ordered source directives and current-emitter determinism. The old and
new executable ASTs intentionally differ. Keep these files independent; do not
regenerate them from the optimized emitter. The older `go-ast` oracle is also
untouched by this change, including its inherited history before this task.
