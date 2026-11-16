// Public standalone host-delivery witness: no VTX mixer, planner or test runner.
#include <AudioToolbox/AudioToolbox.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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

// The target and continuous silent control use identical DefaultOutput configuration.
static AudioUnit prepare(AudioComponent component, Progress *progress, OSStatus *status) {
    AudioUnit unit = NULL;
    *status = AudioComponentInstanceNew(component, &unit);
    AudioStreamBasicDescription format = { .mSampleRate = 48000,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |
            kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4,
        .mChannelsPerFrame = 1, .mBitsPerChannel = 32 };
    AURenderCallbackStruct callback = { render, progress };
    if (*status == noErr) *status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 0, &format, sizeof(format));
    if (*status == noErr) *status = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input, 0, &callback, sizeof(callback));
    if (*status == noErr) *status = AudioUnitInitialize(unit);
    return unit;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    const int rapid = argc == 2 && strcmp(argv[1], "--rapid-restart") == 0;
    const int guarded = argc == 2 && strcmp(argv[1], "--guarded-idle-restart") == 0;
    const int idle = guarded || (argc == 2 && strcmp(argv[1], "--idle-restart") == 0);
    if (argc != 1 && !rapid && !idle) return 2;
    const unsigned primers = idle ? 3 : rapid ? 1 : 0, span = primers + 1;
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS) _Exit(1);
    const uint64_t second = (uint64_t)1000000000 * timebase.denom / timebase.numer;
    AudioComponentDescription description = { .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_DefaultOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple };
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (!component) _Exit(1);
    int failed = 0, incomplete = 0;
    uint64_t first_prelude_start = 0, prelude_start = 0, prelude_stopped = 0;
    AudioDeviceID prelude_device = 0;
    Progress guard_progress = {0};
    if (!atomic_is_lock_free(&guard_progress.frames) || !atomic_is_lock_free(&guard_progress.active)) _Exit(1);
    AudioUnit guard_unit = NULL;
    AudioDeviceID guard_device = 0;
    uint64_t previous_guard_frames = 0;
    printf("pid=%d timebaseNumer=%u timebaseDenom=%u iterations=20 requiredFrames=48000 deadlineSeconds=10 rapidRestart=%d idleRestart=%d primers=%u guarded=%d\n",
           getpid(), timebase.numer, timebase.denom, rapid, idle, primers, guarded);
    if (guarded) {
        OSStatus status;
        guard_unit = prepare(component, &guard_progress, &status);
        UInt32 size = sizeof(guard_device);
        if (status == noErr) status = AudioUnitGetProperty(guard_unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &guard_device, &size);
        if (status != noErr) { fprintf(stderr, "guardSetupStatus=%d\n", (int)status); _Exit(1); }
        UInt32 running = 0;
        AudioObjectPropertyAddress address = { kAudioDevicePropertyDeviceIsRunningSomewhere,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        size = sizeof(running);
        OSStatus running_status = AudioObjectGetPropertyData(guard_device, &address, 0, NULL, &size, &running);
        printf("guardDevice=%u deviceRunningBeforeStart=%u runningStatus=%d\n", guard_device, running, (int)running_status);
        if (running_status != noErr || running != 0) incomplete = 1;
        const uint64_t deadline = mach_absolute_time() + 10 * second;
        if (status == noErr) status = AudioOutputUnitStart(guard_unit);
        if (status != noErr) { fprintf(stderr, "guardStartStatus=%d\n", (int)status); _Exit(1); }
        while (mach_absolute_time() < deadline && atomic_load_explicit(&guard_progress.reached_goal_at, memory_order_acquire) == 0)
            usleep(1000);
        const uint64_t reached = atomic_load_explicit(&guard_progress.reached_goal_at, memory_order_acquire);
        const int ready = reached != 0 && reached <= deadline;
        printf("guardDevice=%u ready=%d deadline=%llu reached=%llu\n", guard_device, ready,
               (unsigned long long)deadline, (unsigned long long)reached);
        observe(0, "guard-ready", &guard_progress, guard_unit);
        if (!ready) _Exit(1);
        previous_guard_frames = atomic_load(&guard_progress.frames);
    }
    for (unsigned cycle = 1; cycle <= 20 * span; ++cycle) {
        const unsigned iteration = (cycle - 1) / span + 1;
        const int prelude = (cycle - 1) % span < primers;
        Progress progress = {0};
        if (!atomic_is_lock_free(&progress.frames) || !atomic_is_lock_free(&progress.active)) _Exit(1);
        OSStatus status;
        AudioUnit unit = prepare(component, &progress, &status);
        UInt32 capacity = 0, size = sizeof(capacity);
        if (status == noErr) status = AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global, 0, &capacity, &size);
        printf("iteration=%u prelude=%d maximumFramesPerSlice=%u\n", iteration, prelude, capacity);
        if (status != noErr) {
            fprintf(stderr, "iteration=%u setupStatus=%d\n", iteration, (int)status);
            _Exit(1);
        }
        AudioDeviceID device = 0;
        size = sizeof(device);
        OSStatus device_status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &device, &size);
        Float64 rate = 0;
        AudioObjectPropertyAddress address = { kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        size = sizeof(rate);
        OSStatus rate_status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &rate);
        printf("iteration=%u prelude=%d device=%u deviceStatus=%d nominalRate=%.0f rateStatus=%d\n",
               iteration, prelude, device, (int)device_status, rate, (int)rate_status);
        UInt32 device_running = 0;
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere;
        size = sizeof(device_running);
        OSStatus running_status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &device_running);
        printf("iteration=%u prelude=%d deviceRunningBeforeStart=%u deviceRunningStatus=%d\n",
               iteration, prelude, device_running, (int)running_status);
        if (device_status != noErr || running_status != noErr || device_running != (UInt32)guarded ||
            (guarded && device != guard_device)) incomplete = 1;
        const uint64_t start = mach_absolute_time(), deadline = start + 10 * second;
        if (status == noErr) status = AudioOutputUnitStart(unit);
        const uint64_t start_returned = mach_absolute_time();
        if (status != noErr) {
            fprintf(stderr, "iteration=%u startStatus=%d\n", iteration, (int)status);
            _Exit(1); // Process exit retains the callback's stack owner.
        }
        if (prelude) {
            // Stop each primer inside the virtual device's 260 ms first-timer window.
            // Avoid property queries/logging between Start and Stop so they cannot mask it.
            prelude_start = start;
            if (cycle % span == 1) {
                first_prelude_start = start;
                prelude_device = device;
            } else if (device != prelude_device) incomplete = 1;
            const uint64_t minimum = idle ? second / 100 : second / 20;
            while (mach_absolute_time() - start_returned < minimum ||
                   (atomic_load(&progress.frames) == 0 && mach_absolute_time() - start_returned < second / 20))
                usleep(1000);
            status = AudioOutputUnitStop(unit);
            prelude_stopped = mach_absolute_time();
            printf("iteration=%u prelude=1 start=%llu startReturned=%llu stopped=%llu stopStatus=%d frames=%llu entries=%llu callbacks=%llu active=%u\n",
                   iteration, (unsigned long long)start, (unsigned long long)start_returned,
                   (unsigned long long)prelude_stopped,
                   (int)status, (unsigned long long)atomic_load(&progress.frames),
                   (unsigned long long)atomic_load(&progress.entries),
                   (unsigned long long)atomic_load(&progress.callbacks), atomic_load(&progress.active));
            if (atomic_load(&progress.frames) == 0 || atomic_load(&progress.active) != 0 ||
                atomic_load(&progress.entries) != atomic_load(&progress.callbacks)) incomplete = 1;
            if (status != noErr || AudioUnitUninitialize(unit) != noErr ||
                AudioComponentInstanceDispose(unit) != noErr) _Exit(1);
            if (idle && cycle % span == primers) {
                // Historical failure followed several short sessions and an idle gap.
                // Let pending first timers fire against the stopped device before restarting.
                while (mach_absolute_time() - prelude_stopped < second / 2) usleep(1000);
            }
            continue;
        }
        printf("iteration=%u startStatus=%d\n", iteration, (int)status);
        if (primers) {
            const int within_window = idle
                ? prelude_stopped - first_prelude_start < second * 260 / 1000 && start - prelude_stopped >= second / 2
                : start_returned - prelude_start < second * 260 / 1000;
            printf("iteration=%u %sWindowMet=%d firstPreludeStart=%llu preludeStart=%llu preludeStopped=%llu targetStart=%llu targetStartReturned=%llu restartMilliseconds=%.3f\n",
                   iteration, idle ? "idle" : "rapid", within_window,
                   (unsigned long long)first_prelude_start, (unsigned long long)prelude_start,
                   (unsigned long long)prelude_stopped, (unsigned long long)start,
                   (unsigned long long)start_returned,
                   (double)(start_returned - prelude_start) * 1000 / second);
            if (!within_window || device != prelude_device || running_status != noErr || device_running != (UInt32)guarded)
                incomplete = 1; // An unexercised interleaving is not a passing witness.
        }
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
        if (status != noErr) _Exit(1);
        status = AudioUnitUninitialize(unit);
        if (status != noErr) _Exit(1);
        status = AudioComponentInstanceDispose(unit);
        if (status != noErr) _Exit(1);
        if (atomic_load(&progress.active) != 0 ||
            atomic_load(&progress.entries) != atomic_load(&progress.callbacks)) failed = 1;
        if (guarded) {
            // Observe off the target's measured interval; guard frames never credit a target.
            const uint64_t frames = atomic_load(&guard_progress.frames);
            UInt32 running = 0, guard_size = sizeof(running);
            const OSStatus run_status = AudioUnitGetProperty(guard_unit, kAudioOutputUnitProperty_IsRunning,
                kAudioUnitScope_Global, 0, &running, &guard_size);
            AudioDeviceID current_device = 0;
            guard_size = sizeof(current_device);
            const OSStatus device_status = AudioUnitGetProperty(guard_unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &current_device, &guard_size);
            printf("iteration=%u guardFrames=%llu guardDelta=%llu guardRunning=%u guardRunningStatus=%d guardDevice=%u guardDeviceStatus=%d\n",
                   iteration, (unsigned long long)frames, (unsigned long long)(frames - previous_guard_frames),
                   running, (int)run_status, current_device, (int)device_status);
            if (frames - previous_guard_frames < 48000 || run_status != noErr || running != 1 ||
                device_status != noErr || current_device != guard_device) failed = 1;
            previous_guard_frames = frames;
        }
    }
    if (guarded) {
        observe(0, "guard-end", &guard_progress, guard_unit);
        UInt32 running = 0, size = sizeof(running);
        if (AudioUnitGetProperty(guard_unit, kAudioOutputUnitProperty_IsRunning,
            kAudioUnitScope_Global, 0, &running, &size) != noErr || running != 1) failed = 1;
        const OSStatus stop_status = AudioOutputUnitStop(guard_unit);
        printf("guardStopStatus=%d\n", (int)stop_status);
        if (stop_status != noErr || AudioUnitUninitialize(guard_unit) != noErr ||
            AudioComponentInstanceDispose(guard_unit) != noErr) _Exit(1);
        if (atomic_load(&guard_progress.active) != 0 ||
            atomic_load(&guard_progress.entries) != atomic_load(&guard_progress.callbacks)) failed = 1;
    }
    printf("deliveryFailed=%d witnessIncomplete=%d\n", failed, incomplete);
    return failed ? 1 : incomplete ? 2 : 0; // Later cycles never erase earlier failures.
}
