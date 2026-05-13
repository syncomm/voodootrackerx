#ifndef VTX_C_MIXER_H
#define VTX_C_MIXER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VTX_C_MIXER_DEFAULT_SAMPLE_RATE 44100.0
#define VTX_C_MIXER_DEFAULT_CHANNEL_COUNT 2u

// Temporary fixed voice limit for the early offline C mixer path.
// Rendering uses this preallocated storage and does not allocate in the render call.
#define VTX_C_MIXER_MAX_VOICES 32u

typedef enum {
    VTX_C_MIXER_STATUS_OK = 0,
    VTX_C_MIXER_STATUS_INVALID_ARGUMENT = 1,
} VTXCMixerStatus;

typedef enum {
    VTX_C_MIXER_LOOP_NONE = 0,
    VTX_C_MIXER_LOOP_FORWARD = 1,
    VTX_C_MIXER_LOOP_PING_PONG = 2,
} VTXCMixerLoopMode;

typedef struct {
    double sample_rate;
    uint32_t channel_count;
} VTXCMixerConfig;

typedef struct {
    float *sample_pcm;
    uint32_t sample_frame_count;
    double sample_position;
    float gain;
    float pan;
    VTXCMixerLoopMode loop_mode;
    uint32_t loop_start_frame;
    uint32_t loop_end_frame;
    int ping_pong_direction;
    int active;
} VTXCMixerVoice;

typedef struct {
    VTXCMixerConfig config;
    uint32_t voice_count;
    VTXCMixerVoice voices[VTX_C_MIXER_MAX_VOICES];
} VTXCMixerState;

VTXCMixerConfig vtx_c_mixer_default_config(void);
VTXCMixerStatus vtx_c_mixer_init(VTXCMixerState *state, VTXCMixerConfig config);
VTXCMixerStatus vtx_c_mixer_reset(VTXCMixerState *state);
VTXCMixerStatus vtx_c_mixer_configure(VTXCMixerState *state, VTXCMixerConfig config);

// Clears all active one-shot voices and returns the mixer to deterministic silence.
VTXCMixerStatus vtx_c_mixer_clear_voices(VTXCMixerState *state);

// Copies a caller-owned mono Float32 sample buffer into C-owned one-shot voice storage.
VTXCMixerStatus vtx_c_mixer_add_one_shot_sample(
    VTXCMixerState *state,
    const float *sample_pcm,
    uint32_t sample_frame_count,
    float gain,
    float pan,
    uint32_t *out_voice_index
);

// Copies a caller-owned mono Float32 sample buffer into C-owned voice storage.
// loop_end_frame is exclusive; invalid loop definitions fall back to one-shot playback.
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
);
VTXCMixerStatus vtx_c_mixer_render(
    VTXCMixerState *state,
    float *output_interleaved_float32,
    uint32_t frame_count
);

#ifdef __cplusplus
}
#endif

#endif
