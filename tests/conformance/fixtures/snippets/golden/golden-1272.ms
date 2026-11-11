// conform: tags=diagnostics
// conform: phase=check
import ListBuilder from "@std/collections/collections.ms"
import system from "@std/system.ms"
fn length(values: List[Int]) Int:
    return values.length()
fn os_name() String:
    return system().info().os
