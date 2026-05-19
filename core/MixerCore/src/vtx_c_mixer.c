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

static float vtx_c_mixer_sanitized_fadeout_decrement(float decrement) {
    if (!isfinite(decrement) || decrement <= 0.0f) {
        return 0.0f;
    }
    return vtx_c_mixer_clamp(decrement, 0.0f, 1.0f);
}

static float vtx_c_mixer_sanitized_pan(float pan) {
    if (!isfinite(pan)) {
        return 0.0f;
    }
    return vtx_c_mixer_clamp(pan, -1.0f, 1.0f);
}

static int vtx_c_mixer_voice_state_event_is_valid(
    int update_gain,
    float gain,
    int update_pan,
    float pan,
    int update_sample_step,
    double sample_step
) {
    if (!update_gain && !update_pan && !update_sample_step) {
        return 0;
    }
    if (update_gain && !isfinite(gain)) {
        return 0;
    }
    if (update_pan && !isfinite(pan)) {
        return 0;
    }
    if (update_sample_step && (!isfinite(sample_step) || sample_step <= 0.0 || sample_step > (double)UINT32_MAX)) {
        return 0;
    }
    return 1;
}

static float vtx_c_mixer_left_pan_gain(float pan) {
    return pan <= 0.0f ? 1.0f : 1.0f - pan;
}

static float vtx_c_mixer_right_pan_gain(float pan) {
    return pan >= 0.0f ? 1.0f : 1.0f + pan;
}

static float vtx_c_mixer_effective_ramped_value(
    int ramp_active,
    float start,
    float target,
    uint32_t total_frames,
    uint32_t position_frame,
    float fallback
) {
    float progress;

    if (!ramp_active || total_frames == 0u) {
        return fallback;
    }
    if (position_frame + 1u >= total_frames) {
        return target;
    }
    progress = (float)(position_frame + 1u) / (float)total_frames;
    return start + ((target - start) * progress);
}

static float vtx_c_mixer_effective_gain(const VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return 0.0f;
    }
    return vtx_c_mixer_effective_ramped_value(
        voice->gain_ramp_active,
        voice->gain_ramp_start,
        voice->gain_ramp_target,
        voice->gain_ramp_total_frames,
        voice->gain_ramp_position_frame,
        voice->gain
    );
}

static float vtx_c_mixer_effective_pan(const VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return 0.0f;
    }
    return vtx_c_mixer_effective_ramped_value(
        voice->pan_ramp_active,
        voice->pan_ramp_start,
        voice->pan_ramp_target,
        voice->pan_ramp_total_frames,
        voice->pan_ramp_position_frame,
        voice->pan
    );
}

static void vtx_c_mixer_clear_gain_ramp(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    voice->gain_ramp_active = 0;
    voice->gain_ramp_start = 0.0f;
    voice->gain_ramp_target = 0.0f;
    voice->gain_ramp_total_frames = 0u;
    voice->gain_ramp_position_frame = 0u;
}

static void vtx_c_mixer_clear_pan_ramp(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    voice->pan_ramp_active = 0;
    voice->pan_ramp_start = 0.0f;
    voice->pan_ramp_target = 0.0f;
    voice->pan_ramp_total_frames = 0u;
    voice->pan_ramp_position_frame = 0u;
}

static void vtx_c_mixer_start_gain_ramp(VTXCMixerVoice *voice, float target) {
    if (voice == NULL) {
        return;
    }
    target = vtx_c_mixer_sanitized_gain(target);
    voice->gain_ramp_start = vtx_c_mixer_effective_gain(voice);
    voice->gain_ramp_target = target;
    voice->gain_ramp_total_frames = VTX_C_MIXER_GAIN_PAN_UPDATE_RAMP_FRAMES;
    voice->gain_ramp_position_frame = 0u;
    voice->gain_ramp_active = voice->gain_ramp_total_frames > 0u;
    voice->gain = target;
}

static void vtx_c_mixer_start_pan_ramp(VTXCMixerVoice *voice, float target) {
    if (voice == NULL) {
        return;
    }
    target = vtx_c_mixer_sanitized_pan(target);
    voice->pan_ramp_start = vtx_c_mixer_effective_pan(voice);
    voice->pan_ramp_target = target;
    voice->pan_ramp_total_frames = VTX_C_MIXER_GAIN_PAN_UPDATE_RAMP_FRAMES;
    voice->pan_ramp_position_frame = 0u;
    voice->pan_ramp_active = voice->pan_ramp_total_frames > 0u;
    voice->pan = target;
}

static void vtx_c_mixer_set_gain_immediate(VTXCMixerVoice *voice, float gain) {
    if (voice == NULL) {
        return;
    }
    voice->gain = vtx_c_mixer_sanitized_gain(gain);
    vtx_c_mixer_clear_gain_ramp(voice);
}

static void vtx_c_mixer_set_pan_immediate(VTXCMixerVoice *voice, float pan) {
    if (voice == NULL) {
        return;
    }
    voice->pan = vtx_c_mixer_sanitized_pan(pan);
    vtx_c_mixer_clear_pan_ramp(voice);
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
    if (source->sustain_enabled &&
        source->sustain_frame <= destination->points[destination->point_count - 1u].position_frame) {
        destination->sustain_enabled = 1;
        destination->sustain_frame = source->sustain_frame;
    }
    if (source->loop_enabled &&
        source->loop_start_frame <= source->loop_end_frame &&
        source->loop_end_frame <= destination->points[destination->point_count - 1u].position_frame) {
        destination->loop_enabled = 1;
        destination->loop_start_frame = source->loop_start_frame;
        destination->loop_end_frame = source->loop_end_frame;
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

static void vtx_c_mixer_advance_envelope(VTXCMixerEnvelopeState *envelope, int key_on) {
    if (envelope == NULL || !envelope->enabled) {
        return;
    }
    if (key_on &&
        envelope->sustain_enabled &&
        envelope->position_frame >= envelope->sustain_frame) {
        envelope->position_frame = envelope->sustain_frame;
        return;
    }
    if (envelope->position_frame < UINT32_MAX) {
        envelope->position_frame++;
    }
    if (key_on && envelope->loop_enabled && envelope->position_frame > envelope->loop_end_frame) {
        uint32_t loop_length = envelope->loop_end_frame - envelope->loop_start_frame + 1u;
        if (loop_length > 0u) {
            envelope->position_frame = envelope->loop_start_frame +
                ((envelope->position_frame - envelope->loop_end_frame - 1u) % loop_length);
        }
    }
}

static void vtx_c_mixer_advance_voice_envelopes(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    vtx_c_mixer_advance_envelope(&voice->volume_envelope, voice->key_on);
    vtx_c_mixer_advance_envelope(&voice->pan_envelope, voice->key_on);
}

static void vtx_c_mixer_advance_value_ramps(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    if (voice->gain_ramp_active) {
        if (voice->gain_ramp_position_frame + 1u >= voice->gain_ramp_total_frames) {
            voice->gain = voice->gain_ramp_target;
            vtx_c_mixer_clear_gain_ramp(voice);
        } else {
            voice->gain_ramp_position_frame++;
        }
    }
    if (voice->pan_ramp_active) {
        if (voice->pan_ramp_position_frame + 1u >= voice->pan_ramp_total_frames) {
            voice->pan = voice->pan_ramp_target;
            vtx_c_mixer_clear_pan_ramp(voice);
        } else {
            voice->pan_ramp_position_frame++;
        }
    }
}

static void vtx_c_mixer_update_voice_key_state(VTXCMixerVoice *voice, uint64_t absolute_frame) {
    if (voice == NULL || !voice->key_on || !voice->has_key_off_frame) {
        return;
    }
    if (absolute_frame >= voice->key_off_frame) {
        voice->key_on = 0;
    }
}

static void vtx_c_mixer_apply_voice_state_events(VTXCMixerState *state, uint64_t absolute_frame) {
    if (state == NULL) {
        return;
    }
    while (state->next_voice_state_event_index < state->voice_state_event_count) {
        VTXCMixerVoiceStateEvent *event = &state->voice_state_events[state->next_voice_state_event_index];
        VTXCMixerVoice *voice;
        if (event->scheduled_frame > absolute_frame) {
            break;
        }
        if (event->voice_index < state->voice_count) {
            voice = &state->voices[event->voice_index];
            if (event->update_gain) {
                if (event->ramp_enabled) {
                    vtx_c_mixer_start_gain_ramp(voice, event->gain);
                } else {
                    vtx_c_mixer_set_gain_immediate(voice, event->gain);
                }
            }
            if (event->update_pan) {
                if (event->ramp_enabled) {
                    vtx_c_mixer_start_pan_ramp(voice, event->pan);
                } else {
                    vtx_c_mixer_set_pan_immediate(voice, event->pan);
                }
            }
            if (event->update_sample_step) {
                voice->sample_step = vtx_c_mixer_sanitized_sample_step(event->sample_step);
            }
        }
        state->next_voice_state_event_index++;
    }
}

static void vtx_c_mixer_advance_voice_fadeout(VTXCMixerVoice *voice) {
    if (voice == NULL || voice->key_on || voice->fadeout_decrement_per_frame <= 0.0f) {
        return;
    }
    voice->fadeout_value = vtx_c_mixer_clamp(
        voice->fadeout_value - voice->fadeout_decrement_per_frame,
        0.0f,
        1.0f
    );
    if (voice->fadeout_value <= 0.0f) {
        voice->active = 0;
    }
}

static void vtx_c_mixer_advance_render_cursor(VTXCMixerState *state) {
    if (state == NULL || state->current_frame == UINT64_MAX) {
        return;
    }
    state->current_frame++;
}

static uint32_t vtx_c_mixer_clamped_next_source_index(
    const VTXCMixerVoice *voice,
    uint32_t source_index
) {
    if (source_index + 1u < voice->sample_frame_count) {
        return source_index + 1u;
    }
    return source_index;
}

static int vtx_c_mixer_source_index_is_inside_loop(
    const VTXCMixerVoice *voice,
    uint32_t source_index
) {
    return source_index >= voice->loop_start_frame &&
        source_index < voice->loop_end_frame;
}

static uint32_t vtx_c_mixer_forward_loop_next_source_index(
    const VTXCMixerVoice *voice,
    uint32_t source_index
) {
    if (vtx_c_mixer_source_index_is_inside_loop(voice, source_index) &&
        source_index + 1u >= voice->loop_end_frame) {
        return voice->loop_start_frame;
    }
    return vtx_c_mixer_clamped_next_source_index(voice, source_index);
}

static uint32_t vtx_c_mixer_ping_pong_loop_next_source_index(
    const VTXCMixerVoice *voice,
    uint32_t source_index
) {
    if (vtx_c_mixer_source_index_is_inside_loop(voice, source_index) &&
        source_index + 1u >= voice->loop_end_frame) {
        return voice->loop_end_frame >= 2u
            ? voice->loop_end_frame - 2u
            : source_index;
    }
    return vtx_c_mixer_clamped_next_source_index(voice, source_index);
}

static uint32_t vtx_c_mixer_interpolation_next_source_index(
    const VTXCMixerVoice *voice,
    uint32_t source_index
) {
    switch (voice->loop_mode) {
    case VTX_C_MIXER_LOOP_FORWARD:
        return vtx_c_mixer_forward_loop_next_source_index(voice, source_index);
    case VTX_C_MIXER_LOOP_PING_PONG:
        return vtx_c_mixer_ping_pong_loop_next_source_index(voice, source_index);
    case VTX_C_MIXER_LOOP_NONE:
    default:
        return vtx_c_mixer_clamped_next_source_index(voice, source_index);
    }
}

static float vtx_c_mixer_linear_interpolated_sample(
    const VTXCMixerVoice *voice,
    uint32_t source_index
) {
    double fraction;
    uint32_t next_index;
    float current_sample;
    float next_sample;

    current_sample = voice->sample_pcm[source_index];
    fraction = voice->sample_position - (double)source_index;
    if (fraction <= 0.0) {
        return current_sample;
    }
    if (fraction >= 1.0) {
        fraction = 1.0;
    }

    next_index = vtx_c_mixer_interpolation_next_source_index(voice, source_index);
    next_sample = voice->sample_pcm[next_index];
    return (float)(((double)current_sample * (1.0 - fraction)) + ((double)next_sample * fraction));
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

static int vtx_c_mixer_voice_slot_is_loaded(const VTXCMixerVoice *voice) {
    return voice != NULL && (voice->sample_pcm != NULL || voice->sample_frame_count > 0u);
}

static uint32_t vtx_c_mixer_alloc_voice_slot(VTXCMixerState *state, int *reused_slot) {
    uint32_t voice_index;

    if (reused_slot != NULL) {
        *reused_slot = 0;
    }
    for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
        if (!vtx_c_mixer_voice_slot_is_loaded(&state->voices[voice_index])) {
            if (reused_slot != NULL) {
                *reused_slot = 1;
            }
            return voice_index;
        }
    }
    return state->voice_count;
}

static void vtx_c_mixer_remove_voice_state_events_for_voice(VTXCMixerState *state, uint32_t voice_index) {
    uint32_t read_index;
    uint32_t write_index = 0u;
    uint32_t next_voice_state_event_index = 0u;

    if (state == NULL) {
        return;
    }
    for (read_index = 0u; read_index < state->voice_state_event_count; read_index++) {
        if (state->voice_state_events[read_index].voice_index == voice_index) {
            continue;
        }
        if (write_index != read_index) {
            state->voice_state_events[write_index] = state->voice_state_events[read_index];
        }
        if (read_index < state->next_voice_state_event_index) {
            next_voice_state_event_index++;
        }
        write_index++;
    }
    state->voice_state_event_count = write_index;
    state->next_voice_state_event_index = next_voice_state_event_index > write_index
        ? write_index
        : next_voice_state_event_index;
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
    uint32_t initial_sample_frame,
    int reject_past_scheduled_start,
    uint32_t *out_voice_index
) {
    VTXCMixerVoice *voice;
    float *sample_copy = NULL;
    uint32_t sample_index;
    uint32_t voice_index;
    int reused_slot = 0;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (sample_frame_count > 0 && sample_pcm == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (reject_past_scheduled_start && scheduled_start_frame < state->current_frame) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    voice_index = vtx_c_mixer_alloc_voice_slot(state, &reused_slot);
    if (voice_index >= VTX_C_MIXER_MAX_VOICES) {
        return VTX_C_MIXER_STATUS_VOICE_CAPACITY_EXCEEDED;
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

    voice = &state->voices[voice_index];
    memset(voice, 0, sizeof(*voice));
    voice->sample_pcm = sample_copy;
    voice->sample_frame_count = sample_frame_count;
    voice->initial_sample_frame = initial_sample_frame;
    voice->sample_position = (double)initial_sample_frame;
    voice->initial_sample_step = vtx_c_mixer_sanitized_sample_step(sample_step);
    voice->sample_step = voice->initial_sample_step;
    voice->scheduled_start_frame = scheduled_start_frame;
    voice->initial_gain = vtx_c_mixer_sanitized_gain(gain);
    voice->initial_pan = vtx_c_mixer_sanitized_pan(pan);
    voice->gain = voice->initial_gain;
    voice->pan = voice->initial_pan;
    voice->loop_mode = loop_mode;
    voice->loop_start_frame = loop_start_frame;
    voice->loop_end_frame = loop_end_frame;
    voice->ping_pong_direction = 1;
    voice->key_on = 1;
    voice->fadeout_value = 1.0f;
    voice->fadeout_decrement_per_frame = 0.0f;
    voice->active = sample_frame_count > 0 && sample_copy != NULL && initial_sample_frame < sample_frame_count;
    if (out_voice_index != NULL) {
        *out_voice_index = voice_index;
    }
    if (!reused_slot) {
        state->voice_count++;
    }
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerConfig vtx_c_mixer_default_config(void) {
    VTXCMixerConfig config;
    config.sample_rate = VTX_C_MIXER_DEFAULT_SAMPLE_RATE;
    config.channel_count = VTX_C_MIXER_DEFAULT_CHANNEL_COUNT;
    return config;
}

uint32_t vtx_c_mixer_gain_pan_update_ramp_frame_count(void) {
    return VTX_C_MIXER_GAIN_PAN_UPDATE_RAMP_FRAMES;
}

uint32_t vtx_c_mixer_loaded_voice_count(const VTXCMixerState *state) {
    uint32_t voice_index;
    uint32_t loaded_count = 0u;

    if (state == NULL) {
        return 0u;
    }
    for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
        if (vtx_c_mixer_voice_slot_is_loaded(&state->voices[voice_index])) {
            loaded_count++;
        }
    }
    return loaded_count;
}

uint32_t vtx_c_mixer_active_voice_count(const VTXCMixerState *state) {
    uint32_t voice_index;
    uint32_t active_count = 0u;

    if (state == NULL) {
        return 0u;
    }
    for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
        if (state->voices[voice_index].active) {
            active_count++;
        }
    }
    return active_count;
}

uint64_t vtx_c_mixer_current_frame(const VTXCMixerState *state) {
    return state == NULL ? 0u : state->current_frame;
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
        voice->sample_position = (double)voice->initial_sample_frame;
        voice->sample_step = voice->initial_sample_step;
        voice->ping_pong_direction = 1;
        voice->gain = voice->initial_gain;
        voice->pan = voice->initial_pan;
        vtx_c_mixer_clear_gain_ramp(voice);
        vtx_c_mixer_clear_pan_ramp(voice);
        voice->volume_envelope.position_frame = 0u;
        voice->pan_envelope.position_frame = 0u;
        voice->key_on = 1;
        voice->fadeout_value = 1.0f;
        voice->active = voice->sample_frame_count > 0 &&
            voice->sample_pcm != NULL &&
            voice->initial_sample_frame < voice->sample_frame_count;
    }
    state->next_voice_state_event_index = 0u;
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
    state->voice_state_event_count = 0u;
    state->next_voice_state_event_index = 0u;
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_set_voice_channel_tag(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint32_t channel_tag
) {
    if (state == NULL ||
        voice_index >= state->voice_count ||
        !vtx_c_mixer_voice_slot_is_loaded(&state->voices[voice_index])) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    state->voices[voice_index].has_channel_tag = 1;
    state->voices[voice_index].channel_tag = channel_tag;
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_stop_voices_for_channel_tag(
    VTXCMixerState *state,
    uint32_t channel_tag,
    uint32_t *out_stopped_count
) {
    uint32_t voice_index;
    uint32_t stopped_count = 0u;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    for (voice_index = 0u; voice_index < state->voice_count; voice_index++) {
        VTXCMixerVoice *voice = &state->voices[voice_index];
        if (!vtx_c_mixer_voice_slot_is_loaded(voice) ||
            !voice->has_channel_tag ||
            voice->channel_tag != channel_tag) {
            continue;
        }
        vtx_c_mixer_remove_voice_state_events_for_voice(state, voice_index);
        vtx_c_mixer_release_voice(voice);
        stopped_count++;
    }
    if (out_stopped_count != NULL) {
        *out_stopped_count = stopped_count;
    }
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
    return vtx_c_mixer_add_sample_voice_with_step_at_source_frame(
        state,
        sample_pcm,
        sample_frame_count,
        sample_step,
        0u,
        gain,
        pan,
        loop_mode,
        loop_start_frame,
        loop_end_frame,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_add_sample_voice_with_step_at_source_frame(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    uint32_t initial_sample_frame,
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
        initial_sample_frame,
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
    return vtx_c_mixer_add_scheduled_sample_voice_with_step_at_source_frame(
        state,
        sample_pcm,
        sample_frame_count,
        sample_step,
        0u,
        gain,
        pan,
        loop_mode,
        loop_start_frame,
        loop_end_frame,
        scheduled_start_frame,
        out_voice_index
    );
}

VTXCMixerStatus vtx_c_mixer_add_scheduled_sample_voice_with_step_at_source_frame(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    double sample_step,
    uint32_t initial_sample_frame,
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
        initial_sample_frame,
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

VTXCMixerStatus vtx_c_mixer_set_voice_key_off_frame(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t key_off_frame,
    float fadeout_decrement_per_frame
) {
    VTXCMixerVoice *voice;

    if (state == NULL || voice_index >= state->voice_count) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    voice = &state->voices[voice_index];
    if (key_off_frame < voice->scheduled_start_frame) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    voice->has_key_off_frame = 1;
    voice->key_off_frame = key_off_frame;
    voice->fadeout_decrement_per_frame = vtx_c_mixer_sanitized_fadeout_decrement(fadeout_decrement_per_frame);
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_set_voice_runtime_state(
    VTXCMixerState *state,
    uint32_t voice_index,
    double sample_position,
    int ping_pong_direction,
    uint32_t volume_envelope_position_frame,
    uint32_t pan_envelope_position_frame,
    int key_on,
    float fadeout_value
) {
    VTXCMixerVoice *voice;

    if (state == NULL || voice_index >= state->voice_count) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (!isfinite(sample_position) || sample_position < 0.0 || sample_position > (double)UINT32_MAX) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (!isfinite(fadeout_value)) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }

    voice = &state->voices[voice_index];
    voice->sample_position = sample_position;
    voice->ping_pong_direction = ping_pong_direction < 0 ? -1 : 1;
    voice->volume_envelope.position_frame = volume_envelope_position_frame;
    voice->pan_envelope.position_frame = pan_envelope_position_frame;
    voice->key_on = key_on ? 1 : 0;
    voice->fadeout_value = vtx_c_mixer_clamp(fadeout_value, 0.0f, 1.0f);
    voice->active = voice->sample_frame_count > 0 &&
        voice->sample_pcm != NULL &&
        voice->sample_position < (double)voice->sample_frame_count &&
        voice->fadeout_value > 0.0f;
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_set_voice_gain_pan_ramp_state(
    VTXCMixerState *state,
    uint32_t voice_index,
    VTXCMixerValueRampRuntimeState gain_ramp,
    VTXCMixerValueRampRuntimeState pan_ramp
) {
    VTXCMixerVoice *voice;

    if (state == NULL || voice_index >= state->voice_count) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (gain_ramp.active &&
        (!isfinite(gain_ramp.start) ||
         !isfinite(gain_ramp.target) ||
         gain_ramp.total_frames == 0u ||
         gain_ramp.position_frame >= gain_ramp.total_frames)) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (pan_ramp.active &&
        (!isfinite(pan_ramp.start) ||
         !isfinite(pan_ramp.target) ||
         pan_ramp.total_frames == 0u ||
         pan_ramp.position_frame >= pan_ramp.total_frames)) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }

    voice = &state->voices[voice_index];
    if (gain_ramp.active) {
        voice->gain_ramp_active = 1;
        voice->gain_ramp_start = vtx_c_mixer_sanitized_gain(gain_ramp.start);
        voice->gain_ramp_target = vtx_c_mixer_sanitized_gain(gain_ramp.target);
        voice->gain_ramp_total_frames = gain_ramp.total_frames;
        voice->gain_ramp_position_frame = gain_ramp.position_frame;
        voice->gain = voice->gain_ramp_target;
    } else {
        vtx_c_mixer_clear_gain_ramp(voice);
    }
    if (pan_ramp.active) {
        voice->pan_ramp_active = 1;
        voice->pan_ramp_start = vtx_c_mixer_sanitized_pan(pan_ramp.start);
        voice->pan_ramp_target = vtx_c_mixer_sanitized_pan(pan_ramp.target);
        voice->pan_ramp_total_frames = pan_ramp.total_frames;
        voice->pan_ramp_position_frame = pan_ramp.position_frame;
        voice->pan = voice->pan_ramp_target;
    } else {
        vtx_c_mixer_clear_pan_ramp(voice);
    }
    return VTX_C_MIXER_STATUS_OK;
}

static VTXCMixerStatus vtx_c_mixer_schedule_voice_gain_pan_update_internal(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    int update_gain,
    float gain,
    int update_pan,
    float pan,
    int update_sample_step,
    double sample_step,
    int ramp_enabled
) {
    VTXCMixerVoiceStateEvent event;
    uint32_t insert_index;
    uint32_t move_index;

    if (state == NULL || voice_index >= state->voice_count) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (scheduled_frame < state->current_frame) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (!vtx_c_mixer_voice_state_event_is_valid(
            update_gain,
            gain,
            update_pan,
            pan,
            update_sample_step,
            sample_step
        )) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (state->voice_state_event_count >= VTX_C_MIXER_MAX_VOICE_STATE_EVENTS) {
        return VTX_C_MIXER_STATUS_VOICE_CAPACITY_EXCEEDED;
    }

    event.voice_index = voice_index;
    event.scheduled_frame = scheduled_frame;
    event.update_gain = update_gain ? 1 : 0;
    event.gain = vtx_c_mixer_sanitized_gain(gain);
    event.update_pan = update_pan ? 1 : 0;
    event.pan = vtx_c_mixer_sanitized_pan(pan);
    event.update_sample_step = update_sample_step ? 1 : 0;
    event.sample_step = vtx_c_mixer_sanitized_sample_step(sample_step);
    event.ramp_enabled = ramp_enabled ? 1 : 0;

    insert_index = state->voice_state_event_count;
    while (insert_index > state->next_voice_state_event_index &&
           state->voice_state_events[insert_index - 1u].scheduled_frame > scheduled_frame) {
        insert_index--;
    }
    for (move_index = state->voice_state_event_count; move_index > insert_index; move_index--) {
        state->voice_state_events[move_index] = state->voice_state_events[move_index - 1u];
    }
    state->voice_state_events[insert_index] = event;
    state->voice_state_event_count++;
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_schedule_voice_gain_pan_update(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    int update_gain,
    float gain,
    int update_pan,
    float pan
) {
    return vtx_c_mixer_schedule_voice_gain_pan_update_internal(
        state,
        voice_index,
        scheduled_frame,
        update_gain,
        gain,
        update_pan,
        pan,
        0,
        1.0,
        1
    );
}

VTXCMixerStatus vtx_c_mixer_schedule_voice_sample_step_update(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    double sample_step
) {
    return vtx_c_mixer_schedule_voice_gain_pan_update_internal(
        state,
        voice_index,
        scheduled_frame,
        0,
        0.0f,
        0,
        0.0f,
        1,
        sample_step,
        0
    );
}

VTXCMixerStatus vtx_c_mixer_schedule_voice_gain_pan_update_immediate(
    VTXCMixerState *state,
    uint32_t voice_index,
    uint64_t scheduled_frame,
    int update_gain,
    float gain,
    int update_pan,
    float pan
) {
    return vtx_c_mixer_schedule_voice_gain_pan_update_internal(
        state,
        voice_index,
        scheduled_frame,
        update_gain,
        gain,
        update_pan,
        pan,
        0,
        1.0,
        0
    );
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
        vtx_c_mixer_apply_voice_state_events(state, absolute_frame);
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
            vtx_c_mixer_update_voice_key_state(voice, absolute_frame);
            if (voice->sample_position < 0.0 || voice->sample_position > (double)UINT32_MAX) {
                voice->active = 0;
                continue;
            }
            source_index = (uint32_t)voice->sample_position;
            if (voice->sample_pcm == NULL || source_index >= voice->sample_frame_count) {
                voice->active = 0;
                continue;
            }

            mono_sample = vtx_c_mixer_linear_interpolated_sample(voice, source_index) *
                vtx_c_mixer_effective_gain(voice) *
                vtx_c_mixer_evaluate_envelope(&voice->volume_envelope, 1.0f) *
                voice->fadeout_value;
            if (channel_count_size == 1) {
                output_interleaved_float32[frame_offset] += mono_sample;
            } else {
                float effective_pan = vtx_c_mixer_sanitized_pan(
                    vtx_c_mixer_effective_pan(voice) +
                    vtx_c_mixer_evaluate_envelope(&voice->pan_envelope, 0.0f)
                );
                output_interleaved_float32[frame_offset] += mono_sample * vtx_c_mixer_left_pan_gain(effective_pan);
                output_interleaved_float32[frame_offset + 1] += mono_sample * vtx_c_mixer_right_pan_gain(effective_pan);
            }

            vtx_c_mixer_advance_sample_position(voice);
            vtx_c_mixer_advance_voice_envelopes(voice);
            vtx_c_mixer_advance_value_ramps(voice);
            vtx_c_mixer_advance_voice_fadeout(voice);
        }
        vtx_c_mixer_advance_render_cursor(state);
    }
    return VTX_C_MIXER_STATUS_OK;
}
