// conform: tags=diagnostics
// conform: phase=check
size := match 1:
        n:
            values.add(n, n)
            values.get(n).get()
        none: values.length()