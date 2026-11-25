// conform: phase=check
// conform: tags=alternatives,diagnostics,parser,tier-core
enum Wrong { ... }
// expect-error: MS1000 3:14-3:17 an enum must declare at least one variant; replace '...' with 'Name' or 'Name(field Type)'
