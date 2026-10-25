package main

import (
 "encoding/json"
 "fmt"
 "io"
 "net/http"
 "os"
 "time"
)

type Input struct { Name string `json:"name"` }
func main() {
 mux := http.NewServeMux()
 message := func(w http.ResponseWriter, name string) {w.Header().Set("Content-Type", "application/json"); json.NewEncoder(w).Encode(map[string]string{"message": "Hello, " + name})}
 mux.HandleFunc("GET /hello/{name}", func(w http.ResponseWriter, r *http.Request) {message(w, r.PathValue("name"))})
 mux.HandleFunc("POST /echo", func(w http.ResponseWriter, r *http.Request) {
  reader := http.MaxBytesReader(w, r.Body, 4096); defer reader.Close()
  decoder := json.NewDecoder(reader); decoder.DisallowUnknownFields()
  var input Input; var trailing any
  if decoder.Decode(&input) != nil || decoder.Decode(&trailing) != io.EOF {http.Error(w, "Invalid JSON", 400); return}
  message(w, input.Name)
 })
 mux.HandleFunc("GET /events", func(w http.ResponseWriter, r *http.Request) {
  w.Header().Set("Content-Type", "text/event-stream"); fmt.Fprint(w,"data: one\n\n"); w.(http.Flusher).Flush()
  select {case <-r.Context().Done(): return; case <-time.After(10*time.Millisecond): fmt.Fprint(w,"data: two\n\n")}
 })
 mux.HandleFunc("GET /{$}", func(w http.ResponseWriter,r *http.Request) {w.Header().Set("Content-Type","text/html"); fmt.Fprint(w,"<h1>Hello</h1>")})
 port:=os.Getenv("PORT"); if port=="" {port="19803"}
 server:=&http.Server{Addr:"127.0.0.1:"+port, Handler:http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){w.Header().Set("X-Example","reference");mux.ServeHTTP(w,r)}), ReadHeaderTimeout:5*time.Second}
 if error:=server.ListenAndServe(); error!=nil && error!=http.ErrServerClosed {panic(error)}
}
