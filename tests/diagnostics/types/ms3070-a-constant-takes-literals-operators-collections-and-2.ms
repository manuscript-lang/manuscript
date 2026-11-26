// conform: tags=diagnostics
// conform: phase=check
queue := Queue[Int](capacity: 2)
same := queue == queue
// expect-error: MS3070 3:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
