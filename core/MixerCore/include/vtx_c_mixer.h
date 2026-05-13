#ifndef VTX_C_MIXER_H
#define VTX_C_MIXER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTX_C_MIXER_DEFAULT_SAMPLE_RATE 44100.0
#define VTX_C_MIXER_DEFAULT_CHANNEL_COUNT 2u

typedef enum {
    VTX_C_MIXER_STATUS_OK = 0,
    VTX_C_MIXER_STATUS_INVALID_ARGUMENT = 1,
} VTXCMixerStatus;

typedef struct {
    double sample_rate;
    uint32_t channel_count;
} VTXCMixerConfig;

typedef struct {
    VTXCMixerConfig config;
} VTXCMixerState;

VTXCMixerConfig vtx_c_mixer_default_config(void);
VTXCMixerStatus vtx_c_mixer_init(VTXCMixerState *state, VTXCMixerConfig config);
VTXCMixerStatus vtx_c_mixer_reset(VTXCMixerState *state);
VTXCMixerStatus vtx_c_mixer_configure(VTXCMixerState *state, VTXCMixerConfig config);
VTXCMixerStatus vtx_c_mixer_render(
    VTXCMixerState *state,
    float *output_interleaved_float32,
    uint32_t frame_count
);

#ifdef __cplusplus
}
#endif

#endif
