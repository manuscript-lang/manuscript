// conform: phase=check
// conform: tags=alternatives,diagnostics,parser,tier-core
enum Wrong {
    value: Int
}
// expect-error: MS1000 4:10-4:11 enum variants have no field or method bodies; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and write methods after the enum as 'fn Name.method(...)'
