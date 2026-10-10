/* The generated ordinary wrappers include these stateful callback adapters.
 * Native client_data is passed through unchanged. Only the wide callback
 * values cross a thunk; no archive input or output is staged here. */
struct cpkt_archive_callbacks {
  uintptr_t archive_key;
  cpkt_archive_archive_skip_callback *skip;
  cpkt_archive_archive_seek_callback *seek;
  struct cpkt_archive_callbacks *next;
};
static pthread_mutex_t cpkt_archive_callbacks_mutex = PTHREAD_MUTEX_INITIALIZER;
static struct cpkt_archive_callbacks *cpkt_archive_callbacks_head;

static int cpkt_archive_callbacks_set(struct archive *archive,
                                      cpkt_archive_archive_skip_callback *skip,
                                      cpkt_archive_archive_seek_callback *seek,
                                      int set_seek) {
  struct cpkt_archive_callbacks *item;
  pthread_mutex_lock(&cpkt_archive_callbacks_mutex);
  for (item = cpkt_archive_callbacks_head;
       item && item->archive_key != (uintptr_t)archive; item = item->next) {
  }
  if (!item) {
    if ((set_seek && !seek) || (!set_seek && !skip)) {
      pthread_mutex_unlock(&cpkt_archive_callbacks_mutex);
      return ARCHIVE_OK;
    }
    item = calloc(1, sizeof(*item));
    if (!item) {
      pthread_mutex_unlock(&cpkt_archive_callbacks_mutex);
      archive_set_error(archive, ENOMEM, "C89 callback allocation failed");
      return ARCHIVE_FATAL;
    }
    item->archive_key = (uintptr_t)archive;
    item->next = cpkt_archive_callbacks_head;
    cpkt_archive_callbacks_head = item;
  }
  if (set_seek)
    item->seek = seek;
  else
    item->skip = skip;
  pthread_mutex_unlock(&cpkt_archive_callbacks_mutex);
  return ARCHIVE_OK;
}

static la_int64_t cpkt_archive_skip(struct archive *archive, void *data,
                                    la_int64_t request) {
  struct cpkt_archive_callbacks *item;
  cpkt_archive_archive_skip_callback *callback = NULL;
  pthread_mutex_lock(&cpkt_archive_callbacks_mutex);
  for (item = cpkt_archive_callbacks_head;
       item && item->archive_key != (uintptr_t)archive; item = item->next) {
  }
  if (item)
    callback = item->skip;
  pthread_mutex_unlock(&cpkt_archive_callbacks_mutex);
  return callback
             ? cpkt_archive_signed_to_native(callback(
                   archive, data, cpkt_archive_signed_from_native(request)))
             : 0;
}

static la_int64_t cpkt_archive_seek(struct archive *archive, void *data,
                                    la_int64_t offset, int whence) {
  struct cpkt_archive_callbacks *item;
  cpkt_archive_archive_seek_callback *callback = NULL;
  pthread_mutex_lock(&cpkt_archive_callbacks_mutex);
  for (item = cpkt_archive_callbacks_head;
       item && item->archive_key != (uintptr_t)archive; item = item->next) {
  }
  if (item)
    callback = item->seek;
  pthread_mutex_unlock(&cpkt_archive_callbacks_mutex);
  return callback ? cpkt_archive_signed_to_native(callback(
                        archive, data, cpkt_archive_signed_from_native(offset),
                        whence))
                  : -1;
}

static void cpkt_archive_callbacks_remove(uintptr_t archive_key) {
  struct cpkt_archive_callbacks **link, *item;
  pthread_mutex_lock(&cpkt_archive_callbacks_mutex);
  for (link = &cpkt_archive_callbacks_head;
       *link && (*link)->archive_key != archive_key; link = &(*link)->next) {
  }
  item = *link;
  if (item)
    *link = item->next;
  pthread_mutex_unlock(&cpkt_archive_callbacks_mutex);
  free(item);
}

int cpkt_archive_archive_read_set_skip_callback(
    struct archive *archive, cpkt_archive_archive_skip_callback *callback) {
  int result = cpkt_archive_callbacks_set(archive, callback, NULL, 0);
  if (result != ARCHIVE_OK)
    return result;
  return archive_read_set_skip_callback(archive,
                                        callback ? cpkt_archive_skip : NULL);
}
int cpkt_archive_archive_read_set_seek_callback(
    struct archive *archive, cpkt_archive_archive_seek_callback *callback) {
  int result = cpkt_archive_callbacks_set(archive, NULL, callback, 1);
  if (result != ARCHIVE_OK)
    return result;
  return archive_read_set_seek_callback(archive,
                                        callback ? cpkt_archive_seek : NULL);
}
int cpkt_archive_archive_read_open2(
    struct archive *archive, void *data,
    cpkt_archive_archive_open_callback *open_callback,
    cpkt_archive_archive_read_callback *read_callback,
    cpkt_archive_archive_skip_callback *skip_callback,
    cpkt_archive_archive_close_callback *close_callback) {
  int result = cpkt_archive_callbacks_set(archive, skip_callback, NULL, 0);
  if (result != ARCHIVE_OK)
    return result;
  return archive_read_open2(archive, data, open_callback, read_callback,
                            skip_callback ? cpkt_archive_skip : NULL,
                            close_callback);
}

#define CPKT_ARCHIVE_FREE(name)                                                \
  int cpkt_archive_##name(struct archive *archive) {                           \
    uintptr_t archive_key = (uintptr_t)archive;                                \
    int result = name(archive);                                                \
    cpkt_archive_callbacks_remove(archive_key);                                \
    return result;                                                             \
  }
CPKT_ARCHIVE_FREE(archive_free)
CPKT_ARCHIVE_FREE(archive_read_free)
CPKT_ARCHIVE_FREE(archive_write_free)
CPKT_ARCHIVE_FREE(archive_read_finish)
CPKT_ARCHIVE_FREE(archive_write_finish)
#undef CPKT_ARCHIVE_FREE

struct cpkt_archive_lookup {
  void *data;
  cpkt_compression_i64 (*id)(void *, const char *, cpkt_compression_i64);
  const char *(*name)(void *, cpkt_compression_i64);
  void (*cleanup)(void *);
};
static la_int64_t cpkt_archive_lookup_id(void *context, const char *name,
                                         la_int64_t id) {
  struct cpkt_archive_lookup *lookup = context;
  return cpkt_archive_signed_to_native(
      lookup->id(lookup->data, name, cpkt_archive_signed_from_native(id)));
}
static const char *cpkt_archive_lookup_name(void *context, la_int64_t id) {
  struct cpkt_archive_lookup *lookup = context;
  return lookup->name(lookup->data, cpkt_archive_signed_from_native(id));
}
static void cpkt_archive_lookup_cleanup(void *context) {
  struct cpkt_archive_lookup *lookup = context;
  if (lookup->cleanup)
    lookup->cleanup(lookup->data);
  free(lookup);
}
#define CPKT_ARCHIVE_ID_LOOKUP(name)                                           \
  int cpkt_archive_##name(struct archive *archive, void *data,                 \
                          cpkt_compression_i64 (*callback)(                    \
                              void *, const char *, cpkt_compression_i64),     \
                          void (*cleanup)(void *)) {                           \
    struct cpkt_archive_lookup *lookup;                                        \
    int result;                                                                \
    if (!callback)                                                             \
      return name(archive, data, NULL, cleanup);                               \
    lookup = calloc(1, sizeof(*lookup));                                       \
    if (!lookup) {                                                             \
      archive_set_error(archive, ENOMEM, "C89 lookup allocation failed");      \
      return ARCHIVE_FATAL;                                                    \
    }                                                                          \
    lookup->data = data;                                                       \
    lookup->id = callback;                                                     \
    lookup->cleanup = cleanup;                                                 \
    result = name(archive, lookup, cpkt_archive_lookup_id,                     \
                  cpkt_archive_lookup_cleanup);                                \
    if (result != ARCHIVE_OK)                                                  \
      free(lookup);                                                            \
    return result;                                                             \
  }
CPKT_ARCHIVE_ID_LOOKUP(archive_write_disk_set_group_lookup)
CPKT_ARCHIVE_ID_LOOKUP(archive_write_disk_set_user_lookup)
#undef CPKT_ARCHIVE_ID_LOOKUP
#define CPKT_ARCHIVE_NAME_LOOKUP(function)                                     \
  int cpkt_archive_##function(                                                 \
      struct archive *archive, void *data,                                     \
      const char *(*callback)(void *, cpkt_compression_i64),                   \
      void (*cleanup)(void *)) {                                               \
    struct cpkt_archive_lookup *lookup;                                        \
    int result;                                                                \
    if (!callback)                                                             \
      return function(archive, data, NULL, cleanup);                           \
    lookup = calloc(1, sizeof(*lookup));                                       \
    if (!lookup) {                                                             \
      archive_set_error(archive, ENOMEM, "C89 lookup allocation failed");      \
      return ARCHIVE_FATAL;                                                    \
    }                                                                          \
    lookup->data = data;                                                       \
    lookup->name = callback;                                                   \
    lookup->cleanup = cleanup;                                                 \
    result = function(archive, lookup, cpkt_archive_lookup_name,               \
                      cpkt_archive_lookup_cleanup);                            \
    if (result != ARCHIVE_OK)                                                  \
      free(lookup);                                                            \
    return result;                                                             \
  }
CPKT_ARCHIVE_NAME_LOOKUP(archive_read_disk_set_gname_lookup)
CPKT_ARCHIVE_NAME_LOOKUP(archive_read_disk_set_uname_lookup)
#undef CPKT_ARCHIVE_NAME_LOOKUP

void cpkt_archive_archive_set_error(struct archive *archive, int error,
                                    const char *format, ...) {
  va_list args, copy;
  char *message;
  int length;
  va_start(args, format);
  va_copy(copy, args);
  length = vsnprintf(NULL, 0, format, copy);
  va_end(copy);
  if (length < 0 || !(message = malloc((size_t)length + 1))) {
    va_end(args);
    archive_set_error(archive, ENOMEM, "C89 error formatting failed");
    return;
  }
  vsnprintf(message, (size_t)length + 1, format, args);
  va_end(args);
  archive_set_error(archive, error, "%s", message);
  free(message);
}
