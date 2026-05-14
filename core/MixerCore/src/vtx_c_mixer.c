#include "vtx_c_mixer.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static double vtx_c_mixer_sanitized_sample_rate(double sample_rate) {
    return isfinite(sample_rate) && sample_rate > 0.0
        ? sample_rate
        : VTX_C_MIXER_DEFAULT_SAMPLE_RATE;
}

static uint32_t vtx_c_mixer_sanitized_channel_count(uint32_t channel_count) {
    return channel_count > 0
        ? channel_count
        : VTX_C_MIXER_DEFAULT_CHANNEL_COUNT;
}

static VTXCMixerConfig vtx_c_mixer_sanitized_config(VTXCMixerConfig config) {
    VTXCMixerConfig sanitized;
    sanitized.sample_rate = vtx_c_mixer_sanitized_sample_rate(config.sample_rate);
    sanitized.channel_count = vtx_c_mixer_sanitized_channel_count(config.channel_count);
    return sanitized;
}

static float vtx_c_mixer_sanitized_sample(float sample) {
    return isfinite(sample) ? sample : 0.0f;
}

static float vtx_c_mixer_sanitized_gain(float gain) {
    return isfinite(gain) ? gain : 0.0f;
}

static double vtx_c_mixer_sanitized_sample_step(double sample_step) {
    return isfinite(sample_step) && sample_step > 0.0 && sample_step <= (double)UINT32_MAX
        ? sample_step
        : 1.0;
}

static float vtx_c_mixer_clamp(float value, float minimum, float maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static float vtx_c_mixer_sanitized_pan(float pan) {
    if (!isfinite(pan)) {
        return 0.0f;
    }
    return vtx_c_mixer_clamp(pan, -1.0f, 1.0f);
}

static float vtx_c_mixer_left_pan_gain(float pan) {
    return pan <= 0.0f ? 1.0f : 1.0f - pan;
}

static float vtx_c_mixer_right_pan_gain(float pan) {
    return pan >= 0.0f ? 1.0f : 1.0f + pan;
}

static VTXCMixerLoopMode vtx_c_mixer_sanitized_loop_mode(VTXCMixerLoopMode loop_mode) {
    switch (loop_mode) {
    case VTX_C_MIXER_LOOP_FORWARD:
    case VTX_C_MIXER_LOOP_PING_PONG:
        return loop_mode;
    case VTX_C_MIXER_LOOP_NONE:
    default:
        return VTX_C_MIXER_LOOP_NONE;
    }
}

static int vtx_c_mixer_loop_is_valid(
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint32_t sample_frame_count
) {
    if (loop_mode == VTX_C_MIXER_LOOP_NONE) {
        return 0;
    }
    if (sample_frame_count == 0 ||
        loop_start_frame >= sample_frame_count ||
        loop_end_frame > sample_frame_count ||
        loop_end_frame <= loop_start_frame) {
        return 0;
    }
    if (loop_mode == VTX_C_MIXER_LOOP_PING_PONG && loop_end_frame - loop_start_frame < 2u) {
        return 0;
    }
    return 1;
}

static void vtx_c_mixer_sanitize_loop(
    VTXCMixerLoopMode *loop_mode,
    uint32_t *loop_start_frame,
    uint32_t *loop_end_frame,
    uint32_t sample_frame_count
) {
    *loop_mode = vtx_c_mixer_sanitized_loop_mode(*loop_mode);
    if (!vtx_c_mixer_loop_is_valid(*loop_mode, *loop_start_frame, *loop_end_frame, sample_frame_count)) {
        *loop_mode = VTX_C_MIXER_LOOP_NONE;
        *loop_start_frame = 0u;
        *loop_end_frame = 0u;
    }
}

static void vtx_c_mixer_disable_envelope(VTXCMixerEnvelopeState *envelope) {
    if (envelope == NULL) {
        return;
    }
    memset(envelope, 0, sizeof(*envelope));
}

static int vtx_c_mixer_envelope_is_valid(const VTXCMixerEnvelope *envelope) {
    uint32_t point_index;

    if (envelope == NULL ||
        envelope->point_count == 0 ||
        envelope->point_count > VTX_C_MIXER_MAX_ENVELOPE_POINTS ||
        envelope->points == NULL) {
        return 0;
    }

    for (point_index = 0; point_index < envelope->point_count; point_index++) {
        const VTXCMixerEnvelopePoint *point = &envelope->points[point_index];
        if (!isfinite(point->value)) {
            return 0;
        }
        if (point_index > 0 &&
            point->position_frame <= envelope->points[point_index - 1u].position_frame) {
            return 0;
        }
    }
    return 1;
}

static void vtx_c_mixer_copy_envelope(
    VTXCMixerEnvelopeState *destination,
    const VTXCMixerEnvelope *source,
    float minimum_value,
    float maximum_value
) {
    uint32_t point_index;

    if (destination == NULL) {
        return;
    }
    if (!vtx_c_mixer_envelope_is_valid(source)) {
        vtx_c_mixer_disable_envelope(destination);
        return;
    }

    memset(destination, 0, sizeof(*destination));
    destination->enabled = 1;
    destination->point_count = source->point_count;
    for (point_index = 0; point_index < source->point_count; point_index++) {
        destination->points[point_index].position_frame = source->points[point_index].position_frame;
        destination->points[point_index].value = vtx_c_mixer_clamp(
            source->points[point_index].value,
            minimum_value,
            maximum_value
        );
    }
}

static float vtx_c_mixer_evaluate_envelope(
    const VTXCMixerEnvelopeState *envelope,
    float default_value
) {
    uint32_t point_index;
    uint32_t position_frame;

    if (envelope == NULL || !envelope->enabled || envelope->point_count == 0) {
        return default_value;
    }

    position_frame = envelope->position_frame;
    if (position_frame <= envelope->points[0].position_frame) {
        return envelope->points[0].value;
    }

    for (point_index = 1; point_index < envelope->point_count; point_index++) {
        const VTXCMixerEnvelopePoint *previous = &envelope->points[point_index - 1u];
        const VTXCMixerEnvelopePoint *next = &envelope->points[point_index];
        if (position_frame <= next->position_frame) {
            float span = (float)(next->position_frame - previous->position_frame);
            float progress = (float)(position_frame - previous->position_frame) / span;
            return previous->value + ((next->value - previous->value) * progress);
        }
    }

    return envelope->points[envelope->point_count - 1u].value;
}

static void vtx_c_mixer_advance_envelope(VTXCMixerEnvelopeState *envelope) {
    if (envelope == NULL || !envelope->enabled) {
        return;
    }
    if (envelope->position_frame < UINT32_MAX) {
        envelope->position_frame++;
    }
}

static void vtx_c_mixer_advance_voice_envelopes(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    vtx_c_mixer_advance_envelope(&voice->volume_envelope);
    vtx_c_mixer_advance_envelope(&voice->pan_envelope);
}

static void vtx_c_mixer_advance_render_cursor(VTXCMixerState *state) {
    if (state == NULL || state->current_frame == UINT64_MAX) {
        return;
    }
    state->current_frame++;
}

static void vtx_c_mixer_advance_one_shot_position(VTXCMixerVoice *voice) {
    voice->sample_position += voice->sample_step;
    if (voice->sample_position >= (double)voice->sample_frame_count) {
        voice->active = 0;
    }
}

static void vtx_c_mixer_advance_forward_loop_position(VTXCMixerVoice *voice) {
    double loop_length;
    double overflow;

    voice->sample_position += voice->sample_step;
    if (voice->sample_position < (double)voice->loop_end_frame) {
        return;
    }

    loop_length = (double)(voice->loop_end_frame - voice->loop_start_frame);
    if (loop_length <= 0.0) {
        voice->active = 0;
        return;
    }
    overflow = voice->sample_position - (double)voice->loop_end_frame;
    voice->sample_position = (double)voice->loop_start_frame + fmod(overflow, loop_length);
}

static void vtx_c_mixer_advance_ping_pong_loop_position(VTXCMixerVoice *voice) {
    double first_loop_frame;
    double last_loop_frame;
    double span;
    double period;

    voice->sample_position += voice->sample_step * (double)voice->ping_pong_direction;

    first_loop_frame = (double)voice->loop_start_frame;
    last_loop_frame = (double)(voice->loop_end_frame - 1u);
    span = last_loop_frame - first_loop_frame;
    if (span <= 0.0) {
        voice->sample_position = first_loop_frame;
        voice->ping_pong_direction = 1;
        return;
    }

    period = span * 2.0;
    if (voice->ping_pong_direction > 0 && voice->sample_position > last_loop_frame) {
        double overshoot = fmod(voice->sample_position - last_loop_frame, period);
        voice->sample_position = last_loop_frame + overshoot;
    } else if (voice->ping_pong_direction < 0 && voice->sample_position < first_loop_frame) {
        double overshoot = fmod(first_loop_frame - voice->sample_position, period);
        voice->sample_position = first_loop_frame - overshoot;
    }

    if (voice->ping_pong_direction > 0 && voice->sample_position > last_loop_frame) {
        double overshoot = voice->sample_position - last_loop_frame;
        voice->sample_position = last_loop_frame - overshoot;
        voice->ping_pong_direction = -1;
    } else if (voice->ping_pong_direction < 0 && voice->sample_position < first_loop_frame) {
        double overshoot = first_loop_frame - voice->sample_position;
        voice->sample_position = first_loop_frame + overshoot;
        voice->ping_pong_direction = 1;
    }
}

static void vtx_c_mixer_advance_sample_position(VTXCMixerVoice *voice) {
    switch (voice->loop_mode) {
    case VTX_C_MIXER_LOOP_FORWARD:
        vtx_c_mixer_advance_forward_loop_position(voice);
        break;
    case VTX_C_MIXER_LOOP_PING_PONG:
        vtx_c_mixer_advance_ping_pong_loop_position(voice);
        break;
    case VTX_C_MIXER_LOOP_NONE:
    default:
        vtx_c_mixer_advance_one_shot_position(voice);
        break;
    }
}

static void vtx_c_mixer_release_voice(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    free(voice->sample_pcm);
    memset(voice, 0, sizeof(*voice));
}

static VTXCMixerStatus vtx_c_mixer_add_sample_voice_internal(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint64_t scheduled_start_frame,
    int reject_past_scheduled_start,
    uint32_t *out_voice_index
) {
    VTXCMixerVoice *voice;
    float *sample_copy = NULL;
    uint32_t sample_index;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (sample_frame_count > 0 && sample_pcm == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (reject_past_scheduled_start && scheduled_start_frame < state->current_frame) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (state->voice_count >= VTX_C_MIXER_MAX_VOICES) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (sample_frame_count > 0) {
        if ((size_t)sample_frame_count > SIZE_MAX / sizeof(float)) {
            return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
        }
        sample_copy = (float *)malloc((size_t)sample_frame_count * sizeof(float));
        if (sample_copy == NULL) {
            return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
        }
        for (sample_index = 0; sample_index < sample_frame_count; sample_index++) {
            sample_copy[sample_index] = vtx_c_mixer_sanitized_sample(sample_pcm[sample_index]);
        }
    }

    vtx_c_mixer_sanitize_loop(&loop_mode, &loop_start_frame, &loop_end_frame, sample_frame_count);

    voice = &state->voices[state->voice_count];
    memset(voice, 0, sizeof(*voice));
    voice->sample_pcm = sample_copy;
    voice->sample_frame_count = sample_frame_count;
    voice->sample_position = 0.0;
    voice->sample_step = vtx_c_mixer_sanitized_sample_step(sample_step);
    voice->scheduled_start_frame = scheduled_start_frame;
    voice->gain = vtx_c_mixer_sanitized_gain(gain);
    voice->pan = vtx_c_mixer_sanitized_pan(pan);
    voice->loop_mode = loop_mode;
    voice->loop_start_frame = loop_start_frame;
    voice->loop_end_frame = loop_end_frame;
    voice->ping_pong_direction = 1;
    voice->active = sample_frame_count > 0 && sample_copy != NULL;
    if (out_voice_index != NULL) {
        *out_voice_index = state->voice_count;
    }
    state->voice_count++;
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerConfig vtx_c_mixer_default_config(void) {
    VTXCMixerConfig config;
    config.sample_rate = VTX_C_MIXER_DEFAULT_SAMPLE_RATE;
    config.channel_count = VTX_C_MIXER_DEFAULT_CHANNEL_COUNT;
    return config;
}

VTXCMixerStatus vtx_c_mixer_init(VTXCMixerState *state, VTXCMixerConfig config) {
    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    memset(state, 0, sizeof(*state));
    state->config = vtx_c_mixer_sanitized_config(config);
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_reset(VTXCMixerState *state) {
    uint32_t voice_index;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    state->current_frame = 0u;
    for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
        VTXCMixerVoice *voice = &state->voices[voice_index];
        voice->sample_position = 0.0;
        voice->ping_pong_direction = 1;
        voice->volume_envelope.position_frame = 0u;
        voice->pan_envelope.position_frame = 0u;
        voice->active = voice->sample_frame_count > 0 && voice->sample_pcm != NULL;
    }
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_configure(VTXCMixerState *state, VTXCMixerConfig config) {
    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    state->config = vtx_c_mixer_sanitized_config(config);
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_clear_voices(VTXCMixerState *state) {
    uint32_t voice_index;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
        vtx_c_mixer_release_voice(&state->voices[voice_index]);
    }
    state->voice_count = 0;
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_add_one_shot_sample(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    uint32_t *out_voice_index
) {
    return vtx_c_mixer_add_sample_voice(
        state,
        sample_pcm,
        sample_frame_count,
        gain,
        pan,
        VTX_C_MIXER_LOOP_NONE,
        0u,
        0u,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_add_sample_voice(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint32_t *out_voice_index
) {
    return vtx_c_mixer_add_sample_voice_with_step(
        state,
        sample_pcm,
        sample_frame_count,
        1.0,
        gain,
        pan,
        loop_mode,
        loop_start_frame,
        loop_end_frame,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_add_sample_voice_with_step(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint32_t *out_voice_index
) {
    return vtx_c_mixer_add_sample_voice_internal(
        state,
        sample_pcm,
        sample_frame_count,
        sample_step,
        gain,
        pan,
        loop_mode,
        loop_start_frame,
        loop_end_frame,
        0u,
        0,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_add_scheduled_sample_voice(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint64_t scheduled_start_frame,
    uint32_t *out_voice_index
) {
    return vtx_c_mixer_add_scheduled_sample_voice_with_step(
        state,
        sample_pcm,
        sample_frame_count,
        1.0,
        gain,
        pan,
        loop_mode,
        loop_start_frame,
        loop_end_frame,
        scheduled_start_frame,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_add_scheduled_sample_voice_with_step(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    float gain,
    float pan,
    VTXCMixerLoopMode loop_mode,
    uint32_t loop_start_frame,
    uint32_t loop_end_frame,
    uint64_t scheduled_start_frame,
    uint32_t *out_voice_index
) {
    return vtx_c_mixer_add_sample_voice_internal(
        state,
        sample_pcm,
        sample_frame_count,
        sample_step,
        gain,
        pan,
        loop_mode,
        loop_start_frame,
        loop_end_frame,
        scheduled_start_frame,
        1,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_set_voice_volume_envelope(
    VTXCMixerState *state,
    uint32_t voice_index,
    const VTXCMixerEnvelope *envelope
) {
    if (state == NULL || voice_index >= state->voice_count) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    vtx_c_mixer_copy_envelope(&state->voices[voice_index].volume_envelope, envelope, 0.0f, 1.0f);
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_set_voice_pan_envelope(
    VTXCMixerState *state,
    uint32_t voice_index,
    const VTXCMixerEnvelope *envelope
) {
    if (state == NULL || voice_index >= state->voice_count) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    vtx_c_mixer_copy_envelope(&state->voices[voice_index].pan_envelope, envelope, -1.0f, 1.0f);
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_render(
    VTXCMixerState *state,
    float *output_interleaved_float32,
    uint32_t frame_count
) {
    size_t frame_count_size;
    size_t channel_count_size;
    size_t sample_count;
    size_t byte_count;
    size_t frame_index;
    uint32_t voice_index;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (frame_count == 0) {
        return VTX_C_MIXER_STATUS_OK;
    }
    if (output_interleaved_float32 == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }

    state->config = vtx_c_mixer_sanitized_config(state->config);
    frame_count_size = (size_t)frame_count;
    channel_count_size = (size_t)state->config.channel_count;
    if (channel_count_size == 0 || frame_count_size > SIZE_MAX / channel_count_size) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    sample_count = frame_count_size * channel_count_size;
    if (sample_count > SIZE_MAX / sizeof(float)) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }

    byte_count = sample_count * sizeof(float);
    memset(output_interleaved_float32, 0, byte_count);

    for (frame_index = 0; frame_index < frame_count_size; frame_index++) {
        size_t frame_offset = frame_index * channel_count_size;
        uint64_t absolute_frame = state->current_frame;
        for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
            VTXCMixerVoice *voice = &state->voices[voice_index];
            uint32_t source_index;
            float mono_sample;

            if (!voice->active) {
                continue;
            }
            if (absolute_frame < voice->scheduled_start_frame) {
                continue;
            }
            if (voice->sample_position < 0.0 || voice->sample_position > (double)UINT32_MAX) {
                voice->active = 0;
                continue;
            }
            source_index = (uint32_t)voice->sample_position;
            if (voice->sample_pcm == NULL || source_index >= voice->sample_frame_count) {
                voice->active = 0;
                continue;
            }

            mono_sample = voice->sample_pcm[source_index] *
                voice->gain *
                vtx_c_mixer_evaluate_envelope(&voice->volume_envelope, 1.0f);
            if (channel_count_size == 1) {
                output_interleaved_float32[frame_offset] += mono_sample;
            } else {
                float effective_pan = vtx_c_mixer_sanitized_pan(
                    voice->pan + vtx_c_mixer_evaluate_envelope(&voice->pan_envelope, 0.0f)
                );
                output_interleaved_float32[frame_offset] += mono_sample * vtx_c_mixer_left_pan_gain(effective_pan);
                output_interleaved_float32[frame_offset + 1] += mono_sample * vtx_c_mixer_right_pan_gain(effective_pan);
            }

            vtx_c_mixer_advance_sample_position(voice);
            vtx_c_mixer_advance_voice_envelopes(voice);
        }
        vtx_c_mixer_advance_render_cursor(state);
    }
    return VTX_C_MIXER_STATUS_OK;
}
