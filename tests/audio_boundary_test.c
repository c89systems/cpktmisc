#if defined(__linux__)
#define _GNU_SOURCE
#endif
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

/* Load the real ring implementation before interposing its publication point.
 * This schedules a device callback deterministically, without audio hardware.
 */
#define MA_API static
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_NO_GENERATION
#define MA_NO_ALSA
#define MA_NO_PULSEAUDIO
#define MA_NO_JACK
#define MA_NO_COREAUDIO
#define MA_NO_RUNTIME_LINKING
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>

static ma_device *consume_after_commit;
static float played[1600];
static unsigned long simulated_ms;
static unsigned long callback_elapsed_ms;
static unsigned long requested_sleep_ms;
static int bounded_allocations;
static ma_result publish_and_consume(ma_pcm_rb *rb, ma_uint32 count);
static void *bounded_realloc(void *memory, size_t size);
static int observed_time(struct timeval *tv, void *zone);
static void observed_sleep(ma_uint32 milliseconds);
static ma_result observed_start(ma_device *device);
#define ma_pcm_rb_commit_write publish_and_consume
#define realloc bounded_realloc
#define gettimeofday observed_time
#define ma_sleep observed_sleep
#define ma_device_start observed_start
#include "../src/audio.c"
#undef ma_pcm_rb_commit_write
#undef realloc
#undef gettimeofday
#undef ma_sleep
#undef ma_device_start

static ma_result observed_start(ma_device *device) {
  struct cpkt_audio_playback_impl *impl;
  ma_uint32 count;
  if (simulated_ms == 0)
    return ma_device_start(device);
  impl = device->pUserData;
  count = ma_pcm_rb_available_read(&impl->rb);
  if (count != 0)
    cpkt_audio_playback_callback(device, played, NULL, count);
  simulated_ms += callback_elapsed_ms;
  return MA_SUCCESS;
}

static ma_result publish_and_consume(ma_pcm_rb *rb, ma_uint32 count) {
  ma_result result = ma_pcm_rb_commit_write(rb, count);
  if (result == MA_SUCCESS && consume_after_commit != NULL) {
    cpkt_audio_playback_callback(consume_after_commit, played, NULL, count);
    simulated_ms += callback_elapsed_ms;
  }
  return result;
}

static int observed_time(struct timeval *tv, void *zone) {
  if (simulated_ms == 0)
    return gettimeofday(tv, zone);
  tv->tv_sec = simulated_ms / 1000UL;
  tv->tv_usec = (simulated_ms % 1000UL) * 1000UL;
  return 0;
}

static void observed_sleep(ma_uint32 milliseconds) {
  if (simulated_ms == 0) {
    ma_sleep(milliseconds);
  } else {
    requested_sleep_ms += milliseconds;
    simulated_ms += milliseconds;
  }
}

static void *bounded_realloc(void *memory, size_t size) {
  if (bounded_allocations && size > 4U * 1024U * 1024U) {
    return NULL;
  }
  return realloc(memory, size);
}

#define CHECK(expression)                                                      \
  do {                                                                         \
    if (!(expression)) {                                                       \
      fprintf(stderr, "audio boundary: %s failed at line %d\n", #expression,   \
              __LINE__);                                                       \
      return 1;                                                                \
    }                                                                          \
  } while (0)

static int playback_drain(void) {
  struct cpkt_audio_playback_impl impl = {0};
  cpkt_audio_playback playback = {0};
  float frames[8] = {0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f, 0.7f, 0.8f};
  size_t written = 0;
  CHECK(ma_pcm_rb_init(ma_format_f32, 1, 8, NULL, NULL, &impl.rb) ==
        MA_SUCCESS);
  impl.device.pUserData = &impl;
  impl.started = 1;
  playback.impl = &impl;
  consume_after_commit = &impl.device;
  CHECK(cpkt_audio_playback_write_f32_mono_16k_impl(&playback, frames, 8,
                                                    &written) == CPKT_AUDIO_OK);
  consume_after_commit = NULL;
  CHECK(written == 8 && memcmp(played, frames, sizeof(frames)) == 0);
  CHECK(cpkt_audio_playback_drain_impl(&playback) == CPKT_AUDIO_OK);
  ma_pcm_rb_uninit(&impl.rb);
  return 0;
}

static int capture_overrun(void) {
  struct cpkt_audio_capture_impl impl = {0};
  cpkt_audio_capture capture = {0};
  float original[8] = {1, 2, 3, 4, 5, 6, 7, 8};
  float incoming[8] = {11, 12, 13, 14, 15, 16, 17, 18};
  float output[8];
  void *held = NULL;
  ma_uint32 count = 4;
  size_t read = 0;
  CHECK(ma_pcm_rb_init(ma_format_f32, 1, 8, NULL, NULL, &impl.rb) ==
        MA_SUCCESS);
  impl.device.pUserData = &impl;
  capture.impl = &impl;
  cpkt_audio_capture_callback(&impl.device, NULL, original, 8);
  CHECK(ma_pcm_rb_acquire_read(&impl.rb, &count, &held) == MA_SUCCESS &&
        count == 4);
  /* The producer overruns while the consumer still owns this read view. */
  cpkt_audio_capture_callback(&impl.device, NULL, incoming, 8);
  CHECK(memcmp(held, original, count * sizeof(float)) == 0);
  CHECK(ma_pcm_rb_commit_read(&impl.rb, count) == MA_SUCCESS);
  CHECK(cpkt_audio_capture_read_f32_mono_16k_impl(&capture, output, 8, &read) ==
        CPKT_AUDIO_OK);
  CHECK(read == 4 && memcmp(output, original + 4, 4 * sizeof(float)) == 0);
  cpkt_audio_capture_callback(&impl.device, NULL, incoming, 8);
  CHECK(cpkt_audio_capture_read_f32_mono_16k_impl(&capture, output, 8, &read) ==
        CPKT_AUDIO_OK);
  CHECK(read == 8 && memcmp(output, incoming, sizeof(incoming)) == 0);
  ma_pcm_rb_uninit(&impl.rb);
  return 0;
}

static int playback_timing(void) {
  struct cpkt_audio_playback_impl impl = {0};
  cpkt_audio_playback playback = {0};
  float frames[3200];
  size_t written = 0;
  size_t i;
  for (i = 0; i < 3200; ++i)
    frames[i] = 0.1f;
  CHECK(ma_pcm_rb_init(ma_format_f32, 1, 1600, NULL, NULL, &impl.rb) ==
        MA_SUCCESS);
  impl.device.pUserData = &impl;
  impl.started = 1;
  playback.impl = &impl;
  simulated_ms = 1000;
  callback_elapsed_ms = 100;
  consume_after_commit = &impl.device;
  CHECK(cpkt_audio_playback_write_f32_mono_16k_impl(&playback, frames, 3200,
                                                    &written) == CPKT_AUDIO_OK);
  consume_after_commit = NULL;
  CHECK(written == 3200 && simulated_ms == 1200);
  CHECK(cpkt_audio_playback_drain_impl(&playback) == CPKT_AUDIO_OK);
  CHECK(requested_sleep_ms == 0);
  ma_pcm_rb_uninit(&impl.rb);
  return 0;
}

static int playback_stopped(void) {
  struct cpkt_audio_playback_impl impl = {0};
  cpkt_audio_playback playback = {0};
  float frames[8] = {0};
  void *write_view = NULL;
  void *read_view = NULL;
  ma_uint32 count = 8;
  CHECK(ma_pcm_rb_init(ma_format_f32, 1, 8, NULL, NULL, &impl.rb) ==
        MA_SUCCESS);
  playback.impl = &impl;
  CHECK(ma_pcm_rb_acquire_write(&impl.rb, &count, &write_view) == MA_SUCCESS &&
        count == 8);
  memcpy(write_view, frames, sizeof(frames));
  CHECK(ma_pcm_rb_commit_write(&impl.rb, count) == MA_SUCCESS);
  /* stop() leaves the ring queued but stops its device consumer. */
  CHECK(cpkt_audio_playback_drain_impl(&playback) == CPKT_AUDIO_ERR_IO);
  count = 8;
  CHECK(ma_pcm_rb_acquire_read(&impl.rb, &count, &read_view) == MA_SUCCESS);
  CHECK(ma_pcm_rb_commit_read(&impl.rb, count) == MA_SUCCESS);
  CHECK(cpkt_audio_playback_drain_impl(&playback) == CPKT_AUDIO_OK);
  ma_pcm_rb_uninit(&impl.rb);
  return 0;
}

static int playback_gaps(void) {
  struct cpkt_audio_playback_impl impl = {0};
  cpkt_audio_playback playback = {0};
  float frames[16] = {0};
  size_t written = 0;
  CHECK(ma_pcm_rb_init(ma_format_f32, 1, 16, NULL, NULL, &impl.rb) ==
        MA_SUCCESS);
  impl.device.pUserData = &impl;
  impl.started = 1;
  impl.drain_latency_ms = 100;
  playback.impl = &impl;
  simulated_ms = 1000;
  callback_elapsed_ms = 1;
  consume_after_commit = &impl.device;
  CHECK(cpkt_audio_playback_write_f32_mono_16k_impl(&playback, frames, 16,
                                                    &written) == CPKT_AUDIO_OK);
  simulated_ms += 1000;
  CHECK(cpkt_audio_playback_write_f32_mono_16k_impl(&playback, frames, 16,
                                                    &written) == CPKT_AUDIO_OK);
  consume_after_commit = NULL;
  CHECK(cpkt_audio_playback_drain_impl(&playback) == CPKT_AUDIO_OK);
  CHECK(requested_sleep_ms == 100);
  ma_pcm_rb_uninit(&impl.rb);
  return 0;
}

static int playback_restart(void) {
  struct cpkt_audio_playback_impl impl = {0};
  cpkt_audio_playback playback = {0};
  float frames[16] = {0};
  void *write_view = NULL;
  ma_uint32 count = 16;
  CHECK(ma_pcm_rb_init(ma_format_f32, 1, 16, NULL, NULL, &impl.rb) ==
        MA_SUCCESS);
  CHECK(ma_pcm_rb_acquire_write(&impl.rb, &count, &write_view) == MA_SUCCESS);
  memcpy(write_view, frames, sizeof(frames));
  CHECK(ma_pcm_rb_commit_write(&impl.rb, count) == MA_SUCCESS);
  impl.device.pUserData = &impl;
  impl.drain_latency_ms = 100;
  playback.impl = &impl;
  simulated_ms = 1000;
  callback_elapsed_ms = 1;
  CHECK(cpkt_audio_playback_start_impl(&playback) == CPKT_AUDIO_OK);
  CHECK(cpkt_audio_playback_drain_impl(&playback) == CPKT_AUDIO_OK);
  CHECK(requested_sleep_ms == 100);
  ma_pcm_rb_uninit(&impl.rb);
  return 0;
}

static int send_bytes(int socket_fd, const void *buffer, size_t size) {
  const unsigned char *cursor = buffer;
  while (size != 0) {
    ssize_t sent = send(socket_fd, cursor, size, 0);
    if (sent <= 0)
      return 1;
    cursor += sent;
    size -= (size_t)sent;
  }
  return 0;
}

static int url_forward_seek(void) {
  struct sockaddr_in address = {0};
  socklen_t address_size = sizeof(address);
  int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
  pid_t server;
  char url[128];
  struct cpkt_audio_url_source *source = NULL;
  unsigned char output[8];
  CHECK(listen_fd >= 0);
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  CHECK(bind(listen_fd, (struct sockaddr *)&address, sizeof(address)) == 0);
  CHECK(listen(listen_fd, 1) == 0);
  CHECK(getsockname(listen_fd, (struct sockaddr *)&address, &address_size) ==
        0);
  server = fork();
  CHECK(server >= 0);
  if (server == 0) {
    int client = accept(listen_fd, NULL, NULL);
    unsigned char zeros[4096] = {0};
    char request[512];
    char header[128];
    size_t i;
    if (client < 0)
      _exit(1);
    (void)recv(client, request, sizeof(request), 0);
    (void)snprintf(
        header, sizeof(header),
        "HTTP/1.1 200 OK\r\nContent-Length: %u\r\nConnection: close\r\n\r\n",
        16U * 1024U * 1024U + 8U);
    if (send_bytes(client, header, strlen(header)))
      _exit(1);
    for (i = 0; i < 4096; ++i)
      if (send_bytes(client, zeros, sizeof(zeros)))
        _exit(1);
    if (send_bytes(client, "audioend", 8))
      _exit(1);
    close(client);
    close(listen_fd);
    _exit(0);
  }
  close(listen_fd);
  bounded_allocations = 1;
  (void)snprintf(url, sizeof(url), "http://127.0.0.1:%u/seek",
                 ntohs(address.sin_port));
  CHECK(cpkt_audio_url_source_create(&source, url) == CPKT_AUDIO_OK);
  CHECK(cpkt_audio_url_seek(source, 16L * 1024L * 1024L, CPKT_AUDIO_SEEK_SET) ==
        0);
  CHECK(cpkt_audio_url_read(source, output, sizeof(output)) == sizeof(output));
  CHECK(memcmp(output, "audioend", sizeof(output)) == 0);
  CHECK(cpkt_audio_url_seek(source, -8, CPKT_AUDIO_SEEK_CUR) == 0);
  CHECK(cpkt_audio_url_read(source, output, sizeof(output)) == sizeof(output));
  CHECK(memcmp(output, "audioend", sizeof(output)) == 0);
  CHECK(cpkt_audio_url_seek(source, 0, CPKT_AUDIO_SEEK_SET) != 0);
  cpkt_audio_url_source_destroy(source);
  CHECK(waitpid(server, NULL, 0) == server);
  return 0;
}

static int file_url_streaming(void) {
  unsigned char header[44] = {
      'R', 'I', 'F', 'F', 36, 0, 0,   1,   'W', 'A',  'V',  'E', 'f', 'm', 't',
      ' ', 16,  0,   0,   0,  1, 0,   1,   0,   0x80, 0x3e, 0,   0,   0,   0x7d,
      0,   0,   2,   0,   16, 0, 'd', 'a', 't', 'a',  0,    0,   0,   1};
  FILE *file;
  char cwd[1024];
  char url[1200];
  cpkt_audio_decoder *decoder = NULL;
  float frames[128];
  size_t read = 0;
  size_t i;
  file = fopen("cpkt boundary.wav", "wb");
  CHECK(file != NULL);
  CHECK(fwrite(header, 1, sizeof(header), file) == sizeof(header));
  CHECK(fseek(file, 16L * 1024L * 1024L + 43L, SEEK_SET) == 0);
  CHECK(fputc(0, file) == 0 && fclose(file) == 0);
  CHECK(getcwd(cwd, sizeof(cwd)) != NULL);
  CHECK(snprintf(url, sizeof(url), "file://%s/cpkt%%20boundary.wav", cwd) <
        (int)sizeof(url));
  bounded_allocations = 1;
  CHECK(cpkt_audio_decoder_open_url(&decoder, url, NULL) == CPKT_AUDIO_OK);
  CHECK(decoder->read_f32_mono_16k(decoder, frames, 128, &read) ==
        CPKT_AUDIO_OK);
  CHECK(read == 128);
  for (i = 0; i < read; ++i)
    CHECK(frames[i] == 0.0f);
  decoder->destroy(decoder);
  bounded_allocations = 0;
  CHECK(remove("cpkt boundary.wav") == 0);
  CHECK(cpkt_audio_decoder_open_url(&decoder, "file:///missing-cpkt-audio.wav",
                                    NULL) != CPKT_AUDIO_OK &&
        decoder == NULL);
  CHECK(cpkt_audio_decoder_open_url(&decoder,
                                    "file://remote.invalid/etc/passwd",
                                    NULL) != CPKT_AUDIO_OK &&
        decoder == NULL);
  CHECK(cpkt_audio_decoder_open_url(&decoder, "file:///etc/passwd%00.wav",
                                    NULL) != CPKT_AUDIO_OK &&
        decoder == NULL);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  if (strcmp(argv[1], "playback") == 0)
    return playback_drain();
  if (strcmp(argv[1], "capture") == 0)
    return capture_overrun();
  if (strcmp(argv[1], "timing") == 0)
    return playback_timing();
  if (strcmp(argv[1], "stopped") == 0)
    return playback_stopped();
  if (strcmp(argv[1], "gaps") == 0)
    return playback_gaps();
  if (strcmp(argv[1], "restart") == 0)
    return playback_restart();
  if (strcmp(argv[1], "seek") == 0)
    return url_forward_seek();
  if (strcmp(argv[1], "file-url") == 0)
    return file_url_streaming();
  return 2;
}
