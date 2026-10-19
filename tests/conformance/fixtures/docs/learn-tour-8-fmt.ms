# conform: tags=aliasing,alternatives,formatter,interpolation,match,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:137
import expect_equal from "@std/testing.ms"

type Todo:
    title: String
    completed: Bool = false

type Status:
    case Draft
    case Published(url: String)

fn status_label(status: Status) String:
    match status:
        Draft:
            return "Not published"
        Published(url):
            return "Published at {url}"

test "publish a help page":
    var todo = Todo("Update the help page")
    todo.completed = true
    let backup = todo.clone()
    todo.title = "Update the contact page"
    let label = status_label(Status.Published("/help"))
    try expect_equal(backup.title, "Update the help page")
    try expect_equal(backup.completed, true)
    try expect_equal(label, "Published at /help")
