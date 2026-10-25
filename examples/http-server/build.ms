from "@std/http.ms" import Request, Response
from "@std/web_html.ms" import Html, html_response
from "@std/web_build.ms" import StaticBuild
from "@std/fs.ms" import filesystem
from "@std/process.ms" import arguments
from "@std/io.ms" import IoError

# ms run build.ms -- /tmp/manuscript-site
# The destination must not exist. Publish that directory with an ordinary static host.
def page(request: Request) -> Response:
    return (
        html_response(
            Html.Element(
                "main",
                Map[String, String](),
                children: [
                    Html.Element(
                        "h1",
                        Map[String, String](),
                        children: [
                            Html.Text(
                                "Built with Manuscript"
                            )
                        ]
                    ),
                    Html.Element(
                        "p",
                        Map[String, String](),
                        children: [
                            Html.Text(
                                "The same handler can run at build time or serve a live route."
                            )
                        ]
                    )
                ]
            )
        )
        .get()
        .clone()
    )

export def main() -> Int:
    let destination = arguments().get(0, "site-output").clone()
    var build = StaticBuild()
    build.render("/", "index.html", page).get()
    (
        build.stage(
            lambda staging:
                let result = filesystem().copy_tree(
                    staging, destination, max_entries: 4096, max_bytes: 67108864
                )
                if result.is_error(): return error(
                    IoError.Failed(result.err().message())
                )

                return ok(())
        ).get()
    )
    return 0
