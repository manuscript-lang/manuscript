/* runtime/std/http_engine.c: the thread that runs libcurl. One libuv loop drives every client's multi handle
 * with curl's socket interface (uv_poll for sockets, uv_timer for curl's timeout), so a request waits on no
 * thread of its own. Callers hand it work as commands through a queue and an async handle; it never calls
 * into the scheduler: the callers' waits are woken through the waiter hooks. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <uv.h>

#include "base/alloc.h"
#include "runtime/std/http_client_internal.h"

typedef enum CmdKind { CMD_START, CMD_RESUME, CMD_CANCEL, CMD_CLOSE_CLIENT, CMD_FREE_CLIENT } CmdKind;

typedef struct Cmd {
  CmdKind kind;
  MsHttpResponse *response;
  MsHttpClient *client;
  struct Cmd *next;
} Cmd;

static struct {
  uv_once_t once;
  uv_mutex_t lock;
  uv_loop_t loop;
  uv_async_t async;
  uv_thread_t thread;
  Cmd *head, *tail;
} engine = {.once = UV_ONCE_INIT};

/* A socket curl asked to watch. */
typedef struct SockWatch {
  uv_poll_t poll;
  MsHttpClient *client;
} SockWatch;

/* ---- curl's socket interface ---- */

static void end_transfer(MsHttpResponse *response, CURLcode result);

static void check_done(MsHttpClient *client) {
  int queued = 0;
  CURLMsg *message = NULL;
  while ((message = curl_multi_info_read(client->multi, &queued)) != NULL) {
    if (message->msg != CURLMSG_DONE) {
      continue;
    }
    MsHttpResponse *response = NULL;
    (void)curl_easy_getinfo(message->easy_handle, CURLINFO_PRIVATE, &response);
    if (response != NULL) {
      end_transfer(response, message->data.result);
    }
  }
}

static void act(MsHttpClient *client, curl_socket_t socket, int flags) {
  int running = 0;
  (void)curl_multi_socket_action(client->multi, socket, flags, &running);
  check_done(client);
}

static void on_poll(uv_poll_t *poll, int status, int events) {
  SockWatch *watch = (SockWatch *)poll;
  int flags = 0;
  if (status < 0) {
    flags = CURL_CSELECT_ERR;
  } else {
    flags = ((events & UV_READABLE) != 0 ? CURL_CSELECT_IN : 0) |
            ((events & UV_WRITABLE) != 0 ? CURL_CSELECT_OUT : 0);
  }
  uv_os_fd_t fd = 0;
  (void)uv_fileno((uv_handle_t *)poll, &fd);
  act(watch->client, (curl_socket_t)fd, flags);
}

static void on_watch_closed(uv_handle_t *handle) {
  ms_free(handle);
}

static int on_socket(CURL *easy, curl_socket_t socket, int what, void *user, void *socket_data) {
  (void)easy;
  MsHttpClient *client = user;
  SockWatch *watch = socket_data;
  if (what == CURL_POLL_REMOVE) {
    if (watch != NULL) {
      uv_poll_stop(&watch->poll);
      uv_close((uv_handle_t *)&watch->poll, on_watch_closed);
      (void)curl_multi_assign(client->multi, socket, NULL);
    }
    return 0;
  }
  if (watch == NULL) {
    watch = ms_alloc_zeroed(sizeof *watch);
    watch->client = client;
    if (uv_poll_init_socket(&engine.loop, &watch->poll, socket) != 0) {
      ms_free(watch);
      return -1;
    }
    (void)curl_multi_assign(client->multi, socket, watch);
  }
  const int events = (what == CURL_POLL_IN || what == CURL_POLL_INOUT ? UV_READABLE : 0) |
                     (what == CURL_POLL_OUT || what == CURL_POLL_INOUT ? UV_WRITABLE : 0);
  return uv_poll_start(&watch->poll, events, on_poll) == 0 ? 0 : -1;
}

static void on_timer_fired(uv_timer_t *timer) {
  act(timer->data, CURL_SOCKET_TIMEOUT, 0);
}

static int on_timeout(CURLM *multi, long timeout_ms, void *user) {
  (void)multi;
  MsHttpClient *client = user;
  uv_timer_t *timer = client->timer;
  if (timeout_ms < 0) {
    uv_timer_stop(timer);
  } else {
    uv_timer_start(timer, on_timer_fired, (uint64_t)timeout_ms, 0);
  }
  return 0;
}

/* The multi handle's callbacks and timer, set up on first use (on the engine thread). */
static void attach(MsHttpClient *client) {
  if (client->timer != NULL) {
    return;
  }
  uv_timer_t *timer = ms_alloc_zeroed(sizeof *timer);
  uv_timer_init(&engine.loop, timer);
  timer->data = client;
  client->timer = timer;
  curl_multi_setopt(client->multi, CURLMOPT_SOCKETFUNCTION, on_socket);
  curl_multi_setopt(client->multi, CURLMOPT_SOCKETDATA, client);
  curl_multi_setopt(client->multi, CURLMOPT_TIMERFUNCTION, on_timeout);
  curl_multi_setopt(client->multi, CURLMOPT_TIMERDATA, client);
}

/* ---- commands ---- */

static void remove_active(MsHttpClient *client, MsHttpResponse *response) {
  MsHttpResponse **items = (MsHttpResponse **)(void *)client->active.ptr;
  for (size_t i = 0; i < client->active.len; i++) {
    if (items[i] == response) {
      items[i] = items[--client->active.len];
      return;
    }
  }
}

/* A transfer ended (or is ended): takes its handle out of the multi and gives back the engine's reference. */
static void retire(MsHttpResponse *response) {
  MsHttpClient *client = response->client;
  remove_active(client, response);
  curl_multi_remove_handle(client->multi, response->easy);
  ms_http_response_unref(response);
}

static void do_start(MsHttpResponse *response) {
  MsHttpClient *client = response->client;
  attach(client);
  ms_list_push(&client->active, sizeof response, &response);
  curl_multi_add_handle(client->multi, response->easy);
  act(client, CURL_SOCKET_TIMEOUT, 0);
}

static bool is_active(const MsHttpResponse *response) {
  const MsHttpResponse *const *items =
      (const MsHttpResponse *const *)(const void *)response->client->active.ptr;
  for (size_t i = 0; i < response->client->active.len; i++) {
    if (items[i] == response) {
      return true;
    }
  }
  return false;
}

static void end_transfer(MsHttpResponse *response, CURLcode result) {
  ms_http_response_finished(response, result);
  retire(response);
}

static void do_cancel(MsHttpResponse *response) {
  if (is_active(response)) {
    end_transfer(response, CURLE_ABORTED_BY_CALLBACK);
  }
  ms_http_response_unref(response); /* the command's own reference */
}

static void do_close_client(MsHttpClient *client) {
  while (client->active.len > 0) {
    MsHttpResponse *response = ((MsHttpResponse **)(void *)client->active.ptr)[client->active.len - 1];
    end_transfer(response, CURLE_ABORTED_BY_CALLBACK);
  }
}

static void on_timer_closed(uv_handle_t *handle) {
  ms_free(handle);
}

static void do_free_client(MsHttpClient *client) {
  do_close_client(client);
  curl_multi_cleanup(client->multi); /* removes its sockets through on_socket */
  curl_share_cleanup(client->share);
  for (size_t i = 0; i < CURL_LOCK_DATA_LAST; i++) {
    ms_http_mutex_free(client->share_locks[i]);
  }
  if (client->timer != NULL) {
    uv_close((uv_handle_t *)client->timer, on_timer_closed);
  }
  ms_list_free(&client->active);
  ms_string_release(&client->roots);
  ms_string_release(&client->certificate);
  ms_string_release(&client->key);
  ms_free(client);
}

static void run(Cmd *cmd) {
  switch (cmd->kind) {
  case CMD_START:
    do_start(cmd->response);
    break;
  case CMD_RESUME:
    if (is_active(cmd->response)) {
      (void)curl_easy_pause(cmd->response->easy, CURLPAUSE_CONT);
      act(cmd->response->client, CURL_SOCKET_TIMEOUT, 0);
    }
    ms_http_response_unref(cmd->response);
    break;
  case CMD_CANCEL:
    do_cancel(cmd->response);
    break;
  case CMD_CLOSE_CLIENT:
    do_close_client(cmd->client);
    break;
  case CMD_FREE_CLIENT:
    do_free_client(cmd->client);
    break;
  }
}

static void on_async(uv_async_t *async) {
  (void)async;
  for (;;) {
    uv_mutex_lock(&engine.lock);
    Cmd *cmd = engine.head;
    if (cmd != NULL) {
      engine.head = cmd->next;
      if (engine.head == NULL) {
        engine.tail = NULL;
      }
    }
    uv_mutex_unlock(&engine.lock);
    if (cmd == NULL) {
      return;
    }
    run(cmd);
    ms_free(cmd);
  }
}

static void engine_main(void *unused) {
  (void)unused;
  (void)uv_run(&engine.loop, UV_RUN_DEFAULT);
}

static void engine_init(void) {
  (void)uv_mutex_init(&engine.lock);
  (void)uv_loop_init(&engine.loop);
  (void)uv_async_init(&engine.loop, &engine.async, on_async);
  (void)uv_thread_create(&engine.thread, engine_main, NULL);
}

static void submit(CmdKind kind, MsHttpResponse *response, MsHttpClient *client) {
  uv_once(&engine.once, engine_init);
  Cmd *cmd = ms_alloc_zeroed(sizeof *cmd);
  cmd->kind = kind;
  cmd->response = response;
  cmd->client = client;
  uv_mutex_lock(&engine.lock);
  if (engine.tail != NULL) {
    engine.tail->next = cmd;
  } else {
    engine.head = cmd;
  }
  engine.tail = cmd;
  uv_mutex_unlock(&engine.lock);
  (void)uv_async_send(&engine.async);
}

/* A command that outlives the caller's reference holds its own. */
static void hold(MsHttpResponse *response) {
  atomic_fetch_add(&response->refs, 1);
}

void ms_http_engine_start(MsHttpResponse *response) {
  hold(response); /* the engine's, given back by retire */
  submit(CMD_START, response, NULL);
}

void ms_http_engine_resume(MsHttpResponse *response) {
  hold(response);
  submit(CMD_RESUME, response, NULL);
}

void ms_http_engine_cancel(MsHttpResponse *response) {
  hold(response);
  submit(CMD_CANCEL, response, NULL);
}

void ms_http_engine_close_client(MsHttpClient *client) {
  submit(CMD_CLOSE_CLIENT, NULL, client);
}

void ms_http_engine_free_client(MsHttpClient *client) {
  submit(CMD_FREE_CLIENT, NULL, client);
}
