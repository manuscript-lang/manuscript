import Bytes from "@std/bytes.ms"
import IoError, ReadStream from "@std/io/io.ms"
import (
    HttpError,
    HttpHeaders,
    HttpMethod,
    HttpResponseMetadata,
    NativeHttpClient,
    NativeHttpServer,
    NativeResponseBody,
    ResponseBody
) from "@std/net/http.ms"
import Duration from "@std/os/time.ms"

export extern fn msstd_http_client_close(handle: NativeHttpClient) Unit

export extern fn msstd_http_client_request(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: String,
    max_response_bytes: Int?,
    timeout: Duration?
) ResponseBody!HttpError

export extern fn msstd_http_client_request_bytes(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: Bytes,
    max_response_bytes: Int?,
    timeout: Duration?
) ResponseBody!HttpError

export extern fn msstd_http_client_request_stream(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: ReadStream,
    max_response_bytes: Int?,
    timeout: Duration?
) ResponseBody!HttpError

export extern fn msstd_http_server_address(handle: NativeHttpServer) String

export extern fn msstd_http_server_adopt(handle: NativeHttpServer, connection: Int) Unit

export extern fn msstd_http_server_close(handle: NativeHttpServer) Unit

export extern fn msstd_http_server_wait(handle: NativeHttpServer) Unit!IoError

export extern fn msstd_http_body_close(handle: NativeResponseBody) Unit

export extern fn msstd_http_body_metadata(
    handle: NativeResponseBody
) HttpResponseMetadata

export extern fn msstd_http_body_read(
    handle: NativeResponseBody,
    max_bytes: Int?
) Bytes?!IoError

export extern fn msstd_http_body_read_all(handle: NativeResponseBody) Bytes!IoError
