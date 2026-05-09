import importlib.util, math, struct, sys, tempfile, unittest, wave
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "audio-compare.py"


def load_audio_compare_module():
    spec = importlib.util.spec_from_file_location("audio_compare", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


audio_compare = load_audio_compare_module()


def write_sine_wav(path, sample_rate=8000, channels=1, seconds=0.25, amplitude=0.5):
    frame_count = int(sample_rate * seconds)
    frames = bytearray()
    for frame in range(frame_count):
        sample = math.sin(2.0 * math.pi * 440.0 * frame / sample_rate)
        value = int(max(-1.0, min(1.0, sample * amplitude)) * 32767)
        for _ in range(channels):
            frames.extend(struct.pack("<h", value))

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(bytes(frames))


class AudioCompareTests(unittest.TestCase):
    def test_identical_files_report_correlation_and_no_first_difference(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_sine_wav(reference)
            write_sine_wav(candidate)

            report = audio_compare.build_report(reference, candidate, 1.0, 1.0e-4)

            self.assertIn("Sample rate: match (8000 Hz)", report)
            self.assertIn("Channels: match (1)", report)
            self.assertIn("Normalized correlation: 1.00000000", report)
            self.assertIn("First difference > 0.0001: none within analyzed window", report)

    def test_level_difference_is_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_sine_wav(reference, amplitude=0.5)
            write_sine_wav(candidate, amplitude=0.25)

            report = audio_compare.build_report(reference, candidate, 1.0, 1.0e-4)

            self.assertIn("RMS level difference: -6.02 dB", report)
            self.assertIn("Peak level difference: -6.02 dB", report)
            self.assertIn("First difference > 0.0001: 0.000125 s", report)

    def test_sample_rate_mismatch_skips_sample_comparison(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_sine_wav(reference, sample_rate=8000)
            write_sine_wav(candidate, sample_rate=11025)

            report = audio_compare.build_report(reference, candidate, 1.0, 1.0e-4)

            self.assertIn(
                "Sample rate: mismatch (reference 8000 Hz, candidate 11025 Hz)",
                report,
            )
            self.assertIn("Skipped because sample rate or channel count differs.", report)
