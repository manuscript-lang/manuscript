// conform: tags=diagnostics
// conform: phase=check
offset := 7
values := [1, 2].map((outer) => [3, 4].map((inner) => outer + inner + offset))
