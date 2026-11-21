/* runtime/std/http_client.c: the client: options, the connection pool, cancellation, and the request loop
 * that follows redirects by the language's policy. One request on the wire is http_exchange.c. */
#include "base/alloc.h"
#include "base/chars.h"
#include "runtime/std/http_client_internal.h"
#include "runtime/std/time_internal.h"

/* ---- share locks: DNS, TLS sessions and cookies shared by every easy handle of a client ---- */

static void share_lock(CURL *handle, curl_lock_data data, curl_lock_access access, void *user) {
  (void)handle;
  (void)access;
  ms_spin_lock(&((MsHttpClient *)user)->share_locks[data]);
}

static void share_unlock(CURL *handle, curl_lock_data data, void *user) {
  (void)handle;
  ms_spin_unlock(&((MsHttpClient *)user)->share_locks[data]);
}

/* ---- lifecycle ---- */

static MsSpan keep(MsString *slot, MsSpan text) {
  *slot = ms_string_from_span(text);
  return ms_string_span(slot);
}

MsHttpClient *ms_http_client_new(const MsHttpClientOptions *options, MsString *err) {
  if ((options->limit_redirects && options->max_redirects < 0) ||
      (options->limit_idle && options->max_idle < 0) || options->max_header_bytes < 0 ||
      (options->expire_idle && options->idle_timeout_ns < 0) ||
      (options->certificate_pem.len > 0) != (options->private_key_pem.len > 0)) {
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

static void conn_destroy(HttpConn *conn) {
  curl_easy_cleanup(conn->easy);
  curl_multi_cleanup(conn->multi);
  ms_free(conn);
}

static void idle_drop_all(MsHttpClient *client) {
  ms_spin_lock(&client->lock);
  MsList idle = client->idle;
  client->idle = (MsList){0};
  ms_spin_unlock(&client->lock);
  HttpConn **items = (HttpConn **)(void *)idle.ptr;
  for (size_t i = 0; i < idle.len; i++) {
    conn_destroy(items[i]);
  }
  ms_list_free(&idle);
}

void ms_http_client_release(MsHttpClient *client) {
  if (client == NULL || atomic_fetch_sub(&client->refs, 1) != 1) {
    return;
  }
  idle_drop_all(client);
  ms_list_free(&client->active);
  curl_share_cleanup(client->share);
  ms_string_release(&client->roots);
  ms_string_release(&client->certificate);
  ms_string_release(&client->key);
  ms_free(client);
}

void ms_http_client_close(MsHttpClient *client) {
  atomic_store(&client->closed, true);
  ms_spin_lock(&client->lock);
  MsHttpResponse **items = (MsHttpResponse **)(void *)client->active.ptr;
  for (size_t i = 0; i < client->active.len; i++) {
    (void)curl_multi_wakeup(items[i]->conn->multi);
  }
  ms_spin_unlock(&client->lock);
  idle_drop_all(client);
}

bool ms_http_client_closed(const MsHttpClient *client) {
  return atomic_load(&((MsHttpClient *)(uintptr_t)client)->closed);
}

/* ---- the pool ---- */

static HttpConn *conn_new(void) {
  HttpConn *conn = ms_alloc_zeroed(sizeof *conn);
  conn->multi = curl_multi_init();
  conn->easy = curl_easy_init();
  return conn;
}

HttpConn *ms_http_conn_take(MsHttpClient *client) {
  const MsHttpClientOptions *o = &client->options;
  const int64_t now = ms_clock_monotonic_since_start();
  HttpConn *found = NULL;
  ms_spin_lock(&client->lock);
  while (client->idle.len > 0 && found == NULL) {
    HttpConn *conn = ((HttpConn **)(void *)client->idle.ptr)[--client->idle.len];
    if (o->expire_idle && now - conn->idle_since_ns > o->idle_timeout_ns) {
      conn_destroy(conn); /* idle too long, as is everything older */
      continue;
    }
    found = conn;
  }
  ms_spin_unlock(&client->lock);
  return found != NULL ? found : conn_new();
}

void ms_http_conn_give(MsHttpClient *client, HttpConn *conn, bool reusable) {
  if (!reusable || atomic_load(&client->closed)) {
    conn_destroy(conn);
    return;
  }
  conn->idle_since_ns = ms_clock_monotonic_since_start();
  HttpConn *oldest = NULL;
  ms_spin_lock(&client->lock);
  if (client->options.limit_idle && client->options.max_idle > 0 &&
      client->idle.len >= (size_t)client->options.max_idle) {
    HttpConn **items = (HttpConn **)(void *)client->idle.ptr;
    oldest = items[0];
    __builtin_memmove(items, items + 1, (client->idle.len - 1) * sizeof *items);
    client->idle.len--;
  }
  ms_list_push(&client->idle, sizeof conn, &conn);
  ms_spin_unlock(&client->lock);
  if (oldest != NULL) {
    conn_destroy(oldest);
  }
}

void ms_http_active_add(MsHttpClient *client, MsHttpResponse *response) {
  ms_spin_lock(&client->lock);
  ms_list_push(&client->active, sizeof response, &response);
  ms_spin_unlock(&client->lock);
}

void ms_http_active_remove(MsHttpClient *client, MsHttpResponse *response) {
  ms_spin_lock(&client->lock);
  MsHttpResponse **items = (MsHttpResponse **)(void *)client->active.ptr;
  for (size_t i = 0; i < client->active.len; i++) {
    if (items[i] == response) {
      items[i] = items[--client->active.len];
      break;
    }
  }
  ms_spin_unlock(&client->lock);
}
