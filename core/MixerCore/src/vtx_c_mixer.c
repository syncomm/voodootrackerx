#include "vtx_c_mixer.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
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
    state->config = vtx_c_mixer_sanitized_config(config);
    return VTX_C_MIXER_STATUS_OK;
}

VTXCMixerStatus vtx_c_mixer_reset(VTXCMixerState *state) {
    if (state == NULL) {
        return VTX_C_MIXER_STATUS_INVALID_ARGUMENT;
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

VTXCMixerStatus vtx_c_mixer_render(
    VTXCMixerState *state,
    float *output_interleaved_float32,
    uint32_t frame_count
) {
    size_t frame_count_size;
    size_t channel_count_size;
    size_t sample_count;
    size_t byte_count;

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
    return VTX_C_MIXER_STATUS_OK;
}
