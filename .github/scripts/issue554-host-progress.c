// Public standalone host-delivery witness: no VTX mixer, planner or test runner.
#include <AudioToolbox/AudioToolbox.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    _Atomic uint64_t frames;
    _Atomic uint64_t callbacks;
    _Atomic uint64_t entries;
    _Atomic uint64_t nil_buffers;
    _Atomic uint64_t reached_goal_at;
    _Atomic uint64_t last_host_time;
    _Atomic uint64_t last_sample_bits;
    _Atomic uint32_t timestamp_flags;
    _Atomic uint32_t active;
} Progress;

static OSStatus render(void *context, AudioUnitRenderActionFlags *flags,
                       const AudioTimeStamp *time, UInt32 bus, UInt32 frames,
                       AudioBufferList *data) {
    (void)flags;
    (void)bus;
    Progress *p = context;
    atomic_fetch_add_explicit(&p->entries, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&p->active, 1, memory_order_relaxed);
    if (data) {
        for (UInt32 i = 0; i < data->mNumberBuffers; ++i) {
            if (data->mBuffers[i].mData)
                memset(data->mBuffers[i].mData, 0, data->mBuffers[i].mDataByteSize);
        }
        uint64_t previous = atomic_fetch_add_explicit(&p->frames, frames, memory_order_relaxed);
        if (previous < 48000 && previous + frames >= 48000)
            atomic_store_explicit(&p->reached_goal_at, mach_absolute_time(), memory_order_release);
    } else atomic_fetch_add_explicit(&p->nil_buffers, 1, memory_order_relaxed);
    atomic_store_explicit(&p->last_host_time, time->mHostTime, memory_order_relaxed);
    uint64_t bits;
    memcpy(&bits, &time->mSampleTime, sizeof(bits));
    atomic_store_explicit(&p->last_sample_bits, bits, memory_order_relaxed);
    atomic_store_explicit(&p->timestamp_flags, time->mFlags, memory_order_relaxed);
    atomic_fetch_add_explicit(&p->callbacks, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&p->active, 1, memory_order_relaxed);
    return noErr;
}

static void observe(unsigned iteration, const char *phase, Progress *p, AudioUnit unit) {
    UInt32 running = 0, size = sizeof(running);
    OSStatus status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_IsRunning,
        kAudioUnitScope_Global, 0, &running, &size);
    uint64_t bits = atomic_load(&p->last_sample_bits);
    double sample;
    memcpy(&sample, &bits, sizeof(sample));
    printf("iteration=%u phase=%s now=%llu frames=%llu callbacks=%llu entries=%llu nilBuffers=%llu active=%u "
           "lastHostTime=%llu lastSampleTime=%.0f timestampFlags=%u running=%u runningStatus=%d\n", iteration, phase,
           (unsigned long long)mach_absolute_time(),
           (unsigned long long)atomic_load(&p->frames),
           (unsigned long long)atomic_load(&p->callbacks),
           (unsigned long long)atomic_load(&p->entries),
           (unsigned long long)atomic_load(&p->nil_buffers), atomic_load(&p->active),
           (unsigned long long)atomic_load(&p->last_host_time), sample,
           atomic_load(&p->timestamp_flags), running, (int)status);
    fflush(stdout);
}

int main(void) {
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS) return 1;
    const uint64_t second = (uint64_t)1000000000 * timebase.denom / timebase.numer;
    AudioComponentDescription description = { .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_DefaultOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple };
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (!component) return 1;
    int failed = 0;
    printf("pid=%d timebaseNumer=%u timebaseDenom=%u iterations=20 requiredFrames=48000 deadlineSeconds=10\n",
           getpid(), timebase.numer, timebase.denom);
    for (unsigned iteration = 1; iteration <= 20; ++iteration) {
        Progress progress = {0};
        if (!atomic_is_lock_free(&progress.frames) || !atomic_is_lock_free(&progress.active)) return 1;
        AudioUnit unit = NULL;
        OSStatus status = AudioComponentInstanceNew(component, &unit);
        AudioStreamBasicDescription format = { .mSampleRate = 48000,
            .mFormatID = kAudioFormatLinearPCM,
            .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4,
            .mChannelsPerFrame = 1, .mBitsPerChannel = 32 };
        AURenderCallbackStruct callback = { render, &progress };
        if (status == noErr) status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, 0, &format, sizeof(format));
        if (status == noErr) status = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input, 0, &callback, sizeof(callback));
        if (status == noErr) status = AudioUnitInitialize(unit);
        UInt32 capacity = 0, size = sizeof(capacity);
        if (status == noErr) status = AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global, 0, &capacity, &size);
        printf("iteration=%u maximumFramesPerSlice=%u\n", iteration, capacity);
        const uint64_t start = mach_absolute_time(), deadline = start + 10 * second;
        if (status == noErr) status = AudioOutputUnitStart(unit);
        printf("iteration=%u startStatus=%d\n", iteration, (int)status);
        if (status != noErr) return 1; // Process exit retains the callback's stack owner.
        AudioDeviceID device = 0;
        size = sizeof(device);
        OSStatus device_status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &device, &size);
        Float64 rate = 0;
        AudioObjectPropertyAddress address = { kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        size = sizeof(rate);
        OSStatus rate_status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &rate);
        printf("iteration=%u device=%u deviceStatus=%d nominalRate=%.0f rateStatus=%d\n",
               iteration, device, (int)device_status, rate, (int)rate_status);
        uint64_t next_observation = start;
        while (mach_absolute_time() < deadline && atomic_load_explicit(&progress.reached_goal_at, memory_order_acquire) == 0) {
            if (mach_absolute_time() >= next_observation) {
                observe(iteration, "live", &progress, unit);
                next_observation = mach_absolute_time() + second;
            }
            usleep(1000); // Deliberately no Main run-loop servicing, matching the failing case.
        }
        // Freeze before any OS query/logging can delay and accidentally admit late frames.
        const uint64_t reached = atomic_load_explicit(&progress.reached_goal_at, memory_order_acquire);
        const int completed = reached != 0 && reached <= deadline;
        if (!completed) failed = 1;
        printf("iteration=%u completedWithinDeadline=%d start=%llu deadline=%llu reached=%llu\n",
               iteration, completed, (unsigned long long)start,
               (unsigned long long)deadline, (unsigned long long)reached);
        observe(iteration, "deadline-or-completion", &progress, unit);
        status = AudioOutputUnitStop(unit);
        printf("iteration=%u stopStatus=%d\n", iteration, (int)status);
        if (status != noErr) return 1;
        status = AudioUnitUninitialize(unit);
        if (status != noErr) return 1;
        status = AudioComponentInstanceDispose(unit);
        if (status != noErr) return 1;
    }
    return failed; // A later successful cycle never erases an earlier failure.
}
