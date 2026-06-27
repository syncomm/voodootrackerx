import AppKit
import AudioToolbox
import XCTest

final class RuntimeCMixerTests: XCTestCase {
    func testRuntimeCMixerAdapterEventPlanReportsLxxEnvelopePositionMetadata() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32),
            PlaybackEnvelopePoint(tick: 2, value: 0),
        ])
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x15, effectParam: 0x02),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let sameFrameEvents = plan.events.filter { $0.scheduledFrame == 0 }
        let lxx = try XCTUnwrap(sameFrameEvents.first { $0.categories.contains("lxx_set_envelope_position") })

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("lxx_set_envelope_position"))
        XCTAssertEqual(sameFrameEvents.map(\.primaryCategory), ["note_trigger", "lxx_set_envelope_position"])
        XCTAssertEqual(lxx.effectType, 0x15)
        XCTAssertEqual(lxx.effectParam, 0x02)
        if case let .envelopePositionUpdate(activeEventIndex, positionFrame) = lxx.action {
            XCTAssertEqual(activeEventIndex, 0)
            XCTAssertEqual(positionFrame, 2)
        } else {
            XCTFail("Expected Lxx runtime event to bridge as envelope-position update")
        }
    }

    func testRuntimeCMixerAdapterEventPlanReportsE5xSetFinetuneMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x5F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])]
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let adaptedPlan = try XCTUnwrap(plan.plan)
        let mapping = try XCTUnwrap(adaptedPlan.diagnostics.eventMappings.first)
        let diagnostic = try XCTUnwrap(adaptedPlan.diagnostics.setFinetuneEffects.first)

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("e5x_set_finetune"))
        XCTAssertTrue(noteTrigger.categories.contains("e5x_set_finetune"))
        XCTAssertEqual(noteTrigger.effectType, 0x0E)
        XCTAssertEqual(noteTrigger.effectParam, 0x5F)
        XCTAssertEqual(mapping.effectType, 0x0E)
        XCTAssertEqual(mapping.effectParam, 0x5F)
        XCTAssertEqual(mapping.effectiveFinetune, 112)
        XCTAssertEqual(diagnostic.status, .applied)
    }

    func testRuntimeCMixerAdapterEventPlanReportsKxxKeyOffMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x14, effectParam: 0x01),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])], initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let keyOff = try XCTUnwrap(try XCTUnwrap(plan.plan).diagnostics.keyOffEvents.first)

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("key_off"))
        XCTAssertTrue(plan.categories.contains("kxx_key_off"))
        XCTAssertTrue(noteTrigger.categories.contains("key_off"))
        XCTAssertTrue(noteTrigger.categories.contains("kxx_key_off"))
        XCTAssertEqual(noteTrigger.effectType, 0x14)
        XCTAssertEqual(noteTrigger.effectParam, 0x01)
        XCTAssertEqual(keyOff.effectType, 0x14)
        XCTAssertEqual(keyOff.scheduledFrame, 5)
    }

    func testRuntimeCMixerAdapterEventPlanReportsSampleOffset900MemoryMetadata() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let memoryTrigger = try XCTUnwrap(plan.events.first {
            $0.categories.contains("note_trigger") &&
                $0.categories.contains("900_sample_offset_memory_applied")
        })

        XCTAssertTrue(plan.categories.contains("effect_memory_reused"))
        XCTAssertTrue(memoryTrigger.categories.contains("sample_offset"))
        XCTAssertTrue(memoryTrigger.categories.contains("effect_memory_reused"))
        XCTAssertEqual(memoryTrigger.effectType, 0x09)
        XCTAssertEqual(memoryTrigger.effectParam, 0x00)
    }

    func testRuntimeCMixerAdapterEventPlanReportsPortamentoSlideMemoryMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x20),
                makePlaybackRow(index: 2, effectType: 0x01, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let memoryUpdates = plan.events.filter {
            $0.categories.contains("step_update") &&
                $0.categories.contains("portamento_1xx_memory_reused")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("portamento_1xx_memory_reused"))
        XCTAssertTrue(plan.categories.contains("effect_memory_reused"))
        XCTAssertEqual(memoryUpdates.count, 3)
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.categories.contains("portamento_update") })
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.effectType == 0x01 })
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.effectParam == 0x00 })
    }

    func testRuntimeCMixerAdapterEventPlanReportsE1xMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x1F),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x11),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let update = try XCTUnwrap(plan.events.first { $0.categories.contains("e1x_fine_portamento_up") && $0.categories.contains("step_update") })

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("e1x_fine_portamento_up"))
        XCTAssertTrue(noteTrigger.categories.contains("e1x_fine_portamento_up"))
        XCTAssertEqual(noteTrigger.effectType, 0x0E)
        XCTAssertEqual(noteTrigger.effectParam, 0x1F)
        XCTAssertEqual(update.effectType, 0x0E)
        XCTAssertEqual(update.effectParam, 0x11)
        XCTAssertEqual(update.scheduledFrame, 4)
    }

    func testRuntimeCMixerAdapterEventPlanReportsE2xMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x2F),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x21),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let update = try XCTUnwrap(plan.events.first { $0.categories.contains("e2x_fine_portamento_down") && $0.categories.contains("step_update") })

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("e2x_fine_portamento_down"))
        XCTAssertTrue(noteTrigger.categories.contains("e2x_fine_portamento_down"))
        XCTAssertEqual(noteTrigger.effectType, 0x0E)
        XCTAssertEqual(noteTrigger.effectParam, 0x2F)
        XCTAssertEqual(update.effectType, 0x0E)
        XCTAssertEqual(update.effectParam, 0x21)
        XCTAssertEqual(update.scheduledFrame, 4)
    }

    func testRuntimeCMixerAdapterEventPlanReportsXxyMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x21, effectParam: 0x1F),
                makePlaybackRow(index: 1, effectType: 0x21, effectParam: 0x21),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let update = try XCTUnwrap(plan.events.first { $0.categories.contains("x2x_extra_fine_portamento_down") && $0.categories.contains("step_update") })

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("xxy_extra_fine_portamento"))
        XCTAssertTrue(plan.categories.contains("x1x_extra_fine_portamento_up"))
        XCTAssertTrue(plan.categories.contains("x2x_extra_fine_portamento_down"))
        XCTAssertTrue(noteTrigger.categories.contains("xxy_extra_fine_portamento"))
        XCTAssertTrue(noteTrigger.categories.contains("x1x_extra_fine_portamento_up"))
        XCTAssertEqual(noteTrigger.effectType, 0x21)
        XCTAssertEqual(noteTrigger.effectParam, 0x1F)
        XCTAssertEqual(update.effectType, 0x21)
        XCTAssertEqual(update.effectParam, 0x21)
        XCTAssertEqual(update.scheduledFrame, 4)
    }

    func testRuntimeCMixerAdapterEventPlanReportsFineVolumeSlideMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0E, effectParam: 0xAF),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0xA1),
                makePlaybackRow(index: 2, effectType: 0x0E, effectParam: 0xB1),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let eaxUpdate = try XCTUnwrap(plan.events.first { $0.categories.contains("eax_fine_volume_slide_up") && $0.categories.contains("gain_pan_update") })
        let ebxUpdate = try XCTUnwrap(plan.events.first { $0.categories.contains("ebx_fine_volume_slide_down") && $0.categories.contains("gain_pan_update") })

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("eax_fine_volume_slide_up"))
        XCTAssertTrue(plan.categories.contains("ebx_fine_volume_slide_down"))
        XCTAssertTrue(noteTrigger.categories.contains("eax_fine_volume_slide_up"))
        XCTAssertEqual(noteTrigger.effectType, 0x0E)
        XCTAssertEqual(noteTrigger.effectParam, 0xAF)
        XCTAssertEqual(eaxUpdate.effectType, 0x0E)
        XCTAssertEqual(eaxUpdate.effectParam, 0xA1)
        XCTAssertEqual(eaxUpdate.scheduledFrame, 1)
        XCTAssertEqual(ebxUpdate.effectType, 0x0E)
        XCTAssertEqual(ebxUpdate.effectParam, 0xB1)
        XCTAssertEqual(ebxUpdate.scheduledFrame, 2)
    }

    func testRuntimeCMixerAdapterEventPlanReportsAxyTickLevelGainUpdateMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x0F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first {
            $0.categories.contains("note_trigger") && $0.categories.contains("axy_volume_slide")
        })
        let gainUpdates = plan.events.filter {
            $0.categories.contains("gain_pan_update") && $0.categories.contains("axy_volume_slide")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("axy_volume_slide"))
        XCTAssertEqual(noteTrigger.effectType, 0x0A)
        XCTAssertEqual(noteTrigger.effectParam, 0x0F)
        XCTAssertEqual(gainUpdates.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(gainUpdates.map(\.scheduledFrame), [1, 2])
        XCTAssertTrue(gainUpdates.allSatisfy { $0.effectType == 0x0A })
        XCTAssertTrue(gainUpdates.allSatisfy { $0.effectParam == 0x0F })
    }

    func testRuntimeCMixerAdapterEventPlanReportsAxyVolumeSlideMemoryMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x01),
                makePlaybackRow(index: 1, note: 52, instrument: 1, effectType: 0x0A, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let memoryTrigger = try XCTUnwrap(plan.events.first {
            $0.categories.contains("note_trigger") &&
                $0.categories.contains("axy_volume_slide_memory_reused")
        })
        let memoryUpdates = plan.events.filter {
            $0.categories.contains("gain_pan_update") &&
                $0.categories.contains("axy_volume_slide_memory_reused")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("effect_memory_reused"))
        XCTAssertTrue(plan.categories.contains("axy_volume_slide_memory_reused"))
        XCTAssertEqual(memoryTrigger.effectType, 0x0A)
        XCTAssertEqual(memoryTrigger.effectParam, 0x00)
        XCTAssertEqual(memoryUpdates.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(memoryUpdates.map(\.effectType), [0x0A, 0x0A])
        XCTAssertEqual(memoryUpdates.map(\.effectParam), [0x00, 0x00])
    }

    func testRuntimeCMixerAdapterEventPlanReportsTonePortamentoVolumeSlide5xyMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x02),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let stepUpdates = plan.events.filter {
            $0.categories.contains("step_update") &&
                $0.categories.contains("tone_portamento_volume_slide_5xy")
        }
        let gainUpdates = plan.events.filter {
            $0.categories.contains("gain_pan_update") &&
                $0.categories.contains("tone_portamento_volume_slide_5xy")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("tone_portamento_volume_slide_5xy"))
        XCTAssertEqual(stepUpdates.map(\.effectType), [0x05, 0x05, 0x05])
        XCTAssertEqual(stepUpdates.map(\.effectParam), [0x02, 0x02, 0x02])
        XCTAssertEqual(stepUpdates.map(\.scheduledFrame), [9, 10, 11])
        XCTAssertEqual(gainUpdates.map(\.effectType), [0x05, 0x05, 0x05])
        XCTAssertEqual(gainUpdates.map(\.effectParam), [0x02, 0x02, 0x02])
        XCTAssertEqual(gainUpdates.map(\.scheduledFrame), [9, 10, 11])
    }

    func testRuntimeCMixerAdapterEventPlanReportsVolumeColumnTonePortamentoMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, volumeColumn: 0xF4),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let stepUpdates = plan.events.filter {
            $0.categories.contains("step_update") &&
                $0.categories.contains("volume_column_tone_portamento")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("volume_column_tone_portamento"))
        XCTAssertTrue(stepUpdates.allSatisfy { $0.categories.contains("portamento_update") })
        XCTAssertTrue(stepUpdates.allSatisfy { $0.effectType == nil })
        XCTAssertTrue(stepUpdates.allSatisfy { $0.effectParam == nil })
        XCTAssertEqual(stepUpdates.map(\.volumeColumn), [0xF4, 0xF4, 0xF4])
        XCTAssertEqual(stepUpdates.map(\.scheduledFrame), [9, 10, 11])
    }

    func testRuntimeCMixerAdapterEventPlanReports500VolumeSlideMemoryMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                makePlaybackRow(index: 1, effectType: 0x05, effectParam: 0x02),
                makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let memoryUpdates = plan.events.filter {
            $0.categories.contains("gain_pan_update") &&
                $0.categories.contains("tone_portamento_volume_slide_5xy_500_memory_reused")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("effect_memory_reused"))
        XCTAssertTrue(plan.categories.contains("tone_portamento_volume_slide_5xy_memory_reused"))
        XCTAssertTrue(plan.categories.contains("tone_portamento_volume_slide_5xy_500_memory_reused"))
        XCTAssertEqual(memoryUpdates.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(memoryUpdates.map(\.effectType), [0x05, 0x05])
        XCTAssertEqual(memoryUpdates.map(\.effectParam), [0x00, 0x00])
    }

    func testRuntimeCMixerAdapterEventPlanReportsRxyMultiRetriggerMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x1B, effectParam: 0xA2),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let rxyTriggers = plan.events.filter {
            $0.categories.contains("note_trigger") &&
                $0.categories.contains("rxy_multi_retrigger")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("rxy_multi_retrigger"))
        XCTAssertEqual(rxyTriggers.map(\.syntheticTick), [0, 2, 4])
        XCTAssertTrue(rxyTriggers.allSatisfy { $0.categories.contains("retrigger") })
        XCTAssertTrue(rxyTriggers.allSatisfy { $0.effectType == 0x1B })
        XCTAssertTrue(rxyTriggers.allSatisfy { $0.effectParam == 0xA2 })
    }

    func testRuntimeCMixerAdapterEventPlanIncludesVibrato4xyStepUpdates() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let vibratoUpdates = plan.events.filter { $0.categories.contains("vibrato_update") }

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(vibratoUpdates.count, 4)
        XCTAssertTrue(plan.categories.contains("vibrato_update"))
        XCTAssertTrue(plan.categories.contains("step_update"))
        XCTAssertEqual(vibratoUpdates.map(\.effectType), [0x04, 0x04, 0x04, 0x04])
        XCTAssertEqual(vibratoUpdates.map(\.effectParam), [0x48, 0x48, 0x48, 0x48])
    }

    func testRuntimeCMixerAdapterEventPlanReportsVibrato4xyMemoryMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let memoryUpdates = plan.events.filter {
            $0.categories.contains("step_update") &&
                $0.categories.contains("4xy_vibrato_memory_applied")
        }

        XCTAssertEqual(memoryUpdates.count, 4)
        XCTAssertTrue(plan.categories.contains("effect_memory_reused"))
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.categories.contains("effect_memory_reused") })
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.effectType == 0x04 })
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.effectParam == 0x00 })
    }

    func testRuntimeCMixerAdapterEventPlanReportsVibratoVolumeSlide6xyMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, note: 52, instrument: 1, effectType: 0x06, effectParam: 0x02),
                makePlaybackRow(index: 2, effectType: 0x06, effectParam: 0x01),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first {
            $0.categories.contains("note_trigger") && $0.categories.contains("vibrato_volume_slide_6xy")
        })
        let gainUpdate = try XCTUnwrap(plan.events.first {
            $0.categories.contains("gain_pan_update") && $0.categories.contains("vibrato_volume_slide_6xy")
        })
        let stepUpdates = plan.events.filter {
            $0.categories.contains("step_update") && $0.categories.contains("vibrato_volume_slide_6xy")
        }

        XCTAssertTrue(plan.generated)
        XCTAssertTrue(plan.categories.contains("vibrato_volume_slide_6xy"))
        XCTAssertEqual(noteTrigger.effectType, 0x06)
        XCTAssertEqual(noteTrigger.effectParam, 0x02)
        XCTAssertEqual(gainUpdate.effectType, 0x06)
        XCTAssertEqual(gainUpdate.effectParam, 0x01)
        XCTAssertEqual(gainUpdate.scheduledFrame, 8)
        XCTAssertEqual(stepUpdates.count, 8)
        XCTAssertTrue(stepUpdates.allSatisfy { $0.effectType == 0x06 })
        XCTAssertTrue(stepUpdates.allSatisfy { $0.categories.contains("effect_memory_reused") })
        XCTAssertTrue(stepUpdates.allSatisfy { $0.categories.contains("6xy_vibrato_memory_applied") })
    }

    func testRuntimeCMixerTraceConfigurationParsesDebugPath() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-c-runtime-trace-\(UUID().uuidString).jsonl")

        XCTAssertEqual(
            RuntimeCMixerTraceConfiguration.traceURL(environment: [
                RuntimeCMixerTraceConfiguration.pathEnvironmentKey: url.path
            ])?.path,
            url.path
        )
        XCTAssertNil(RuntimeCMixerTraceConfiguration.traceURL(environment: [:]))
    }

    func testRuntimeCMixerTraceConfigurationCanBeDisabledByEnvironment() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("disabled-c-runtime-trace-\(UUID().uuidString).jsonl")

        XCTAssertNil(RuntimeCMixerTraceConfiguration.traceURL(environment: [
            RuntimeCMixerTraceConfiguration.pathEnvironmentKey: url.path,
            RuntimeCMixerDiagnosticEnvironment.disableTraceEnvironmentKey: "1"
        ]))
        XCTAssertNil(RuntimeCMixerTraceConfiguration.traceURL(environment: [
            RuntimeCMixerTraceConfiguration.pathEnvironmentKey: url.path,
            RuntimeCMixerDiagnosticEnvironment.minimalCallbackEnvironmentKey: "1"
        ]))
    }

    @MainActor
    func testRuntimeMixerMetricsTraceConfigurationDisabledByDefaultAndParsesEnabledValues() {
        XCTAssertFalse(RuntimeMixerMetricsTraceConfiguration.makeWriter(environment: [:]).isEnabled)
        XCTAssertFalse(RuntimeMixerMetricsTraceConfiguration.makeWriter(environment: [
            RuntimeMixerMetricsTraceConfiguration.enabledEnvironmentKey: "0"
        ]).isEnabled)

        for value in ["1", "true", "yes", "on"] {
            XCTAssertTrue(RuntimeMixerMetricsTraceConfiguration.makeWriter(environment: [
                RuntimeMixerMetricsTraceConfiguration.enabledEnvironmentKey: value
            ]).isEnabled)
        }
    }

    func testRuntimeMixerMetricsTraceFormatterRedactsPathLikeValues() {
        let record = RuntimeMixerMetricsTraceRecord(
            phase: "stop_summary",
            fields: [
                RuntimeMixerMetricsTraceField("local\\path", "C:\\local\\private.xm"),
                RuntimeMixerMetricsTraceField("module_title", "private-local-title"),
                RuntimeMixerMetricsTraceField("output_peak", Float(0.5)),
            ]
        )

        let line = RuntimeMixerMetricsTraceFormatter.line(for: record)

        XCTAssertTrue(line.hasPrefix("vtx_runtime_mixer_metrics schema=1 phase=stop_summary"))
        XCTAssertTrue(line.contains("local_path=redacted"))
        XCTAssertTrue(line.contains("module_title=redacted"))
        XCTAssertTrue(line.contains("output_peak=0.500000"))
        XCTAssertFalse(line.contains("C:\\"))
        XCTAssertFalse(line.contains("private-local-title"))
    }

    func testRuntimeMixerMetricsContinuityClassificationTreatsAdjacentJumpsAsWatch() {
        XCTAssertEqual(
            RuntimeMixerMetricsClassification.continuityStatus(
                outputDiscontinuityCount: 0,
                adjacentJumpCountGT025: 3,
                maxOutputAdjacentSampleJump: 0.42
            ),
            "watch"
        )
    }

    func testRuntimeMixerMetricsContinuityClassificationTreatsDiscontinuitiesAsConcern() {
        XCTAssertEqual(
            RuntimeMixerMetricsClassification.continuityStatus(
                outputDiscontinuityCount: 1,
                adjacentJumpCountGT025: 3,
                maxOutputAdjacentSampleJump: 0.9
            ),
            "possible_discontinuity"
        )
    }

    func testRuntimeMixerMetricsLevelClassificationIsSeparateFromContinuity() {
        XCTAssertEqual(
            RuntimeMixerMetricsClassification.continuityStatus(
                outputDiscontinuityCount: 0,
                adjacentJumpCountGT025: 0,
                maxOutputAdjacentSampleJump: 0.1
            ),
            "clean"
        )
        XCTAssertEqual(
            RuntimeMixerMetricsClassification.outputLevelStatus(
                overrangeSampleCount: 2,
                clippingSampleCount: 0,
                clippingDetected: false
            ),
            "level_concern"
        )
        XCTAssertEqual(
            RuntimeMixerMetricsClassification.outputLevelStatus(
                overrangeSampleCount: 0,
                clippingSampleCount: 0,
                clippingDetected: false
            ),
            "clean"
        )
    }

    @MainActor
    func testRuntimeMixerMetricsTraceDisabledWriterEmitsNoStopSummary() {
        let writer = TestRuntimeMixerMetricsTraceWriter(isEnabled: false)
        let engine = RuntimeCMixerAudioEngine(
            sampleRate: 100,
            startsOutputHostOnDemand: false,
            runtimeMixerMetricsTraceWriter: writer
        )
        let sample = makePlaybackSample(pcm: [1, -1, 1, -1], baseSampleRate: 100)

        engine.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0))
        _ = engine.renderForTesting(frameCount: 4)
        engine.stopAll(context: nil, reason: "transport_stop")

        XCTAssertTrue(writer.records.isEmpty)
        XCTAssertEqual(writer.flushCount, 0)
    }

    @MainActor
    func testRuntimeMixerMetricsTraceRecordsSanitizedStopSummaryFromInjectedWriter() throws {
        let writer = TestRuntimeMixerMetricsTraceWriter()
        let outputPolicy = RuntimeCMixerOutputPolicy(
            outputGain: 0.5,
            headroomPolicy: "test_runtime_headroom",
            gainPolicySource: "test",
            fixedHeadroomDB: -6
        )
        let engine = RuntimeCMixerAudioEngine(
            sampleRate: 100,
            outputPolicy: outputPolicy,
            startsOutputHostOnDemand: false,
            runtimeMixerMetricsTraceWriter: writer
        )
        let sample = makePlaybackSample(pcm: [1, -1, 1, -1], baseSampleRate: 100)

        engine.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0))
        _ = engine.renderForTesting(frameCount: 4)
        engine.stopAll(context: nil, reason: "transport_stop")

        let record = try XCTUnwrap(writer.records.last)
        let fields = Dictionary(uniqueKeysWithValues: record.fields.map { ($0.key, $0.value) })
        let line = try XCTUnwrap(writer.lines.last)

        XCTAssertEqual(record.phase, "stop_summary")
        XCTAssertEqual(fields["runtime_audio_backend"], "c_mixer")
        XCTAssertEqual(fields["runtime_output_host_type"], "coreaudio_default_output_unit")
        XCTAssertEqual(fields["stop_reason"], "transport_stop")
        XCTAssertEqual(fields["sample_rate"], "100.000000")
        XCTAssertEqual(fields["channel_count"], "2")
        XCTAssertEqual(fields["rendered_frame_count"], "4")
        XCTAssertEqual(fields["render_callback_count"], "1")
        XCTAssertNotNil(fields["output_peak"])
        XCTAssertNotNil(fields["output_rms"])
        XCTAssertEqual(fields["overrange_sample_count"], "0")
        XCTAssertEqual(fields["clipping_sample_count"], "0")
        XCTAssertEqual(fields["clipping_detected"], "false")
        XCTAssertNotNil(fields["output_discontinuity_count"])
        XCTAssertNotNil(fields["adjacent_jump_count_gt_0_25"])
        XCTAssertNotNil(fields["adjacent_jump_count_gt_0_35"])
        XCTAssertNotNil(fields["adjacent_jump_count_gt_0_50"])
        XCTAssertNotNil(fields["max_output_adjacent_sample_jump"])
        XCTAssertNotNil(fields["continuity_status"])
        XCTAssertEqual(fields["output_level_status"], "clean")
        XCTAssertEqual(fields["runtime_output_gain"], "0.500000")
        XCTAssertEqual(fields["runtime_headroom_policy"], "test_runtime_headroom")
        XCTAssertEqual(fields["runtime_fixed_headroom_db"], "-6.000000")
        XCTAssertEqual(fields["runtime_auto_headroom_enabled"], "false")
        XCTAssertEqual(writer.flushCount, 1)
        XCTAssertTrue(line.hasPrefix("vtx_runtime_mixer_metrics schema=1 phase=stop_summary"))
        XCTAssertFalse(line.contains("/"))
        XCTAssertFalse(line.contains("module_title"))
    }

    func testRuntimeCMixerCaptureConfigurationIsDisabledByDefault() {
        XCTAssertNil(RuntimeCMixerCaptureConfiguration.resolve(environment: [:]))
    }

    func testRuntimeCMixerCaptureConfigurationCanBeDisabledByEnvironment() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("disabled-capture-\(UUID().uuidString).wav")

        XCTAssertNil(RuntimeCMixerCaptureConfiguration.resolve(environment: [
            RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: url.path,
            RuntimeCMixerDiagnosticEnvironment.disableCaptureEnvironmentKey: "1"
        ]))
    }

    func testRuntimeCMixerMinimalCallbackModeDisablesNewOutputBufferVerification() {
        let configuration = RuntimeCMixerCallbackDiagnosticsConfiguration.resolve(environment: [
            RuntimeCMixerDiagnosticEnvironment.minimalCallbackEnvironmentKey: "1"
        ])

        XCTAssertTrue(configuration.minimalCallbackMode)
        XCTAssertFalse(configuration.outputBufferVerificationEnabled)
    }

    func testRuntimeCMixerCaptureConfigurationParsesPathAndSecondsCap() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-c-runtime-capture-\(UUID().uuidString).wav")

        let configured = RuntimeCMixerCaptureConfiguration.resolve(environment: [
            RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: url.path,
            RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "0.25"
        ])
        let capped = RuntimeCMixerCaptureConfiguration.resolve(environment: [
            RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: url.path,
            RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "999"
        ])

        XCTAssertEqual(configured?.url.path, url.path)
        XCTAssertEqual(configured?.pathName, url.lastPathComponent)
        XCTAssertEqual(configured?.seconds, 0.25)
        XCTAssertEqual(configured?.secondsPolicy, "env_runtime_capture_seconds")
        XCTAssertNil(configured?.configurationWarning)
        XCTAssertEqual(configured?.frameLimit(sampleRate: 100), 25)
        XCTAssertEqual(capped?.seconds, RuntimeCMixerCaptureConfiguration.maximumCaptureSeconds)
        XCTAssertEqual(capped?.configurationWarning, "runtime_capture_seconds_capped")
    }

    func testRuntimeCMixerDeviceIdentityHashIsDeterministicAndRedacted() {
        let first = RuntimeCMixerDeviceIdentityRedactor.hashedStableID("local-device-uid")
        let second = RuntimeCMixerDeviceIdentityRedactor.hashedStableID("local-device-uid")
        let different = RuntimeCMixerDeviceIdentityRedactor.hashedStableID("other-local-device-uid")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, "local-device-uid")
        XCTAssertEqual(first?.count, 16)
        XCTAssertNotEqual(first, different)
        XCTAssertNil(RuntimeCMixerDeviceIdentityRedactor.hashedStableID("  "))
    }

    func testRuntimeCMixerRouteLabelSanitizesSafeManualLabels() {
        XCTAssertEqual(
            RuntimeCMixerDeviceIdentityRedactor.safeRouteLabel(" Built In / Wired Output "),
            "built-in-wired-output"
        )
        XCTAssertEqual(
            RuntimeCMixerDeviceIdentityRedactor.safeRouteLabel(environment: [
                RuntimeCMixerDiagnosticEnvironment.routeLabelEnvironmentKey: "Bluetooth Route"
            ]),
            "bluetooth-route"
        )
        XCTAssertNil(RuntimeCMixerDeviceIdentityRedactor.safeRouteLabel(" / "))
    }

    @MainActor
    func testRuntimeCMixerTraceWriterEmitsValidJSONL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-c-runtime-trace-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let writer = try RuntimeCMixerTraceJSONLWriter(url: url)
        let event = RuntimeCMixerTraceEvent(
            runtimeAction: "c_mixer_add_voice",
            runtimeAudioBackend: "c_mixer",
            backendFlagValue: "c_mixer",
            runtimeEventSource: "offline_adapter_plan",
            adapterPlanGenerated: true,
            adapterPlanGenerationMS: 12.5,
            plannedEventCount: 8,
            consumedPlannedEventCount: 3,
            skippedUnmatchedPlannedEventCount: 1,
            runtimeRowOrderMapping: "order:1 pattern:3 row:16 tick:2",
            adapterEventCategory: "note_trigger",
            adapterEventCategoriesConsumed: ["gain_pan_update", "note_trigger"],
            runtimeEventCategory: "note_trigger",
            plannedEventID: 7,
            plannedSourceOrderIndex: 1,
            plannedSourcePatternIndex: 3,
            plannedSourceRowIndex: 16,
            plannedSourceTickInRow: 2,
            plannedSourceChannelIndex: 0,
            plannedEventFrame: 1024,
            plannedRuntimeFrame: 256,
            plannedRuntimeFrameOffset: -768,
            runtimeApplicationFrame: 260,
            eventFrameDelta: 4,
            eventApplicationTiming: "callback_start",
            eventAppliedFrame: 260,
            inCallbackOffset: 4,
            plannedVsAppliedDelta: 4,
            sameFrameBurstSize: 3,
            sameFrameBurstID: 260,
            sameFrameBurstEventOrdinal: 2,
            sameFrameBurstCategories: ["gain_pan_update", "note_trigger", "replacement_stop_ramp"],
            sameFrameBurstAffectedChannels: [0, 3],
            sameFrameBurstNoteTriggerCount: 2,
            sameFrameBurstReplacementRampCount: 1,
            sameFrameBurstGainPanUpdateCount: 1,
            sameFrameBurstStepUpdateCount: 0,
            sameFrameBurstNoteCutCount: 0,
            sameFrameBurstKeyOffCount: 0,
            sameFrameBurstGlobalVolumeUpdateCount: 1,
            sameFrameBurstActiveVoiceCountBefore: 2,
            sameFrameBurstActiveVoiceCountAfter: 3,
            sameFrameBurstLoadedVoiceCountBefore: 2,
            sameFrameBurstLoadedVoiceCountAfter: 3,
            sameFrameBurstVoicesEnteringRampDown: 1,
            sameFrameBurstVoicesCompletingRampDown: 0,
            sameFrameBurstNewVoicesStarted: 2,
            sameFrameBurstSustainedVoicesCarried: 1,
            sameFrameBurstAtOrderStart: true,
            sameFrameBurstAtRowTransition: true,
            adapterActiveEventIndex: 42,
            adapterCurrentEventIndexBefore: 42,
            adapterCurrentEventIndexAfter: 42,
            adapterChannelAssociationRetained: true,
            adapterSustainedVoiceUpdate: true,
            maxPlannedVsAppliedDelta: 4,
            appliedPlannedEventCount: 3,
            exactFrameAppliedEventCount: 2,
            callbackBoundaryAppliedEventCount: 1,
            latePlannedEventCount: 0,
            fallbackToSimpleRuntimeEventCount: 0,
            runtimeEventFallbackReason: nil,
            runtimeOutputHostType: "coreaudio_default_output_unit",
            runtimeOutputHostRunning: true,
            runtimeOutputHostStartCount: 2,
            runtimeOutputHostPrepareStatus: 0,
            runtimeOutputHostInitializeStatus: 0,
            runtimeOutputHostStartStatus: 0,
            runtimeOutputHostStopStatus: nil,
            runtimeOutputHostLastErrorStatus: nil,
            sampleRate: 44_100,
            channelCount: 2,
            context: AudioRuntimeTraceContext(
                orderIndex: 1,
                patternIndex: 3,
                rowIndex: 16,
                tickInRow: 2,
                channelIndex: 0,
                noteValue: 49,
                instrumentIndex: 2,
                effectType: 0x09,
                effectParam: 0x02,
                volumeColumn: 0x30,
                speed: 6,
                bpm: 125,
                tickIndex: 12
            ),
            targetScope: "channel",
            activeVoiceCount: 1,
            loadedVoiceCount: 1,
            activeVoiceCountBefore: 2,
            activeVoiceCountAfter: 1,
            loadedVoiceCountBefore: 2,
            loadedVoiceCountAfter: 1,
            stoppedVoiceCount: 1,
            rampedVoiceCount: 2,
            replacementRampFrames: CSoftwareMixer.replacementStopRampFrameCount,
            replacementVoicesOverlap: true,
            currentFrame: 256,
            runtimeRenderedFrameCount: 512,
            scheduledVoiceCount: 0,
            eventQueueBacklogCount: 0,
            callbackIndex: 3,
            callbackRequestedFrameCount: 256,
            callbackStartFrame: 256,
            callbackEndFrame: 512,
            renderCallbackCount: 3,
            renderCallCount: 2,
            successfulRenderCount: 2,
            failedRenderCount: 1,
            requestedFrameCount: 256,
            cumulativeRequestedFrameCount: 768,
            renderedFrameCount: 512,
            renderFrameCount: 256,
            minRequestedFrameCount: 128,
            maxRequestedFrameCount: 512,
            lastRequestedFrameCount: 256,
            lastRenderedFrameCount: 256,
            lastRenderSucceeded: true,
            zeroFillCount: 1,
            underrunCount: 1,
            silentOutputCallbackCount: 0,
            unexpectedSilentOutputCount: 0,
            outputPeak: 0.75,
            outputRMS: 0.25,
            lastOutputPeak: 0.5,
            lastOutputRMS: 0.125,
            overrangeSampleCount: 0,
            clippingSampleCount: 0,
            clippingDetected: false,
            runtimeOutputGain: 1,
            runtimeHeadroomPolicy: "unity_runtime_gain_no_auto_headroom",
            runtimeGainPolicyLabel: "unity_runtime_gain_no_auto_headroom",
            runtimeDefaultHeadroomDB: -12,
            runtimeGainPolicySource: "default",
            runtimeGainPolicyIsEnvironmentOverride: false,
            runtimeAutoHeadroomEnabled: false,
            runtimeFixedHeadroomDB: nil,
            runtimeClippingRecommendation: nil,
            runtimeCaptureEnabled: true,
            runtimeCapturePathName: "runtime-capture.wav",
            runtimeCaptureSampleRate: 44_100,
            runtimeCaptureChannelCount: 2,
            runtimeCaptureSeconds: 240,
            runtimeCaptureFrameLimit: 10_584_000,
            runtimeCapturedFrameCount: 512,
            runtimeCaptureDurationSeconds: 0.011_609_977,
            runtimeCaptureTruncated: false,
            runtimeCaptureOutputPeak: 0.5,
            runtimeCaptureOutputRMS: 0.125,
            runtimeCaptureOverrangeSampleCount: 0,
            runtimeCaptureClippingSampleCount: 0,
            runtimeCaptureWriteSucceeded: true,
            runtimeCaptureWriteError: nil,
            runtimeCaptureConfigurationWarning: nil,
            noteTriggerEventCount: 4,
            cMixerAddVoiceCount: 2,
            gainPanUpdateCount: 3,
            stepUpdateCount: 3,
            stopChannelCount: 1,
            replacementRampCount: 2,
            clearAllCount: 1,
            previousOrderIndex: 1,
            previousPatternIndex: 3,
            previousRowIndex: 15,
            nextOrderIndex: 1,
            nextPatternIndex: 3,
            nextRowIndex: 16,
            transitionPhase: "after_events",
            transitionRuntimeFrame: 260,
            transitionReplacementRampCount: 1,
            transitionUpdateCount: 2,
            cMixerCallSucceeded: true,
            reason: "test"
        )

        writer.record(event)
        writer.flush()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.last, 0x0A)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["runtimeAction"] as? String, "c_mixer_add_voice")
        XCTAssertEqual(object["runtimeAudioBackend"] as? String, "c_mixer")
        XCTAssertEqual(object["backendFlagValue"] as? String, "c_mixer")
        XCTAssertEqual(object["runtimeOutputHostType"] as? String, "coreaudio_default_output_unit")
        XCTAssertEqual(object["runtimeOutputHostRunning"] as? Bool, true)
        XCTAssertEqual(object["runtimeOutputHostStartCount"] as? Int, 2)
        XCTAssertEqual(object["runtimeOutputHostPrepareStatus"] as? Int, 0)
        XCTAssertEqual(object["runtimeOutputHostInitializeStatus"] as? Int, 0)
        XCTAssertEqual(object["runtimeOutputHostStartStatus"] as? Int, 0)
        XCTAssertEqual(object["runtimeEventSource"] as? String, "offline_adapter_plan")
        XCTAssertEqual(object["adapterPlanGenerated"] as? Bool, true)
        XCTAssertEqual(object["adapterPlanGenerationMS"] as? Double, 12.5)
        XCTAssertEqual(object["plannedEventCount"] as? Int, 8)
        XCTAssertEqual(object["consumedPlannedEventCount"] as? Int, 3)
        XCTAssertEqual(object["skippedUnmatchedPlannedEventCount"] as? Int, 1)
        XCTAssertEqual(object["runtimeRowOrderMapping"] as? String, "order:1 pattern:3 row:16 tick:2")
        XCTAssertEqual(object["adapterEventCategory"] as? String, "note_trigger")
        XCTAssertEqual(object["adapterEventCategoriesConsumed"] as? [String], ["gain_pan_update", "note_trigger"])
        XCTAssertEqual(object["runtimeEventCategory"] as? String, "note_trigger")
        XCTAssertEqual(object["plannedEventID"] as? Int, 7)
        XCTAssertEqual(object["plannedSourceOrderIndex"] as? Int, 1)
        XCTAssertEqual(object["plannedSourcePatternIndex"] as? Int, 3)
        XCTAssertEqual(object["plannedSourceRowIndex"] as? Int, 16)
        XCTAssertEqual(object["plannedSourceTickInRow"] as? Int, 2)
        XCTAssertEqual(object["plannedSourceChannelIndex"] as? Int, 0)
        XCTAssertEqual(object["plannedEventFrame"] as? Int, 1024)
        XCTAssertEqual(object["plannedRuntimeFrame"] as? Int, 256)
        XCTAssertEqual(object["plannedRuntimeFrameOffset"] as? Int, -768)
        XCTAssertEqual(object["runtimeApplicationFrame"] as? Int, 260)
        XCTAssertEqual(object["eventFrameDelta"] as? Int, 4)
        XCTAssertEqual(object["eventApplicationTiming"] as? String, "callback_start")
        XCTAssertEqual(object["eventAppliedFrame"] as? Int, 260)
        XCTAssertEqual(object["inCallbackOffset"] as? Int, 4)
        XCTAssertEqual(object["plannedVsAppliedDelta"] as? Int, 4)
        XCTAssertEqual(object["sameFrameBurstSize"] as? Int, 3)
        XCTAssertEqual(object["sameFrameBurstID"] as? Int, 260)
        XCTAssertEqual(object["sameFrameBurstEventOrdinal"] as? Int, 2)
        XCTAssertEqual(object["sameFrameBurstCategories"] as? [String], ["gain_pan_update", "note_trigger", "replacement_stop_ramp"])
        XCTAssertEqual(object["sameFrameBurstAffectedChannels"] as? [Int], [0, 3])
        XCTAssertEqual(object["sameFrameBurstNoteTriggerCount"] as? Int, 2)
        XCTAssertEqual(object["sameFrameBurstReplacementRampCount"] as? Int, 1)
        XCTAssertEqual(object["sameFrameBurstGainPanUpdateCount"] as? Int, 1)
        XCTAssertEqual(object["sameFrameBurstStepUpdateCount"] as? Int, 0)
        XCTAssertEqual(object["sameFrameBurstNoteCutCount"] as? Int, 0)
        XCTAssertEqual(object["sameFrameBurstKeyOffCount"] as? Int, 0)
        XCTAssertEqual(object["sameFrameBurstGlobalVolumeUpdateCount"] as? Int, 1)
        XCTAssertEqual(object["sameFrameBurstActiveVoiceCountBefore"] as? Int, 2)
        XCTAssertEqual(object["sameFrameBurstActiveVoiceCountAfter"] as? Int, 3)
        XCTAssertEqual(object["sameFrameBurstLoadedVoiceCountBefore"] as? Int, 2)
        XCTAssertEqual(object["sameFrameBurstLoadedVoiceCountAfter"] as? Int, 3)
        XCTAssertEqual(object["sameFrameBurstVoicesEnteringRampDown"] as? Int, 1)
        XCTAssertEqual(object["sameFrameBurstVoicesCompletingRampDown"] as? Int, 0)
        XCTAssertEqual(object["sameFrameBurstNewVoicesStarted"] as? Int, 2)
        XCTAssertEqual(object["sameFrameBurstSustainedVoicesCarried"] as? Int, 1)
        XCTAssertEqual(object["sameFrameBurstAtOrderStart"] as? Bool, true)
        XCTAssertEqual(object["sameFrameBurstAtRowTransition"] as? Bool, true)
        XCTAssertEqual(object["adapterActiveEventIndex"] as? Int, 42)
        XCTAssertEqual(object["adapterCurrentEventIndexBefore"] as? Int, 42)
        XCTAssertEqual(object["adapterCurrentEventIndexAfter"] as? Int, 42)
        XCTAssertEqual(object["adapterChannelAssociationRetained"] as? Bool, true)
        XCTAssertEqual(object["adapterSustainedVoiceUpdate"] as? Bool, true)
        XCTAssertEqual(object["maxPlannedVsAppliedDelta"] as? Int, 4)
        XCTAssertEqual(object["appliedPlannedEventCount"] as? Int, 3)
        XCTAssertEqual(object["exactFrameAppliedEventCount"] as? Int, 2)
        XCTAssertEqual(object["callbackBoundaryAppliedEventCount"] as? Int, 1)
        XCTAssertEqual(object["latePlannedEventCount"] as? Int, 0)
        XCTAssertEqual(object["fallbackToSimpleRuntimeEventCount"] as? Int, 0)
        XCTAssertEqual(object["sampleRate"] as? Double, 44_100)
        XCTAssertEqual(object["channelCount"] as? Int, 2)
        XCTAssertEqual(object["orderIndex"] as? Int, 1)
        XCTAssertEqual(object["rowIndex"] as? Int, 16)
        XCTAssertEqual(object["tickInRow"] as? Int, 2)
        XCTAssertEqual(object["channelIndex"] as? Int, 0)
        XCTAssertEqual(object["noteValue"] as? Int, 49)
        XCTAssertEqual(object["instrumentIndex"] as? Int, 2)
        XCTAssertEqual(object["effect"] as? String, "0902")
        XCTAssertEqual(object["volumeColumn"] as? String, "30")
        XCTAssertEqual(object["targetScope"] as? String, "channel")
        XCTAssertEqual(object["targetedAllVoices"] as? Bool, false)
        XCTAssertEqual(object["activeVoiceCount"] as? Int, 1)
        XCTAssertEqual(object["loadedVoiceCount"] as? Int, 1)
        XCTAssertEqual(object["activeVoiceCountBefore"] as? Int, 2)
        XCTAssertEqual(object["activeVoiceCountAfter"] as? Int, 1)
        XCTAssertEqual(object["loadedVoiceCountBefore"] as? Int, 2)
        XCTAssertEqual(object["loadedVoiceCountAfter"] as? Int, 1)
        XCTAssertEqual(object["stoppedVoiceCount"] as? Int, 1)
        XCTAssertEqual(object["rampedVoiceCount"] as? Int, 2)
        XCTAssertEqual(object["replacementRampFrames"] as? Int, CSoftwareMixer.replacementStopRampFrameCount)
        XCTAssertEqual(object["replacementVoicesOverlap"] as? Bool, true)
        XCTAssertEqual(object["currentFrame"] as? Int, 256)
        XCTAssertEqual(object["runtimeRenderedFrameCount"] as? Int, 512)
        XCTAssertEqual(object["scheduledVoiceCount"] as? Int, 0)
        XCTAssertEqual(object["eventQueueBacklogCount"] as? Int, 0)
        XCTAssertEqual(object["callbackIndex"] as? Int, 3)
        XCTAssertEqual(object["callbackRequestedFrameCount"] as? Int, 256)
        XCTAssertEqual(object["callbackStartFrame"] as? Int, 256)
        XCTAssertEqual(object["callbackEndFrame"] as? Int, 512)
        XCTAssertEqual(object["renderCallbackCount"] as? Int, 3)
        XCTAssertEqual(object["successfulRenderCount"] as? Int, 2)
        XCTAssertEqual(object["failedRenderCount"] as? Int, 1)
        XCTAssertEqual(object["requestedFrameCount"] as? Int, 256)
        XCTAssertEqual(object["cumulativeRequestedFrameCount"] as? Int, 768)
        XCTAssertEqual(object["renderedFrameCount"] as? Int, 512)
        XCTAssertEqual(object["minRequestedFrameCount"] as? Int, 128)
        XCTAssertEqual(object["maxRequestedFrameCount"] as? Int, 512)
        XCTAssertEqual(object["lastRequestedFrameCount"] as? Int, 256)
        XCTAssertEqual(object["lastRenderedFrameCount"] as? Int, 256)
        XCTAssertEqual(object["lastRenderSucceeded"] as? Bool, true)
        XCTAssertEqual(object["zeroFillCount"] as? Int, 1)
        XCTAssertEqual(object["underrunCount"] as? Int, 1)
        XCTAssertEqual(object["clippingDetected"] as? Bool, false)
        XCTAssertEqual(object["runtimeHeadroomPolicy"] as? String, "unity_runtime_gain_no_auto_headroom")
        XCTAssertEqual(object["runtimeGainPolicyLabel"] as? String, "unity_runtime_gain_no_auto_headroom")
        XCTAssertEqual(object["runtimeDefaultHeadroomDB"] as? Double, -12)
        XCTAssertEqual(object["runtimeGainPolicySource"] as? String, "default")
        XCTAssertEqual(object["runtimeGainPolicyIsEnvironmentOverride"] as? Bool, false)
        XCTAssertEqual(object["runtimeAutoHeadroomEnabled"] as? Bool, false)
        XCTAssertEqual(object["runtimeCaptureEnabled"] as? Bool, true)
        XCTAssertEqual(object["runtimeCapturePathName"] as? String, "runtime-capture.wav")
        XCTAssertEqual(object["runtimeCaptureSampleRate"] as? Double, 44_100)
        XCTAssertEqual(object["runtimeCaptureChannelCount"] as? Int, 2)
        XCTAssertEqual(object["runtimeCaptureSeconds"] as? Double, 240)
        XCTAssertEqual(object["runtimeCaptureFrameLimit"] as? Int, 10_584_000)
        XCTAssertEqual(object["runtimeCapturedFrameCount"] as? Int, 512)
        XCTAssertEqual(object["runtimeCaptureDurationSeconds"] as? Double, 0.011_609_977)
        XCTAssertEqual(object["runtimeCaptureTruncated"] as? Bool, false)
        XCTAssertEqual(object["runtimeCaptureOutputPeak"] as? Double, 0.5)
        XCTAssertEqual(object["runtimeCaptureOutputRMS"] as? Double, 0.125)
        XCTAssertEqual(object["runtimeCaptureOverrangeSampleCount"] as? Int, 0)
        XCTAssertEqual(object["runtimeCaptureClippingSampleCount"] as? Int, 0)
        XCTAssertEqual(object["runtimeCaptureWriteSucceeded"] as? Bool, true)
        XCTAssertEqual(object["noteTriggerEventCount"] as? Int, 4)
        XCTAssertEqual(object["cMixerAddVoiceCount"] as? Int, 2)
        XCTAssertEqual(object["gainPanUpdateCount"] as? Int, 3)
        XCTAssertEqual(object["stepUpdateCount"] as? Int, 3)
        XCTAssertEqual(object["stopChannelCount"] as? Int, 1)
        XCTAssertEqual(object["replacementRampCount"] as? Int, 2)
        XCTAssertEqual(object["clearAllCount"] as? Int, 1)
        XCTAssertEqual(object["previousOrderIndex"] as? Int, 1)
        XCTAssertEqual(object["previousPatternIndex"] as? Int, 3)
        XCTAssertEqual(object["previousRowIndex"] as? Int, 15)
        XCTAssertEqual(object["nextOrderIndex"] as? Int, 1)
        XCTAssertEqual(object["nextPatternIndex"] as? Int, 3)
        XCTAssertEqual(object["nextRowIndex"] as? Int, 16)
        XCTAssertEqual(object["transitionPhase"] as? String, "after_events")
        XCTAssertEqual(object["transitionRuntimeFrame"] as? Int, 260)
        XCTAssertEqual(object["transitionReplacementRampCount"] as? Int, 1)
        XCTAssertEqual(object["transitionUpdateCount"] as? Int, 2)
        XCTAssertEqual(object["cMixerCallSucceeded"] as? Bool, true)
    }

    func testRuntimeCMixerTraceDistinguishesAppliedAndDeferredUpdates() throws {
        let applied = RuntimeCMixerTraceEvent(
            runtimeAction: "c_mixer_update_gain_pan_step_applied",
            runtimeAudioBackend: "c_mixer",
            context: AudioRuntimeTraceContext(orderIndex: 1, patternIndex: 2, rowIndex: 3, tickInRow: 4, channelIndex: 5),
            targetScope: "channel",
            activeVoiceCountBefore: 1,
            activeVoiceCountAfter: 1,
            targetVoiceIndex: 7,
            gainBefore: 1,
            gainAfter: 0.5,
            panBefore: 0,
            panAfter: 1,
            sampleStepBefore: 1,
            sampleStepAfter: 2,
            updateDisposition: "update_applied",
            updateType: "combined",
            updateEpsilon: RuntimeCMixerRenderCore.updateEpsilon,
            gainRequested: 0.5,
            panRequested: 1,
            sampleStepRequested: 2,
            gainDelta: 0.5,
            panDelta: 1,
            sampleStepDelta: 1,
            gainUpdateStatus: "applied",
            panUpdateStatus: "applied",
            sampleStepUpdateStatus: "applied",
            updateSuppressedEpsilonGainCount: 1,
            updateSuppressedEpsilonPanCount: 2,
            updateSuppressedEpsilonStepCount: 3,
            updateSuppressedNoChangeCount: 4,
            updateAppliedAfterEpsilonFilterCount: 5,
            cMixerCallSucceeded: true,
            reason: "runtime_c_mixer_update_applied_combined"
        )
        let deferred = RuntimeCMixerTraceEvent(
            runtimeAction: "c_mixer_update_deferred_missing_data",
            runtimeAudioBackend: "c_mixer",
            context: AudioRuntimeTraceContext(orderIndex: 1, patternIndex: 2, rowIndex: 3, tickInRow: 4, channelIndex: 6),
            targetScope: "channel",
            updateDisposition: "update_deferred_missing_data",
            updateType: "step",
            cMixerCallSucceeded: nil,
            reason: "runtime_c_mixer_update_deferred_missing_data_missing_sample_step_target"
        )

        let appliedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: RuntimeCMixerTraceJSONLFormatter.line(for: applied)) as? [String: Any])
        let deferredObject = try XCTUnwrap(JSONSerialization.jsonObject(with: RuntimeCMixerTraceJSONLFormatter.line(for: deferred)) as? [String: Any])

        XCTAssertEqual(appliedObject["runtimeAction"] as? String, "c_mixer_update_gain_pan_step_applied")
        XCTAssertEqual(appliedObject["channelIndex"] as? Int, 5)
        XCTAssertEqual(appliedObject["targetVoiceIndex"] as? Int, 7)
        XCTAssertEqual(appliedObject["gainBefore"] as? Double, 1)
        XCTAssertEqual(appliedObject["gainAfter"] as? Double, 0.5)
        XCTAssertEqual(appliedObject["panBefore"] as? Double, 0)
        XCTAssertEqual(appliedObject["panAfter"] as? Double, 1)
        XCTAssertEqual(appliedObject["sampleStepBefore"] as? Double, 1)
        XCTAssertEqual(appliedObject["sampleStepAfter"] as? Double, 2)
        XCTAssertEqual(appliedObject["updateDisposition"] as? String, "update_applied")
        XCTAssertEqual(appliedObject["updateType"] as? String, "combined")
        XCTAssertEqual(appliedObject["updateEpsilon"] as? Double, RuntimeCMixerRenderCore.updateEpsilon)
        XCTAssertEqual(appliedObject["gainRequested"] as? Double, 0.5)
        XCTAssertEqual(appliedObject["panRequested"] as? Double, 1)
        XCTAssertEqual(appliedObject["sampleStepRequested"] as? Double, 2)
        XCTAssertEqual(appliedObject["gainDelta"] as? Double, 0.5)
        XCTAssertEqual(appliedObject["panDelta"] as? Double, 1)
        XCTAssertEqual(appliedObject["sampleStepDelta"] as? Double, 1)
        XCTAssertEqual(appliedObject["gainUpdateStatus"] as? String, "applied")
        XCTAssertEqual(appliedObject["panUpdateStatus"] as? String, "applied")
        XCTAssertEqual(appliedObject["sampleStepUpdateStatus"] as? String, "applied")
        XCTAssertEqual(appliedObject["updateSuppressedEpsilonGainCount"] as? Int, 1)
        XCTAssertEqual(appliedObject["updateSuppressedEpsilonPanCount"] as? Int, 2)
        XCTAssertEqual(appliedObject["updateSuppressedEpsilonStepCount"] as? Int, 3)
        XCTAssertEqual(appliedObject["updateSuppressedNoChangeCount"] as? Int, 4)
        XCTAssertEqual(appliedObject["updateAppliedAfterEpsilonFilterCount"] as? Int, 5)
        XCTAssertEqual(appliedObject["cMixerCallSucceeded"] as? Bool, true)
        XCTAssertEqual(deferredObject["runtimeAction"] as? String, "c_mixer_update_deferred_missing_data")
        XCTAssertEqual(deferredObject["channelIndex"] as? Int, 6)
        XCTAssertEqual(deferredObject["updateDisposition"] as? String, "update_deferred_missing_data")
        XCTAssertEqual(deferredObject["updateType"] as? String, "step")
        XCTAssertEqual(deferredObject["reason"] as? String, "runtime_c_mixer_update_deferred_missing_data_missing_sample_step_target")
        XCTAssertNil(deferredObject["targetVoiceIndex"])
    }

    func testRuntimeCMixerTraceSerializesCoreAudioRouteAndCallbackDiagnostics() throws {
        let event = RuntimeCMixerTraceEvent(
            runtimeAction: "runtime_output_host_diagnostics",
            runtimeAudioBackend: "c_mixer",
            runtimeOutputHostType: "coreaudio_default_output_unit",
            runtimeOutputHostRunning: true,
            runtimeOutputHostStartCount: 2,
            sampleRate: 48_000,
            cMixerRenderSampleRate: 48_000,
            cMixerRenderChannelCount: 2,
            audioHardwareNominalSampleRate: 48_000,
            audioHardwareDeviceID: 42,
            audioHardwareDeviceUIDHash: "abcdef0123456789",
            audioOutputRouteLabel: "bluetooth-route",
            audioHardwareIOBufferFrameSize: 256,
            audioHardwareIOBufferDuration: 0.005_333_333,
            audioHardwareLatencyFrames: 64,
            audioHardwareLatencyDuration: 0.001_333_333,
            audioHardwareSafetyOffsetFrames: 12,
            audioHardwareSafetyOffsetDuration: 0.000_25,
            audioHardwareTransportType: 1_651_275_109,
            audioHardwareTransportTypeName: "bluetooth",
            audioGraphFormatChangeCount: 0,
            audioOutputRouteChangeCount: 3,
            audioGraphFormatChanged: false,
            audioOutputRouteChanged: true,
            audioOutputDeviceChanged: true,
            audioOutputSampleRateChanged: true,
            audioOutputChannelCountChanged: false,
            audioHardwareIOBufferDurationChanged: true,
            callbackThreadIsMain: false,
            callbackThreadID: 1_234,
            callbackMainThreadDependencyDetected: false,
            callbackAllocationWarning: true,
            callbackRealtimeSafeDiagnostics: false,
            callbackDiagnosticDropCount: 7,
            callbackRingBufferCapacity: 32_768,
            callbackLockWaitCount: 0,
            callbackLockWaitDurationMS: 0,
            callbackLockFailureCount: 2,
            callbackLockAttemptCount: 10,
            callbackTryLockFailureCount: 2,
            callbackLockFailureAudioImpact: true,
            callbackRenderedFromStaleSnapshotCount: 2,
            callbackRenderedSilenceDueToUnavailableStateCount: 0,
            callbackSkippedDiagnosticsDueToLockCount: 2,
            callbackSkippedAudioDueToLockCount: 0,
            lifecycleChangeWhileRenderingCount: 0,
            audioUnitLifecycleCallWhileCallbackActiveCount: 0,
            eventQueueProducerThreadID: 100,
            eventQueueProducerThreadIsMain: true,
            eventQueueConsumerThreadID: 1_234,
            eventQueueConsumerThreadIsMain: false,
            reason: "coreaudio_output_host_diagnostics"
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: RuntimeCMixerTraceJSONLFormatter.line(for: event)) as? [String: Any])

        XCTAssertEqual(object["runtimeAction"] as? String, "runtime_output_host_diagnostics")
        XCTAssertEqual(object["runtimeOutputHostType"] as? String, "coreaudio_default_output_unit")
        XCTAssertEqual(object["audioHardwareDeviceID"] as? Int, 42)
        XCTAssertEqual(object["audioHardwareDeviceUIDHash"] as? String, "abcdef0123456789")
        XCTAssertEqual(object["audioOutputRouteLabel"] as? String, "bluetooth-route")
        XCTAssertEqual(object["audioHardwareTransportTypeName"] as? String, "bluetooth")
        XCTAssertEqual(object["runtimeOutputHostRunning"] as? Bool, true)
        XCTAssertEqual(object["runtimeOutputHostStartCount"] as? Int, 2)
        XCTAssertEqual(object["audioGraphFormatChangeCount"] as? Int, 0)
        XCTAssertEqual(object["audioOutputRouteChangeCount"] as? Int, 3)
        XCTAssertEqual(object["audioGraphFormatChanged"] as? Bool, false)
        XCTAssertEqual(object["audioOutputRouteChanged"] as? Bool, true)
        XCTAssertEqual(object["audioOutputDeviceChanged"] as? Bool, true)
        XCTAssertEqual(object["audioOutputSampleRateChanged"] as? Bool, true)
        XCTAssertEqual(object["audioOutputChannelCountChanged"] as? Bool, false)
        XCTAssertEqual(object["audioHardwareIOBufferDurationChanged"] as? Bool, true)
        XCTAssertEqual(object["callbackThreadIsMain"] as? Bool, false)
        XCTAssertEqual(object["callbackThreadID"] as? Int, 1_234)
        XCTAssertEqual(object["callbackAllocationWarning"] as? Bool, true)
        XCTAssertEqual(object["callbackRealtimeSafeDiagnostics"] as? Bool, false)
        XCTAssertEqual(object["callbackDiagnosticDropCount"] as? Int, 7)
        XCTAssertEqual(object["callbackRingBufferCapacity"] as? Int, 32_768)
        XCTAssertEqual(object["callbackLockAttemptCount"] as? Int, 10)
        XCTAssertEqual(object["callbackLockFailureCount"] as? Int, 2)
        XCTAssertEqual(object["callbackTryLockFailureCount"] as? Int, 2)
        XCTAssertEqual(object["callbackLockFailureAudioImpact"] as? Bool, true)
        XCTAssertEqual(object["callbackRenderedFromStaleSnapshotCount"] as? Int, 2)
        XCTAssertEqual(object["callbackSkippedDiagnosticsDueToLockCount"] as? Int, 2)
        XCTAssertEqual(object["callbackSkippedAudioDueToLockCount"] as? Int, 0)
        XCTAssertEqual(object["eventQueueProducerThreadIsMain"] as? Bool, true)
        XCTAssertEqual(object["eventQueueConsumerThreadIsMain"] as? Bool, false)
    }

    func testRuntimeCMixerRouteChangeTraceEventSerializesChangeReasons() throws {
        let event = RuntimeCMixerTraceEvent(
            runtimeAction: "audio_output_route_changed",
            runtimeAudioBackend: "c_mixer",
            runtimeEventCategory: "audio_graph_change",
            runtimeOutputHostType: "coreaudio_default_output_unit",
            runtimeOutputHostRunning: true,
            runtimeOutputHostStartCount: 2,
            sampleRate: 48_000,
            audioHardwareNominalSampleRate: 48_000,
            audioHardwareDeviceUIDHash: "abcdef0123456789",
            audioOutputRouteLabel: "usb-interface",
            audioHardwareIOBufferFrameSize: 128,
            audioHardwareIOBufferDuration: 0.002_666_667,
            audioHardwareTransportTypeName: "usb",
            audioGraphFormatChangeCount: 0,
            audioOutputRouteChangeCount: 1,
            audioGraphFormatChanged: false,
            audioOutputRouteChanged: true,
            audioOutputDeviceChanged: true,
            audioOutputSampleRateChanged: true,
            audioOutputChannelCountChanged: false,
            audioHardwareIOBufferDurationChanged: true,
            reason: "audio_output_route_changed"
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: RuntimeCMixerTraceJSONLFormatter.line(for: event)) as? [String: Any])

        XCTAssertEqual(object["runtimeAction"] as? String, "audio_output_route_changed")
        XCTAssertEqual(object["runtimeEventCategory"] as? String, "audio_graph_change")
        XCTAssertEqual(object["audioOutputRouteLabel"] as? String, "usb-interface")
        XCTAssertEqual(object["audioHardwareDeviceUIDHash"] as? String, "abcdef0123456789")
        XCTAssertEqual(object["audioHardwareTransportTypeName"] as? String, "usb")
        XCTAssertEqual(object["audioOutputRouteChanged"] as? Bool, true)
        XCTAssertEqual(object["audioOutputDeviceChanged"] as? Bool, true)
        XCTAssertEqual(object["audioOutputSampleRateChanged"] as? Bool, true)
        XCTAssertEqual(object["audioHardwareIOBufferDurationChanged"] as? Bool, true)
    }

    func testRuntimeAudioBackendSelectionDefaultsToCoreAudioCMixer() {
        let selection = RuntimeAudioBackendSelection.resolve(environment: [:])

        XCTAssertEqual(selection.backend, .cMixer)
        XCTAssertNil(selection.requestedValue)
        XCTAssertNil(selection.fallbackReason)
        XCTAssertTrue(selection.backend.usesRuntimeCMixer)
        XCTAssertEqual(selection.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
    }

    func testRuntimeAudioBackendSelectionTreatsAVAudioAsRetiredCoreAudioFallback() {
        let selection = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "av_audio"
        ])

        XCTAssertEqual(selection.backend, .cMixer)
        XCTAssertEqual(selection.requestedValue, "av_audio")
        XCTAssertEqual(selection.fallbackReason, RuntimeAudioBackendSelection.retiredAVAudioFallbackReason)
        XCTAssertTrue(selection.backend.usesRuntimeCMixer)
        XCTAssertEqual(selection.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertNotEqual(selection.backend.runtimeOutputHostType, "av_audio_player_node_varispeed")
    }

    func testRuntimeAudioBackendSelectionHasNoSelectableAVAudioPlayerNodeHost() {
        let selection = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "av_audio_player_node_varispeed"
        ])

        XCTAssertEqual(selection.backend, .cMixer)
        XCTAssertEqual(selection.requestedValue, "av_audio_player_node_varispeed")
        XCTAssertEqual(selection.fallbackReason, "unknown_backend")
        XCTAssertTrue(selection.backend.usesRuntimeCMixer)
        XCTAssertEqual(selection.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertNotEqual(selection.backend.runtimeOutputHostType, "av_audio_player_node_varispeed")
    }

    func testRuntimeAudioBackendSelectionMapsPrimaryCMixerFlagToCoreAudioHost() {
        let selection = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "c_mixer"
        ])

        XCTAssertEqual(selection.backend, .cMixer)
        XCTAssertEqual(selection.requestedValue, "c_mixer")
        XCTAssertNil(selection.fallbackReason)
        XCTAssertTrue(selection.backend.usesRuntimeCMixer)
        XCTAssertEqual(selection.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
    }

    func testRuntimeAudioBackendSelectionKeepsCoreAudioCMixerAlias() {
        let selection = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "c_mixer_coreaudio"
        ])

        XCTAssertEqual(selection.backend, .cMixerCoreAudio)
        XCTAssertEqual(selection.requestedValue, "c_mixer_coreaudio")
        XCTAssertNil(selection.fallbackReason)
        XCTAssertTrue(selection.backend.usesRuntimeCMixer)
        XCTAssertEqual(selection.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
    }

    func testRuntimeAudioBackendSelectionHasNoSelectableSourceNodeHost() {
        let primary = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "c_mixer"
        ])
        let alias = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "c_mixer_coreaudio"
        ])
        let unknown = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "av_audio_source_node"
        ])

        XCTAssertEqual(primary.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(alias.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertNotEqual(primary.backend.runtimeOutputHostType, "av_audio_source_node")
        XCTAssertNotEqual(alias.backend.runtimeOutputHostType, "av_audio_source_node")
        XCTAssertEqual(unknown.backend, .cMixer)
        XCTAssertEqual(unknown.fallbackReason, "unknown_backend")
        XCTAssertEqual(unknown.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
    }

    func testRuntimeAudioBackendSelectionFallsBackToCoreAudioDefaultForUnknownValue() {
        let selection = RuntimeAudioBackendSelection.resolve(environment: [
            RuntimeAudioBackendSelection.environmentKey: "raw_core_audio"
        ])

        XCTAssertEqual(selection.backend, .cMixer)
        XCTAssertEqual(selection.requestedValue, "raw_core_audio")
        XCTAssertEqual(selection.fallbackReason, "unknown_backend")
        XCTAssertTrue(selection.backend.usesRuntimeCMixer)
        XCTAssertEqual(selection.backend.runtimeOutputHostType, "coreaudio_default_output_unit")
    }

    func testRuntimeCMixerCoreAudioHostConfigurationInitializesSampleRateAndChannels() {
        let configuration = RuntimeCMixerCoreAudioHostConfiguration(
            sampleRate: 48_000,
            channelCount: 2
        )

        XCTAssertEqual(configuration.sampleRate, 48_000)
        XCTAssertEqual(configuration.channelCount, 2)
        XCTAssertEqual(configuration.streamDescription.mSampleRate, 48_000)
        XCTAssertEqual(configuration.streamDescription.mChannelsPerFrame, 2)
        XCTAssertEqual(configuration.streamDescription.mFramesPerPacket, 1)
        XCTAssertEqual(configuration.streamDescription.mBytesPerFrame, UInt32(MemoryLayout<Float>.size))
        XCTAssertNotEqual(configuration.streamDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved, 0)
    }

    func testRuntimeCMixerOutputHostLifecycleStartStopResetIsStable() {
        var lifecycle = RuntimeCMixerOutputHostLifecycle()

        XCTAssertEqual(lifecycle.state, .stopped)
        lifecycle.prepare(status: noErr, initializeStatus: noErr)
        XCTAssertEqual(lifecycle.state, .prepared)
        XCTAssertEqual(lifecycle.lastPrepareStatus, noErr)
        XCTAssertEqual(lifecycle.lastInitializeStatus, noErr)
        lifecycle.start(status: noErr)
        XCTAssertEqual(lifecycle.state, .running)
        XCTAssertEqual(lifecycle.lastStartStatus, noErr)
        lifecycle.stop(status: noErr)
        XCTAssertEqual(lifecycle.state, .prepared)
        XCTAssertEqual(lifecycle.lastStopStatus, noErr)
        lifecycle.start(status: noErr)
        XCTAssertEqual(lifecycle.state, .running)
        lifecycle.reset()
        XCTAssertEqual(lifecycle.state, .stopped)
    }

    func testRuntimeCMixerOutputHostLifecycleRecordsOSStatusFailureWithoutStarting() {
        var lifecycle = RuntimeCMixerOutputHostLifecycle()

        XCTAssertFalse(lifecycle.start(status: kAudio_ParamError))

        XCTAssertEqual(lifecycle.state, .stopped)
        XCTAssertEqual(lifecycle.lastStartStatus, kAudio_ParamError)
        XCTAssertEqual(lifecycle.lastErrorStatus, kAudio_ParamError)
    }

    func testRuntimeCMixerSampleRatePolicyUsesOutputGraphRateWhenAvailable() {
        let selection = RuntimeCMixerSampleRateSelection.resolve(
            environment: [:],
            candidates: RuntimeCMixerSampleRateCandidates(
                outputNodeSampleRate: 48_000,
                mainMixerSampleRate: 44_100,
                hardwareSampleRate: 48_000
            )
        )

        XCTAssertEqual(selection.sampleRate, 48_000)
        XCTAssertEqual(selection.policy, "graph_aligned")
        XCTAssertEqual(selection.source, "output_node")
        XCTAssertNil(selection.configurationWarning)
    }

    func testRuntimeCMixerSampleRatePolicyFallsBackWhenGraphRateIsUnavailable() {
        let selection = RuntimeCMixerSampleRateSelection.resolve(
            environment: [:],
            candidates: RuntimeCMixerSampleRateCandidates(
                outputNodeSampleRate: 0,
                mainMixerSampleRate: nil,
                hardwareSampleRate: Double.nan
            )
        )

        XCTAssertEqual(selection.sampleRate, MixerRenderConfig.defaultSampleRate)
        XCTAssertEqual(selection.policy, "fallback_44100")
        XCTAssertEqual(selection.source, "fallback_44100")
        XCTAssertNil(selection.configurationWarning)
    }

    func testRuntimeCMixerSampleRatePolicyUsesHardwareBeforeMainMixerFallback() {
        let selection = RuntimeCMixerSampleRateSelection.resolve(
            environment: [:],
            candidates: RuntimeCMixerSampleRateCandidates(
                outputNodeSampleRate: nil,
                mainMixerSampleRate: 44_100,
                hardwareSampleRate: 48_000
            )
        )

        XCTAssertEqual(selection.sampleRate, 48_000)
        XCTAssertEqual(selection.policy, "graph_aligned")
        XCTAssertEqual(selection.source, "hardware")
    }

    func testRuntimeCMixerSampleRatePolicyAcceptsExplicitEnvironmentOverride() {
        let selection = RuntimeCMixerSampleRateSelection.resolve(
            environment: [
                RuntimeCMixerSampleRateSelection.environmentKey: "96000"
            ],
            candidates: RuntimeCMixerSampleRateCandidates(
                outputNodeSampleRate: 48_000,
                mainMixerSampleRate: 48_000,
                hardwareSampleRate: 48_000
            )
        )

        XCTAssertEqual(selection.sampleRate, 96_000)
        XCTAssertEqual(selection.policy, "explicit_env")
        XCTAssertEqual(selection.source, "environment")
        XCTAssertNil(selection.configurationWarning)
    }

    func testRuntimeCMixerSampleRatePolicyFallsBackToGraphForInvalidEnvironmentOverride() {
        let selection = RuntimeCMixerSampleRateSelection.resolve(
            environment: [
                RuntimeCMixerSampleRateSelection.environmentKey: "not-a-rate"
            ],
            candidates: RuntimeCMixerSampleRateCandidates(
                outputNodeSampleRate: 48_000,
                mainMixerSampleRate: 48_000,
                hardwareSampleRate: 48_000
            )
        )

        XCTAssertEqual(selection.sampleRate, 48_000)
        XCTAssertEqual(selection.policy, "graph_aligned")
        XCTAssertEqual(selection.source, "output_node")
        XCTAssertEqual(selection.configurationWarning, "invalid_runtime_sample_rate")
    }

    func testRuntimeCMixerFormatDiagnosticsDetectMatchingRates() {
        let likely = RuntimeCMixerFormatDiagnostics.formatConversionLikely(
            sourceSampleRate: 48_000,
            sourceChannelCount: 2,
            mainMixerSampleRate: 48_000,
            mainMixerChannelCount: 2,
            outputSampleRate: 48_000,
            outputChannelCount: 2,
            hardwareSampleRate: 48_000
        )

        XCTAssertFalse(likely)
        XCTAssertEqual(RuntimeCMixerFormatDiagnostics.sampleRatesMatch(48_000, 48_000.4), true)
    }

    func testRuntimeCMixerFormatDiagnosticsDetectLikelyConversionWhenRatesDiffer() {
        let likely = RuntimeCMixerFormatDiagnostics.formatConversionLikely(
            sourceSampleRate: 44_100,
            sourceChannelCount: 2,
            mainMixerSampleRate: 48_000,
            mainMixerChannelCount: 2,
            outputSampleRate: 48_000,
            outputChannelCount: 2,
            hardwareSampleRate: 48_000
        )

        XCTAssertTrue(likely)
    }

    func testRuntimeCMixerDefaultGainPolicyUsesConservativeHeadroom() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [:])

        XCTAssertEqual(RuntimeCMixerOutputPolicy.defaultHeadroomDB, -12)
        XCTAssertEqual(policy.headroomPolicy, "default_runtime_headroom_db")
        XCTAssertEqual(policy.outputGain, Float(pow(10.0, RuntimeCMixerOutputPolicy.defaultHeadroomDB / 20.0)), accuracy: 0.000_001)
        XCTAssertEqual(policy.fixedHeadroomDB, RuntimeCMixerOutputPolicy.defaultHeadroomDB)
        XCTAssertEqual(policy.gainPolicySource, "default")
        XCTAssertEqual(policy.gainPolicyIsEnvironmentOverride, false)
        XCTAssertFalse(policy.autoHeadroomEnabled)
        XCTAssertNil(policy.configurationWarning)
    }

    func testRuntimeCMixerGainPolicyParsesExplicitGain() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "0.5"
        ])

        XCTAssertEqual(policy.headroomPolicy, "env_runtime_gain")
        XCTAssertEqual(policy.outputGain, 0.5, accuracy: 0.000_001)
        XCTAssertNil(policy.fixedHeadroomDB)
        XCTAssertEqual(policy.gainPolicySource, "environment_override")
        XCTAssertEqual(policy.gainPolicyIsEnvironmentOverride, true)
        XCTAssertNil(policy.configurationWarning)
    }

    func testRuntimeCMixerGainPolicyFallsBackForInvalidGain() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1.5"
        ])

        XCTAssertEqual(policy.headroomPolicy, "default_runtime_headroom_db_fallback")
        XCTAssertEqual(policy.outputGain, RuntimeCMixerOutputPolicy.defaultPolicy.outputGain, accuracy: 0.000_001)
        XCTAssertEqual(policy.fixedHeadroomDB, RuntimeCMixerOutputPolicy.defaultHeadroomDB)
        XCTAssertEqual(policy.gainPolicySource, "default_fallback")
        XCTAssertEqual(policy.gainPolicyIsEnvironmentOverride, false)
        XCTAssertEqual(policy.configurationWarning, "invalid_runtime_gain")
    }

    func testRuntimeCMixerGainPolicyParsesNegativeHeadroomDB() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.headroomDBEnvironmentKey: "-6"
        ])

        XCTAssertEqual(policy.headroomPolicy, "env_runtime_headroom_db")
        XCTAssertEqual(policy.outputGain, Float(pow(10.0, -6.0 / 20.0)), accuracy: 0.000_001)
        XCTAssertEqual(policy.fixedHeadroomDB, -6)
        XCTAssertEqual(policy.gainPolicySource, "environment_override")
        XCTAssertEqual(policy.gainPolicyIsEnvironmentOverride, true)
        XCTAssertNil(policy.configurationWarning)
    }

    func testRuntimeCMixerGainPolicyRejectsPositiveHeadroomDB() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.headroomDBEnvironmentKey: "3"
        ])

        XCTAssertEqual(policy.headroomPolicy, "default_runtime_headroom_db_fallback")
        XCTAssertEqual(policy.outputGain, RuntimeCMixerOutputPolicy.defaultPolicy.outputGain, accuracy: 0.000_001)
        XCTAssertEqual(policy.fixedHeadroomDB, RuntimeCMixerOutputPolicy.defaultHeadroomDB)
        XCTAssertEqual(policy.gainPolicySource, "default_fallback")
        XCTAssertEqual(policy.gainPolicyIsEnvironmentOverride, false)
        XCTAssertEqual(policy.configurationWarning, "invalid_runtime_headroom_db")
    }

    func testRuntimeCMixerGainPolicyFallsBackWhenGainAndHeadroomAreBothSet() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "0.5",
            RuntimeCMixerOutputPolicy.headroomDBEnvironmentKey: "-6"
        ])

        XCTAssertEqual(policy.headroomPolicy, "default_runtime_headroom_db_fallback")
        XCTAssertEqual(policy.outputGain, RuntimeCMixerOutputPolicy.defaultPolicy.outputGain, accuracy: 0.000_001)
        XCTAssertEqual(policy.fixedHeadroomDB, RuntimeCMixerOutputPolicy.defaultHeadroomDB)
        XCTAssertEqual(policy.gainPolicySource, "default_fallback")
        XCTAssertEqual(policy.gainPolicyIsEnvironmentOverride, false)
        XCTAssertEqual(policy.configurationWarning, "conflicting_runtime_gain_policy")
    }

    func testRuntimeCMixerUpdatePolicyDefaultsToExistingEpsilon() {
        let policy = RuntimeCMixerUpdatePolicy.resolve(environment: [:])

        XCTAssertEqual(policy.updateEpsilonPolicy, "default_runtime_update_epsilon")
        XCTAssertEqual(policy.updateEpsilon, RuntimeCMixerRenderCore.updateEpsilon, accuracy: 0.000_000_001)
        XCTAssertNil(policy.configurationWarning)
    }

    func testRuntimeCMixerUpdatePolicyParsesLocalDiagnosticOverride() {
        let policy = RuntimeCMixerUpdatePolicy.resolve(environment: [
            RuntimeCMixerUpdatePolicy.epsilonEnvironmentKey: "0"
        ])

        XCTAssertEqual(policy.updateEpsilonPolicy, "env_runtime_update_epsilon")
        XCTAssertEqual(policy.updateEpsilon, 0)
        XCTAssertNil(policy.configurationWarning)
    }

    func testRuntimeCMixerUpdatePolicyFallsBackForInvalidOverride() {
        let policy = RuntimeCMixerUpdatePolicy.resolve(environment: [
            RuntimeCMixerUpdatePolicy.epsilonEnvironmentKey: "-1"
        ])

        XCTAssertEqual(policy.updateEpsilonPolicy, "default_runtime_update_epsilon_fallback")
        XCTAssertEqual(policy.updateEpsilon, RuntimeCMixerRenderCore.updateEpsilon, accuracy: 0.000_000_001)
        XCTAssertEqual(policy.configurationWarning, "invalid_runtime_update_epsilon")
    }

    func testRuntimeCMixerSongEndTailPolicyDefaultsAndParsesEnvironment() {
        let defaultPolicy = RuntimeCMixerSongEndTailPolicy.resolve(environment: [:])
        let explicit = RuntimeCMixerSongEndTailPolicy.resolve(environment: [
            RuntimeCMixerSongEndTailPolicy.tailSecondsEnvironmentKey: "0.25"
        ])
        let invalid = RuntimeCMixerSongEndTailPolicy.resolve(environment: [
            RuntimeCMixerSongEndTailPolicy.tailSecondsEnvironmentKey: "not-a-duration"
        ])

        XCTAssertEqual(defaultPolicy.tailSeconds, 3)
        XCTAssertEqual(defaultPolicy.tailPolicy, "default_runtime_tail_seconds")
        XCTAssertEqual(defaultPolicy.tailFrames(sampleRate: 100), 300)
        XCTAssertEqual(explicit.tailSeconds, 0.25)
        XCTAssertEqual(explicit.tailPolicy, "env_runtime_tail_seconds")
        XCTAssertEqual(explicit.tailFrames(sampleRate: 100), 25)
        XCTAssertEqual(invalid.tailSeconds, 3)
        XCTAssertEqual(invalid.tailPolicy, "default_runtime_tail_seconds_fallback")
        XCTAssertEqual(invalid.configurationWarning, "invalid_runtime_tail_seconds")
    }

    @MainActor
    func testPlaybackAudioOutputFactoryDefaultsToCoreAudioCMixerBackend() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let output = PlaybackAudioOutputFactory.make(environment: [:], runtimeCMixerTraceWriter: traceWriter)
        let selectedSampleRate = traceWriter.events.first?.selectedRuntimeSampleRate ?? MixerRenderConfig.defaultSampleRate

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAction, "backend_selected")
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertNil(traceWriter.events.first?.backendFlagValue)
        XCTAssertNil(traceWriter.events.first?.fallbackReason)
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(traceWriter.events.first?.sampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.cMixerRuntimeSampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, false)
        XCTAssertEqual(traceWriter.events.first?.runtimeTailSeconds, 3)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryTreatsRetiredAVAudioFlagAsCoreAudioCMixerFallback() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let output = PlaybackAudioOutputFactory.make(
            environment: [RuntimeAudioBackendSelection.environmentKey: "av_audio"],
            runtimeCMixerTraceWriter: traceWriter
        )
        let selectedSampleRate = traceWriter.events.first?.selectedRuntimeSampleRate ?? MixerRenderConfig.defaultSampleRate

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAction, "backend_selected")
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.backendFlagValue, "av_audio")
        XCTAssertEqual(traceWriter.events.first?.fallbackReason, RuntimeAudioBackendSelection.retiredAVAudioFallbackReason)
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(traceWriter.events.first?.sampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.cMixerRuntimeSampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, false)
        XCTAssertEqual(traceWriter.events.first?.runtimeTailSeconds, 3)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryAppliesCMixerPoliciesForRetiredAVAudioFallback() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("retired-av-audio-capture-\(UUID().uuidString).wav")
        let output = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "av_audio",
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "0.5",
                RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
                RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "0.5"
            ],
            runtimeCMixerTraceWriter: traceWriter
        )

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.backendFlagValue, "av_audio")
        XCTAssertEqual(traceWriter.events.first?.fallbackReason, RuntimeAudioBackendSelection.retiredAVAudioFallbackReason)
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputGain, 0.5)
        XCTAssertEqual(traceWriter.events.first?.runtimeHeadroomPolicy, "env_runtime_gain")
        XCTAssertEqual(traceWriter.events.first?.runtimeDefaultHeadroomDB, -12)
        XCTAssertEqual(traceWriter.events.first?.runtimeGainPolicySource, "environment_override")
        XCTAssertEqual(traceWriter.events.first?.runtimeGainPolicyIsEnvironmentOverride, true)
        XCTAssertNil(traceWriter.events.first?.runtimeGainConfigurationWarning)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, true)
        XCTAssertEqual(traceWriter.events.first?.runtimeCapturePathName, captureURL.lastPathComponent)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureSeconds, 0.5)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryUsesExplicitPrimaryCMixerAlias() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let output = PlaybackAudioOutputFactory.make(
            environment: [RuntimeAudioBackendSelection.environmentKey: "c_mixer"],
            runtimeCMixerTraceWriter: traceWriter
        )
        let selectedSampleRate = traceWriter.events.first?.selectedRuntimeSampleRate ?? MixerRenderConfig.defaultSampleRate

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.backendFlagValue, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(traceWriter.events.first?.sampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.cMixerRuntimeSampleRate, selectedSampleRate)
        XCTAssertNotNil(traceWriter.events.first?.runtimeSampleRatePolicy)
        XCTAssertEqual(traceWriter.events.first?.channelCount, 2)
        XCTAssertEqual(traceWriter.events.first?.runtimeHeadroomPolicy, "default_runtime_headroom_db")
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputGain, RuntimeCMixerOutputPolicy.defaultPolicy.outputGain)
        XCTAssertEqual(traceWriter.events.first?.runtimeDefaultHeadroomDB, -12)
        XCTAssertEqual(traceWriter.events.first?.runtimeGainPolicySource, "default")
        XCTAssertEqual(traceWriter.events.first?.runtimeGainPolicyIsEnvironmentOverride, false)
        XCTAssertEqual(traceWriter.events.first?.runtimeAutoHeadroomEnabled, false)
        XCTAssertEqual(traceWriter.events.first?.runtimeFixedHeadroomDB, RuntimeCMixerOutputPolicy.defaultHeadroomDB)
        XCTAssertEqual(traceWriter.events.first?.runtimeUpdateEpsilon, RuntimeCMixerRenderCore.updateEpsilon)
        XCTAssertEqual(traceWriter.events.first?.runtimeUpdateEpsilonPolicy, "default_runtime_update_epsilon")
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, false)
        XCTAssertEqual(traceWriter.events.first?.runtimeTailSeconds, 3)
        XCTAssertEqual(traceWriter.events.first?.runtimeTailFrames, Int((selectedSampleRate * 3).rounded(.up)))
        XCTAssertEqual(traceWriter.events.first?.runtimeTailPolicy, "default_runtime_tail_seconds")
        let initializedEvent = traceWriter.events.first { $0.runtimeAction == "backend_initialized" }
        XCTAssertEqual(initializedEvent?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(initializedEvent?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(initializedEvent?.runtimeOutputHostRunning, false)
        XCTAssertEqual(initializedEvent?.runtimeOutputHostStartCount, 0)
        XCTAssertEqual(initializedEvent?.selectedRuntimeSampleRate, selectedSampleRate)
        XCTAssertEqual(initializedEvent?.cMixerRuntimeSampleRate, selectedSampleRate)
        XCTAssertEqual(initializedEvent?.cMixerRenderSampleRate, selectedSampleRate)
        XCTAssertEqual(initializedEvent?.cMixerRenderChannelCount, MixerRenderConfig.defaultChannelCount)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryUsesCoreAudioCMixerCompatibilityAlias() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let output = PlaybackAudioOutputFactory.make(
            environment: [RuntimeAudioBackendSelection.environmentKey: "c_mixer_coreaudio"],
            runtimeCMixerTraceWriter: traceWriter
        )
        let selectedSampleRate = traceWriter.events.first?.selectedRuntimeSampleRate ?? MixerRenderConfig.defaultSampleRate

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual((output as? PlaybackAudioBackendProviding)?.runtimeAudioBackend, .cMixerCoreAudio)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer_coreaudio")
        XCTAssertEqual(traceWriter.events.first?.backendFlagValue, "c_mixer_coreaudio")
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(traceWriter.events.first?.sampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.cMixerRuntimeSampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.channelCount, 2)
        XCTAssertEqual(traceWriter.events.first?.runtimeTailSeconds, 3)
        XCTAssertEqual(traceWriter.events.first?.runtimeTailFrames, Int((selectedSampleRate * 3).rounded(.up)))
        XCTAssertEqual(traceWriter.events.first?.runtimeTailPolicy, "default_runtime_tail_seconds")

        let initializedEvent = traceWriter.events.first { $0.runtimeAction == "backend_initialized" }
        XCTAssertEqual(initializedEvent?.runtimeAudioBackend, "c_mixer_coreaudio")
        XCTAssertEqual(initializedEvent?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(initializedEvent?.runtimeOutputHostRunning, false)
        XCTAssertEqual(initializedEvent?.runtimeOutputHostStartCount, 0)
        XCTAssertEqual(initializedEvent?.selectedRuntimeSampleRate, selectedSampleRate)
        XCTAssertEqual(initializedEvent?.cMixerRenderSampleRate, selectedSampleRate)
        XCTAssertEqual(initializedEvent?.cMixerRenderChannelCount, MixerRenderConfig.defaultChannelCount)
        XCTAssertEqual(initializedEvent?.audioFormatConversionLikely, false)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryRecordsSafeRouteLabelForRetiredAVAudioFallbackAndCMixerBackend() {
        let avTraceWriter = TestRuntimeCMixerTraceWriter()
        _ = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "av_audio",
                RuntimeCMixerDiagnosticEnvironment.routeLabelEnvironmentKey: "Bluetooth Route"
            ],
            runtimeCMixerTraceWriter: avTraceWriter
        )
        XCTAssertEqual(avTraceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(avTraceWriter.events.first?.fallbackReason, RuntimeAudioBackendSelection.retiredAVAudioFallbackReason)
        XCTAssertEqual(avTraceWriter.events.first?.audioOutputRouteLabel, "bluetooth-route")

        let cTraceWriter = TestRuntimeCMixerTraceWriter()
        _ = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerDiagnosticEnvironment.routeLabelEnvironmentKey: "Bluetooth Route"
            ],
            runtimeCMixerTraceWriter: cTraceWriter
        )
        XCTAssertEqual(cTraceWriter.events.first?.audioOutputRouteLabel, "bluetooth-route")
        XCTAssertEqual(
            cTraceWriter.events.first { $0.runtimeAction == "backend_initialized" }?.audioOutputRouteLabel,
            "bluetooth-route"
        )
    }

    @MainActor
    func testPlaybackAudioOutputFactoryAppliesExplicitCMixerRuntimeSampleRateOverride() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let output = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerSampleRateSelection.environmentKey: "48000"
            ],
            runtimeCMixerTraceWriter: traceWriter
        )

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.selectedRuntimeSampleRate, 48_000)
        XCTAssertEqual(traceWriter.events.first?.cMixerRuntimeSampleRate, 48_000)
        XCTAssertEqual(traceWriter.events.first?.runtimeSampleRatePolicy, "explicit_env")
        XCTAssertEqual(traceWriter.events.first?.runtimeSampleRateSource, "environment")
        XCTAssertNil(traceWriter.events.first?.runtimeSampleRateConfigurationWarning)
        let initializedEvent = traceWriter.events.first { $0.runtimeAction == "backend_initialized" }
        XCTAssertEqual(initializedEvent?.cMixerRenderSampleRate, 48_000)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryEnablesCaptureOnlyForCMixerBackendWithPath() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-c-runtime-capture-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: captureURL)
        }
        let output = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
                RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "0.5"
            ],
            runtimeCMixerTraceWriter: traceWriter
        )
        let selectedSampleRate = traceWriter.events.first?.selectedRuntimeSampleRate ?? MixerRenderConfig.defaultSampleRate

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, true)
        XCTAssertEqual(traceWriter.events.first?.runtimeCapturePathName, captureURL.lastPathComponent)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureSampleRate, selectedSampleRate)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureChannelCount, MixerRenderConfig.defaultChannelCount)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureSeconds, 0.5)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureFrameLimit, Int((selectedSampleRate * 0.5).rounded(.up)))
        XCTAssertEqual(traceWriter.events.first?.runtimeCapturedFrameCount, 0)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureTruncated, false)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryReportsDebugStopSeparatelyFromCaptureSecondsForBothCMixerHosts() {
        for backendValue in ["c_mixer", "c_mixer_coreaudio"] {
            let traceWriter = TestRuntimeCMixerTraceWriter()
            let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("debug-stop-capture-\(backendValue)-\(UUID().uuidString).wav")
            _ = PlaybackAudioOutputFactory.make(
                environment: [
                    RuntimeAudioBackendSelection.environmentKey: backendValue,
                    RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
                    RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "0.5",
                    PlaybackDebugLaunchConfiguration.stopAfterSecondsEnvironmentKey: "2.0"
                ],
                runtimeCMixerTraceWriter: traceWriter
            )

            let selected = traceWriter.events.first
            XCTAssertEqual(selected?.runtimeAudioBackend, backendValue)
            XCTAssertEqual(selected?.runtimeCaptureSeconds, 0.5)
            XCTAssertEqual(selected?.debugStopAfterSeconds, 2.0)
            XCTAssertEqual(selected?.runtimeCaptureEnabled, true)
        }
    }

    func testRuntimeCMixerCaptureLimitDoesNotStopRenderingPlaybackAudio() {
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("capture-limit-\(UUID().uuidString).wav")
        let captureConfiguration = RuntimeCMixerCaptureConfiguration.resolve(environment: [
            RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
            RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "0.2"
        ])
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 10, channelCount: 1),
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            captureConfiguration: captureConfiguration
        )
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 10, loopStart: 0, loopLength: 2, loopType: 1)
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))

        XCTAssertPCMEqual(renderRuntimePCM(core, frames: 2), [1, 1])
        let cappedSnapshot = core.snapshot()
        XCTAssertEqual(cappedSnapshot.capture.frameLimit, 2)
        XCTAssertEqual(cappedSnapshot.capture.capturedFrameCount, 2)
        XCTAssertTrue(cappedSnapshot.capture.truncated)

        XCTAssertPCMEqual(renderRuntimePCM(core, frames: 3), [1, 1, 1])
        let continuedSnapshot = core.snapshot()
        XCTAssertEqual(continuedSnapshot.currentFrame, 5)
        XCTAssertEqual(continuedSnapshot.activeVoiceCount, 1)
        XCTAssertEqual(continuedSnapshot.capture.capturedFrameCount, 2)
        XCTAssertTrue(continuedSnapshot.capture.truncated)
        XCTAssertFalse(continuedSnapshot.captureCapTriggeredPlaybackStop)
    }

    func testRuntimeCMixerTailFramesAreAddedToPlannedSongEnd() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            songEndTailPolicy: RuntimeCMixerSongEndTailPolicy(
                tailSeconds: 0.25,
                tailPolicy: "test_runtime_tail_seconds",
                configurationWarning: nil
            )
        )

        core.configureAdapterEventScheduleForTesting([], runtimeFrameOffset: 5, plannedSongEndFrame: 30)
        let snapshot = core.snapshot()

        XCTAssertEqual(snapshot.plannedSongEndFrame, 30)
        XCTAssertEqual(snapshot.plannedSongEndRuntimeFrame, 35)
        XCTAssertEqual(snapshot.runtimeTailSeconds, 0.25)
        XCTAssertEqual(snapshot.runtimeTailFrames, 25)
        XCTAssertEqual(snapshot.songEndStopFrame, 55)
        XCTAssertEqual(snapshot.songEndStopRuntimeFrame, 60)
    }

    func testRuntimeCMixerCaptureLongerThanSongEndDoesNotExtendPlayback() {
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("long-capture-\(UUID().uuidString).wav")
        let captureConfiguration = RuntimeCMixerCaptureConfiguration.resolve(environment: [
            RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
            RuntimeCMixerCaptureConfiguration.secondsEnvironmentKey: "10"
        ])
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 10, channelCount: 1),
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            captureConfiguration: captureConfiguration,
            songEndTailPolicy: RuntimeCMixerSongEndTailPolicy(
                tailSeconds: 0.2,
                tailPolicy: "test_runtime_tail_seconds",
                configurationWarning: nil
            )
        )
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 10, loopStart: 0, loopLength: 2, loopType: 1)
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        core.configureAdapterEventScheduleForTesting([], runtimeFrameOffset: 0, plannedSongEndFrame: 2)

        XCTAssertPCMEqual(renderRuntimePCM(core, frames: 6), [1, 1, 1, 1, 0, 0])
        let snapshot = core.snapshot()

        XCTAssertEqual(snapshot.capture.frameLimit, 100)
        XCTAssertEqual(snapshot.capture.capturedFrameCount, 6)
        XCTAssertFalse(snapshot.capture.truncated)
        XCTAssertEqual(snapshot.runtimeFrameAtSongEndTailStop, 4)
        XCTAssertEqual(snapshot.activeVoiceCountAtTailStop, 1)
        XCTAssertEqual(snapshot.loadedVoiceCountAtTailStop, 1)
        XCTAssertEqual(snapshot.activeVoiceCount, 0)
        XCTAssertEqual(snapshot.loadedVoiceCount, 0)
        XCTAssertFalse(snapshot.captureCapTriggeredPlaybackStop)
    }

    func testRuntimeCMixerSongEndLifecycleDiagnosticsDetectSustainedVoicesAfterPlanEnd() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 10, channelCount: 1),
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 10, loopStart: 0, loopLength: 2, loopType: 1)
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        core.configureAdapterEventScheduleForTesting([], runtimeFrameOffset: 0, plannedSongEndFrame: 2)

        XCTAssertPCMEqual(renderRuntimePCM(core, frames: 5), [1, 1, 1, 1, 1])
        let snapshot = core.snapshot()

        XCTAssertEqual(snapshot.plannedSongEndFrame, 2)
        XCTAssertEqual(snapshot.plannedSongEndRuntimeFrame, 2)
        XCTAssertEqual(snapshot.runtimeFrameAtPlannedSongEnd, 2)
        XCTAssertEqual(snapshot.eventQueueExhaustedFrame, 0)
        XCTAssertTrue(snapshot.eventQueueExhausted)
        XCTAssertEqual(snapshot.activeVoiceCountAtPlannedSongEnd, 1)
        XCTAssertEqual(snapshot.loadedVoiceCountAtPlannedSongEnd, 1)
        XCTAssertEqual(snapshot.activeVoiceCountAfterPlannedSongEnd, 1)
        XCTAssertEqual(snapshot.loadedVoiceCountAfterPlannedSongEnd, 1)
        XCTAssertEqual(snapshot.outputContinuesAfterPlannedSongEnd, true)
        XCTAssertEqual(snapshot.finalSustainedVoicesContinueAfterPlannedSongEnd, true)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryDisablesCaptureForCMixerBackendWhenFlagged() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("disabled-engine-capture-\(UUID().uuidString).wav")
        let output = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
                RuntimeCMixerDiagnosticEnvironment.disableCaptureEnvironmentKey: "1"
            ],
            runtimeCMixerTraceWriter: traceWriter
        )

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, false)
        XCTAssertNil(traceWriter.events.first?.runtimeCapturePathName)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryMinimalCallbackModeKeepsCMixerDefaultAndDisablesCapture() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("minimal-engine-capture-\(UUID().uuidString).wav")
        let output = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerCaptureConfiguration.pathEnvironmentKey: captureURL.path,
                RuntimeCMixerDiagnosticEnvironment.minimalCallbackEnvironmentKey: "1"
            ],
            runtimeCMixerTraceWriter: traceWriter
        )

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.runtimeMinimalCallbackMode, true)
        XCTAssertEqual(traceWriter.events.first?.runtimeCaptureEnabled, false)
    }

    @MainActor
    func testPlaybackAudioOutputFactoryTracesCMixerGainPolicyEnvironmentOverrides() {
        let gainTraceWriter = TestRuntimeCMixerTraceWriter()
        _ = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "0.5"
            ],
            runtimeCMixerTraceWriter: gainTraceWriter
        )

        XCTAssertEqual(gainTraceWriter.events.first?.runtimeHeadroomPolicy, "env_runtime_gain")
        XCTAssertEqual(gainTraceWriter.events.first?.runtimeOutputGain ?? 0, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(gainTraceWriter.events.first?.runtimeDefaultHeadroomDB, -12)
        XCTAssertEqual(gainTraceWriter.events.first?.runtimeGainPolicySource, "environment_override")
        XCTAssertEqual(gainTraceWriter.events.first?.runtimeGainPolicyIsEnvironmentOverride, true)
        XCTAssertNil(gainTraceWriter.events.first?.runtimeFixedHeadroomDB)

        let headroomTraceWriter = TestRuntimeCMixerTraceWriter()
        _ = PlaybackAudioOutputFactory.make(
            environment: [
                RuntimeAudioBackendSelection.environmentKey: "c_mixer",
                RuntimeCMixerOutputPolicy.headroomDBEnvironmentKey: "-6"
            ],
            runtimeCMixerTraceWriter: headroomTraceWriter
        )

        XCTAssertEqual(headroomTraceWriter.events.first?.runtimeHeadroomPolicy, "env_runtime_headroom_db")
        XCTAssertEqual(headroomTraceWriter.events.first?.runtimeOutputGain ?? 0, Float(pow(10.0, -6.0 / 20.0)), accuracy: 0.000_001)
        XCTAssertEqual(headroomTraceWriter.events.first?.runtimeDefaultHeadroomDB, -12)
        XCTAssertEqual(headroomTraceWriter.events.first?.runtimeGainPolicySource, "environment_override")
        XCTAssertEqual(headroomTraceWriter.events.first?.runtimeGainPolicyIsEnvironmentOverride, true)
        XCTAssertEqual(headroomTraceWriter.events.first?.runtimeFixedHeadroomDB, -6)
    }

    func testRuntimeCMixerCaptureBufferRecordsFramesInOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ordered-capture-\(UUID().uuidString).wav")
        let configuration = RuntimeCMixerCaptureConfiguration(
            url: url,
            pathName: url.lastPathComponent,
            seconds: 1,
            secondsPolicy: "env_runtime_capture_seconds",
            configurationWarning: nil
        )
        let buffer = RuntimeCMixerCaptureBuffer(
            configuration: configuration,
            config: MixerRenderConfig(sampleRate: 4, channelCount: 2)
        )
        var first = [Float(0.1), -0.2, 0.3, -0.4]
        var second = [Float(0.5), -0.6]

        let firstSummary = first.withUnsafeMutableBufferPointer { pointer in
            buffer.capture(pointer, frameCount: 2, channelCount: 2)
        }
        let secondSummary = second.withUnsafeMutableBufferPointer { pointer in
            buffer.capture(pointer, frameCount: 1, channelCount: 2)
        }

        let capture = try XCTUnwrap(buffer.blockSnapshot())
        XCTAssertEqual(capture.snapshot.enabled, true)
        XCTAssertEqual(capture.snapshot.pathName, url.lastPathComponent)
        XCTAssertEqual(capture.snapshot.sampleRate, 4)
        XCTAssertEqual(capture.snapshot.channelCount, 2)
        XCTAssertEqual(capture.snapshot.capturedFrameCount, 3)
        XCTAssertEqual(capture.snapshot.truncated, false)
        XCTAssertEqual(capture.snapshot.outputPeak, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(capture.snapshot.outputRMS, Float(sqrt(0.91 / 6.0)), accuracy: 0.000_001)
        XCTAssertPCMEqual(capture.block.interleavedPCM, [0.1, -0.2, 0.3, -0.4, 0.5, -0.6])
        let expectedFirstSummary = first.withUnsafeBufferPointer {
            RuntimeCMixerSampleSummary.summarize($0, frameCount: 2, channelCount: 2)
        }
        let expectedSecondSummary = second.withUnsafeBufferPointer {
            RuntimeCMixerSampleSummary.summarize($0, frameCount: 1, channelCount: 2)
        }
        XCTAssertEqual(firstSummary?.checksum, expectedFirstSummary.checksum)
        XCTAssertEqual(secondSummary?.checksum, expectedSecondSummary.checksum)
    }

    @MainActor
    func testCoreAudioCMixerBackendRenderForTestingUsesSharedRenderCore() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = RuntimeCMixerAudioEngine(
            backend: .cMixerCoreAudio,
            sampleRate: 100,
            channelCount: 1,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let sample = makePlaybackSample(pcm: [0.25, 0.5, 0.75, 1.0], baseSampleRate: 100)

        engine.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0))
        let output = engine.renderForTesting(frameCount: 4)

        XCTAssertPCMEqual(output, [0.25, 0.5, 0.75, 1.0])
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer_coreaudio")
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputHostType, "coreaudio_default_output_unit")
        XCTAssertEqual(traceWriter.events.last?.runtimeAudioBackend, "c_mixer_coreaudio")
    }

    func testRuntimeCMixerCaptureBufferRespectsFrameCapAndReportsTruncation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("truncated-capture-\(UUID().uuidString).wav")
        let configuration = RuntimeCMixerCaptureConfiguration(
            url: url,
            pathName: url.lastPathComponent,
            seconds: 0.03,
            secondsPolicy: "env_runtime_capture_seconds",
            configurationWarning: nil
        )
        let buffer = RuntimeCMixerCaptureBuffer(
            configuration: configuration,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1)
        )
        var output = [Float(0.25), 0.5, 0.75, 1.0, -1.25]

        _ = output.withUnsafeMutableBufferPointer { pointer in
            buffer.capture(pointer, frameCount: 5, channelCount: 1)
        }

        let capture = try XCTUnwrap(buffer.blockSnapshot())
        XCTAssertEqual(capture.snapshot.frameLimit, 3)
        XCTAssertEqual(capture.snapshot.capturedFrameCount, 3)
        XCTAssertEqual(capture.snapshot.truncated, true)
        XCTAssertEqual(capture.snapshot.clippingSampleCount, 0)
        XCTAssertEqual(capture.snapshot.overrangeSampleCount, 0)
        XCTAssertPCMEqual(capture.block.interleavedPCM, [0.25, 0.5, 0.75])
    }

    func testRuntimeCMixerCaptureWriterProducesValidPCM16WAV() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-writer-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let configuration = RuntimeCMixerCaptureConfiguration(
            url: url,
            pathName: url.lastPathComponent,
            seconds: 1,
            secondsPolicy: "env_runtime_capture_seconds",
            configurationWarning: nil
        )
        let buffer = RuntimeCMixerCaptureBuffer(
            configuration: configuration,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2)
        )
        var output = [Float(0), 0.5, -0.5, 1.0]
        _ = output.withUnsafeMutableBufferPointer { pointer in
            buffer.capture(pointer, frameCount: 2, channelCount: 2)
        }
        let capture = try XCTUnwrap(buffer.blockSnapshot())

        let diagnostics = try RuntimeCMixerCaptureWAVWriter.write(capture)
        let wav = try parsePCM16WAV(Data(contentsOf: url))

        XCTAssertEqual(wav.sampleRate, 100)
        XCTAssertEqual(wav.channelCount, 2)
        XCTAssertEqual(wav.bitsPerSample, 16)
        XCTAssertEqual(wav.samples, [0, 16_384, -16_384, Int16.max])
        XCTAssertEqual(diagnostics.postGainPeak, 1)
        XCTAssertEqual(diagnostics.pcm16ClippingSampleCount, 1)
    }

    func testRuntimeCMixerAdapterEventPlanBuildsFromPlaybackSongFixture() {
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 256), baseSampleRate: 44_100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x01, effectParam: 0x02),
                    makePlaybackRow(index: 1, volumeColumn: 0x20),
                    makePlaybackRow(index: 2, effectType: 0x08, effectParam: 0xFF)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 125)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 44_100)

        XCTAssertTrue(plan.generated)
        XCTAssertGreaterThan(plan.plannedEventCount, 0)
        XCTAssertTrue(plan.events.contains { event in
            if case .noteTrigger = event.action {
                return true
            }
            return false
        })
        XCTAssertTrue(plan.categories.contains("gain_pan_update"))
        XCTAssertTrue(plan.categories.contains("step_update"))
        XCTAssertTrue(plan.categories.contains("portamento_update"))
    }

    func testRuntimeCMixerAdapterEventPlanKeepsRepeatedLargeSampleSemantics() throws {
        var pcm = Array(repeating: Float(0.25), count: 8_192)
        pcm[128] = .infinity
        let sample = makePlaybackSample(pcm: pcm, baseSampleRate: 44_100)
        let rows = (0..<24).map { rowIndex in
            makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
        }
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 44_100)
        let noteTriggers = plan.events.compactMap { event -> SyntheticTrackerEvent? in
            if case let .noteTrigger(_, syntheticEvent, _) = event.action {
                return syntheticEvent
            }
            return nil
        }

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.plannedEventCount, rows.count)
        XCTAssertEqual(plan.categories, ["note_trigger", "replacement"])
        XCTAssertEqual(noteTriggers.count, rows.count)
        for event in noteTriggers {
            XCTAssertEqual(event.sample.frameCount, pcm.count)
            XCTAssertEqual(event.sample.monoPCM[0], 0.25)
            XCTAssertEqual(event.sample.monoPCM[128], 0)
        }
    }

    func testRuntimeCMixerAdapterEventPlanOrdersSameFrameUpdatesBeforeTriggers() {
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 256), baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1)],
                3: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0x20, effectType: 0, effectParam: 0),
                        PlaybackCell(note: 53, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let sameFrameEvents = plan.events.filter { $0.scheduledFrame == 10 }

        XCTAssertEqual(sameFrameEvents.map(\.primaryCategory), ["gain_pan_update", "note_trigger"])
        XCTAssertEqual(sameFrameEvents.map(\.channelIndex), [0, 1])
    }

    func testRuntimeCMixerAdapterEventPlanUsesSelectedRuntimeSampleRateForFrames() {
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 256), baseSampleRate: 48_000)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 48_000)
        let noteTrigger = plan.events.first { event in
            if case .noteTrigger = event.action {
                return true
            }
            return false
        }

        XCTAssertEqual(plan.sampleRate, 48_000)
        XCTAssertEqual(noteTrigger?.scheduledFrame, 4_800)
    }

    func testRuntimeCMixerAdapterEventPlanReportsPlannedSongEndFrameFromRuntimeTimeline() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 3],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.sampleRate, 100)
        XCTAssertEqual(plan.plannedSongEndFrame, 30)
        XCTAssertEqual(plan.plannedSongEndSeconds, 0.3)
    }

    func testRuntimeCMixerAdapterEventPlanTraversesGeneratedMultiPatternLoopBoundaryFixture() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let noteTriggers = plan.events.compactMap { event -> (RuntimeCMixerAdapterEvent, PlaybackSongSyntheticEventMapping)? in
            guard case let .noteTrigger(_, _, mapping) = event.action else {
                return nil
            }
            return (event, mapping)
        }

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.plannedEventCount, 3)
        XCTAssertEqual(plan.events.map(\.scheduledFrame), [0, 48, 96])
        XCTAssertEqual(plan.events.map(\.categories), [
            ["note_trigger"],
            ["note_trigger", "replacement"],
            ["note_trigger", "replacement"],
        ])
        XCTAssertEqual(plan.plannedSongEndFrame, 144)
        XCTAssertEqual(plan.plannedSongEndSeconds, 1.44)
        XCTAssertEqual(noteTriggers.map { $0.0.source }, [
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0),
            PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 0),
        ])
        XCTAssertEqual(noteTriggers.map { $0.1.note }, [49, 53, 56])
        XCTAssertEqual(noteTriggers.map { $0.1.instrumentIndex }, [1, 1, 1])
        XCTAssertEqual(noteTriggers.map { $0.1.sampleIndex }, [0, 0, 0])
    }

    func testRuntimeCMixerAdapterEventPlanSelectsPatternLoopRangeFromExistingGeneratedFixturePlan() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let boundary = try XCTUnwrap(TestPlaybackPatternLoopTransportBoundaryResolver.boundary(
            containing: PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 2),
            in: song
        ))

        let rangeEvents = plan.testEvents(in: boundary.range)
        let noteTriggers = rangeEvents.compactMap { event -> (RuntimeCMixerAdapterEvent, PlaybackSongSyntheticEventMapping)? in
            guard case let .noteTrigger(_, _, mapping) = event.action else {
                return nil
            }
            return (event, mapping)
        }

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.plannedEventCount, 3)
        XCTAssertEqual(plan.plannedSongEndFrame, 144)
        XCTAssertEqual(plan.events.map(\.scheduledFrame), [0, 48, 96])
        XCTAssertEqual(rangeEvents.map(\.scheduledFrame), [48])
        XCTAssertEqual(noteTriggers.map { $0.0.source }, [
            PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0)
        ])
        XCTAssertEqual(noteTriggers.map { $0.1.note }, [53])
        XCTAssertEqual(boundary.adapterPlanStrategy, .existingPlanRange)
        XCTAssertTrue(boundary.requiresRuntimeAdapterPlan)
        XCTAssertFalse(boundary.usesTimerDrivenTriggers)
        XCTAssertFalse(boundary.clearsActiveVoicesAtBoundary)
    }

    func testRuntimeCMixerAdapterEventPlanBuildsProductionPatternLoopRangeFromExistingGeneratedFixturePlan() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let playbackRange = try XCTUnwrap(song.patternLoopRange(containing: PlaybackPosition(
            orderIndex: 1,
            patternIndex: 1,
            rowIndex: 2
        )))

        let loopRange = try XCTUnwrap(plan.adapterEventLoopRange(for: playbackRange))

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(loopRange.playbackRange.orderIndex, 1)
        XCTAssertEqual(loopRange.playbackRange.patternIndex, 1)
        XCTAssertEqual(loopRange.plannedStartFrame, 48)
        XCTAssertEqual(loopRange.plannedEndFrame, 96)
        XCTAssertEqual(loopRange.frameCount, 48)
        XCTAssertEqual(loopRange.events.map(\.scheduledFrame), [48])
        XCTAssertEqual(loopRange.events.map(\.source), [
            PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0)
        ])
    }

    @MainActor
    func testRuntimeCMixerLoopOffPublicFixtureSchedulesOrdersZeroOneTwoOnce() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let harness = makeRuntimeCMixerPlaybackHarness(sampleRate: 100)

        harness.engine.load(song: song)
        harness.engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: false,
            timingSession: nil
        )
        _ = harness.audioEngine.renderForTesting(frameCount: 160)

        let addVoices = harness.traceWriter.events.filter { $0.runtimeAction == "c_mixer_add_voice" }
        XCTAssertEqual(addVoices.map(\.plannedSourceOrderIndex), [0, 1, 2])
        XCTAssertEqual(addVoices.map(\.plannedSourcePatternIndex), [0, 1, 2])
        XCTAssertEqual(addVoices.map(\.plannedRuntimeFrame), [0, 48, 96])
        XCTAssertTrue(addVoices.allSatisfy { $0.runtimeEventSource == "offline_adapter_plan" })
    }

    @MainActor
    func testRuntimeCMixerPatternLoopFromOrderZeroRepeatsAdapterPlanRangeWithoutClearAll() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let harness = makeRuntimeCMixerPlaybackHarness(sampleRate: 100)

        harness.engine.load(song: song)
        harness.engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: true,
            timingSession: nil
        )
        _ = harness.audioEngine.renderForTesting(frameCount: 160)

        let addVoices = Array(harness.traceWriter.events.filter { $0.runtimeAction == "c_mixer_add_voice" }.prefix(4))
        XCTAssertEqual(addVoices.map(\.plannedSourceOrderIndex), [0, 0, 0, 0])
        XCTAssertEqual(addVoices.map(\.plannedSourcePatternIndex), [0, 0, 0, 0])
        XCTAssertEqual(addVoices.map(\.plannedRuntimeFrame), [0, 48, 96, 144])
        XCTAssertTrue(addVoices.allSatisfy { $0.runtimeEventSource == "offline_adapter_plan" })
        XCTAssertNil(harness.traceWriter.events.first { $0.runtimeAction == "note_trigger" })
        XCTAssertTrue(clearAllEventsAfterRenderStarted(in: harness.traceWriter.events).isEmpty)
    }

    @MainActor
    func testRuntimeCMixerPatternLoopFromOrderOneDoesNotAdvanceToOrderTwo() throws {
        let song = try loadMultiPatternLoopBoundarySong()
        let harness = makeRuntimeCMixerPlaybackHarness(sampleRate: 100)

        harness.engine.load(song: song)
        harness.engine.play(
            from: PlaybackStartContext(moduleTitle: "fixture", songPosition: 1, patternIndex: 1, row: 0),
            loopEnabled: true,
            timingSession: nil
        )
        _ = harness.audioEngine.renderForTesting(frameCount: 160)

        let addVoices = Array(harness.traceWriter.events.filter { $0.runtimeAction == "c_mixer_add_voice" }.prefix(4))
        XCTAssertEqual(addVoices.map(\.plannedSourceOrderIndex), [1, 1, 1, 1])
        XCTAssertEqual(addVoices.map(\.plannedSourcePatternIndex), [1, 1, 1, 1])
        XCTAssertEqual(addVoices.map(\.plannedRuntimeFrame), [0, 48, 96, 144])
        XCTAssertFalse(harness.traceWriter.events.contains { $0.plannedSourceOrderIndex == 2 })
        XCTAssertTrue(addVoices.allSatisfy { $0.runtimeEventSource == "offline_adapter_plan" })
        XCTAssertTrue(clearAllEventsAfterRenderStarted(in: harness.traceWriter.events).isEmpty)
    }

    func testSampleTimePositionResolverMapsExactRowStartFrames() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowCounts: [2: 2, 3: 1],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let plan = try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100).plan)
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)

        let first = try XCTUnwrap(resolver.position(atFrame: 0))
        let second = try XCTUnwrap(resolver.position(atFrame: 10))
        let third = try XCTUnwrap(resolver.position(atFrame: 20))

        XCTAssertEqual(first.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(first.tickInRow, 0)
        XCTAssertEqual(second.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(second.tickInRow, 0)
        XCTAssertEqual(third.source, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 0))
        XCTAssertEqual(third.tickInRow, 0)
    }

    func testSampleTimePositionResolverUsesSelectedRuntimeSampleRate() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let plan = try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 48_000).plan)
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)

        let first = try XCTUnwrap(resolver.position(atFrame: 4_799))
        let second = try XCTUnwrap(resolver.position(atFrame: 4_800))

        XCTAssertEqual(first.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(first.tickInRow, 0)
        XCTAssertEqual(second.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(second.tickInRow, 0)
    }

    func testSampleTimePositionResolverMapsFramesInsideRowToTick() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 1],
            initialTiming: PlaybackTiming(speed: 2, bpm: 25)
        )
        let plan = try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100).plan)
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)

        let firstTick = try XCTUnwrap(resolver.position(atFrame: 9))
        let secondTick = try XCTUnwrap(resolver.position(atFrame: 15))

        XCTAssertEqual(firstTick.source.rowIndex, 0)
        XCTAssertEqual(firstTick.tickInRow, 0)
        XCTAssertEqual(secondTick.source.rowIndex, 0)
        XCTAssertEqual(secondTick.tickInRow, 1)
        XCTAssertEqual(secondTick.frameOffsetInRow, 15)
    }

    func testRuntimeAdapterPlanUsesAccumulatedExactRowStartForPlannedTickFrames() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            initialTiming: PlaybackTiming(speed: 2, bpm: 11)
        )
        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let context = AudioRuntimeTraceContext(orderIndex: 0, patternIndex: 2, rowIndex: 1, tickInRow: 1)
        let adaptedPlan = try XCTUnwrap(plan.plan)
        let resolver = PlaybackSongSampleTimePositionResolver(plan: adaptedPlan)

        XCTAssertEqual(plan.plannedRowStartFrame(matching: context), 45)
        XCTAssertEqual(plan.plannedFrame(matching: context), 68)
        XCTAssertEqual(resolver.position(atFrame: 67)?.tickInRow, 0)
        XCTAssertEqual(resolver.position(atFrame: 68)?.tickInRow, 1)
    }

    func testSampleTimePositionResolverUsesFxxTimingChanges() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x02),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2)
                ]
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let plan = try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100).plan)
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)

        let changedSpeedTick = try XCTUnwrap(resolver.position(atFrame: 20))
        let followingRow = try XCTUnwrap(resolver.position(atFrame: 30))

        XCTAssertEqual(changedSpeedTick.source.rowIndex, 1)
        XCTAssertEqual(changedSpeedTick.tickInRow, 1)
        XCTAssertEqual(changedSpeedTick.effectiveSpeed, 2)
        XCTAssertEqual(followingRow.source.rowIndex, 2)
        XCTAssertEqual(followingRow.tickInRow, 0)
    }

    func testSampleTimePositionResolverHandlesEndOfRangeSafely() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 1],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let plan = try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100).plan)
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)

        let position = try XCTUnwrap(resolver.position(atFrame: 10_000))

        XCTAssertEqual(position.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(position.tickInRow, 0)
        XCTAssertEqual(position.status, "at_or_after_end")
    }

    private func makeLongFollowResolverSong() -> PlaybackSong {
        let orderPatternIndices = Array(0...36)
        var patternRowsByIndex = [Int: [PlaybackRow]]()
        for patternIndex in orderPatternIndices {
            patternRowsByIndex[patternIndex] = (0..<128).map { makePlaybackRow(index: $0) }
        }
        patternRowsByIndex[35]?[0x4D] = makePlaybackRow(index: 0x4D)
        patternRowsByIndex[35]?[0x4E] = makePlaybackRow(index: 0x4E, note: 64, instrument: 0, effectType: 0x03, effectParam: 0x00)
        patternRowsByIndex[35]?[0x4F] = makePlaybackRow(index: 0x4F, volumeColumn: 0x40)
        patternRowsByIndex[35]?[0x50] = makePlaybackRow(index: 0x50, note: 49, instrument: 1)
        return makePlaybackSong(
            orderPatternIndices: orderPatternIndices,
            patternRowsByIndex: patternRowsByIndex,
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
    }

    private func rowTiming(
        in plan: PlaybackSongSyntheticPlan,
        orderIndex: Int,
        rowIndex: Int
    ) throws -> PlaybackSongSyntheticRowTimingDiagnostic {
        try XCTUnwrap(plan.diagnostics.rowTiming.first {
            $0.source.orderIndex == orderIndex && $0.source.rowIndex == rowIndex
        })
    }

    func testSampleTimePositionResolverMapsLongTimelineAcrossMultiOrderBoundary() throws {
        let song = makeLongFollowResolverSong()
        let plan = PlaybackSongSyntheticAdapter.adapt(
            song,
            startOrderIndex: 0,
            orderCount: song.orders.count,
            sampleRate: 100
        )
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)
        let targetTiming = try rowTiming(in: plan, orderIndex: 35, rowIndex: 0x51)
        let target = try XCTUnwrap(resolver.position(atFrame: targetTiming.rowStartFrame))

        XCTAssertEqual(target.source, PlaybackPosition(orderIndex: 35, patternIndex: 35, rowIndex: 0x51))
        XCTAssertEqual(target.tickInRow, 0)
        XCTAssertEqual(target.status, "in_range")
        XCTAssertEqual(target.frame, targetTiming.rowStartFrame)
    }

    func testSampleTimePositionResolverHandlesHighRowsAndOrderTransition() throws {
        let song = makeLongFollowResolverSong()
        let plan = PlaybackSongSyntheticAdapter.adapt(
            song,
            startOrderIndex: 0,
            orderCount: song.orders.count,
            sampleRate: 100
        )
        let resolver = PlaybackSongSampleTimePositionResolver(plan: plan)
        let row4E = try rowTiming(in: plan, orderIndex: 35, rowIndex: 0x4E)
        let row4F = try rowTiming(in: plan, orderIndex: 35, rowIndex: 0x4F)
        let row7F = try rowTiming(in: plan, orderIndex: 35, rowIndex: 0x7F)
        let order36 = try rowTiming(in: plan, orderIndex: 36, rowIndex: 0)

        XCTAssertEqual(try XCTUnwrap(resolver.position(atFrame: row4E.rowStartFrame)).source, PlaybackPosition(orderIndex: 35, patternIndex: 35, rowIndex: 0x4E))
        XCTAssertEqual(try XCTUnwrap(resolver.position(atFrame: row4F.rowStartFrame)).source, PlaybackPosition(orderIndex: 35, patternIndex: 35, rowIndex: 0x4F))
        XCTAssertEqual(try XCTUnwrap(resolver.position(atFrame: order36.rowStartFrame - 1)).source, PlaybackPosition(orderIndex: 35, patternIndex: 35, rowIndex: 0x7F))
        XCTAssertEqual(try XCTUnwrap(resolver.position(atFrame: row7F.rowStartFrame)).source, PlaybackPosition(orderIndex: 35, patternIndex: 35, rowIndex: 0x7F))
        XCTAssertEqual(try XCTUnwrap(resolver.position(atFrame: order36.rowStartFrame)).source, PlaybackPosition(orderIndex: 36, patternIndex: 36, rowIndex: 0))
    }

    func testFullRunAndDirectStartResolverMappingsAgreeAfterBaseFrameAdjustment() throws {
        let song = makeLongFollowResolverSong()
        let fullPlan = PlaybackSongSyntheticAdapter.adapt(
            song,
            startOrderIndex: 0,
            orderCount: song.orders.count,
            sampleRate: 100
        )
        let directPlan = PlaybackSongSyntheticAdapter.adapt(
            song,
            startOrderIndex: 34,
            orderCount: 3,
            sampleRate: 100
        )
        let fullResolver = PlaybackSongSampleTimePositionResolver(plan: fullPlan)
        let directResolver = PlaybackSongSampleTimePositionResolver(plan: directPlan)
        let fullBase = try rowTiming(in: fullPlan, orderIndex: 34, rowIndex: 0)
        let fullTarget = try rowTiming(in: fullPlan, orderIndex: 35, rowIndex: 0x51)
        let directTarget = try rowTiming(in: directPlan, orderIndex: 35, rowIndex: 0x51)
        let fullPosition = try XCTUnwrap(fullResolver.position(atFrame: fullTarget.rowStartFrame))
        let directPosition = try XCTUnwrap(directResolver.position(atFrame: directTarget.rowStartFrame))

        XCTAssertEqual(fullPosition.source, directPosition.source)
        XCTAssertEqual(fullPosition.tickInRow, directPosition.tickInRow)
        XCTAssertEqual(fullPosition.frame - fullBase.rowStartFrame, directPosition.frame)
    }

    @MainActor
    private func makeRuntimeCMixerPlaybackHarness(
        backend: RuntimeAudioBackend = .cMixer,
        sampleRate: Double = 100,
        channelCount: Int = 1,
        environment: [String: String] = [:]
    ) -> (
        engine: PlaybackEngine,
        audioEngine: RuntimeCMixerAudioEngine,
        traceWriter: TestRuntimeCMixerTraceWriter
    ) {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            backend: backend,
            sampleRate: sampleRate,
            channelCount: channelCount,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            songEndTailPolicy: RuntimeCMixerSongEndTailPolicy.resolve(environment: environment),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        return (
            PlaybackEngine(
                audioEngine: audioEngine,
                runtimeCMixerTraceWriter: traceWriter,
                startsRealtimeTimer: false,
                runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler(),
                environment: environment
            ),
            audioEngine,
            traceWriter
        )
    }

    @MainActor
    func testPlaybackEngineFirstPlayReportsRuntimeAdapterPlanGenerationTimeForBothHosts() throws {
        for backend in [RuntimeAudioBackend.cMixer, .cMixerCoreAudio] {
            let harness = makeRuntimeCMixerPlaybackHarness(backend: backend)
            let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 128), baseSampleRate: 100)
            harness.engine.load(song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [
                    2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]
                ],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
            ))

            let invalidated = try XCTUnwrap(harness.traceWriter.events.first { $0.runtimeAction == "adapter_plan_configured" })
            XCTAssertEqual(invalidated.runtimeAudioBackend, backend.diagnosticName)
            XCTAssertEqual(invalidated.adapterPlanGenerated, false)
            XCTAssertEqual(invalidated.plannedEventCount, 0)
            XCTAssertNil(invalidated.adapterPlanGenerationMS)
            XCTAssertFalse(harness.audioEngine.hasRuntimeAdapterEventPlan)

            harness.engine.play(from: nil)

            let configuredEvents = harness.traceWriter.events.filter { $0.runtimeAction == "adapter_plan_configured" }
            XCTAssertEqual(configuredEvents.count, 2)
            let configured = try XCTUnwrap(configuredEvents.last)
            XCTAssertEqual(configured.runtimeAudioBackend, backend.diagnosticName)
            XCTAssertEqual(configured.adapterPlanGenerated, true)
            XCTAssertEqual(configured.plannedEventCount, 1)
            XCTAssertGreaterThanOrEqual(configured.adapterPlanGenerationMS ?? -1, 0)
            XCTAssertTrue(harness.audioEngine.hasRuntimeAdapterEventPlan)
            XCTAssertNil(harness.traceWriter.events.first { $0.runtimeAction == "backend_prepared" })
            XCTAssertNil(harness.traceWriter.events.first { $0.runtimeAction == "backend_start" })
        }
    }

    @MainActor
    func testRuntimeCMixerSongEndTailSilencesBothRuntimeBackendsAndReportsDiagnostics() throws {
        for backend in [RuntimeAudioBackend.cMixer, .cMixerCoreAudio] {
            let traceWriter = TestRuntimeCMixerTraceWriter()
            let audioEngine = RuntimeCMixerAudioEngine(
                backend: backend,
                sampleRate: 10,
                channelCount: 1,
                outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                    RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
                ]),
                songEndTailPolicy: RuntimeCMixerSongEndTailPolicy(
                    tailSeconds: 0.2,
                    tailPolicy: "test_runtime_tail_seconds",
                    configurationWarning: nil
                ),
                startsOutputHostOnDemand: false,
                traceWriter: traceWriter
            )
            let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 10, loopStart: 0, loopLength: 2, loopType: 1)

            audioEngine.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0))
            audioEngine.configureAdapterEventScheduleForTesting([], runtimeFrameOffset: 0, plannedSongEndFrame: 2)

            let output = audioEngine.renderForTesting(frameCount: 6)
            XCTAssertPCMEqual(output, [1, 1, 1, 1, 0, 0])

            let snapshot = audioEngine.snapshotForTesting()
            XCTAssertEqual(audioEngine.runtimeAudioBackend, backend)
            XCTAssertEqual(snapshot.plannedSongEndFrame, 2)
            XCTAssertEqual(snapshot.runtimeTailFrames, 2)
            XCTAssertEqual(snapshot.songEndStopFrame, 4)
            XCTAssertEqual(snapshot.runtimeFrameAtPlannedSongEnd, 2)
            XCTAssertEqual(snapshot.runtimeFrameAtSongEndTailStop, 4)
            XCTAssertEqual(snapshot.activeVoiceCountAtPlannedSongEnd, 1)
            XCTAssertEqual(snapshot.loadedVoiceCountAtPlannedSongEnd, 1)
            XCTAssertEqual(snapshot.activeVoiceCountAtTailStop, 1)
            XCTAssertEqual(snapshot.loadedVoiceCountAtTailStop, 1)
            XCTAssertEqual(snapshot.activeVoiceCount, 0)
            XCTAssertEqual(snapshot.loadedVoiceCount, 0)
            XCTAssertTrue(snapshot.eventQueueExhausted)

            audioEngine.stopAll(context: nil, reason: "runtime_song_end_tail")
            let stopEvent = try XCTUnwrap(traceWriter.events.last { $0.runtimeAction == "c_mixer_clear_all" })
            XCTAssertEqual(stopEvent.runtimeAudioBackend, backend.diagnosticName)
            XCTAssertEqual(stopEvent.stopReason, "song_end_tail")
            XCTAssertEqual(stopEvent.runtimeFrameAtSongEndTailStop, 4)
            XCTAssertEqual(stopEvent.activeVoiceCountAtTailStop, 1)
            XCTAssertEqual(stopEvent.loadedVoiceCountAtTailStop, 1)
            XCTAssertEqual(stopEvent.eventQueueExhausted, true)
            XCTAssertEqual(stopEvent.captureCapTriggeredPlaybackStop, false)
        }
    }

    @MainActor
    func testRuntimeCMixerStopReasonDiagnosticsDistinguishDebugStopAndCaptureCap() throws {
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("debug-stop-capture-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: captureURL)
        }
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            sampleRate: 100,
            channelCount: 1,
            captureConfiguration: RuntimeCMixerCaptureConfiguration(
                url: captureURL,
                pathName: captureURL.lastPathComponent,
                seconds: 0.02,
                secondsPolicy: "env_runtime_capture_seconds",
                configurationWarning: nil
            ),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )

        _ = audioEngine.renderForTesting(frameCount: 3)
        audioEngine.stopAll(context: nil, reason: "debug_stop_after_seconds")

        let stopEvent = try XCTUnwrap(traceWriter.events.last { $0.runtimeAction == "c_mixer_clear_all" })
        let captureEvent = try XCTUnwrap(traceWriter.events.last { $0.runtimeAction == "capture_truncated" })

        XCTAssertEqual(stopEvent.stopReason, "debug_stop")
        XCTAssertEqual(stopEvent.captureCapTriggeredPlaybackStop, false)
        XCTAssertEqual(captureEvent.stopReason, "capture_cap_only")
        XCTAssertEqual(captureEvent.captureTruncated, true)
        XCTAssertEqual(captureEvent.captureCapTriggeredPlaybackStop, false)
    }

    @MainActor
    func testRuntimeCMixerDebugStopStillStopsPlaybackBeforeSongEndTail() throws {
        let harness = makeRuntimeCMixerPlaybackHarness(environment: [
            RuntimeCMixerSongEndTailPolicy.tailSecondsEnvironmentKey: "3"
        ])
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        harness.engine.stopFromDebugTimer()

        XCTAssertEqual(harness.engine.state.mode, .stopped)
        let stopEvent = try XCTUnwrap(harness.traceWriter.events.last { $0.runtimeAction == "c_mixer_clear_all" })
        XCTAssertEqual(stopEvent.stopReason, "debug_stop")
        XCTAssertNil(stopEvent.runtimeFrameAtSongEndTailStop)
    }

    @MainActor
    func testPlaybackEngineGenericAudioOutputPublishesTimerFollowPosition() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.play(from: nil)
        engine.advanceOneTick()

        XCTAssertEqual(positions, [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)
        ])
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(engine.currentPublishedFollowPosition?.position, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(engine.currentPublishedFollowPosition?.source, .playbackTimer)
    }

    @MainActor
    func testRuntimeCMixerPlaybackFollowPublishesSampleTimePosition() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 3],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))
        var positions = [PlaybackPosition]()
        harness.engine.positionDidChange = { positions.append($0) }

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 25)
        harness.engine.advanceOneTick()

        XCTAssertEqual(harness.engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(positions.last, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2))
        XCTAssertEqual(harness.engine.currentPublishedFollowPosition?.source, .cMixerSampleTime)
        XCTAssertEqual(harness.engine.currentPublishedFollowPosition?.position, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2))
        XCTAssertEqual(harness.engine.currentPublishedFollowPosition?.sampleTimeFrame, 25)
        XCTAssertEqual(harness.engine.currentPublishedFollowPosition?.syntheticRow, 2)
    }

    @MainActor
    func testRuntimeCMixerFollowPublicationContinuesAfterUnresolvedProviderResult() {
        let audioEngine = TestRuntimeFollowAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioEngine, startsRealtimeTimer: false)
        let row1 = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)
        let row2 = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2)
        audioEngine.followPositions = [
            nil,
            PlaybackFollowPosition(position: row1, tickInRow: 0, source: .cMixerSampleTime, sampleTimeFrame: 10, sampleTimeStatus: "in_range", syntheticRow: 1),
            PlaybackFollowPosition(position: row2, tickInRow: 0, source: .cMixerSampleTime, sampleTimeFrame: 20, sampleTimeStatus: "in_range", syntheticRow: 2)
        ]
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 3],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.play(from: nil)
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(positions.last, row2)
        XCTAssertEqual(engine.currentPublishedFollowPosition?.source, .cMixerSampleTime)
        XCTAssertEqual(audioEngine.recordedFollowEvents.first?.resolverFailureReason, "resolver_unresolved")
        XCTAssertNil(audioEngine.recordedFollowEvents.last?.resolverFailureReason)
    }

    @MainActor
    func testRuntimeCMixerTraceIncludesPublishedFollowPositionSource() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 3],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))
        var consumedPositions = [PlaybackPosition]()
        harness.engine.positionDidChange = { consumedPositions.append($0) }

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 25)
        harness.engine.advanceOneTick()

        let publishedEvents = harness.traceWriter.events.filter {
            $0.runtimeAction == "playback_follow_position_published"
        }
        let latest = publishedEvents.last
        XCTAssertEqual(latest?.publishedPlaybackFollowPositionSource, "c_mixer_sample_time")
        XCTAssertEqual(latest?.publishedPlaybackFollowOrderIndex, 0)
        XCTAssertEqual(latest?.publishedPlaybackFollowPatternIndex, 2)
        XCTAssertEqual(latest?.publishedPlaybackFollowRowIndex, 2)
        XCTAssertEqual(latest?.publishedPlaybackFollowTickInRow, 0)
        XCTAssertEqual(latest?.publishedPlaybackFollowSampleTimeFrame, 25)
        XCTAssertEqual(latest?.publishedPlaybackFollowSyntheticRow, 2)
        XCTAssertEqual(latest?.publishedPlaybackFollowToCMixerFrameDelta, 0)
        XCTAssertEqual(latest?.publishedPlaybackFollowToCMixerRowDelta, 0)
        XCTAssertEqual(latest?.playbackEngineToPublishedPlaybackFollowFrameDelta, 15)
        XCTAssertEqual(latest?.playbackEngineToPublishedPlaybackFollowRowDelta, 1)
        XCTAssertEqual(latest?.playbackEngineToCMixerFrameDelta, 15)
        XCTAssertEqual(latest?.followPublishedCount, 2)
        XCTAssertEqual(latest?.followConsumedCount, 2)
        XCTAssertEqual(latest?.followDroppedCount, 0)
        XCTAssertEqual(latest?.followSuppressedCount, 0)
        XCTAssertEqual(latest?.followUnresolvedPositionCount, 0)
        XCTAssertEqual(latest?.followLastPublishedOrder, 0)
        XCTAssertEqual(latest?.followLastPublishedRow, 2)
        XCTAssertEqual(latest?.followLastConsumedOrder, 0)
        XCTAssertEqual(latest?.followLastConsumedRow, 2)
        XCTAssertEqual(latest?.followSampleFrame, 25)
        XCTAssertNil(latest?.followResolverFailureReason)
        XCTAssertEqual(consumedPositions.last, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2))
    }

    @MainActor
    func testRuntimeCMixerFollowPublicationCanBeDisabledForDiagnostics() {
        let harness = makeRuntimeCMixerPlaybackHarness(environment: [
            RuntimeCMixerDiagnosticEnvironment.disableFollowPublicationEnvironmentKey: "1"
        ])
        var publishedPositions = [PlaybackPosition]()
        harness.engine.positionDidChange = { position in
            publishedPositions.append(position)
        }
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 25)
        harness.engine.advanceOneTick()

        XCTAssertTrue(publishedPositions.isEmpty)
        let latest = harness.traceWriter.events.last { $0.runtimeAction == "playback_follow_position_published" }
        XCTAssertEqual(latest?.playbackFollowPublicationDisabled, true)
        XCTAssertEqual(latest?.playbackFollowPublicationCount, 0)
        XCTAssertEqual(latest?.playbackFollowPublicationSuppressedCount, 2)
        XCTAssertEqual(latest?.followPublishedCount, 0)
        XCTAssertEqual(latest?.followConsumedCount, 0)
        XCTAssertEqual(latest?.followSuppressedCount, 2)
        XCTAssertEqual(latest?.followDroppedCount, 0)
    }

    @MainActor
    func testRuntimeCMixerHeldFollowPublishesSampleTimeAfterPlaybackTimerEnd() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        defer {
            harness.engine.stop()
        }
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3, 4],
            patternRowCounts: [2: 2, 3: 2, 4: 2],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))
        var positions = [PlaybackPosition]()
        harness.engine.positionDidChange = { positions.append($0) }

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 35)
        for _ in 0..<6 {
            harness.engine.advanceOneTick()
        }
        _ = harness.audioEngine.renderForTesting(frameCount: 20)
        harness.engine.publishRuntimeCMixerHeldFollowPositionForTesting()

        XCTAssertEqual(harness.engine.state.isPlaying, true)
        XCTAssertEqual(positions.last, PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 1))
        XCTAssertEqual(harness.engine.currentPublishedFollowPosition?.source, .cMixerSampleTime)
        XCTAssertEqual(harness.engine.currentPublishedFollowPosition?.sampleTimeFrame, 55)
    }

    @MainActor
    func testRuntimeCMixerStopPreservesPublishedSampleTimePosition() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 3],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 25)
        harness.engine.advanceOneTick()
        harness.engine.stop()

        XCTAssertEqual(harness.engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2))
        XCTAssertEqual(harness.traceWriter.events.last { $0.runtimeAction == "spacebarStop" }, nil)
        let stopEvent = harness.traceWriter.events.last { $0.runtimeAction == "stop" }
        XCTAssertEqual(stopEvent?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(stopEvent?.previousRowIndex, 1)
        XCTAssertEqual(stopEvent?.nextRowIndex, 2)
        XCTAssertEqual(stopEvent?.reason, "transport_stop_preserve_position")
    }

    @MainActor
    func testRuntimeCMixerConsumesPlannedNoteEventsInsteadOfSimpleRuntimeNotes() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let engine = PlaybackEngine(
            audioEngine: audioEngine,
            runtimeCMixerTraceWriter: traceWriter,
            startsRealtimeTimer: false
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 512), baseSampleRate: 44_100)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: nil)
        _ = audioEngine.renderForTesting(frameCount: 16)

        let addVoice = traceWriter.events.first { $0.runtimeAction == "c_mixer_add_voice" }
        XCTAssertEqual(addVoice?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(addVoice?.adapterPlanGenerated, true)
        XCTAssertEqual(addVoice?.adapterEventCategory, "note_trigger")
        XCTAssertEqual(addVoice?.plannedEventCount, 1)
        XCTAssertEqual(addVoice?.consumedPlannedEventCount, 1)
        XCTAssertEqual(addVoice?.runtimeEventCategory, "note_trigger")
        XCTAssertEqual(addVoice?.plannedEventFrame, 0)
        XCTAssertEqual(addVoice?.plannedRuntimeFrame, 0)
        XCTAssertEqual(addVoice?.plannedRuntimeFrameOffset, 0)
        XCTAssertEqual(addVoice?.runtimeApplicationFrame, 0)
        XCTAssertEqual(addVoice?.cMixerRenderedFrames, 0)
        XCTAssertEqual(addVoice?.cMixerPlaybackSeconds, 0)
        XCTAssertEqual(addVoice?.cMixerSampleTimeFrame, 0)
        XCTAssertEqual(addVoice?.cMixerSampleTimeOrderIndex, 0)
        XCTAssertEqual(addVoice?.cMixerSampleTimePatternIndex, 2)
        XCTAssertEqual(addVoice?.cMixerSampleTimeRowIndex, 0)
        XCTAssertEqual(addVoice?.cMixerSampleTimeTickInRow, 0)
        XCTAssertEqual(addVoice?.playbackEngineOrderIndex, 0)
        XCTAssertEqual(addVoice?.playbackEnginePatternIndex, 2)
        XCTAssertEqual(addVoice?.playbackEngineRowIndex, 0)
        XCTAssertEqual(addVoice?.playbackEngineTickInRow, 0)
        XCTAssertEqual(addVoice?.playbackEngineToCMixerFrameDelta, 0)
        XCTAssertEqual(addVoice?.playbackEngineToCMixerPositionMismatch, false)
        XCTAssertEqual(addVoice?.eventFrameDelta, 0)
        XCTAssertEqual(addVoice?.eventApplicationTiming, "exact_frame")
        XCTAssertNil(traceWriter.events.first { $0.runtimeAction == "note_trigger" })
    }

    @MainActor
    func testRuntimeCMixerScheduledNoteInsideCallbackAppliesAtExactOffset() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        let output = harness.audioEngine.renderForTesting(frameCount: 12)

        XCTAssertTrue(output[0..<10].allSatisfy { abs($0) < 0.000_001 })
        XCTAssertGreaterThan(abs(output[10]), 0.000_001)
        let addVoice = harness.traceWriter.events.first { $0.runtimeAction == "c_mixer_add_voice" }
        XCTAssertEqual(addVoice?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(addVoice?.adapterEventCategory, "note_trigger")
        XCTAssertEqual(addVoice?.plannedEventFrame, 10)
        XCTAssertEqual(addVoice?.plannedRuntimeFrame, 10)
        XCTAssertEqual(addVoice?.runtimeApplicationFrame, 10)
        XCTAssertEqual(addVoice?.eventAppliedFrame, 10)
        XCTAssertEqual(addVoice?.inCallbackOffset, 10)
        XCTAssertEqual(addVoice?.cMixerRenderedFrames, 10)
        XCTAssertEqual(addVoice?.cMixerPlaybackSeconds ?? -1, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(addVoice?.cMixerSampleTimeFrame, 10)
        XCTAssertEqual(addVoice?.cMixerSampleTimeRowIndex, 1)
        XCTAssertEqual(addVoice?.cMixerSampleTimeTickInRow, 0)
        XCTAssertEqual(addVoice?.playbackEngineToCMixerFrameDelta, 0)
        XCTAssertEqual(addVoice?.playbackEngineToCMixerPositionMismatch, false)
        XCTAssertEqual(addVoice?.plannedVsAppliedDelta, 0)
        XCTAssertEqual(addVoice?.eventApplicationTiming, "exact_frame")
        XCTAssertEqual(addVoice?.callbackStartFrame, 0)
        XCTAssertEqual(addVoice?.callbackEndFrame, 12)
        XCTAssertEqual(addVoice?.exactFrameAppliedEventCount, 1)
        XCTAssertEqual(addVoice?.callbackBoundaryAppliedEventCount, 0)
        XCTAssertEqual(addVoice?.latePlannedEventCount, 0)
        XCTAssertEqual(addVoice?.maxPlannedVsAppliedDelta, 0)
    }

    @MainActor
    func testRuntimeCMixerEventsAfterCallbackRemainQueuedUntilTheirFrame() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        let firstCallback = harness.audioEngine.renderForTesting(frameCount: 10)

        XCTAssertTrue(firstCallback.allSatisfy { abs($0) < 0.000_001 })
        XCTAssertNil(harness.traceWriter.events.first { $0.runtimeAction == "c_mixer_add_voice" })
        XCTAssertEqual(
            harness.traceWriter.events.first { $0.runtimeAction == "adapter_event_schedule_configured" }?.eventQueueBacklogCount,
            1
        )

        _ = harness.audioEngine.renderForTesting(frameCount: 1)

        let addVoice = harness.traceWriter.events.first { $0.runtimeAction == "c_mixer_add_voice" }
        XCTAssertEqual(addVoice?.plannedRuntimeFrame, 10)
        XCTAssertEqual(addVoice?.eventAppliedFrame, 10)
        XCTAssertEqual(addVoice?.inCallbackOffset, 0)
        XCTAssertEqual(addVoice?.plannedVsAppliedDelta, 0)
        XCTAssertEqual(addVoice?.eventApplicationTiming, "exact_frame")
        XCTAssertEqual(addVoice?.callbackStartFrame, 10)
        XCTAssertEqual(addVoice?.callbackEndFrame, 11)
    }

    @MainActor
    func testRuntimeCMixerStopAllowsPlannedScheduleToBeConfiguredAgain() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 12)
        harness.engine.stop()
        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 12)

        let configuredEvents = harness.traceWriter.events.filter {
            $0.runtimeAction == "adapter_event_schedule_configured"
        }
        let addVoiceEvents = harness.traceWriter.events.filter {
            $0.runtimeAction == "c_mixer_add_voice"
        }

        XCTAssertEqual(configuredEvents.count, 2)
        XCTAssertEqual(addVoiceEvents.count, 2)
        XCTAssertEqual(addVoiceEvents.map(\.plannedRuntimeFrame), [10, 10])
        XCTAssertEqual(addVoiceEvents.map(\.eventAppliedFrame), [10, 10])
        XCTAssertEqual(addVoiceEvents.map(\.plannedVsAppliedDelta), [0, 0])
    }

    @MainActor
    func testRuntimeCMixerSameFrameBurstAppliesInDeterministicOrder() {
        let harness = makeRuntimeCMixerPlaybackHarness(channelCount: 2)
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                        PlaybackCell(note: 53, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 1)

        let addVoices = harness.traceWriter.events.filter { $0.runtimeAction == "c_mixer_add_voice" }
        XCTAssertEqual(addVoices.map(\.channelIndex), [0, 1])
        XCTAssertEqual(addVoices.map(\.plannedRuntimeFrame), [0, 0])
        XCTAssertEqual(addVoices.map(\.eventAppliedFrame), [0, 0])
        XCTAssertEqual(addVoices.map(\.sameFrameBurstSize), [2, 2])
        XCTAssertEqual(addVoices.map(\.plannedVsAppliedDelta), [0, 0])
    }

    @MainActor
    func testRuntimeCMixerOrderBoundarySustainedVoiceUpdatePrecedesSameFrameNewNote() {
        let harness = makeRuntimeCMixerPlaybackHarness(channelCount: 2)
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 256), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ],
                3: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 0, instrument: 0, volumeColumn: 0x20, effectType: 0, effectParam: 0),
                        PlaybackCell(note: 53, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 12)

        let sameFrameEvents = harness.traceWriter.events.filter {
            $0.eventAppliedFrame == 10 &&
                ["c_mixer_update_gain_pan_applied", "c_mixer_add_voice"].contains($0.runtimeAction)
        }
        XCTAssertEqual(sameFrameEvents.map(\.runtimeAction), [
            "c_mixer_update_gain_pan_applied",
            "c_mixer_add_voice"
        ])

        let gainUpdate = sameFrameEvents.first
        XCTAssertEqual(gainUpdate?.sameFrameBurstID, 10)
        XCTAssertEqual(gainUpdate?.sameFrameBurstEventOrdinal, 1)
        XCTAssertEqual(gainUpdate?.sameFrameBurstSize, 2)
        XCTAssertTrue(gainUpdate?.sameFrameBurstCategories?.contains("gain_pan_update") == true)
        XCTAssertTrue(gainUpdate?.sameFrameBurstCategories?.contains("note_trigger") == true)
        XCTAssertEqual(gainUpdate?.sameFrameBurstAffectedChannels, [0, 1])
        XCTAssertEqual(gainUpdate?.sameFrameBurstGainPanUpdateCount, 1)
        XCTAssertEqual(gainUpdate?.sameFrameBurstNoteTriggerCount, 1)
        XCTAssertEqual(gainUpdate?.sameFrameBurstReplacementRampCount, 0)
        XCTAssertEqual(gainUpdate?.sameFrameBurstActiveVoiceCountBefore, 1)
        XCTAssertEqual(gainUpdate?.sameFrameBurstActiveVoiceCountAfter, 2)
        XCTAssertEqual(gainUpdate?.sameFrameBurstNewVoicesStarted, 1)
        XCTAssertEqual(gainUpdate?.sameFrameBurstSustainedVoicesCarried, 1)
        XCTAssertEqual(gainUpdate?.sameFrameBurstAtOrderStart, true)
        XCTAssertEqual(gainUpdate?.sameFrameBurstAtRowTransition, true)
        XCTAssertEqual(gainUpdate?.adapterActiveEventIndex, 0)
        XCTAssertEqual(gainUpdate?.adapterCurrentEventIndexBefore, 0)
        XCTAssertEqual(gainUpdate?.adapterCurrentEventIndexAfter, 0)
        XCTAssertEqual(gainUpdate?.adapterChannelAssociationRetained, true)
        XCTAssertEqual(gainUpdate?.adapterSustainedVoiceUpdate, true)

        let noteTrigger = sameFrameEvents.dropFirst().first
        XCTAssertEqual(noteTrigger?.sameFrameBurstEventOrdinal, 2)
        XCTAssertEqual(noteTrigger?.sameFrameBurstID, 10)
        XCTAssertEqual(noteTrigger?.adapterSustainedVoiceUpdate, false)
        XCTAssertEqual(noteTrigger?.plannedVsAppliedDelta, 0)
    }

    @MainActor
    func testRuntimeCMixerConsumesPlannedGainPanAndStepUpdates() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let engine = PlaybackEngine(
            audioEngine: audioEngine,
            runtimeCMixerTraceWriter: traceWriter,
            startsRealtimeTimer: false
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 512), baseSampleRate: 44_100)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x01, effectParam: 0x02),
                    makePlaybackRow(index: 1, volumeColumn: 0x20)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 125)
        ))

        engine.play(from: nil)
        _ = audioEngine.renderForTesting(frameCount: 4_096)

        let stepUpdate = traceWriter.events.first { $0.runtimeAction == "c_mixer_update_step_applied" }
        XCTAssertEqual(stepUpdate?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(stepUpdate?.adapterEventCategory, "step_update")
        XCTAssertEqual(stepUpdate?.updateDisposition, "update_applied")

        let gainUpdate = traceWriter.events.first { $0.runtimeAction == "c_mixer_update_gain_pan_applied" }
        XCTAssertEqual(gainUpdate?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(gainUpdate?.adapterEventCategory, "gain_pan_update")
        XCTAssertEqual(gainUpdate?.runtimeEventCategory, "gain_pan_update")
        XCTAssertEqual(gainUpdate?.updateDisposition, "update_applied")
        XCTAssertNotNil(gainUpdate?.plannedEventFrame)
        XCTAssertNotNil(gainUpdate?.runtimeApplicationFrame)
        XCTAssertTrue(gainUpdate?.adapterEventCategoriesConsumed?.contains("volume_column_update") == true)
    }

    @MainActor
    func testRuntimeCMixerGainPanUpdateAppliesAtExactOffset() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, volumeColumn: 0x20)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 12)

        let gainUpdate = harness.traceWriter.events.first { $0.runtimeAction == "c_mixer_update_gain_pan_applied" }
        XCTAssertEqual(gainUpdate?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(gainUpdate?.adapterEventCategory, "gain_pan_update")
        XCTAssertEqual(gainUpdate?.runtimeEventCategory, "gain_pan_update")
        XCTAssertEqual(gainUpdate?.plannedRuntimeFrame, 10)
        XCTAssertEqual(gainUpdate?.eventAppliedFrame, 10)
        XCTAssertEqual(gainUpdate?.inCallbackOffset, 10)
        XCTAssertEqual(gainUpdate?.plannedVsAppliedDelta, 0)
        XCTAssertEqual(gainUpdate?.eventApplicationTiming, "exact_frame")
    }

    @MainActor
    func testRuntimeCMixerStepUpdateAppliesAtExactOffset() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x01, effectParam: 0x02)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 12)

        let stepUpdate = harness.traceWriter.events.first { $0.runtimeAction == "c_mixer_update_step_applied" }
        XCTAssertEqual(stepUpdate?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(stepUpdate?.adapterEventCategory, "step_update")
        XCTAssertEqual(stepUpdate?.runtimeEventCategory, "step_pitch_update")
        XCTAssertEqual(stepUpdate?.plannedRuntimeFrame, 10)
        XCTAssertEqual(stepUpdate?.eventAppliedFrame, 10)
        XCTAssertEqual(stepUpdate?.inCallbackOffset, 10)
        XCTAssertEqual(stepUpdate?.plannedVsAppliedDelta, 0)
        XCTAssertEqual(stepUpdate?.eventApplicationTiming, "exact_frame")
    }

    @MainActor
    func testRuntimeCMixerReplacementRampAppliesAtExactOffset() {
        let harness = makeRuntimeCMixerPlaybackHarness()
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        harness.engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        ))

        harness.engine.play(from: nil)
        _ = harness.audioEngine.renderForTesting(frameCount: 12)

        let replacementStop = harness.traceWriter.events.first {
            $0.runtimeAction == "c_mixer_stop_channel_ramped" && $0.reason == "note_replacement_stop_channel"
        }
        XCTAssertEqual(replacementStop?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(replacementStop?.adapterEventCategory, "replacement")
        XCTAssertEqual(replacementStop?.runtimeEventCategory, "replacement_stop_ramp")
        XCTAssertEqual(replacementStop?.plannedRuntimeFrame, 10)
        XCTAssertEqual(replacementStop?.eventAppliedFrame, 10)
        XCTAssertEqual(replacementStop?.inCallbackOffset, 10)
        XCTAssertEqual(replacementStop?.plannedVsAppliedDelta, 0)
        XCTAssertEqual(replacementStop?.eventApplicationTiming, "exact_frame")
    }

    @MainActor
    func testRuntimeCMixerFallsBackClearlyWhenAdapterPlanIsUnavailable() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = RuntimeCMixerAudioEngine(
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 16), baseSampleRate: 44_100)

        engine.trigger(
            AudioVoiceRequest(sample: sample, note: 49, channel: 0),
            context: AudioRuntimeTraceContext(orderIndex: 0, patternIndex: 2, rowIndex: 0, tickInRow: 0, channelIndex: 0)
        )

        let addVoice = traceWriter.events.first { $0.runtimeAction == "c_mixer_add_voice" }
        XCTAssertEqual(addVoice?.runtimeEventSource, "playback_engine_simple")
        XCTAssertEqual(addVoice?.adapterPlanGenerated, false)
        XCTAssertEqual(addVoice?.plannedEventCount, 0)
        XCTAssertEqual(addVoice?.fallbackToSimpleRuntimeEventCount, 1)
        XCTAssertEqual(addVoice?.runtimeEventFallbackReason, "adapter_plan_unavailable")
    }

    @MainActor
    func testPlaybackAudioOutputFactoryTracesUnknownBackendFallback() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let output = PlaybackAudioOutputFactory.make(
            environment: [RuntimeAudioBackendSelection.environmentKey: "raw_core_audio"],
            runtimeCMixerTraceWriter: traceWriter
        )

        XCTAssertTrue(output is RuntimeCMixerAudioEngine)
        XCTAssertEqual(traceWriter.events.first?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(traceWriter.events.first?.backendFlagValue, "raw_core_audio")
        XCTAssertEqual(traceWriter.events.first?.fallbackReason, "unknown_backend")
        XCTAssertEqual(traceWriter.events.first?.runtimeOutputHostType, "coreaudio_default_output_unit")
    }

    func testRuntimeCMixerRenderCoreRendersTriggeredSampleAndStops() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            maximumRenderFrames: 16
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1, 0.5, 0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 44_100
        )
        let request = AudioVoiceRequest(sample: sample, note: 49, channel: 0)

        XCTAssertTrue(core.trigger(request))
        var output = Array(repeating: Float(0), count: 6)
        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 3))
        }

        let gain = RuntimeCMixerOutputPolicy.defaultPolicy.outputGain
        XCTAssertEqual(output, [gain, gain, 0.5 * gain, 0.5 * gain, 0.25 * gain, 0.25 * gain])

        core.stopAll()
        var silentOutput = Array(repeating: Float(1), count: 6)
        silentOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 3))
        }
        XCTAssertTrue(silentOutput.allSatisfy { abs($0) < 0.000_001 })

        for _ in 0..<3 {
            XCTAssertTrue(core.trigger(request))
            core.stopAll()
        }
    }

    func testRuntimeCMixerCaptureDoesNotChangeRenderedSampleValues() {
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("unchanged-capture-\(UUID().uuidString).wav")
        let captureConfiguration = RuntimeCMixerCaptureConfiguration(
            url: captureURL,
            pathName: captureURL.lastPathComponent,
            seconds: 1,
            secondsPolicy: "env_runtime_capture_seconds",
            configurationWarning: nil
        )
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)
        let outputPolicy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
        ])
        let baseline = RuntimeCMixerRenderCore(config: config, maximumRenderFrames: 16, outputPolicy: outputPolicy)
        let captured = RuntimeCMixerRenderCore(
            config: config,
            maximumRenderFrames: 16,
            outputPolicy: outputPolicy,
            captureConfiguration: captureConfiguration
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, 0.5, 0.75],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 100
        )
        let request = AudioVoiceRequest(sample: sample, note: 49, channel: 0)

        XCTAssertTrue(baseline.trigger(request))
        XCTAssertTrue(captured.trigger(request))
        let baselineOutput = renderRuntimePCM(baseline, frames: 3)
        let capturedOutput = renderRuntimePCM(captured, frames: 3)

        XCTAssertPCMEqual(capturedOutput, baselineOutput)
        XCTAssertPCMEqual(captured.captureBlockSnapshotForWriting()?.block.interleavedPCM ?? [], capturedOutput)
    }

    @MainActor
    func testRuntimeCMixerAudioEngineWritesCaptureOnStopAndReportsDiagnostics() throws {
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("engine-capture-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: captureURL)
        }
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let captureConfiguration = RuntimeCMixerCaptureConfiguration(
            url: captureURL,
            pathName: captureURL.lastPathComponent,
            seconds: 1,
            secondsPolicy: "env_runtime_capture_seconds",
            configurationWarning: nil
        )
        let audioEngine = RuntimeCMixerAudioEngine(
            sampleRate: 100,
            channelCount: 1,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            captureConfiguration: captureConfiguration,
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )

        _ = audioEngine.renderForTesting(frameCount: 2)
        audioEngine.stopAll()

        let captureEvent = try XCTUnwrap(traceWriter.events.first { $0.runtimeAction == "capture_written" })
        XCTAssertEqual(captureEvent.runtimeCaptureEnabled, true)
        XCTAssertEqual(captureEvent.runtimeCapturePathName, captureURL.lastPathComponent)
        XCTAssertEqual(captureEvent.runtimeCaptureSampleRate, 100)
        XCTAssertEqual(captureEvent.runtimeCaptureChannelCount, 1)
        XCTAssertEqual(captureEvent.runtimeCapturedFrameCount, 2)
        XCTAssertEqual(captureEvent.runtimeCaptureDurationSeconds, 0.02)
        XCTAssertEqual(captureEvent.runtimeCaptureTruncated, false)
        XCTAssertEqual(captureEvent.runtimeCaptureOutputPeak, 0)
        XCTAssertEqual(captureEvent.runtimeCaptureClippingSampleCount, 0)
        XCTAssertEqual(captureEvent.runtimeCaptureWriteSucceeded, true)
        XCTAssertNil(captureEvent.runtimeCaptureWriteError)

        let wav = try parsePCM16WAV(Data(contentsOf: captureURL))
        XCTAssertEqual(wav.sampleRate, 100)
        XCTAssertEqual(wav.channelCount, 1)
        XCTAssertEqual(wav.samples, [0, 0])
    }

    @MainActor
    func testRuntimeCMixerAudioEngineTracesCaptureTruncation() throws {
        let captureURL = FileManager.default.temporaryDirectory.appendingPathComponent("engine-truncated-capture-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: captureURL)
        }
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let captureConfiguration = RuntimeCMixerCaptureConfiguration(
            url: captureURL,
            pathName: captureURL.lastPathComponent,
            seconds: 0.02,
            secondsPolicy: "env_runtime_capture_seconds",
            configurationWarning: nil
        )
        let audioEngine = RuntimeCMixerAudioEngine(
            sampleRate: 100,
            channelCount: 1,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            captureConfiguration: captureConfiguration,
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )

        _ = audioEngine.renderForTesting(frameCount: 3)
        audioEngine.stopAll()

        let captureEvent = try XCTUnwrap(traceWriter.events.first { $0.runtimeAction == "capture_truncated" })
        XCTAssertEqual(captureEvent.runtimeCaptureFrameLimit, 2)
        XCTAssertEqual(captureEvent.runtimeCapturedFrameCount, 2)
        XCTAssertEqual(captureEvent.runtimeCaptureTruncated, true)
        XCTAssertEqual(captureEvent.runtimeCaptureWriteSucceeded, true)

        let wav = try parsePCM16WAV(Data(contentsOf: captureURL))
        XCTAssertEqual(wav.samples, [0, 0])
    }

    func testRuntimeCMixerRenderCoreDiagnosticsInitializeCleanly() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2),
            maximumRenderFrames: 16
        )

        let snapshot = core.snapshot()

        XCTAssertEqual(snapshot.sampleRate, 48_000)
        XCTAssertEqual(snapshot.channelCount, 2)
        XCTAssertEqual(snapshot.activeVoiceCount, 0)
        XCTAssertEqual(snapshot.loadedVoiceCount, 0)
        XCTAssertEqual(snapshot.scheduledVoiceCount, 0)
        XCTAssertEqual(snapshot.eventQueueBacklogCount, 0)
        XCTAssertEqual(snapshot.renderCallbackCount, 0)
        XCTAssertEqual(snapshot.renderCallCount, 0)
        XCTAssertEqual(snapshot.successfulRenderCount, 0)
        XCTAssertEqual(snapshot.failedRenderCount, 0)
        XCTAssertNil(snapshot.requestedFrameCount)
        XCTAssertEqual(snapshot.cumulativeRequestedFrameCount, 0)
        XCTAssertEqual(snapshot.renderedFrameCount, 0)
        XCTAssertNil(snapshot.callbackIndex)
        XCTAssertNil(snapshot.callbackRequestedFrameCount)
        XCTAssertNil(snapshot.callbackStartFrame)
        XCTAssertNil(snapshot.callbackEndFrame)
        XCTAssertNil(snapshot.minRequestedFrameCount)
        XCTAssertNil(snapshot.maxRequestedFrameCount)
        XCTAssertEqual(snapshot.zeroFillCount, 0)
        XCTAssertEqual(snapshot.underrunCount, 0)
        XCTAssertEqual(snapshot.silentOutputCallbackCount, 0)
        XCTAssertEqual(snapshot.unexpectedSilentOutputCount, 0)
        XCTAssertEqual(snapshot.outputPeak, 0)
        XCTAssertEqual(snapshot.outputRMS, 0)
        XCTAssertEqual(snapshot.outputDiscontinuityThreshold, RuntimeCMixerRenderCore.outputDiscontinuityThreshold)
        XCTAssertEqual(snapshot.outputDiscontinuityCount, 0)
        XCTAssertEqual(snapshot.outputDiscontinuityThresholdCounts.map(\.count), [0, 0, 0, 0])
        XCTAssertEqual(snapshot.maxOutputAdjacentSampleJump, 0)
        XCTAssertEqual(snapshot.topOutputAdjacentSampleJumps, [])
        XCTAssertNil(snapshot.lastOutputDiscontinuitySampleJump)
        XCTAssertNil(snapshot.lastOutputDiscontinuityCallbackIndex)
        XCTAssertNil(snapshot.lastOutputDiscontinuityRuntimeFrame)
        XCTAssertNil(snapshot.lastOutputDiscontinuityFrameOffset)
        XCTAssertNil(snapshot.lastOutputDiscontinuityChannelIndex)
        XCTAssertEqual(snapshot.outputPeakWarningThreshold, RuntimeCMixerRenderCore.outputPeakWarningThreshold)
        XCTAssertEqual(snapshot.outputPeakWarningSampleCount, 0)
        XCTAssertEqual(snapshot.topOutputPeaks, [])
        XCTAssertEqual(snapshot.overrangeSampleCount, 0)
        XCTAssertEqual(snapshot.clippingSampleCount, 0)
        XCTAssertEqual(snapshot.clippingDetected, false)
        XCTAssertEqual(snapshot.runtimeOutputGain, RuntimeCMixerOutputPolicy.defaultPolicy.outputGain)
        XCTAssertEqual(snapshot.runtimeHeadroomPolicy, "default_runtime_headroom_db")
        XCTAssertEqual(snapshot.runtimeDefaultHeadroomDB, -12)
        XCTAssertEqual(snapshot.runtimeGainPolicySource, "default")
        XCTAssertEqual(snapshot.runtimeGainPolicyIsEnvironmentOverride, false)
        XCTAssertEqual(snapshot.runtimeAutoHeadroomEnabled, false)
        XCTAssertEqual(snapshot.runtimeFixedHeadroomDB, RuntimeCMixerOutputPolicy.defaultHeadroomDB)
        XCTAssertNil(snapshot.runtimeClippingRecommendation)
        XCTAssertEqual(snapshot.runtimeUpdateEpsilon, RuntimeCMixerRenderCore.updateEpsilon)
        XCTAssertEqual(snapshot.runtimeUpdateEpsilonPolicy, "default_runtime_update_epsilon")
        XCTAssertNil(snapshot.runtimeUpdateEpsilonConfigurationWarning)
        XCTAssertEqual(snapshot.capture, .disabled)
        XCTAssertEqual(snapshot.appliedPlannedEventCount, 0)
        XCTAssertEqual(snapshot.exactFrameAppliedEventCount, 0)
        XCTAssertEqual(snapshot.callbackBoundaryAppliedEventCount, 0)
        XCTAssertEqual(snapshot.latePlannedEventCount, 0)
        XCTAssertEqual(snapshot.maxPlannedVsAppliedDelta, 0)
        XCTAssertEqual(snapshot.rampingOutVoiceCount, 0)
        XCTAssertEqual(snapshot.rampDownStartCount, 0)
        XCTAssertEqual(snapshot.rampDownCompletionCount, 0)
        XCTAssertEqual(snapshot.abruptRampDownStopCount, 0)
        XCTAssertEqual(snapshot.callbackDurationWarningThresholdMS, 2)
        XCTAssertNil(snapshot.callbackDurationMinMS)
        XCTAssertNil(snapshot.callbackDurationMaxMS)
        XCTAssertNil(snapshot.callbackDurationAverageMS)
        XCTAssertNil(snapshot.callbackMaxDurationMS)
        XCTAssertNil(snapshot.callbackAvgDurationMS)
        XCTAssertEqual(snapshot.callbackDurationWarningCount, 0)
        XCTAssertNil(snapshot.callbackRenderQuantumDurationMS)
        XCTAssertEqual(snapshot.callbackOverRenderQuantumBudgetCount, 0)
        XCTAssertEqual(snapshot.callbackNearBudgetWarningCount, 0)
        XCTAssertNil(snapshot.callbackIntervalMinMS)
        XCTAssertNil(snapshot.callbackIntervalMaxMS)
        XCTAssertNil(snapshot.callbackIntervalLastMS)
        XCTAssertFalse(snapshot.callbackAllocationWarning)
        XCTAssertTrue(snapshot.callbackRealtimeSafeDiagnostics)
        XCTAssertEqual(snapshot.callbackDiagnosticDropCount, 0)
        XCTAssertEqual(snapshot.callbackRingBufferCapacity, RuntimeCMixerRenderCore.callbackDiagnosticRingCapacity)
        XCTAssertEqual(snapshot.callbackLockFailureCount, 0)
        XCTAssertEqual(snapshot.callbackLockAttemptCount, 0)
        XCTAssertEqual(snapshot.callbackTryLockFailureCount, 0)
        XCTAssertNil(snapshot.callbackLockFailureAudioImpact)
        XCTAssertEqual(snapshot.callbackRenderedFromStaleSnapshotCount, 0)
        XCTAssertEqual(snapshot.callbackRenderedSilenceDueToUnavailableStateCount, 0)
        XCTAssertEqual(snapshot.callbackSkippedDiagnosticsDueToLockCount, 0)
        XCTAssertEqual(snapshot.callbackSkippedAudioDueToLockCount, 0)
        XCTAssertEqual(snapshot.lifecycleChangeWhileRenderingCount, 0)
        XCTAssertEqual(snapshot.audioUnitLifecycleCallWhileCallbackActiveCount, 0)
        XCTAssertEqual(snapshot.runtimeMinimalCallbackMode, false)
        XCTAssertEqual(snapshot.outputBufferCopyAttemptCount, 0)
        XCTAssertEqual(snapshot.outputBufferCopyFailureCount, 0)
        XCTAssertNil(snapshot.outputBufferCopyLastSucceeded)
        XCTAssertNil(snapshot.outputBufferCopyScratchHash)
        XCTAssertNil(snapshot.outputBufferCopyOutputHash)
    }

    func testRuntimeCMixerFixedRingBufferRecordsDeterministically() {
        var ring = RuntimeCMixerFixedRingBuffer<Int>(capacity: 3)

        ring.record(1)
        ring.record(2)
        XCTAssertEqual(ring.drain(), [1, 2])
        XCTAssertTrue(ring.isEmpty)
        XCTAssertEqual(ring.droppedCount, 0)

        ring.record(3)
        ring.record(4)
        XCTAssertEqual(ring.drain(), [3, 4])
        XCTAssertEqual(ring.capacity, 3)
    }

    func testRuntimeCMixerFixedRingBufferDropsAndReportsWhenFull() {
        var ring = RuntimeCMixerFixedRingBuffer<String>(capacity: 2)

        ring.record("a")
        ring.record("b")
        ring.record("c")

        XCTAssertEqual(ring.count, 2)
        XCTAssertEqual(ring.droppedCount, 1)
        XCTAssertEqual(ring.drain(), ["a", "b"])
        XCTAssertEqual(ring.droppedCount, 1)
    }

    func testRuntimeCMixerNormalRenderReportsRealtimeSafeCallbackDiagnostics() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )

        _ = renderRuntimePCM(core, frames: 4)

        let snapshot = core.snapshot()
        XCTAssertFalse(snapshot.callbackAllocationWarning)
        XCTAssertTrue(snapshot.callbackRealtimeSafeDiagnostics)
        XCTAssertEqual(snapshot.callbackDiagnosticDropCount, 0)
        XCTAssertEqual(snapshot.callbackRingBufferCapacity, RuntimeCMixerRenderCore.callbackDiagnosticRingCapacity)
        XCTAssertEqual(snapshot.callbackLockWaitCount, 0)
        XCTAssertEqual(snapshot.callbackLockFailureCount, 0)
    }

    func testRuntimeCMixerCoreAudioCallbackRecordsRealtimeAndCopyDiagnostics() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: [1, 0.5], baseSampleRate: 1_000)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))

        var output = Array(repeating: Float(-1), count: 4)
        output.withUnsafeMutableBufferPointer { outputBuffer in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(outputBuffer.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(outputBuffer.baseAddress)
            )
            var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            let status = withUnsafeMutablePointer(to: &audioBufferList) { listPointer in
                core.render(frameCount: 2, ioData: listPointer)
            }
            XCTAssertEqual(status, noErr)
        }

        XCTAssertPCMEqual(output, [1, 1, 0.5, 0.5])
        let snapshot = core.snapshot()
        XCTAssertFalse(snapshot.callbackAllocationWarning)
        XCTAssertTrue(snapshot.callbackRealtimeSafeDiagnostics)
        XCTAssertEqual(snapshot.callbackLockWaitCount, 0)
        XCTAssertEqual(snapshot.callbackLockFailureCount, 0)
        XCTAssertNotNil(snapshot.callbackDurationMaxMS)
        XCTAssertEqual(snapshot.outputBufferCopyAttemptCount, 1)
        XCTAssertEqual(snapshot.outputBufferCopyFailureCount, 0)
        XCTAssertEqual(snapshot.outputBufferCopyLastSucceeded, true)
        XCTAssertEqual(snapshot.outputBufferCopyLayout, "single_interleaved_buffer")
    }

    func testRuntimeCMixerCoreAudioCallbackLockFailureReusesLastOutputWithoutSkippingAudio() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: [0.25, 0.5, 0.75, 1], baseSampleRate: 1_000)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        XCTAssertPCMEqual(renderCoreAudioRuntimePCM(core, frames: 2), [0.25, 0.5])

        var lockedOutput = [Float]()
        core.withRenderLockHeldForTesting {
            lockedOutput = renderCoreAudioRuntimePCM(core, frames: 2, initialValue: -1)
        }

        XCTAssertPCMEqual(lockedOutput, [0.25, 0.5])
        let snapshot = core.snapshot()
        XCTAssertEqual(snapshot.callbackLockAttemptCount, 2)
        XCTAssertEqual(snapshot.callbackTryLockFailureCount, 1)
        XCTAssertEqual(snapshot.callbackLockFailureCount, 1)
        XCTAssertEqual(snapshot.callbackRenderedFromStaleSnapshotCount, 1)
        XCTAssertEqual(snapshot.callbackSkippedAudioDueToLockCount, 0)
        XCTAssertEqual(snapshot.callbackRenderedSilenceDueToUnavailableStateCount, 0)
        XCTAssertEqual(snapshot.callbackSkippedDiagnosticsDueToLockCount, 1)
        XCTAssertEqual(snapshot.callbackLockFailureAudioImpact, true)
        XCTAssertEqual(snapshot.renderCallbackCount, 1)
        XCTAssertEqual(snapshot.successfulRenderCount, 1)
        XCTAssertEqual(snapshot.failedRenderCount, 0)
    }

    func testRuntimeCMixerCoreAudioCallbackLockFailureCountsUnavailableStateSilence() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            maximumRenderFrames: 16
        )

        var lockedOutput = [Float]()
        core.withRenderLockHeldForTesting {
            lockedOutput = renderCoreAudioRuntimePCM(core, frames: 2, initialValue: -1)
        }

        XCTAssertPCMEqual(lockedOutput, [0, 0])
        let snapshot = core.snapshot()
        XCTAssertEqual(snapshot.callbackLockAttemptCount, 1)
        XCTAssertEqual(snapshot.callbackTryLockFailureCount, 1)
        XCTAssertEqual(snapshot.callbackRenderedFromStaleSnapshotCount, 0)
        XCTAssertEqual(snapshot.callbackRenderedSilenceDueToUnavailableStateCount, 1)
        XCTAssertEqual(snapshot.callbackSkippedAudioDueToLockCount, 0)
        XCTAssertEqual(snapshot.callbackLockFailureAudioImpact, true)
        XCTAssertEqual(snapshot.successfulRenderCount, 0)
        XCTAssertEqual(snapshot.failedRenderCount, 0)
    }

    func testRuntimeCMixerCallbackDiagnosticDrainSkipsInsteadOfBlockingOnRenderLock() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            maximumRenderFrames: 16
        )

        var drained: [RuntimeCMixerAppliedAdapterEventDiagnostic] = []
        core.withRenderLockHeldForTesting {
            drained = core.drainAppliedAdapterEventDiagnostics()
        }

        XCTAssertTrue(drained.isEmpty)
        XCTAssertEqual(core.snapshot().callbackSkippedDiagnosticsDueToLockCount, 1)
    }

    func testRuntimeCMixerLifecycleCountersReportRenderActiveOverlap() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1),
            maximumRenderFrames: 16
        )

        core.withRenderCallbackActiveForTesting {
            _ = core.configureAdapterEventSchedule([], runtimeFrameOffset: 0)
            core.recordAudioUnitLifecycleCallIfCallbackActive()
        }

        let snapshot = core.snapshot()
        XCTAssertEqual(snapshot.lifecycleChangeWhileRenderingCount, 1)
        XCTAssertEqual(snapshot.audioUnitLifecycleCallWhileCallbackActiveCount, 1)
    }

    func testRuntimeCMixerCallbackRealtimeDiagnosticsUpdateCounters() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
            maximumRenderFrames: 16
        )

        core.recordCallbackRealtimeDiagnosticsForTesting(
            durationSeconds: 0.001,
            requestedFrameCount: 10,
            intervalSeconds: nil
        )
        core.recordCallbackRealtimeDiagnosticsForTesting(
            durationSeconds: 0.012,
            requestedFrameCount: 10,
            intervalSeconds: 0.010
        )

        let snapshot = core.snapshot()
        XCTAssertEqual(snapshot.callbackDurationMinMS ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackDurationMaxMS ?? -1, 12, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackDurationAverageMS ?? -1, 6.5, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackMaxDurationMS ?? -1, 12, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackAvgDurationMS ?? -1, 6.5, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackDurationWarningCount, 1)
        XCTAssertEqual(snapshot.callbackRenderQuantumDurationMS ?? -1, 10, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackRenderQuantumMinMS ?? -1, 10, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackRenderQuantumMaxMS ?? -1, 10, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackOverRenderQuantumBudgetCount, 1)
        XCTAssertEqual(snapshot.callbackNearBudgetWarningCount, 1)
        XCTAssertEqual(snapshot.callbackIntervalMinMS ?? -1, 10, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackIntervalMaxMS ?? -1, 10, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.callbackIntervalLastMS ?? -1, 10, accuracy: 0.000_001)
    }

    func testRuntimeCMixerOutputCopyHelperWritesExpectedStereoFramesAndHashes() {
        let scratch = [Float(0.1), -0.2, 0.3, -0.4]
        var output = Array(repeating: Float(-1), count: 4)
        let captureSummary = scratch.withUnsafeBufferPointer {
            RuntimeCMixerSampleSummary.summarize($0, frameCount: 2, channelCount: 2)
        }

        let diagnostics = scratch.withUnsafeBufferPointer { scratchPointer in
            output.withUnsafeMutableBufferPointer { outputPointer in
                RuntimeCMixerOutputBufferCopy.copyInterleavedSamples(
                    scratch: scratchPointer,
                    frameCount: 2,
                    sourceChannelCount: 2,
                    into: outputPointer,
                    outputChannelCount: 2,
                    captureSummary: captureSummary
                )
            }
        }

        XCTAssertPCMEqual(output, scratch)
        XCTAssertEqual(diagnostics.requestedFrameCount, 2)
        XCTAssertEqual(diagnostics.sourceChannelCount, 2)
        XCTAssertEqual(diagnostics.outputChannelCount, 2)
        XCTAssertEqual(diagnostics.copiedFrameCount, 2)
        XCTAssertEqual(diagnostics.copiedSampleCount, 4)
        XCTAssertEqual(diagnostics.expectedSampleCount, 4)
        XCTAssertTrue(diagnostics.filledRequestedFrames)
        XCTAssertTrue(diagnostics.channelCountMatches)
        XCTAssertFalse(diagnostics.partialCopy)
        XCTAssertTrue(diagnostics.succeeded)
        XCTAssertEqual(diagnostics.scratchCaptureHashMatches, true)
        XCTAssertEqual(diagnostics.scratchOutputHashMatches, true)
    }

    func testRuntimeCMixerOutputCopyHelperDetectsPartialOutputBuffer() {
        let scratch = [Float(0.1), -0.2, 0.3, -0.4]
        var output = Array(repeating: Float(-1), count: 2)

        let diagnostics = scratch.withUnsafeBufferPointer { scratchPointer in
            output.withUnsafeMutableBufferPointer { outputPointer in
                RuntimeCMixerOutputBufferCopy.copyInterleavedSamples(
                    scratch: scratchPointer,
                    frameCount: 2,
                    sourceChannelCount: 2,
                    into: outputPointer,
                    outputChannelCount: 2
                )
            }
        }

        XCTAssertPCMEqual(output, [0.1, -0.2])
        XCTAssertEqual(diagnostics.copiedFrameCount, 1)
        XCTAssertEqual(diagnostics.copiedSampleCount, 2)
        XCTAssertEqual(diagnostics.expectedSampleCount, 4)
        XCTAssertFalse(diagnostics.filledRequestedFrames)
        XCTAssertTrue(diagnostics.partialCopy)
        XCTAssertFalse(diagnostics.succeeded)
    }

    func testRuntimeCMixerOutputCopyHelperDetectsShortScratchBuffer() {
        let scratch = [Float(0.1), -0.2]
        var output = Array(repeating: Float(-1), count: 4)

        let diagnostics = scratch.withUnsafeBufferPointer { scratchPointer in
            output.withUnsafeMutableBufferPointer { outputPointer in
                RuntimeCMixerOutputBufferCopy.copyInterleavedSamples(
                    scratch: scratchPointer,
                    frameCount: 2,
                    sourceChannelCount: 2,
                    into: outputPointer,
                    outputChannelCount: 2
                )
            }
        }

        XCTAssertPCMEqual(output, [0.1, -0.2, -1, -1])
        XCTAssertEqual(diagnostics.copiedFrameCount, 1)
        XCTAssertEqual(diagnostics.copiedSampleCount, 2)
        XCTAssertEqual(diagnostics.expectedSampleCount, 4)
        XCTAssertFalse(diagnostics.filledRequestedFrames)
        XCTAssertTrue(diagnostics.partialCopy)
        XCTAssertFalse(diagnostics.succeeded)
    }

    func testRuntimeCMixerRenderCoreReportsRenderPositionDiagnostics() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            maximumRenderFrames: 16
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [1, 0.5, 0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 44_100
        )
        let request = AudioVoiceRequest(sample: sample, note: 49, channel: 0)

        let triggerResult = core.triggerWithDiagnostics(request)
        XCTAssertTrue(triggerResult.succeeded)
        XCTAssertEqual(triggerResult.snapshotAfter.activeVoiceCount, 1)
        XCTAssertEqual(triggerResult.snapshotAfter.loadedVoiceCount, 1)

        var output = Array(repeating: Float(0), count: 4)
        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 2))
        }

        let snapshot = core.snapshot()
        XCTAssertEqual(snapshot.renderCallbackCount, 1)
        XCTAssertEqual(snapshot.renderCallCount, 1)
        XCTAssertEqual(snapshot.successfulRenderCount, 1)
        XCTAssertEqual(snapshot.failedRenderCount, 0)
        XCTAssertEqual(snapshot.requestedFrameCount, 2)
        XCTAssertEqual(snapshot.cumulativeRequestedFrameCount, 2)
        XCTAssertEqual(snapshot.renderedFrameCount, 2)
        XCTAssertEqual(snapshot.callbackIndex, 1)
        XCTAssertEqual(snapshot.callbackRequestedFrameCount, 2)
        XCTAssertEqual(snapshot.callbackStartFrame, 0)
        XCTAssertEqual(snapshot.callbackEndFrame, 2)
        XCTAssertEqual(snapshot.minRequestedFrameCount, 2)
        XCTAssertEqual(snapshot.maxRequestedFrameCount, 2)
        XCTAssertEqual(snapshot.lastRequestedFrameCount, 2)
        XCTAssertEqual(snapshot.lastRenderedFrameCount, 2)
        XCTAssertEqual(snapshot.lastRenderSucceeded, true)
        XCTAssertEqual(snapshot.zeroFillCount, 0)
        XCTAssertEqual(snapshot.silentOutputCallbackCount, 0)
        let gain = RuntimeCMixerOutputPolicy.defaultPolicy.outputGain
        XCTAssertEqual(snapshot.lastOutputPeak, gain, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.outputPeak, gain, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.outputRMS, Float(sqrt(2.5 / 4.0)) * gain, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.outputDiscontinuityCount, 0)
        XCTAssertLessThan(snapshot.maxOutputAdjacentSampleJump, RuntimeCMixerRenderCore.outputDiscontinuityThreshold)
        XCTAssertEqual(snapshot.topOutputPeaks.first?.runtimeFrame, 0)
        XCTAssertEqual(snapshot.topOutputPeaks.first?.peak ?? 0, gain, accuracy: 0.000_001)
        XCTAssertNil(snapshot.lastOutputDiscontinuitySampleJump)
        XCTAssertEqual(snapshot.overrangeSampleCount, 0)
        XCTAssertEqual(snapshot.clippingSampleCount, 0)
        XCTAssertFalse(snapshot.clippingDetected)
        XCTAssertEqual(snapshot.currentFrame, 2)
        XCTAssertEqual(snapshot.appliedPlannedEventCount, 0)
        XCTAssertEqual(snapshot.exactFrameAppliedEventCount, 0)
        XCTAssertEqual(snapshot.callbackBoundaryAppliedEventCount, 0)
        XCTAssertEqual(snapshot.latePlannedEventCount, 0)
        XCTAssertEqual(snapshot.maxPlannedVsAppliedDelta, 0)
    }

    func testRuntimeCMixerRenderCoreReportsOutputDiscontinuityDiagnostics() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: [0, 1, -1, 1], baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        var output = Array(repeating: Float(0), count: 4)
        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 4))
        }

        let snapshot = core.snapshot()
        XCTAssertEqual(snapshot.outputDiscontinuityThreshold, RuntimeCMixerRenderCore.outputDiscontinuityThreshold)
        XCTAssertEqual(snapshot.outputDiscontinuityCount, 3)
        XCTAssertEqual(snapshot.outputDiscontinuityThresholdCounts.map(\.threshold), [0.25, 0.35, 0.50, RuntimeCMixerRenderCore.outputDiscontinuityThreshold])
        XCTAssertEqual(snapshot.outputDiscontinuityThresholdCounts.map(\.count), [3, 3, 3, 3])
        XCTAssertEqual(snapshot.maxOutputAdjacentSampleJump, 2, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.topOutputAdjacentSampleJumps.map(\.sampleJump), [2, 2, 1])
        XCTAssertEqual(snapshot.topOutputAdjacentSampleJumps.map(\.runtimeFrame), [2, 3, 1])
        XCTAssertEqual(snapshot.lastOutputDiscontinuitySampleJump, 2)
        XCTAssertEqual(snapshot.lastOutputDiscontinuityCallbackIndex, 1)
        XCTAssertEqual(snapshot.lastOutputDiscontinuityRuntimeFrame, 2)
        XCTAssertEqual(snapshot.lastOutputDiscontinuityFrameOffset, 2)
        XCTAssertEqual(snapshot.lastOutputDiscontinuityChannelIndex, 0)
    }

    func testRuntimeCMixerLatePlannedEventsAreClassifiedAndAppliedAtCallbackStart() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)

        XCTAssertEqual(renderRuntimePCM(core, frames: 5), Array(repeating: 0, count: 5))
        core.configureAdapterEventScheduleForTesting(plan.events, runtimeFrameOffset: 0)
        XCTAssertEqual(core.snapshot().eventQueueBacklogCount, 1)
        let output = renderRuntimePCM(core, frames: 2)
        let snapshot = core.snapshot()

        XCTAssertGreaterThan(abs(output[0]), 0.000_001)
        XCTAssertEqual(snapshot.currentFrame, 7)
        XCTAssertEqual(snapshot.appliedPlannedEventCount, 1)
        XCTAssertEqual(snapshot.exactFrameAppliedEventCount, 0)
        XCTAssertEqual(snapshot.callbackBoundaryAppliedEventCount, 0)
        XCTAssertEqual(snapshot.latePlannedEventCount, 1)
        XCTAssertEqual(snapshot.maxPlannedVsAppliedDelta, 5)
        XCTAssertEqual(snapshot.eventQueueBacklogCount, 0)
    }

    func testRuntimeCMixerRenderCoreAppliesExplicitOutputGain() {
        let policy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "0.5"
        ])
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            maximumRenderFrames: 16,
            outputPolicy: policy
        )
        let sample = makePlaybackSample(pcm: [1, -0.5], baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        var output = Array(repeating: Float(0), count: 4)
        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 2))
        }

        XCTAssertEqual(output, [0.5, 0.5, -0.25, -0.25])
        XCTAssertEqual(core.snapshot().runtimeHeadroomPolicy, "env_runtime_gain")
        XCTAssertEqual(core.snapshot().runtimeGainPolicySource, "environment_override")
        XCTAssertEqual(core.snapshot().runtimeGainPolicyIsEnvironmentOverride, true)
    }

    func testRuntimeCMixerClippingDiagnosticsDecreaseForHotRenderWhenGainIsApplied() {
        let unityPolicy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
        ])
        let reducedPolicy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.gainEnvironmentKey: "0.25"
        ])
        let hotSample = makePlaybackSample(pcm: [2, -2, 0.5], baseSampleRate: 44_100)

        let unityCore = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: unityPolicy
        )
        XCTAssertTrue(unityCore.trigger(AudioVoiceRequest(sample: hotSample, note: 49, channel: 0)))
        var unityOutput = Array(repeating: Float(0), count: 3)
        unityOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(unityCore.render(into: buffer, frameCount: 3))
        }

        let reducedCore = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: reducedPolicy
        )
        XCTAssertTrue(reducedCore.trigger(AudioVoiceRequest(sample: hotSample, note: 49, channel: 0)))
        var reducedOutput = Array(repeating: Float(0), count: 3)
        reducedOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(reducedCore.render(into: buffer, frameCount: 3))
        }

        let unitySnapshot = unityCore.snapshot()
        let reducedSnapshot = reducedCore.snapshot()
        XCTAssertTrue(unitySnapshot.clippingDetected)
        XCTAssertEqual(unitySnapshot.clippingSampleCount, 2)
        XCTAssertEqual(unitySnapshot.outputPeakWarningSampleCount, 2)
        XCTAssertEqual(unitySnapshot.topOutputPeaks.first?.peak, 2)
        XCTAssertEqual(unitySnapshot.topOutputPeaks.first?.runtimeFrame, 0)
        XCTAssertEqual(unitySnapshot.runtimeClippingRecommendation, RuntimeCMixerOutputPolicy.clippingRecommendation)
        XCTAssertFalse(reducedSnapshot.clippingDetected)
        XCTAssertEqual(reducedSnapshot.clippingSampleCount, 0)
        XCTAssertLessThan(reducedSnapshot.outputPeak, unitySnapshot.outputPeak)
    }

    func testRuntimeCMixerDefaultMinusTwelveAvoidsSyntheticHotRenderClippingSeenAtMinusTen() {
        let oldDefaultEquivalentPolicy = RuntimeCMixerOutputPolicy.resolve(environment: [
            RuntimeCMixerOutputPolicy.headroomDBEnvironmentKey: "-10"
        ])
        let hotSample = makePlaybackSample(pcm: [3.5, -3.5, 0.25], baseSampleRate: 44_100)

        let minusTenCore = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: oldDefaultEquivalentPolicy
        )
        XCTAssertTrue(minusTenCore.trigger(AudioVoiceRequest(sample: hotSample, note: 49, channel: 0)))
        var minusTenOutput = Array(repeating: Float(0), count: 3)
        minusTenOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(minusTenCore.render(into: buffer, frameCount: 3))
        }

        let defaultCore = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        XCTAssertTrue(defaultCore.trigger(AudioVoiceRequest(sample: hotSample, note: 49, channel: 0)))
        var defaultOutput = Array(repeating: Float(0), count: 3)
        defaultOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(defaultCore.render(into: buffer, frameCount: 3))
        }

        let minusTenSnapshot = minusTenCore.snapshot()
        let defaultSnapshot = defaultCore.snapshot()
        XCTAssertEqual(minusTenSnapshot.runtimeFixedHeadroomDB, -10)
        XCTAssertEqual(defaultSnapshot.runtimeFixedHeadroomDB, -12)
        XCTAssertEqual(defaultSnapshot.runtimeGainPolicySource, "default")
        XCTAssertTrue(minusTenSnapshot.clippingDetected)
        XCTAssertEqual(minusTenSnapshot.clippingSampleCount, 2)
        XCTAssertFalse(defaultSnapshot.clippingDetected)
        XCTAssertEqual(defaultSnapshot.clippingSampleCount, 0)
        XCTAssertLessThan(defaultSnapshot.outputPeak, minusTenSnapshot.outputPeak)
    }

    func testRuntimeCMixerRenderCoreDistinguishesSilentOutputFromZeroFill() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 2
        )

        var silentOutput = Array(repeating: Float(1), count: 2)
        silentOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 2))
        }
        XCTAssertEqual(silentOutput, [0, 0])

        var snapshot = core.snapshot()
        XCTAssertEqual(snapshot.renderCallbackCount, 1)
        XCTAssertEqual(snapshot.successfulRenderCount, 1)
        XCTAssertEqual(snapshot.failedRenderCount, 0)
        XCTAssertEqual(snapshot.silentOutputCallbackCount, 1)
        XCTAssertEqual(snapshot.unexpectedSilentOutputCount, 0)
        XCTAssertEqual(snapshot.zeroFillCount, 0)

        var zeroFilledOutput = Array(repeating: Float(1), count: 4)
        zeroFilledOutput.withUnsafeMutableBufferPointer { buffer in
            XCTAssertFalse(core.render(into: buffer, frameCount: 4))
        }
        XCTAssertEqual(zeroFilledOutput, [0, 0, 0, 0])

        snapshot = core.snapshot()
        XCTAssertEqual(snapshot.renderCallbackCount, 2)
        XCTAssertEqual(snapshot.successfulRenderCount, 1)
        XCTAssertEqual(snapshot.failedRenderCount, 1)
        XCTAssertEqual(snapshot.silentOutputCallbackCount, 1)
        XCTAssertEqual(snapshot.zeroFillCount, 1)
        XCTAssertEqual(snapshot.underrunCount, 1)
        XCTAssertEqual(snapshot.lastRenderSucceeded, false)
        XCTAssertEqual(snapshot.lastRequestedFrameCount, 4)
        XCTAssertEqual(snapshot.lastRenderedFrameCount, 0)
    }

    func testRuntimeCMixerRenderCoreStopsOnlyRequestedChannel() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let loudSample = makePlaybackSample(instrumentIndex: 1, pcm: [1, 1, 1], baseSampleRate: 44_100)
        let quietSample = makePlaybackSample(instrumentIndex: 2, pcm: [0.25, 0.25, 0.25], baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: loudSample, note: 49, channel: 0)))
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: quietSample, note: 49, channel: 1)))
        let stopResult = core.stopChannelWithDiagnostics(0, reason: "test_channel_stop")

        XCTAssertEqual(stopResult.stoppedVoiceCount, 1)
        XCTAssertEqual(stopResult.snapshotBefore.activeVoiceCount, 2)
        XCTAssertEqual(stopResult.snapshotAfter.activeVoiceCount, 1)

        var output = Array(repeating: Float(0), count: 3)
        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 3))
        }
        XCTAssertEqual(output, Array(repeating: 0.25 * RuntimeCMixerOutputPolicy.defaultPolicy.outputGain, count: 3))
    }

    func testRuntimeCMixerRenderCoreRampsPriorVoiceOnSameChannelReplacement() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 64,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let firstSample = makePlaybackSample(instrumentIndex: 1, pcm: Array(repeating: 1, count: 64), baseSampleRate: 44_100)
        let otherChannelSample = makePlaybackSample(instrumentIndex: 2, pcm: Array(repeating: 0.25, count: 64), baseSampleRate: 44_100)
        let replacementSample = makePlaybackSample(instrumentIndex: 3, pcm: Array(repeating: 0.5, count: 64), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: firstSample, note: 49, channel: 0)))
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: otherChannelSample, note: 49, channel: 1)))
        let replacement = core.triggerWithDiagnostics(AudioVoiceRequest(sample: replacementSample, note: 49, channel: 0))

        XCTAssertTrue(replacement.succeeded)
        XCTAssertEqual(replacement.channelStopBeforeAdd?.stoppedVoiceCount, 0)
        XCTAssertEqual(replacement.channelStopBeforeAdd?.rampedVoiceCount, 1)
        XCTAssertEqual(replacement.channelStopBeforeAdd?.replacementRampFrames, CSoftwareMixer.replacementStopRampFrameCount)
        XCTAssertEqual(replacement.channelStopBeforeAdd?.replacementVoicesOverlap, true)
        XCTAssertEqual(replacement.snapshotAfter.activeVoiceCount, 3)
        XCTAssertEqual(replacement.snapshotAfter.rampingOutVoiceCount, 1)
        XCTAssertEqual(replacement.snapshotAfter.rampDownStartCount, 1)

        var output = Array(repeating: Float(0), count: 34)
        output.withUnsafeMutableBufferPointer { buffer in
            XCTAssertTrue(core.render(into: buffer, frameCount: 34))
        }
        XCTAssertEqual(output[0], 1.71875, accuracy: 0.000_001)
        XCTAssertEqual(output[30], 0.78125, accuracy: 0.000_001)
        XCTAssertEqual(output[31], 0.75, accuracy: 0.000_001)
        XCTAssertEqual(output[33], 0.75, accuracy: 0.000_001)
        XCTAssertEqual(core.snapshot().activeVoiceCount, 2)
        XCTAssertEqual(core.snapshot().rampingOutVoiceCount, 0)
        XCTAssertEqual(core.snapshot().rampDownCompletionCount, 1)
        XCTAssertEqual(core.snapshot().abruptRampDownStopCount, 0)
    }

    func testRuntimeCMixerSameFrameAdapterUpdateBeforeReplacementReportsRampState() throws {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 64,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let oldEvent = SyntheticTrackerEvent(
            row: 0,
            scheduledStartFrame: 0,
            sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 64)),
            gain: 1,
            pan: 0,
            playbackStep: 1
        )
        let replacementEvent = SyntheticTrackerEvent(
            row: 0,
            scheduledStartFrame: 0,
            sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(0.5), count: 64)),
            gain: 1,
            pan: 0,
            playbackStep: 1
        )
        let oldMapping = makeSyntheticEventMapping(channelIndex: 0, eventIndex: 0)
        let replacementMapping = makeSyntheticEventMapping(channelIndex: 0, eventIndex: 1)

        XCTAssertTrue(core.triggerAdapterEventWithDiagnostics(oldEvent, eventIndex: 0, mapping: oldMapping).succeeded)
        let gainPanUpdate = core.applyAdapterGainPanUpdateWithDiagnostics(
            channel: 0,
            activeEventIndex: 0,
            gain: 0.25,
            pan: 0.75
        )
        let stepUpdate = core.applyAdapterStepUpdateWithDiagnostics(
            channel: 0,
            activeEventIndex: 0,
            playbackStep: 2
        )
        let replacement = core.triggerAdapterEventWithDiagnostics(
            replacementEvent,
            eventIndex: 1,
            mapping: replacementMapping
        )
        let stop = try XCTUnwrap(replacement.channelStopBeforeAdd)

        XCTAssertEqual(gainPanUpdate.disposition, "update_applied")
        XCTAssertEqual(stepUpdate.disposition, "update_applied")
        XCTAssertEqual(stop.replacementGainPanAppliedBeforeRamp, false)
        XCTAssertEqual(stop.replacementStepAppliedBeforeRamp, false)
        XCTAssertEqual(stop.replacementOldVoiceState?.gain ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementOldVoiceState?.pan ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementRampStartState?.gainRampStart ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementRampStartState?.pan ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementRampStartState?.sampleStep ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementRampTargetGain ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementNewVoiceIndex, replacement.newVoiceIndex)
        XCTAssertEqual(stop.replacementNewVoiceChannelTag, 0)
    }

    func testRuntimeCMixerScheduledSameFrameMixedBurstOrderingIsDeterministicForReplacement() {
        func renderFirstFrame() -> Float {
            let core = RuntimeCMixerRenderCore(
                config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
                maximumRenderFrames: 64,
                outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                    RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
                ])
            )
            let oldEvent = SyntheticTrackerEvent(
                row: 0,
                scheduledStartFrame: 0,
                sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 64)),
                gain: 1
            )
            let replacementEvent = SyntheticTrackerEvent(
                row: 0,
                scheduledStartFrame: 0,
                sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(0.5), count: 64)),
                gain: 1
            )
            let oldMapping = makeSyntheticEventMapping(channelIndex: 0, eventIndex: 0)
            let replacementMapping = makeSyntheticEventMapping(channelIndex: 0, eventIndex: 1)
            XCTAssertTrue(core.triggerAdapterEventWithDiagnostics(oldEvent, eventIndex: 0, mapping: oldMapping).succeeded)
            core.configureAdapterEventScheduleForTesting([
                RuntimeCMixerAdapterEvent(
                    id: 2,
                    source: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
                    channelIndex: 0,
                    syntheticTick: 0,
                    scheduledFrame: 0,
                    action: .noteTrigger(eventIndex: 1, event: replacementEvent, mapping: replacementMapping),
                    categories: ["note_trigger", "replacement"]
                ),
                RuntimeCMixerAdapterEvent(
                    id: 1,
                    source: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
                    channelIndex: 0,
                    syntheticTick: 0,
                    scheduledFrame: 0,
                    action: .gainPanUpdate(activeEventIndex: 0, gain: 0.25, pan: nil),
                    categories: ["gain_pan_update"]
                )
            ], runtimeFrameOffset: 0)
            return renderRuntimePCM(core, frames: 1)[0]
        }

        let first = renderFirstFrame()
        XCTAssertEqual(renderFirstFrame(), first, accuracy: 0.000_001)
    }

    func testRuntimeCMixerReplacementDiagnosticsExposeKeyOffFadeoutState() throws {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 64,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let oldEvent = SyntheticTrackerEvent(
            row: 0,
            scheduledStartFrame: 0,
            sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(1), count: 64)),
            gain: 1,
            keyOffFrame: 0,
            fadeoutFrameDecrement: 0.25
        )
        let replacementEvent = SyntheticTrackerEvent(
            row: 0,
            scheduledStartFrame: 1,
            sample: MixerSampleBuffer(monoPCM: Array(repeating: Float(0.5), count: 64)),
            gain: 1
        )
        let oldMapping = makeSyntheticEventMapping(channelIndex: 0, eventIndex: 0)
        let replacementMapping = makeSyntheticEventMapping(channelIndex: 0, eventIndex: 1)

        XCTAssertTrue(core.triggerAdapterEventWithDiagnostics(oldEvent, eventIndex: 0, mapping: oldMapping).succeeded)
        _ = renderRuntimePCM(core, frames: 1)
        let replacement = core.triggerAdapterEventWithDiagnostics(
            replacementEvent,
            eventIndex: 1,
            mapping: replacementMapping
        )
        let stop = try XCTUnwrap(replacement.channelStopBeforeAdd)

        XCTAssertEqual(stop.replacementKeyOffAppliedBeforeRamp, true)
        XCTAssertEqual(stop.replacementFadeoutAppliedBeforeRamp, true)
        XCTAssertEqual(stop.replacementOldVoiceState?.keyOn, false)
        XCTAssertEqual(stop.replacementOldVoiceState?.fadeoutValue ?? -1, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(stop.replacementRampStartState?.keyOn, false)
        XCTAssertEqual(stop.replacementRampStartState?.fadeoutValue ?? -1, 0.75, accuracy: 0.000_001)
    }

    func testRuntimeCMixerGlobalStopClearsReplacementRampImmediately() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let firstSample = makePlaybackSample(pcm: Array(repeating: 1, count: 64), baseSampleRate: 44_100)
        let replacementSample = makePlaybackSample(instrumentIndex: 2, pcm: Array(repeating: 0.5, count: 64), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: firstSample, note: 49, channel: 0)))
        XCTAssertTrue(core.triggerWithDiagnostics(AudioVoiceRequest(sample: replacementSample, note: 49, channel: 0)).succeeded)
        let stop = core.stopAllWithDiagnostics(reason: "transport_stop_all")

        XCTAssertEqual(stop.targetedAllVoices, true)
        XCTAssertEqual(stop.snapshotBefore.activeVoiceCount, 2)
        XCTAssertEqual(stop.snapshotAfter.activeVoiceCount, 0)
        XCTAssertEqual(stop.snapshotAfter.loadedVoiceCount, 0)
        XCTAssertEqual(renderRuntimePCM(core, frames: 4), [0, 0, 0, 0])
    }

    func testRuntimeCMixerGainPanUpdateTargetsOnlyRequestedChannel() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 64,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let firstSample = makePlaybackSample(pcm: Array(repeating: 1, count: 80), baseSampleRate: 44_100)
        let secondSample = makePlaybackSample(instrumentIndex: 2, pcm: Array(repeating: 2, count: 80), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: firstSample, note: 49, channel: 0)))
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: secondSample, note: 49, channel: 1)))
        let update = core.updateWithDiagnostics(
            channel: 1,
            controls: AudioChannelControls(volumeScale: 0.25, pitchOffsetSemitones: 0, panning: 0)
        )
        let output = renderRuntimePCM(core, frames: 40)

        XCTAssertEqual(update.traceAction, "c_mixer_update_gain_pan_applied")
        XCTAssertEqual(update.disposition, "update_applied")
        XCTAssertEqual(update.updateType, "gain")
        XCTAssertEqual(update.channel, 1)
        XCTAssertEqual(update.targetVoiceIndex, 1)
        XCTAssertEqual(update.gainBefore ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(update.gainAfter ?? -1, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(output[39], 1.5, accuracy: 0.000_001)
    }

    func testRuntimeCMixerStepUpdateTargetsOnlyRequestedChannel() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let firstSample = makePlaybackSample(pcm: [100, 101, 102, 103, 104, 105, 106, 107], baseSampleRate: 44_100)
        let secondSample = makePlaybackSample(instrumentIndex: 2, pcm: [0, 1, 2, 3, 4, 5, 6, 7], baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: firstSample, note: 49, channel: 0)))
        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: secondSample, note: 49, channel: 1)))
        let update = core.updateWithDiagnostics(
            channel: 1,
            controls: AudioChannelControls(volumeScale: 1, pitchOffsetSemitones: 12, panning: 0)
        )
        let output = renderRuntimePCM(core, frames: 4)

        XCTAssertEqual(update.traceAction, "c_mixer_update_step_applied")
        XCTAssertEqual(update.disposition, "update_applied")
        XCTAssertEqual(update.updateType, "step")
        XCTAssertEqual(update.channel, 1)
        XCTAssertEqual(update.targetVoiceIndex, 1)
        XCTAssertEqual(update.sampleStepBefore ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(update.sampleStepAfter ?? -1, 2, accuracy: 0.000_001)
        XCTAssertEqual(output, [100, 103, 106, 109])
    }

    func testRuntimeCMixerCombinedGainPanStepUpdateIsDeterministic() {
        func makeCore() -> RuntimeCMixerRenderCore {
            let core = RuntimeCMixerRenderCore(
                config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
                maximumRenderFrames: 80,
                outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                    RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
                ])
            )
            let sample = makePlaybackSample(
                pcm: (0..<160).map { Float($0) },
                baseSampleRate: 44_100
            )
            XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
            return core
        }
        let first = makeCore()
        let second = makeCore()

        let firstUpdate = first.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 0.5, pitchOffsetSemitones: 12, panning: 1)
        )
        let secondUpdate = second.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 0.5, pitchOffsetSemitones: 12, panning: 1)
        )

        XCTAssertEqual(firstUpdate.traceAction, "c_mixer_update_gain_pan_step_applied")
        XCTAssertEqual(firstUpdate.disposition, "update_applied")
        XCTAssertEqual(firstUpdate.updateType, "combined")
        XCTAssertEqual(firstUpdate.reason, "runtime_c_mixer_update_applied_combined")
        XCTAssertEqual(firstUpdate.gainBefore ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(firstUpdate.gainAfter ?? -1, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(firstUpdate.panBefore ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(firstUpdate.panAfter ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(firstUpdate.sampleStepBefore ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(firstUpdate.sampleStepAfter ?? -1, 2, accuracy: 0.000_001)
        XCTAssertEqual(firstUpdate, secondUpdate)
        XCTAssertEqual(renderRuntimePCM(first, frames: 40), renderRuntimePCM(second, frames: 40))
    }

    func testRuntimeCMixerGainDeltaBelowEpsilonIsSuppressedAndDoesNotRestartRamp() {
        func makeCore() -> RuntimeCMixerRenderCore {
            let core = RuntimeCMixerRenderCore(
                config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
                maximumRenderFrames: 80,
                outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                    RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
                ])
            )
            let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 96), baseSampleRate: 44_100)
            XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
            XCTAssertEqual(
                core.updateWithDiagnostics(
                    channel: 0,
                    controls: AudioChannelControls(volumeScale: 0, pitchOffsetSemitones: 0, panning: 0)
                ).traceAction,
                "c_mixer_update_gain_pan_applied"
            )
            return core
        }
        let baseline = makeCore()
        let candidate = makeCore()

        _ = renderRuntimePCM(baseline, frames: 16)
        _ = renderRuntimePCM(candidate, frames: 16)
        let suppressed = candidate.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: Float(RuntimeCMixerRenderCore.updateEpsilon / 2),
                pitchOffsetSemitones: 0,
                panning: 0
            )
        )

        XCTAssertEqual(suppressed.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(suppressed.gainUpdateStatus, "suppressed_epsilon")
        XCTAssertTrue(suppressed.epsilonSuppressedGain)
        XCTAssertFalse(suppressed.gainPanAttempted)
        XCTAssertEqual(suppressed.reason, "runtime_c_mixer_update_suppressed_no_change_epsilon_filtered")
        XCTAssertEqual(renderRuntimePCM(candidate, frames: 24), renderRuntimePCM(baseline, frames: 24))
    }

    func testRuntimeCMixerZeroUpdateEpsilonDiagnosticAppliesTinyMotion() {
        let defaultCore = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let zeroEpsilonCore = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            updatePolicy: RuntimeCMixerUpdatePolicy.resolve(environment: [
                RuntimeCMixerUpdatePolicy.epsilonEnvironmentKey: "0"
            ])
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)
        let tinyGain = 1 - Float(RuntimeCMixerRenderCore.updateEpsilon / 2)

        XCTAssertTrue(defaultCore.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        XCTAssertTrue(zeroEpsilonCore.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        let defaultUpdate = defaultCore.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: tinyGain, pitchOffsetSemitones: 0, panning: 0)
        )
        let zeroEpsilonUpdate = zeroEpsilonCore.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: tinyGain, pitchOffsetSemitones: 0, panning: 0)
        )

        XCTAssertEqual(defaultUpdate.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(defaultUpdate.gainUpdateStatus, "suppressed_epsilon")
        XCTAssertEqual(zeroEpsilonUpdate.traceAction, "c_mixer_update_gain_pan_applied")
        XCTAssertEqual(zeroEpsilonUpdate.gainUpdateStatus, "applied")
        XCTAssertEqual(zeroEpsilonUpdate.updateEpsilon, 0)
        XCTAssertEqual(zeroEpsilonCore.snapshot().runtimeUpdateEpsilonPolicy, "env_runtime_update_epsilon")
    }

    func testRuntimeCMixerPanDeltaBelowEpsilonIsSuppressedAndDoesNotRestartRamp() {
        func makeCore() -> RuntimeCMixerRenderCore {
            let core = RuntimeCMixerRenderCore(
                config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
                maximumRenderFrames: 80,
                outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                    RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
                ])
            )
            let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 96), baseSampleRate: 44_100)
            XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0, panning: 0)))
            XCTAssertEqual(
                core.updateWithDiagnostics(
                    channel: 0,
                    controls: AudioChannelControls(volumeScale: 1, pitchOffsetSemitones: 0, panning: 1)
                ).traceAction,
                "c_mixer_update_gain_pan_applied"
            )
            return core
        }
        let baseline = makeCore()
        let candidate = makeCore()

        _ = renderRuntimePCM(baseline, frames: 16)
        _ = renderRuntimePCM(candidate, frames: 16)
        let suppressed = candidate.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: 1,
                pitchOffsetSemitones: 0,
                panning: 1 - Float(RuntimeCMixerRenderCore.updateEpsilon / 2)
            )
        )

        XCTAssertEqual(suppressed.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(suppressed.panUpdateStatus, "suppressed_epsilon")
        XCTAssertTrue(suppressed.epsilonSuppressedPan)
        XCTAssertFalse(suppressed.gainPanAttempted)
        XCTAssertEqual(suppressed.reason, "runtime_c_mixer_update_suppressed_no_change_epsilon_filtered")
        XCTAssertEqual(renderRuntimePCM(candidate, frames: 24), renderRuntimePCM(baseline, frames: 24))
    }

    func testRuntimeCMixerStepDeltaBelowEpsilonIsSuppressedAndDoesNotScheduleStepUpdate() {
        let baseline = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 80,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let candidate = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 80,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: (0..<128).map { Float($0) }, baseSampleRate: 44_100)
        XCTAssertTrue(baseline.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        XCTAssertTrue(candidate.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))

        let requestedStep = 1 + RuntimeCMixerRenderCore.updateEpsilon / 2
        let suppressed = candidate.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: 1,
                pitchOffsetSemitones: pitchOffsetSemitones(forPlaybackStep: requestedStep),
                panning: 0
            )
        )

        XCTAssertEqual(suppressed.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(suppressed.sampleStepUpdateStatus, "suppressed_epsilon")
        XCTAssertTrue(suppressed.epsilonSuppressedStep)
        XCTAssertFalse(suppressed.stepAttempted)
        XCTAssertEqual(suppressed.sampleStepRequested ?? 0, requestedStep, accuracy: 0.000_000_001)
        XCTAssertEqual(renderRuntimePCM(candidate, frames: 64), renderRuntimePCM(baseline, frames: 64))
    }

    func testRuntimeCMixerDeltaAboveEpsilonAppliesNormally() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: 1 - Float(RuntimeCMixerRenderCore.updateEpsilon * 2),
                pitchOffsetSemitones: 0,
                panning: 0
            )
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_gain_pan_applied")
        XCTAssertEqual(update.disposition, "update_applied")
        XCTAssertEqual(update.updateType, "gain")
        XCTAssertEqual(update.gainUpdateStatus, "applied")
        XCTAssertFalse(update.epsilonSuppressedGain)
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_applied_gain_pan")
    }

    func testRuntimeCMixerCombinedUpdateAppliesOnlyFieldsAboveEpsilon() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)
        let requestedStep = 1 + RuntimeCMixerRenderCore.updateEpsilon / 2

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0, panning: 0)))
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: 1 - Float(RuntimeCMixerRenderCore.updateEpsilon / 2),
                pitchOffsetSemitones: pitchOffsetSemitones(forPlaybackStep: requestedStep),
                panning: 0.5
            )
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_gain_pan_applied")
        XCTAssertEqual(update.disposition, "update_applied")
        XCTAssertEqual(update.updateType, "pan")
        XCTAssertEqual(update.gainUpdateStatus, "suppressed_epsilon")
        XCTAssertEqual(update.panUpdateStatus, "applied")
        XCTAssertEqual(update.sampleStepUpdateStatus, "suppressed_epsilon")
        XCTAssertTrue(update.epsilonSuppressedGain)
        XCTAssertFalse(update.epsilonSuppressedPan)
        XCTAssertTrue(update.epsilonSuppressedStep)
        XCTAssertTrue(update.gainPanApplied)
        XCTAssertFalse(update.stepApplied)
        XCTAssertEqual(update.gainAfter ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(update.panAfter ?? -1, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(update.sampleStepAfter ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_applied_after_epsilon_filter")
    }

    func testRuntimeCMixerAllFieldsBelowEpsilonClassifiesSuppressedNoChange() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)
        let requestedStep = 1 + RuntimeCMixerRenderCore.updateEpsilon / 2

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0, panning: 0)))
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: 1 - Float(RuntimeCMixerRenderCore.updateEpsilon / 2),
                pitchOffsetSemitones: pitchOffsetSemitones(forPlaybackStep: requestedStep),
                panning: Float(RuntimeCMixerRenderCore.updateEpsilon / 2)
            )
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(update.disposition, "update_suppressed_no_change")
        XCTAssertEqual(update.updateType, "none")
        XCTAssertEqual(update.gainUpdateStatus, "suppressed_epsilon")
        XCTAssertEqual(update.panUpdateStatus, "suppressed_epsilon")
        XCTAssertEqual(update.sampleStepUpdateStatus, "suppressed_epsilon")
        XCTAssertTrue(update.epsilonSuppressedGain)
        XCTAssertTrue(update.epsilonSuppressedPan)
        XCTAssertTrue(update.epsilonSuppressedStep)
        XCTAssertFalse(update.gainPanAttempted)
        XCTAssertFalse(update.stepAttempted)
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_suppressed_no_change_epsilon_filtered")
    }

    @MainActor
    func testRuntimeCMixerTraceCountersRecordEpsilonSuppression() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let engine = RuntimeCMixerAudioEngine(
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ]),
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )

        engine.update(
            channel: 0,
            controls: AudioChannelControls(
                volumeScale: 1 - Float(RuntimeCMixerRenderCore.updateEpsilon / 2),
                pitchOffsetSemitones: RuntimeCMixerRenderCore.updateEpsilon / 2,
                panning: defaultRuntimePan(forChannel: 0) + Float(RuntimeCMixerRenderCore.updateEpsilon / 2)
            )
        )

        let event = traceWriter.events.last
        XCTAssertEqual(event?.runtimeAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(event?.updateSuppressedEpsilonGainCount, 1)
        XCTAssertEqual(event?.updateSuppressedEpsilonPanCount, 1)
        XCTAssertEqual(event?.updateSuppressedEpsilonStepCount, 1)
        XCTAssertEqual(event?.updateSuppressedNoChangeCount, 1)
        XCTAssertEqual(event?.updateAppliedAfterEpsilonFilterCount, 0)
        XCTAssertEqual(event?.updateEpsilon, RuntimeCMixerRenderCore.updateEpsilon)
        XCTAssertEqual(event?.gainUpdateStatus, "suppressed_epsilon")
        XCTAssertEqual(event?.panUpdateStatus, "suppressed_epsilon")
        XCTAssertEqual(event?.sampleStepUpdateStatus, "suppressed_epsilon")
    }

    func testRuntimeCMixerNoChangeGainPanUpdateIsSuppressed() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        XCTAssertEqual(
            core.updateWithDiagnostics(
                channel: 0,
                controls: AudioChannelControls(volumeScale: 0.5, pitchOffsetSemitones: 0, panning: 0)
            ).traceAction,
            "c_mixer_update_gain_pan_applied"
        )
        let suppressed = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 0.5, pitchOffsetSemitones: 0, panning: 0)
        )

        XCTAssertEqual(suppressed.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(suppressed.disposition, "update_suppressed_no_change")
        XCTAssertEqual(suppressed.updateType, "none")
        XCTAssertEqual(suppressed.reason, "runtime_c_mixer_update_suppressed_no_change")
        XCTAssertNil(suppressed.succeeded)
    }

    func testRuntimeCMixerNoChangeStepUpdateIsSuppressed() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        XCTAssertEqual(
            core.updateWithDiagnostics(
                channel: 0,
                controls: AudioChannelControls(volumeScale: 1, pitchOffsetSemitones: 12, panning: 0)
            ).traceAction,
            "c_mixer_update_step_applied"
        )
        let suppressed = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 1, pitchOffsetSemitones: 12, panning: 0)
        )

        XCTAssertEqual(suppressed.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(suppressed.disposition, "update_suppressed_no_change")
        XCTAssertEqual(suppressed.updateType, "none")
        XCTAssertEqual(suppressed.reason, "runtime_c_mixer_update_suppressed_no_change")
        XCTAssertNil(suppressed.succeeded)
    }

    func testRuntimeCMixerGainPanUpdateWithoutActiveVoiceStoresStateForNextNote() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16,
            outputPolicy: RuntimeCMixerOutputPolicy.resolve(environment: [
                RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"
            ])
        )
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 44_100)
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 0.25, pitchOffsetSemitones: 12, panning: 0),
            context: AudioRuntimeTraceContext(rowIndex: 0, tickInRow: 0, channelIndex: 0, noteValue: 49)
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_stored_channel_state")
        XCTAssertEqual(update.disposition, "update_stored_channel_state")
        XCTAssertEqual(update.updateType, "combined")
        XCTAssertTrue(update.stepAttempted)
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_stored_channel_state_update_before_note_step_deferred_no_active_voice")
        XCTAssertNil(update.targetVoiceIndex)
        XCTAssertNil(update.succeeded)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0, panning: defaultRuntimePan(forChannel: 0))))
        XCTAssertEqual(renderRuntimePCM(core, frames: 2), [0.25, 0.25])
    }

    func testRuntimeCMixerStepUpdateWithoutActiveVoiceStaysDeferred() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )

        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 1, pitchOffsetSemitones: 12, panning: defaultRuntimePan(forChannel: 0))
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_deferred_no_active_voice")
        XCTAssertEqual(update.disposition, "update_deferred_no_active_voice")
        XCTAssertEqual(update.updateType, "step")
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_deferred_no_active_voice_missing_runtime_channel_state")
        XCTAssertNil(update.targetVoiceIndex)
        XCTAssertNil(update.succeeded)
    }

    func testRuntimeCMixerUpdateAfterChannelStopIsClassifiedSeparately() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        XCTAssertEqual(core.stopChannelWithDiagnostics(0, reason: "test_stop").stoppedVoiceCount, 1)
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 0.5, pitchOffsetSemitones: 0, panning: 0)
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_deferred_stale_after_stop")
        XCTAssertEqual(update.disposition, "update_deferred_stale_after_stop")
        XCTAssertEqual(update.updateType, "gain")
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_deferred_stale_after_stop")
        XCTAssertNil(update.targetVoiceIndex)
        XCTAssertNil(update.succeeded)
    }

    func testRuntimeCMixerMissingUpdateDataStaysDeferredWithReason() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: .nan)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 0.5, pitchOffsetSemitones: 0, panning: 0)
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_deferred_missing_data")
        XCTAssertEqual(update.disposition, "update_deferred_missing_data")
        XCTAssertEqual(update.updateType, "step")
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_deferred_missing_data_missing_sample_step_target")
        XCTAssertEqual(update.targetVoiceIndex, 0)
        XCTAssertEqual(update.succeeded, false)
    }

    func testRuntimeCMixerUnsupportedUpdateStaysDeferredWithReason() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        let update = core.updateWithDiagnostics(
            channel: 0,
            controls: AudioChannelControls(volumeScale: 1, pitchOffsetSemitones: .nan, panning: 0)
        )

        XCTAssertEqual(update.traceAction, "c_mixer_update_deferred_unsupported")
        XCTAssertEqual(update.disposition, "update_deferred_unsupported")
        XCTAssertEqual(update.updateType, "none")
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_deferred_unsupported_invalid_update_values")
        XCTAssertEqual(update.targetVoiceIndex, 0)
        XCTAssertEqual(update.succeeded, false)
    }

    func testRuntimeCMixerUnchangedUpdateStaysDeferredWithReason() {
        let core = RuntimeCMixerRenderCore(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            maximumRenderFrames: 16
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 1, count: 16), baseSampleRate: 44_100)

        XCTAssertTrue(core.trigger(AudioVoiceRequest(sample: sample, note: 49, channel: 0)))
        let update = core.updateWithDiagnostics(channel: 0, controls: AudioChannelControls())

        XCTAssertEqual(update.traceAction, "c_mixer_update_suppressed_no_change")
        XCTAssertEqual(update.disposition, "update_suppressed_no_change")
        XCTAssertEqual(update.updateType, "none")
        XCTAssertEqual(update.reason, "runtime_c_mixer_update_suppressed_no_change")
        XCTAssertEqual(update.targetVoiceIndex, 0)
        XCTAssertNil(update.succeeded)
    }

    @MainActor
    func testRuntimeCMixerTraceDistinguishesAdapterNoteCutFromAllVoiceClear() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let engine = PlaybackEngine(
            audioEngine: audioEngine,
            runtimeCMixerTraceWriter: traceWriter,
            startsRealtimeTimer: false
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 4_096),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC1)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 125)
        ))

        engine.play(from: nil)
        _ = audioEngine.renderForTesting(frameCount: 1_024)

        let noteCut = traceWriter.events.first { $0.runtimeAction == "c_mixer_adapter_note_cut" }
        XCTAssertEqual(noteCut?.targetScope, "channel")
        XCTAssertEqual(noteCut?.targetedAllVoices, false)
        XCTAssertEqual(noteCut?.orderIndex, 0)
        XCTAssertEqual(noteCut?.rowIndex, 0)
        XCTAssertEqual(noteCut?.channelIndex, 0)
        XCTAssertEqual(noteCut?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(noteCut?.adapterEventCategory, "note_cut")
        XCTAssertEqual(noteCut?.reason, "runtime_c_mixer_adapter_plan_note_cut_applied")
        XCTAssertNotNil(noteCut?.targetVoiceIndex)
        XCTAssertEqual(noteCut?.stopChannelCount, 0)
        XCTAssertNil(traceWriter.events.first {
            $0.runtimeAction == "c_mixer_clear_all" &&
                $0.reason == "per_channel_stop_currently_clears_all_runtime_c_voices"
        })

        engine.stop()

        let clearAll = traceWriter.events.last { $0.runtimeAction == "c_mixer_clear_all" }
        XCTAssertEqual(clearAll?.targetScope, "all_channels")
        XCTAssertEqual(clearAll?.targetedAllVoices, true)
        XCTAssertEqual(clearAll?.reason, "transport_stop")
        XCTAssertNotNil(clearAll?.stoppedVoiceCount)
        XCTAssertGreaterThanOrEqual(clearAll?.clearAllCount ?? 0, 1)
        XCTAssertGreaterThanOrEqual(clearAll?.cMixerRenderedFramesBeforeClear ?? 0, 1_024)
        XCTAssertGreaterThan(clearAll?.cMixerPlaybackSecondsBeforeClear ?? 0, 0)
    }

    @MainActor
    func testRuntimeCMixerTraceRecordsChannelScopedReplacement() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let engine = PlaybackEngine(
            audioEngine: audioEngine,
            runtimeCMixerTraceWriter: traceWriter,
            startsRealtimeTimer: false
        )
        let sample = makePlaybackSample(pcm: Array(repeating: 0.25, count: 4_096), baseSampleRate: 44_100)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 125)
        ))

        engine.play(from: nil)
        _ = audioEngine.renderForTesting(frameCount: 1_024)

        let replacementStop = traceWriter.events.first {
            $0.runtimeAction == "c_mixer_stop_channel_ramped" && $0.reason == "note_replacement_stop_channel"
        }
        XCTAssertEqual(replacementStop?.targetScope, "channel")
        XCTAssertEqual(replacementStop?.targetedAllVoices, false)
        XCTAssertEqual(replacementStop?.rowIndex, 1)
        XCTAssertEqual(replacementStop?.channelIndex, 0)
        XCTAssertEqual(replacementStop?.runtimeEventSource, "offline_adapter_plan")
        XCTAssertEqual(replacementStop?.adapterEventCategory, "replacement")
        XCTAssertNil(replacementStop?.stoppedVoiceCount)
        XCTAssertEqual(replacementStop?.rampedVoiceCount, 1)
        XCTAssertEqual(replacementStop?.replacementRampFrames, CSoftwareMixer.replacementStopRampFrameCount)
        XCTAssertEqual(replacementStop?.replacementVoicesOverlap, true)
        XCTAssertEqual(replacementStop?.stopChannelCount, 0)
        XCTAssertEqual(replacementStop?.replacementRampCount, 1)
        XCTAssertEqual(replacementStop?.activeVoiceCountBefore, 1)
        XCTAssertEqual(replacementStop?.activeVoiceCountAfter, 2)
        XCTAssertNil(traceWriter.events.first {
            $0.runtimeAction == "c_mixer_clear_all" &&
                $0.reason == "per_channel_stop_currently_clears_all_runtime_c_voices"
        })
    }

    @MainActor
    func testRuntimeCMixerTraceRecordsRowTransitionsWithRenderSnapshot() {
        let traceWriter = TestRuntimeCMixerTraceWriter()
        let audioEngine = RuntimeCMixerAudioEngine(
            startsOutputHostOnDemand: false,
            traceWriter: traceWriter
        )
        let engine = PlaybackEngine(
            audioEngine: audioEngine,
            runtimeCMixerTraceWriter: traceWriter,
            startsRealtimeTimer: false
        )
        let sample = makePlaybackSample(pcm: [0.25, 0.25], baseSampleRate: 44_100)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 125)
        ))

        engine.play(from: nil)
        engine.advanceOneTick()

        let transitions = traceWriter.events.filter { $0.runtimeAction == "row_transition" }
        XCTAssertEqual(transitions.count, 2)
        XCTAssertEqual(transitions[0].orderIndex, 0)
        XCTAssertEqual(transitions[0].patternIndex, 2)
        XCTAssertEqual(transitions[0].rowIndex, 0)
        XCTAssertEqual(transitions[0].sampleRate, 44_100)
        XCTAssertEqual(transitions[0].channelCount, 2)
        XCTAssertEqual(transitions[0].renderCallbackCount, 0)
        XCTAssertEqual(transitions[0].eventQueueBacklogCount, 0)
        XCTAssertEqual(transitions[0].runtimeHeadroomPolicy, "default_runtime_headroom_db")
        XCTAssertEqual(transitions[0].runtimeOutputGain, RuntimeCMixerOutputPolicy.defaultPolicy.outputGain)
        XCTAssertEqual(transitions[0].transitionPhase, "before_events")
        XCTAssertEqual(transitions[0].nextOrderIndex, 0)
        XCTAssertEqual(transitions[0].nextPatternIndex, 2)
        XCTAssertEqual(transitions[0].nextRowIndex, 0)
        XCTAssertEqual(transitions[0].transitionRuntimeFrame, 0)
        XCTAssertEqual(transitions[0].runtimeEventCategory, "row_transition")
        XCTAssertEqual(transitions[0].cMixerRenderedFrames, 0)
        XCTAssertEqual(transitions[0].cMixerSampleTimeFrame, 0)
        XCTAssertEqual(transitions[0].cMixerSampleTimeOrderIndex, 0)
        XCTAssertEqual(transitions[0].cMixerSampleTimePatternIndex, 2)
        XCTAssertEqual(transitions[0].cMixerSampleTimeRowIndex, 0)
        XCTAssertEqual(transitions[0].cMixerSampleTimeTickInRow, 0)
        XCTAssertEqual(transitions[0].playbackEngineOrderIndex, 0)
        XCTAssertEqual(transitions[0].playbackEnginePatternIndex, 2)
        XCTAssertEqual(transitions[0].playbackEngineRowIndex, 0)
        XCTAssertEqual(transitions[0].playbackEngineTickInRow, 0)
        XCTAssertEqual(transitions[0].plannedSongEndFrame, 1_764)
        XCTAssertEqual(transitions[0].plannedSongEndSeconds ?? 0, 0.04, accuracy: 0.000_001)
        XCTAssertEqual(transitions[0].playbackEngineToCMixerFrameDelta, 0)
        XCTAssertEqual(transitions[0].playbackEngineToCMixerPositionMismatch, false)
        XCTAssertEqual(transitions[0].rowTransitionDeltaCategory, "exact")
        XCTAssertEqual(transitions[1].rowIndex, 1)
        XCTAssertEqual(transitions[1].previousOrderIndex, 0)
        XCTAssertEqual(transitions[1].previousPatternIndex, 2)
        XCTAssertEqual(transitions[1].previousRowIndex, 0)
        XCTAssertNotNil(transitions[1].activeVoiceCount)
        XCTAssertNotNil(transitions[1].loadedVoiceCount)
        XCTAssertEqual(transitions[1].playbackEngineRowIndex, 1)
        XCTAssertEqual(transitions[1].cMixerSampleTimeRowIndex, 0)
        XCTAssertEqual(transitions[1].playbackEngineToCMixerPositionMismatch, true)
        XCTAssertEqual(transitions[1].rowTransitionDeltaCategory, "different_row_or_order")

        let transitionSummaries = traceWriter.events.filter { $0.runtimeAction == "row_transition_after_events" }
        XCTAssertEqual(transitionSummaries.count, 2)
        XCTAssertEqual(transitionSummaries[0].transitionPhase, "after_events")
        XCTAssertEqual(transitionSummaries[0].activeVoiceCountBefore, 0)
        XCTAssertEqual(transitionSummaries[0].activeVoiceCountAfter, 0)
        XCTAssertEqual(transitionSummaries[0].eventQueueBacklogCount, 2)
        XCTAssertEqual(transitionSummaries[0].transitionReplacementRampCount, 0)
        XCTAssertEqual(transitionSummaries[0].transitionUpdateCount, 0)
        XCTAssertEqual(transitionSummaries[1].previousRowIndex, 0)
        XCTAssertEqual(transitionSummaries[1].nextRowIndex, 1)
        XCTAssertNotNil(transitionSummaries[1].transitionRuntimeFrame)
    }

    @MainActor
    func testPlaybackEngineRuntimeTraceRecordsNoteTriggerContext() {
        let audioOutput = TestPlaybackAudioOutput()
        let runtimeTraceWriter = TestRuntimeCMixerTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, runtimeCMixerTraceWriter: runtimeTraceWriter)
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 16),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x09, effectParam: 0x02)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        let event = runtimeTraceWriter.events.first { $0.runtimeAction == "note_trigger" }
        XCTAssertEqual(event?.runtimeAudioBackend, "c_mixer")
        XCTAssertEqual(event?.orderIndex, 0)
        XCTAssertEqual(event?.patternIndex, 2)
        XCTAssertEqual(event?.rowIndex, 0)
        XCTAssertEqual(event?.tickInRow, 0)
        XCTAssertEqual(event?.channelIndex, 0)
        XCTAssertEqual(event?.noteValue, 49)
        XCTAssertEqual(event?.instrumentIndex, 1)
        XCTAssertEqual(event?.effect, "0902")
        XCTAssertEqual(event?.volumeColumn, "30")
        XCTAssertEqual(event?.targetScope, "channel")
        XCTAssertEqual(event?.noteTriggerEventCount, 1)
    }

    private func loadMultiPatternLoopBoundarySong() throws -> PlaybackSong {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        return try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
    }

    private func clearAllEventsAfterRenderStarted(in events: [RuntimeCMixerTraceEvent]) -> [RuntimeCMixerTraceEvent] {
        events.filter {
            $0.runtimeAction == "c_mixer_clear_all" &&
                (($0.cMixerRenderedFramesBeforeClear ?? 0) > 0 || ($0.currentFrame ?? 0) > 0)
        }
    }

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("tests/reference-xm").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing reference XM fixture \(relativePath)")
        }
        return url
    }
}
