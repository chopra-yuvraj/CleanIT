// CleanIT — Sound Service
//
// Generates and plays short audio tones for key app events.
// Uses programmatic WAV generation — no external audio files needed.
// Works on Web, Android, and iOS via audioplayers package.

import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum AppSound {
  /// Student broadcasts a new request — upbeat ascending tone
  requestCreated,

  /// Cleaner receives a new request — alert notification tone
  requestReceived,

  /// QR code scanned successfully — bright success chime
  qrSuccess,

  /// Job completed — celebratory fanfare
  jobCompleted,

  /// Error occurred — low warning tone
  error,
}

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _player = AudioPlayer();

  /// Play a sound for the given app event.
  Future<void> play(AppSound sound) async {
    try {
      final wavBytes = _generateTone(sound);
      await _player.play(BytesSource(wavBytes));
    } catch (e) {
      debugPrint('Sound play error: $e');
    }
  }

  /// Generate a WAV byte array for the given sound type.
  Uint8List _generateTone(AppSound sound) {
    switch (sound) {
      case AppSound.requestCreated:
        // Ascending two-note tone: C5 → E5 (upbeat)
        return _buildChime([
          _Note(523, 0.15), // C5
          _Note(659, 0.20), // E5
        ]);
      case AppSound.requestReceived:
        // Alert tone: E5 → E5 → G5 (attention-grabbing)
        return _buildChime([
          _Note(659, 0.10), // E5
          _Note(0, 0.05),   // pause
          _Note(659, 0.10), // E5
          _Note(784, 0.20), // G5
        ]);
      case AppSound.qrSuccess:
        // Quick success: G5 → C6 (bright)
        return _buildChime([
          _Note(784, 0.12), // G5
          _Note(1047, 0.25), // C6
        ]);
      case AppSound.jobCompleted:
        // Celebration: C5 → E5 → G5 → C6 (ascending arpeggio)
        return _buildChime([
          _Note(523, 0.10), // C5
          _Note(659, 0.10), // E5
          _Note(784, 0.10), // G5
          _Note(1047, 0.30), // C6
        ]);
      case AppSound.error:
        // Low warning: A3 → F3 (descending)
        return _buildChime([
          _Note(220, 0.15), // A3
          _Note(175, 0.25), // F3
        ]);
    }
  }

  /// Build a WAV file from a sequence of notes.
  Uint8List _buildChime(List<_Note> notes) {
    const sampleRate = 22050;
    const bitsPerSample = 16;
    const numChannels = 1;

    // Calculate total samples
    int totalSamples = 0;
    for (final note in notes) {
      totalSamples += (note.duration * sampleRate).round();
    }

    final dataSize = totalSamples * (bitsPerSample ~/ 8);
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    int offset = 0;

    // ── WAV Header ──
    // "RIFF"
    buffer.setUint8(offset++, 0x52); // R
    buffer.setUint8(offset++, 0x49); // I
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint8(offset++, 0x46); // F
    buffer.setUint32(offset, fileSize, Endian.little); offset += 4;
    // "WAVE"
    buffer.setUint8(offset++, 0x57); // W
    buffer.setUint8(offset++, 0x41); // A
    buffer.setUint8(offset++, 0x56); // V
    buffer.setUint8(offset++, 0x45); // E
    // "fmt "
    buffer.setUint8(offset++, 0x66); // f
    buffer.setUint8(offset++, 0x6D); // m
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x20); // (space)
    buffer.setUint32(offset, 16, Endian.little); offset += 4; // chunk size
    buffer.setUint16(offset, 1, Endian.little); offset += 2;  // PCM format
    buffer.setUint16(offset, numChannels, Endian.little); offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little); offset += 4;
    buffer.setUint32(offset, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little); offset += 4;
    buffer.setUint16(offset, numChannels * (bitsPerSample ~/ 8), Endian.little); offset += 2;
    buffer.setUint16(offset, bitsPerSample, Endian.little); offset += 2;
    // "data"
    buffer.setUint8(offset++, 0x64); // d
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint8(offset++, 0x74); // t
    buffer.setUint8(offset++, 0x61); // a
    buffer.setUint32(offset, dataSize, Endian.little); offset += 4;

    // ── Generate PCM samples ──
    for (final note in notes) {
      final numSamples = (note.duration * sampleRate).round();
      for (int i = 0; i < numSamples; i++) {
        double sample = 0;
        if (note.frequency > 0) {
          // Sine wave with volume envelope (fade in/out)
          final t = i / sampleRate;
          final envelope = _envelope(i, numSamples);
          sample = sin(2 * pi * note.frequency * t) * envelope * 0.6;
        }
        final intSample = (sample * 32767).round().clamp(-32768, 32767);
        buffer.setInt16(offset, intSample, Endian.little);
        offset += 2;
      }
    }

    return buffer.buffer.asUint8List();
  }

  /// Smooth envelope: quick fade in, sustain, smooth fade out.
  double _envelope(int sampleIndex, int totalSamples) {
    final fadeIn = (totalSamples * 0.05).round();
    final fadeOut = (totalSamples * 0.3).round();

    if (sampleIndex < fadeIn) {
      return sampleIndex / fadeIn;
    } else if (sampleIndex > totalSamples - fadeOut) {
      return (totalSamples - sampleIndex) / fadeOut;
    }
    return 1.0;
  }

  void dispose() {
    _player.dispose();
  }
}

class _Note {
  final double frequency; // Hz (0 = silence)
  final double duration;  // seconds

  const _Note(this.frequency, this.duration);
}
