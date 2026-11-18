+++
title = "Cookbook"
weight = 1
aliases = ["/learn/common-tasks/", "/learn/best-practices/"]
+++

# Cookbook

Complete programs for common jobs. Pick the one closest to what you are building, copy it, and change it.

## Programs and files

- [Command-line programs](command-line.md): print, read arguments, subcommands and flags
- [Files and standard input](files-and-input.md): read and write text, process lines from stdin, find files by pattern
- [Watching files](watching-files.md): react to changes in a file or folder
- [Tables and colors](terminal-output.md): aligned columns and color that switches off in a pipe

## Data and text

- [Numbers and JSON](text-and-data.md): parse integers, parse JSON, read and write typed JSON
- [YAML and XML](yaml-and-xml.md): read a YAML setting or an XML document
- [Patterns and URLs](text-patterns.md): regular expressions, URL parts and queries
- [Hashes, IDs and random values](ids-and-hashes.md): SHA-256, UUIDs, tokens, repeatable random numbers
- [Exact numbers](exact-numbers.md): numbers beyond Int and exact fractions
- [Images](images.md): build, resize, encode and decode PNG and JPEG

## Networking

- [HTTP requests](http.md): fetch a URL and read the body
- [A JSON API](json-api.md): routes, typed bodies and tests without a socket
- [WebSockets and server-sent events](real-time.md): push data to a client as it happens
- [HTTPS and certificates](tls.md): serve TLS, trust a private authority, watch expiry

## Services

- [Service configuration](service-config.md): settings from a file with environment overrides
- [Logging](logging.md): structured records to stdout or a rotating file
- [Retries and limits](retries.md): retry with backoff, stop calling a failing dependency
- [Background jobs](background-jobs.md): bounded batches, a worker queue, an interval
- [Stopping cleanly](shutdown.md): handle Ctrl-C and SIGTERM
- [Tests with fakes](testing-with-fakes.md): replace a dependency in a test
- [Deploying one binary](deploying.md): a static executable and a container

Shell commands assume POSIX; the HTTP recipe needs Python 3 as a local server. New to the language? Start with the [guide](../guide/_index.md).
