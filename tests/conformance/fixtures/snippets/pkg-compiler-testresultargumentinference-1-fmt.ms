# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_argument_inference_test.go:47 TestResultArgumentInference
fn first() Int:
    let r: Result[Int, Error] = f()
    return h(r)
