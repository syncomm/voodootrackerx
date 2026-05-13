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

static float vtx_c_mixer_sanitized_pan(float pan) {
    if (!isfinite(pan)) {
        return 0.0f;
    }
    if (pan < -1.0f) {
        return -1.0f;
    }
    if (pan > 1.0f) {
        return 1.0f;
    }
    return pan;
}

static float vtx_c_mixer_left_pan_gain(float pan) {
    return pan <= 0.0f ? 1.0f : 1.0f - pan;
}

static float vtx_c_mixer_right_pan_gain(float pan) {
    return pan >= 0.0f ? 1.0f : 1.0f + pan;
}

static void vtx_c_mixer_release_voice(VTXCMixerVoice *voice) {
    if (voice == NULL) {
        return;
    }
    free(voice->sample_pcm);
    memset(voice, 0, sizeof(*voice));
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
    for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
        VTXCMixerVoice *voice = &state->voices[voice_index];
        voice->sample_position = 0.0;
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
    VTXCMixerVoice *voice;
    float *sample_copy = NULL;
    uint32_t sample_index;

    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
    }
    if (sample_frame_count > 0 && sample_pcm == NULL) {
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

    voice = &state->voices[state->voice_count];
    memset(voice, 0, sizeof(*voice));
    voice->sample_pcm = sample_copy;
    voice->sample_frame_count = sample_frame_count;
    voice->sample_position = 0.0;
    voice->gain = vtx_c_mixer_sanitized_gain(gain);
    voice->pan = vtx_c_mixer_sanitized_pan(pan);
    voice->active = sample_frame_count > 0 && sample_copy != NULL;
    if (out_voice_index != NULL) {
        *out_voice_index = state->voice_count;
    }
    state->voice_count++;
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
        for (voice_index = 0; voice_index < state->voice_count; voice_index++) {
            VTXCMixerVoice *voice = &state->voices[voice_index];
            uint32_t source_index;
            float mono_sample;

            if (!voice->active) {
                continue;
            }
            source_index = (uint32_t)voice->sample_position;
            if (voice->sample_pcm == NULL || source_index >= voice->sample_frame_count) {
                voice->active = 0;
                continue;
            }

            mono_sample = voice->sample_pcm[source_index] * voice->gain;
            if (channel_count_size == 1) {
                output_interleaved_float32[frame_offset] += mono_sample;
            } else {
                output_interleaved_float32[frame_offset] += mono_sample * vtx_c_mixer_left_pan_gain(voice->pan);
                output_interleaved_float32[frame_offset + 1] += mono_sample * vtx_c_mixer_right_pan_gain(voice->pan);
            }

            voice->sample_position += 1.0;
            if (voice->sample_position >= (double)voice->sample_frame_count) {
                voice->active = 0;
            }
        }
    }
    return VTX_C_MIXER_STATUS_OK;
}
