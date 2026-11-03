import Bytes from "@std/bytes.ms"
import (
    HttpHeaders,
    HttpMethod,
    HttpResponseMetadata,
    NativeHttpClient,
    HttpExchange,
    HttpServerOptions,
    NativeServing,
    NativeResponseBody,
    RawResponse
) from "@std/net/http.ms"
import Duration from "@std/os/time.ms"

export extern fn msstd_http_client_close(handle: NativeHttpClient) Unit

export extern fn msstd_http_client_share(handle: NativeHttpClient) NativeHttpClient

export extern fn msstd_http_client_request(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: String,
    max_response_bytes: Int?,
    timeout: Duration?
) RawResponse!

export extern fn msstd_http_client_request_bytes(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: Bytes,
    max_response_bytes: Int?,
    timeout: Duration?
) RawResponse!

export extern fn msstd_http_serving_new(
    address: String,
    options: HttpServerOptions,
    handler: fn(HttpExchange) Unit!
) NativeServing!

// Another handle on the same serving, for a connection promise to own.
export extern fn msstd_http_serving_share(serving: NativeServing) NativeServing

export extern fn msstd_http_serving_address(serving: NativeServing) String

export extern fn msstd_http_serving_accept(serving: NativeServing) Int!

export extern fn msstd_http_serving_connect(
    serving: NativeServing,
    connection: Int
) Unit

export extern fn msstd_http_serving_release(serving: NativeServing) Unit

export extern fn msstd_http_body_close(handle: NativeResponseBody) Unit

export extern fn msstd_http_body_metadata(
    handle: NativeResponseBody
) HttpResponseMetadata

export extern fn msstd_http_body_read(
    handle: NativeResponseBody,
    max_bytes: Int?
) Bytes?!

export extern fn msstd_http_body_read_all(handle: NativeResponseBody) Bytes!

export extern fn msstd_http_headers_append(
    headers: HttpHeaders,
    name: String,
    value: Bytes
) Unit!

export extern fn msstd_http_headers_values(
    value: HttpHeaders,
    name: String
) List[Bytes]?

export extern fn msstd_http_headers_names(value: HttpHeaders) List[String]

export extern fn msstd_http_headers_remove(value: HttpHeaders, name: String) Bool

export extern fn msstd_http_headers_clone(value: HttpHeaders) HttpHeaders

export extern fn msstd_http_headers_new() HttpHeaders

// Limits the scheduler threads the runtime starts to `n` (at least 1).
export extern fn msrt_runtime_set_threads(n: Int) Unit
