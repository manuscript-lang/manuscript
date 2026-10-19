# conform: tags=modules,parser,tier-core
# conform: phase=parse
# conform: origin=internal/debugger/lifecycle_test.go:347 buildTarget
package main

import "time"

func main() { time.Sleep(time.Minute) }
