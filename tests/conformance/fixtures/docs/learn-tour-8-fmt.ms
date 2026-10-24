# conform: tags=alternatives,formatter,interpolation,match,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:137
from "@std/testing.ms" import expect_equal

type Todo:
    title: String
    completed: Bool = False

type Status:
    case Draft
    case Published(url: String)

def status_label(status: Status) -> String:
    match status:
        case Draft:
            return "Not published"
        case Published(url):
            return f"Published at {url}"

test "publish a help page":
    var todo = Todo("Update the help page")
    todo.completed = True

    let backup = todo.clone()
    todo.title = "Update the contact page"

    let label = status_label(Status.Published("/help"))
    try expect_equal(backup.title, "Update the help page")
    try expect_equal(backup.completed, True)
    try expect_equal(label, "Published at /help")
