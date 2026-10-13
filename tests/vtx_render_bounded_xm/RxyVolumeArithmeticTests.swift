import XCTest
@testable import VoodooTrackerXPlaybackSupport

final class RxyVolumeArithmeticTests: XCTestCase {
    // Independently recorded semantic results from synthetic one-invocation controls,
    // pinned FT2 87be42543dac82cf802b5bddad917bda62ace131. No reference binary is required.
    private let scaling: [Int: [Int]] = [
        6: [
            0, 0, 1, 1, 2, 2, 3, 3, 5, 5, 6, 6, 7,
            7, 8, 8, 11, 11, 12, 12, 13, 13, 14, 14, 16, 16,
            17, 17, 18, 18, 19, 19, 22, 22, 23, 23, 24, 24, 25,
            25, 27, 27, 28, 28, 29, 29, 30, 30, 33, 33, 34, 34,
            35, 35, 36, 36, 38, 38, 39, 39, 40, 40, 41, 41, 44,
        ],
        7: [
            0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6,
            6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
            13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19,
            19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24, 25, 25,
            26, 26, 27, 27, 28, 28, 29, 29, 30, 30, 31, 31, 32,
        ],
        14: [
            0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18,
            19, 21, 22, 24, 25, 27, 28, 30, 31, 33, 34, 36, 37,
            39, 40, 42, 43, 45, 46, 48, 49, 51, 52, 54, 55, 57,
            58, 60, 61, 63, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
        ],
        15: [
            0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24,
            26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50,
            52, 54, 56, 58, 60, 62, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
            64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
        ],
    ]

    func testAll1040CanonicalModeInputPairsMatchIndependentOracle() {
        let offsets = [0, -1, -2, -4, -8, -16, 0, 0, 0, 1, 2, 4, 8, 16, 0, 0]
        for mode in 0...15 {
            for volume in 0...64 {
                let expected = scaling[mode]?[volume] ?? min(64, max(0, volume + offsets[mode]))
                let result = PlaybackSongSyntheticAdapter.retriggerVolumeAdjustment(modeNibble: mode, currentVolume: volume)
                XCTAssertEqual(result.modeNibble, mode)
                XCTAssertEqual(result.volumeBefore, volume)
                XCTAssertEqual(result.volumeAfter, expected, "mode \(mode), input \(volume)")
                XCTAssertEqual(result.changed, volume != expected)
            }
        }
    }

    func testScalingRepeatedApplicationsMatchEveryObservedIntermediate() {
        let sequences: [Int: [[Int]]] = [
            6: [
                [0, 0],
                [1, 0, 0],
                [2, 1, 0, 0],
                [3, 1, 0, 0],
                [4, 2, 1, 0, 0],
                [15, 8, 5, 2, 1, 0, 0],
                [16, 11, 6, 3, 1, 0, 0],
                [31, 19, 12, 7, 3, 1, 0, 0],
                [32, 22, 14, 8, 5, 2, 1, 0, 0],
                [33, 22, 14, 8, 5, 2, 1, 0, 0],
                [63, 41, 27, 17, 11, 6, 3, 1, 0, 0],
                [64, 44, 29, 18, 12, 7, 3, 1, 0, 0],
            ],
            7: [
                [0, 0],
                [1, 0, 0],
                [2, 1, 0, 0],
                [3, 1, 0, 0],
                [4, 2, 1, 0, 0],
                [15, 7, 3, 1, 0, 0],
                [16, 8, 4, 2, 1, 0, 0],
                [31, 15, 7, 3, 1, 0, 0],
                [32, 16, 8, 4, 2, 1, 0, 0],
                [33, 16, 8, 4, 2, 1, 0, 0],
                [63, 31, 15, 7, 3, 1, 0, 0],
                [64, 32, 16, 8, 4, 2, 1, 0, 0],
            ],
            14: [
                [0, 0],
                [1, 1],
                [2, 3, 4, 6, 9, 13, 19, 28, 42, 63, 64, 64],
                [3, 4, 6, 9, 13, 19, 28, 42, 63, 64, 64],
                [4, 6, 9, 13, 19, 28, 42, 63, 64, 64],
                [15, 22, 33, 49, 64, 64],
                [16, 24, 36, 54, 64, 64],
                [31, 46, 64, 64],
                [32, 48, 64, 64],
                [33, 49, 64, 64],
                [63, 64, 64],
                [64, 64],
            ],
            15: [
                [0, 0],
                [1, 2, 4, 8, 16, 32, 64, 64],
                [2, 4, 8, 16, 32, 64, 64],
                [3, 6, 12, 24, 48, 64, 64],
                [4, 8, 16, 32, 64, 64],
                [15, 30, 60, 64, 64],
                [16, 32, 64, 64],
                [31, 62, 64, 64],
                [32, 64, 64],
                [33, 64, 64],
                [63, 64, 64],
                [64, 64],
            ],
        ]
        for (mode, cases) in sequences {
            for expected in cases {
                var volume = expected[0]
                for next in expected.dropFirst() {
                    volume = PlaybackSongSyntheticAdapter.retriggerVolumeAdjustment(modeNibble: mode, currentVolume: volume).volumeAfter
                    XCTAssertEqual(volume, next, "mode \(mode), start \(expected[0])")
                }
                XCTAssertEqual(expected.last, expected[expected.count - 2]) // Fixed point or clamp reached.
            }
        }
    }

    func testCanonicalInputClampPreventsOverflowAndPreservesExactRules() {
        for (input, canonical) in [(Int.min, 0), (-1, 0), (65, 64), (Int.max, 64)] {
            for mode in 0...15 {
                let result = PlaybackSongSyntheticAdapter.retriggerVolumeAdjustment(modeNibble: mode, currentVolume: input)
                let canonicalResult = PlaybackSongSyntheticAdapter.retriggerVolumeAdjustment(modeNibble: mode, currentVolume: canonical)
                XCTAssertEqual(result, canonicalResult)
            }
        }
    }
}
