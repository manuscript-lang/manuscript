/* runtime/io/edge.c: edge-triggered descriptor registrations on epoll (see edge.h). Other platforms report no support
 * and the callers use the one-shot watches of reactor.c. */
#define _GNU_SOURCE

#include "runtime/io/edge.h"

#ifdef __linux__

#include <errno.h>
#include <sys/epoll.h>
#include <unistd.h>

#include "base/alloc.h"
#include "base/list.h"

typedef struct EdgeRow {
  uint64_t cookie;  /* whose registration this is; 0 when none */
  uint32_t serial;  /* tells this registration's events from a closed one's of the same descriptor number */
  uint8_t ready;    /* MS_IO_BIT_* seen since the last reset */
  uint8_t armed;    /* what a waiter asked for and no edge has answered yet */
} EdgeRow;

MS_LIST_DEFINE(RowList, row_list, EdgeRow)

struct MsEdge {
  int epoll;
  uv_poll_t watch; /* the epoll descriptor in the reactor's loop: readable while edges wait */
  MsIoRing *ring;  /* where the callback that ends a blocking pass puts what it takes */
  RowList rows;    /* by descriptor */
  uint32_t serial;
};

enum { DRAIN_BATCH = 64 };

bool ms_edge_supported(void) { return true; }

static void on_ready(uv_poll_t *handle, int status, int events) {
  (void)status;
  (void)events;
  MsEdge *edge = uv_handle_get_data((uv_handle_t *)handle);
  (void)ms_edge_drain(edge, edge->ring);
}

MsEdge *ms_edge_open(uv_loop_t *loop, MsIoRing *ring) {
  const int epoll = epoll_create1(EPOLL_CLOEXEC);
  if (epoll < 0) {
    return NULL;
  }
  MsEdge *edge = ms_alloc_zeroed(sizeof *edge);
  edge->epoll = epoll;
  edge->ring = ring;
  if (uv_poll_init(loop, &edge->watch, epoll) != 0) {
    (void)close(epoll);
    ms_free(edge);
    return NULL;
  }
  uv_handle_set_data((uv_handle_t *)&edge->watch, edge);
  if (uv_poll_start(&edge->watch, UV_READABLE, on_ready) != 0) {
    uv_close((uv_handle_t *)&edge->watch, NULL);
    (void)close(epoll);
    ms_free(edge);
    return NULL;
  }
  return edge;
}

void ms_edge_close(MsEdge *edge) {
  uv_poll_stop(&edge->watch);
  uv_close((uv_handle_t *)&edge->watch, NULL);
  (void)close(edge->epoll);
  row_list_free(&edge->rows);
  ms_free(edge);
}

static EdgeRow *row_at(MsEdge *edge, int fd) {
  if (fd < 0) {
    return NULL;
  }
  while ((size_t)fd >= edge->rows.len) {
    row_list_push(&edge->rows, (EdgeRow){0});
  }
  return &edge->rows.ptr[fd];
}

static bool register_fd(MsEdge *edge, int fd, EdgeRow *row) {
  struct epoll_event event = {.events = EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET,
                              .data.u64 = (uint64_t)row->serial << 32 | (uint32_t)fd};
  if (epoll_ctl(edge->epoll, EPOLL_CTL_ADD, fd, &event) == 0) {
    return true;
  }
  /* The number was registered before and its old file is still open somewhere: replace the registration. */
  return errno == EEXIST && epoll_ctl(edge->epoll, EPOLL_CTL_MOD, fd, &event) == 0;
}

bool ms_edge_reset(MsEdge *edge, int fd, uint64_t cookie, uint32_t bits) {
  EdgeRow *row = row_at(edge, fd);
  if (row == NULL) {
    return false;
  }
  if (row->cookie != cookie) {
    *row = (EdgeRow){.cookie = cookie, .serial = ++edge->serial};
    if (!register_fd(edge, fd, row)) {
      row->cookie = 0;
      return false;
    }
    return true; /* new: the first system call finds out what is there */
  }
  row->ready &= (uint8_t)~bits;
  return true;
}

bool ms_edge_ready(const MsEdge *edge, int fd, uint32_t bits) {
  return fd >= 0 && (size_t)fd < edge->rows.len && (edge->rows.ptr[fd].ready & bits) != 0;
}

bool ms_edge_arm(MsEdge *edge, int fd, uint32_t bits, MsIoRing *ring) {
  EdgeRow *row = row_at(edge, fd);
  if (row == NULL || row->cookie == 0) {
    return false;
  }
  const uint32_t held = row->ready & bits;
  if (held == 0) {
    row->armed |= (uint8_t)bits;
    return true;
  }
  if ((held & MS_IO_BIT_READ) != 0 &&
      !ms_io_ring_push(ring, (MsIoEvent){.id = (uint64_t)fd, .result = 0, .kind = MS_IO_READ})) {
    return false;
  }
  if ((held & MS_IO_BIT_WRITE) != 0 &&
      !ms_io_ring_push(ring, (MsIoEvent){.id = (uint64_t)fd, .result = 0, .kind = MS_IO_WRITE})) {
    return false;
  }
  return true;
}

void ms_edge_disarm(MsEdge *edge, int fd) {
  if (fd >= 0 && (size_t)fd < edge->rows.len) {
    edge->rows.ptr[fd].armed = 0;
  }
}

void ms_edge_forget(MsEdge *edge, int fd) {
  if (fd >= 0 && (size_t)fd < edge->rows.len && edge->rows.ptr[fd].cookie != 0) {
    (void)epoll_ctl(edge->epoll, EPOLL_CTL_DEL, fd, NULL);
    edge->rows.ptr[fd] = (EdgeRow){0};
  }
}

size_t ms_edge_drain(MsEdge *edge, MsIoRing *ring) {
  struct epoll_event events[DRAIN_BATCH];
  size_t queued = 0;
  for (;;) {
    /* Each edge may queue two events; what does not fit stays in the kernel's list for the next pass. */
    const uint32_t room = ms_io_ring_capacity(ring) - ms_io_ring_length(ring);
    int batch = (int)(room / 2);
    if (batch <= 0) {
      return queued;
    }
    batch = batch > DRAIN_BATCH ? DRAIN_BATCH : batch;
    const int count = epoll_wait(edge->epoll, events, batch, 0);
    for (int i = 0; i < count; i++) {
      const int fd = (int)(uint32_t)events[i].data.u64;
      const uint32_t serial = (uint32_t)(events[i].data.u64 >> 32);
      if ((size_t)fd >= edge->rows.len || edge->rows.ptr[fd].serial != serial || edge->rows.ptr[fd].cookie == 0) {
        continue; /* a registration of a closed descriptor */
      }
      EdgeRow *row = &edge->rows.ptr[fd];
      uint32_t bits = 0;
      if ((events[i].events & EPOLLIN) != 0) {
        bits |= MS_IO_BIT_READ;
      }
      if ((events[i].events & EPOLLOUT) != 0) {
        bits |= MS_IO_BIT_WRITE;
      }
      if ((events[i].events & (EPOLLERR | EPOLLHUP | EPOLLRDHUP)) != 0) {
        bits |= MS_IO_BIT_READ | MS_IO_BIT_WRITE;
      }
      row->ready |= (uint8_t)bits;
      if ((row->armed & bits) != 0) {
        if ((row->armed & bits & MS_IO_BIT_READ) != 0) {
          (void)ms_io_ring_push(ring, (MsIoEvent){.id = (uint64_t)fd, .result = 0, .kind = MS_IO_READ});
          queued++;
        }
        if ((row->armed & bits & MS_IO_BIT_WRITE) != 0) {
          (void)ms_io_ring_push(ring, (MsIoEvent){.id = (uint64_t)fd, .result = 0, .kind = MS_IO_WRITE});
          queued++;
        }
        row->armed &= (uint8_t)~bits;
      }
    }
    if (count < batch) {
      return queued;
    }
  }
}

#else

bool ms_edge_supported(void) { return false; }
MsEdge *ms_edge_open(uv_loop_t *loop, MsIoRing *ring) {
  (void)loop;
  (void)ring;
  return NULL;
}
void ms_edge_close(MsEdge *edge) { (void)edge; }
bool ms_edge_reset(MsEdge *edge, int fd, uint64_t cookie, uint32_t bits) {
  (void)edge;
  (void)fd;
  (void)cookie;
  (void)bits;
  return false;
}
bool ms_edge_ready(const MsEdge *edge, int fd, uint32_t bits) {
  (void)edge;
  (void)fd;
  (void)bits;
  return false;
}
bool ms_edge_arm(MsEdge *edge, int fd, uint32_t bits, MsIoRing *ring) {
  (void)edge;
  (void)fd;
  (void)bits;
  (void)ring;
  return false;
}
void ms_edge_disarm(MsEdge *edge, int fd) { (void)edge;
  (void)fd; }
void ms_edge_forget(MsEdge *edge, int fd) { (void)edge;
  (void)fd; }
size_t ms_edge_drain(MsEdge *edge, MsIoRing *ring) {
  (void)edge;
  (void)ring;
  return 0;
}

#endif
