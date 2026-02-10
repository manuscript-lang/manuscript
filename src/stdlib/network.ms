// std/network - Minimal fetch wrapper

type FetchOptions
  method?: string
  body?: string
  headers?: map[string, string]

type FetchResponse
  status: number
  body: string

type FetchStreamResponse
  status: number
  body: Stream[string]

extern fn fetch(url: string, options?: FetchOptions): Promise[FetchResponse]
extern fn fetch_stream(url: string, options?: FetchOptions): Promise[FetchStreamResponse]
