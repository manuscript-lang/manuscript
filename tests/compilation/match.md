match
---

# match 
```ms
fn statusCode(code number) string {
    match code {
        200: 'ok'
        400: 'bad' + 'request'
        500: 'internal server error'
    }
}
```

```go
package main

func statusCode(code number) string {
    return func() interface{} {
        var __match_result interface{}
        switch code {
        case 200:
            __match_result = "ok"
        case 400:
            __match_result = "bad" + "request"
        case 500:
            __match_result = "internal server error"
        }
        return __match_result
    }()
}
func main() {
}
```

