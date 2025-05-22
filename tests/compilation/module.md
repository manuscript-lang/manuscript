module tests
---

# should be able to import
```ms
import os from 'os'
import {FindDir} from 'os'
import {C1, C2, C3 as D} from 'path'
```
```go
package main

import (
    os "os"
    __import1 "os"
    __import2 "path"
)

var FindDir = __import1.FindDir
var C1 = __import2.C1
var C2 = __import2.C2
var D = __import2.C3

func main() {
}
```