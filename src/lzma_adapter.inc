/* Persistent native streams are necessary because block coders retain their
 * lzma_block pointer. Input and output continue through the caller's buffers.
 */
#include <stdlib.h>

cpkt_compression_u64 cpkt_lzma_u64_literal(const char *literal) {
  return cpkt_lzma_word_from_native(strtoull(literal, NULL, 0));
}

int cpkt_lzma_vli_is_valid(cpkt_compression_u64 value) {
  return value.hi <= 2147483647U ||
         (value.hi == 4294967295U && value.lo == 4294967295U);
}

static void cpkt_lzma_filters_to_native(lzma_filter *destination,
                                        const cpkt_lzma_lzma_filter *source,
                                        size_t capacity) {
  size_t i;
  int ended = source == NULL;
  for (i = 0; i < capacity; ++i) {
    destination[i].id = LZMA_VLI_UNKNOWN;
    destination[i].options = NULL;
    if (!ended) {
      ended = cpkt_lzma_word_to_native(source[i].id) == LZMA_VLI_UNKNOWN;
      if (!ended)
        destination[i] = cpkt_lzma_to_lzma_filter(source[i]);
    }
  }
}
static void cpkt_lzma_filters_from_native(cpkt_lzma_lzma_filter *destination,
                                          const lzma_filter *source,
                                          size_t capacity) {
  size_t i;
  if (!destination)
    return;
  for (i = 0; i < capacity; ++i) {
    destination[i] = cpkt_lzma_from_lzma_filter(source[i]);
    if (source[i].id == LZMA_VLI_UNKNOWN)
      break;
  }
}
struct cpkt_lzma_state {
  lzma_stream stream;
  lzma_block block;
  lzma_filter filters[LZMA_FILTERS_MAX + 1];
  cpkt_lzma_lzma_block *public_block;
};

static struct cpkt_lzma_state *
cpkt_lzma_state_get(cpkt_lzma_lzma_stream *stream) {
  struct cpkt_lzma_state *state;
  if (!stream)
    return NULL;
  state = stream->cpkt_state;
  if (!state) {
    state = calloc(1, sizeof(*state));
    if (!state)
      return NULL;
    stream->cpkt_state = state;
  }
  state->stream = cpkt_lzma_to_lzma_stream(*stream);
  if (state->public_block) {
    state->block = cpkt_lzma_to_lzma_block(*state->public_block);
    cpkt_lzma_filters_to_native(state->filters, state->public_block->filters,
                                LZMA_FILTERS_MAX + 1);
    state->block.filters = state->public_block->filters ? state->filters : NULL;
  }
  return state;
}
static void cpkt_lzma_state_block(struct cpkt_lzma_state *state,
                                  cpkt_lzma_lzma_block *block,
                                  lzma_block native) {
  state->public_block = block;
  state->block = native;
  cpkt_lzma_filters_to_native(state->filters, block->filters,
                              LZMA_FILTERS_MAX + 1);
  state->block.filters = block->filters ? state->filters : NULL;
}
static void cpkt_lzma_state_commit(cpkt_lzma_lzma_stream *stream,
                                   struct cpkt_lzma_state *state) {
  *stream = cpkt_lzma_from_lzma_stream(state->stream);
  stream->cpkt_state = state;
  if (state->public_block) {
    cpkt_lzma_lzma_filter *filters = state->public_block->filters;
    *state->public_block = cpkt_lzma_from_lzma_block(state->block);
    state->public_block->filters = filters;
    cpkt_lzma_filters_from_native(filters, state->filters,
                                  LZMA_FILTERS_MAX + 1);
  }
}
void cpkt_lzma_lzma_end(cpkt_lzma_lzma_stream *stream) {
  struct cpkt_lzma_state *state;
  lzma_stream native;
  if (!stream)
    return;
  state = stream->cpkt_state;
  native = cpkt_lzma_to_lzma_stream(*stream);
  lzma_end(state ? &state->stream : &native);
  if (state) {
    cpkt_lzma_state_commit(stream, state);
    free(state);
  } else {
    *stream = cpkt_lzma_from_lzma_stream(native);
  }
  stream->cpkt_state = NULL;
}
