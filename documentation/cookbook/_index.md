+++
title = "Cookbook"
weight = 1
aliases = ["/learn/common-tasks/", "/learn/best-practices/"]
+++

# Cookbook

Complete programs for common jobs. Pick the one closest to what you are building, copy it, and change it.

- [Command-line programs](command-line.md): print, read arguments, subcommands and flags
- [Files and standard input](files-and-input.md): read and write text, process lines from stdin
- [Numbers and JSON](text-and-data.md): parse integers, parse JSON, read and write typed JSON
- [HTTP requests](http.md): fetch a URL and read the body
- [Service configuration](service-config.md): settings from a file with environment overrides
- [Logging](logging.md): structured records to stdout or a rotating file
- [Retries and limits](retries.md): retry with backoff, stop calling a failing dependency
- [A JSON API](json-api.md): routes, typed bodies and tests without a socket
- [Background jobs](background-jobs.md): bounded batches, a worker queue, an interval
- [Watching files](watching-files.md): react to changes in a file or folder
- [Tests with fakes](testing-with-fakes.md): replace a dependency in a test
- [Stopping cleanly](shutdown.md): handle Ctrl-C and SIGTERM
- [Deploying one binary](deploying.md): a static executable and a container

Shell commands assume POSIX; the HTTP recipe needs Python 3 as a local server. New to the language? Start with the [guide](../guide/_index.md).
