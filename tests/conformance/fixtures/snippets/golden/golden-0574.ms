// conform: tags=diagnostics
// conform: phase=check
callback := fn() Int:
        values := Map[Int, Int]()
        child := fn() Int:
            grandchild := fn() Int: values.length()
            return grandchild()
        return child()