/* runtime/std/http_client.c: the client record: options, its multi handle (run by the engine thread, which
 * also owns its connection pool) and its lifetime. A request is http_client_send.c and http_exchange.c. */
#include "base/alloc.h"
#include "runtime/std/http_client_internal.h"

/* ---- shared state: DNS, TLS sessions and cookies shared by the easy handles of one client ---- */

static void share_lock(CURL *handle, curl_lock_data data, curl_lock_access access, void *user) {
  (void)handle;
  (void)access;
  ms_http_mutex_lock(((MsHttpClient *)user)->share_locks[data]);
}

static void share_unlock(CURL *handle, curl_lock_data data, void *user) {
  (void)handle;
  ms_http_mutex_unlock(((MsHttpClient *)user)->share_locks[data]);
}

static MsSpan keep(MsString *slot, MsSpan text) {
  *slot = ms_string_from_span(text);
  return ms_string_span(slot);
}

static bool options_valid(const MsHttpClientOptions *o) {
  return !((o->limit_redirects && o->max_redirects < 0) || (o->limit_idle && o->max_idle < 0) ||
           o->max_header_bytes < 0 || (o->expire_idle && o->idle_timeout_ns < 0) ||
           (o->certificate_pem.len > 0) != (o->private_key_pem.len > 0));
}

MsHttpClient *ms_http_client_new(const MsHttpClientOptions *options, MsString *err) {
  if (!options_valid(options)) {
    *err = ms_string_from_span(ms_span_of_text("http: invalid client options"));
    return NULL;
  }
  MsHttpClient *client = ms_alloc_zeroed(sizeof *client);
  atomic_init(&client->refs, 1);
  atomic_init(&client->closed, false);
  client->options = *options;
  client->options.roots_pem = keep(&client->roots, options->roots_pem);
  client->options.certificate_pem = keep(&client->certificate, options->certificate_pem);
  client->options.private_key_pem = keep(&client->key, options->private_key_pem);
  client->multi = curl_multi_init();
  if (options->limit_idle && options->max_idle > 0) {
    curl_multi_setopt(client->multi, CURLMOPT_MAXCONNECTS, (long)options->max_idle);
  }
  for (size_t i = 0; i < CURL_LOCK_DATA_LAST; i++) {
    client->share_locks[i] = ms_http_mutex_new();
  }
  client->share = curl_share_init();
  curl_share_setopt(client->share, CURLSHOPT_LOCKFUNC, share_lock);
  curl_share_setopt(client->share, CURLSHOPT_UNLOCKFUNC, share_unlock);
  curl_share_setopt(client->share, CURLSHOPT_USERDATA, client);
  curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);
  curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_SSL_SESSION);
  if (options->cookies) {
    curl_share_setopt(client->share, CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);
  }
  return client;
}

MsHttpClient *ms_http_client_retain(MsHttpClient *client) {
  atomic_fetch_add(&client->refs, 1);
  return client;
}

void ms_http_client_release(MsHttpClient *client) {
  if (client != NULL && atomic_fetch_sub(&client->refs, 1) == 1) {
    ms_http_engine_free_client(client); /* the engine thread owns the multi handle, so it ends it */
  }
}

void ms_http_client_close(MsHttpClient *client) {
  atomic_store(&client->closed, true);
  ms_http_engine_close_client(client);
}

bool ms_http_client_closed(const MsHttpClient *client) {
  return atomic_load(&((MsHttpClient *)(uintptr_t)client)->closed);
}

void ms_http_client_handle_add(MsHttpClient *client) {
  atomic_fetch_add(&client->handles, 1);
}

int ms_http_client_handle_remove(MsHttpClient *client) {
  return atomic_fetch_sub(&client->handles, 1) - 1;
}

int ms_http_client_handle_count(const MsHttpClient *client) {
  return atomic_load(&((MsHttpClient *)(uintptr_t)client)->handles);
}
