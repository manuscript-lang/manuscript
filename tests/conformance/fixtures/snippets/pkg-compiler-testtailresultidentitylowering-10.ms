# conform: tags=modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_tail_test.go:26 TestTailResultIdentityLowering
import TextError from "@std/errors.ms"
fn tail(value: Result[
