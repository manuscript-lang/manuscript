# conform: tags=control-flow,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:115 TestSuccessfulResultBoundsKeepPeerAndPrefixChecks
fn probe() Int:
    var sum = 9223372036854775807
    var peer = 0
    var i = 0
    while i < 1000:
        
