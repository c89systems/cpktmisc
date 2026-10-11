#define _POSIX_C_SOURCE 200809L
#include "../src/sus.c"

static unsigned long capture_budget;
static cpkt_audio_capture fake_capture;
static cpkt_audio_result fake_stop(cpkt_audio_capture *capture) {
  (void)capture;
  return CPKT_AUDIO_OK;
}
static void fake_destroy(cpkt_audio_capture *capture) { (void)capture; }
static cpkt_audio_result
fake_capture_open(cpkt_audio_capture **out,
                  const cpkt_audio_capture_config *config) {
  (void)config;
  fake_capture.stop = fake_stop;
  fake_capture.destroy = fake_destroy;
  *out = &fake_capture;
  return CPKT_AUDIO_OK;
}
static cpkt_audio_result observe_vox_open(cpkt_audio_vox **out,
                                          const cpkt_audio_vox_config *config) {
  capture_budget = config->max_segment_ms;
  *out = NULL;
  return CPKT_AUDIO_ERR_IO;
}
static cpkt_sus fake_model;
static cpkt_sus_transcriber fake_transcriber;
static cpkt_audio_decoder fake_decoder;
static unsigned long observed_prebuffer;
static int observed_context;
static unsigned int created;
static unsigned int destroyed;
static unsigned int segment_calls;
static void model_destroy(cpkt_sus *model) { (void)model; }
static void decoder_destroy(cpkt_audio_decoder *decoder) { (void)decoder; }
static void transcriber_destroy(cpkt_sus_transcriber *transcriber) {
  (void)transcriber;
  ++destroyed;
}
static cpkt_sus_result
transcribe_decoder(cpkt_sus_transcriber *transcriber,
                   cpkt_audio_decoder *decoder,
                   const cpkt_sus_segmented_config *config) {
  (void)transcriber;
  (void)decoder;
  observed_prebuffer = config->prebuffer_ms;
  observed_context = config->keep_context;
  return CPKT_SUS_OK;
}
static cpkt_sus_result
transcribe_segment(cpkt_sus_transcriber *transcriber,
                   cpkt_audio_vox_segment *segment,
                   const cpkt_sus_segmented_config *config) {
  cpkt_sus_segmented_event event = {0};
  (void)transcriber;
  (void)segment;
  observed_context = config->keep_context;
  event.text = segment_calls++ == 0 ? "hello" : "hello world";
  event.text_length = (unsigned long)strlen(event.text);
  return config->segmented_sink(&event, config->segmented_user) == 0
             ? CPKT_SUS_OK
             : CPKT_SUS_ERR_CALLBACK;
}
static cpkt_sus_result
create_transcriber(cpkt_sus *model, cpkt_sus_transcriber **out,
                   const cpkt_sus_transcriber_config *config) {
  (void)model;
  (void)config;
  ++created;
  fake_transcriber.destroy = transcriber_destroy;
  fake_transcriber.transcribe_audio_decoder_segmented = transcribe_decoder;
  fake_transcriber.transcribe_audio_vox_segment = transcribe_segment;
  *out = &fake_transcriber;
  return CPKT_SUS_OK;
}
static cpkt_sus_result model_open(cpkt_sus **out,
                                  const cpkt_sus_config *config) {
  (void)config;
  fake_model.destroy = model_destroy;
  fake_model.create_transcriber = create_transcriber;
  *out = &fake_model;
  return CPKT_SUS_OK;
}
static cpkt_audio_result decoder_open(cpkt_audio_decoder **out,
                                      const char *path,
                                      const cpkt_audio_decoder_config *config) {
  (void)path;
  (void)config;
  fake_decoder.destroy = decoder_destroy;
  *out = &fake_decoder;
  return CPKT_AUDIO_OK;
}
#define cpkt_sus_open_path model_open
#define cpkt_audio_decoder_open_file decoder_open
#define cpkt_audio_decoder_open_url decoder_open
#define cpkt_audio_capture_open_default fake_capture_open
#define cpkt_audio_vox_open observe_vox_open
#define main embedded_cpktxscribe_main
#include "../tools/cpktxscribe.c"
#undef main
#undef cpkt_audio_vox_open
#undef cpkt_audio_capture_open_default
#undef cpkt_sus_open_path
#undef cpkt_audio_decoder_open_file
#undef cpkt_audio_decoder_open_url

#define CHECK(expression)                                                      \
  do {                                                                         \
    if (!(expression)) {                                                       \
      fprintf(stderr, "speech boundary: %s failed at line %d\n", #expression,  \
              __LINE__);                                                       \
      return 1;                                                                \
    }                                                                          \
  } while (0)

static int text_spacing(void) {
  const char *parts[] = {"world", " world", "\tworld", ", world"};
  const char *expected[] = {"hello world", "hello world", "hello\tworld",
                            "hello, world"};
  size_t i;
  for (i = 0; i < 4; ++i) {
    struct cpkt_sus_transcriber_impl impl = {0};
    cpkt_sus_transcriber view = {0};
    char *text = NULL;
    view.impl = &impl;
    CHECK(cpkt_sus_transcriber_append_revised_text(&impl, "hello", 5) ==
          CPKT_SUS_OK);
    CHECK(cpkt_sus_transcriber_append_revised_text(
              &impl, parts[i], strlen(parts[i])) == CPKT_SUS_OK);
    CHECK(cpkt_sus_transcriber_revised_text_impl(&view, &text) == CPKT_SUS_OK);
    CHECK(strcmp(text, expected[i]) == 0);
    free(text);
    free(impl.revised_text);
  }
  return 0;
}

static int capture_segmentation(void) {
  struct cpktxscribe_options options;
  struct cpktxscribe_stream stream = {0};
  cpktxscribe_defaults(&options);
  CHECK(cpktxscribe_run_capture(&options, NULL, &stream) == 1);
  CHECK(capture_budget == 7000);
  options.segment_mode = CPKT_SUS_SEGMENT_MODE_SIMPLEX;
  CHECK(cpktxscribe_run_capture(&options, NULL, &stream) == 1);
  CHECK(capture_budget == 0);
  options.length_ms = 250;
  CHECK(cpktxscribe_run_capture(&options, NULL, &stream) == 1);
  CHECK(capture_budget == 250);
  return 0;
}

static int decoder_options(void) {
  struct cpktxscribe_options options;
  char *arguments[] = {"cpktxscribe", "--keep-context", "0", "--prebuffer-ms",
                       "125",         "fixture.wav"};
  cpktxscribe_defaults(&options);
  options.model_path = "fixture-model";
  options.input_path = "fixture.wav";
  CHECK(cpktxscribe_run(&options) == 0);
  CHECK(observed_prebuffer == 50);
  cpktxscribe_defaults(&options);
  CHECK(cpktxscribe_parse_options(6, arguments, &options));
  options.model_path = "fixture-model";
  options.url = "https://fixture.invalid/input.mp3";
  CHECK(cpktxscribe_run(&options) == 0);
  CHECK(observed_prebuffer == 125);
  CHECK(observed_context < 0);
  CHECK(created == destroyed);
  return 0;
}

static int capture_context(void) {
  struct cpktxscribe_options options;
  struct cpktxscribe_stream stream = {0};
  struct cpktxscribe_capture_run run = {0};
  cpkt_audio_vox_segment segment = {0};
  FILE *output;
  int saved_stdout;
  char text[32] = {0};
  char *arguments[] = {"cpktxscribe", "--capture", "--keep-context", "0"};
  cpktxscribe_defaults(&options);
  fake_model.create_transcriber = create_transcriber;
  run.sus = &fake_model;
  run.options = &options;
  run.stream = &stream;
  output = tmpfile();
  CHECK(output != NULL);
  saved_stdout = dup(STDOUT_FILENO);
  CHECK(saved_stdout >= 0 && dup2(fileno(output), STDOUT_FILENO) >= 0);
  CHECK(cpktxscribe_capture_segment_sink(&segment, &run) == 0);
  CHECK(cpktxscribe_capture_segment_sink(&segment, &run) == 0);
  CHECK(fflush(stdout) == 0 && dup2(saved_stdout, STDOUT_FILENO) >= 0);
  close(saved_stdout);
  rewind(output);
  CHECK(fread(text, 1, sizeof(text) - 1, output) == 11);
  fclose(output);
  CHECK(strcmp(text, "hello world") == 0);
  CHECK(created == 1 && destroyed == 0 && observed_context > 0);
  fake_transcriber.destroy(&fake_transcriber);
  CHECK(destroyed == 1);
  memset(&run, 0, sizeof(run));
  run.sus = &fake_model;
  run.options = &options;
  run.stream = &stream;
  CHECK(cpktxscribe_parse_options(4, arguments, &options));
  CHECK(cpktxscribe_capture_segment_sink(&segment, &run) == 0);
  CHECK(observed_context < 0);
  CHECK(created == 2);
  fake_transcriber.destroy(&fake_transcriber);
  CHECK(destroyed == 2);
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  if (strcmp(argv[1], "spacing") == 0)
    return text_spacing();
  if (strcmp(argv[1], "capture") == 0)
    return capture_segmentation();
  if (strcmp(argv[1], "options") == 0)
    return decoder_options();
  if (strcmp(argv[1], "context") == 0)
    return capture_context();
  return 2;
}
