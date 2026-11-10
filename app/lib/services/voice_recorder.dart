import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Nimmt eine Sprachnotiz auf und liefert sie als WAV-Datei.
///
/// Die Aufnahme läuft als Datenstrom (PCM 16 Bit). Das funktioniert im
/// Browser und auf iOS gleich und braucht keinen Dateipfad.
class VoiceRecorder {
  static const _sampleRate = 16000;

  final _recorder = AudioRecorder();
  final _chunks = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;

  /// Startet die Aufnahme. Liefert false, wenn das Mikrofon gesperrt ist.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    _chunks.clear();
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sampleRate, numChannels: 1),
    );
    _subscription = stream.listen(_chunks.add);
    return true;
  }

  /// Beendet die Aufnahme und liefert die WAV-Datei.
  Future<Uint8List> stop() async {
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    return wavFromPcm(_chunks.takeBytes(), sampleRate: _sampleRate);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _recorder.dispose();
  }
}

/// Setzt den WAV-Kopf (44 Byte) vor rohe PCM-Daten (16 Bit, mono).
Uint8List wavFromPcm(Uint8List pcm, {required int sampleRate, int channels = 1}) {
  final header = ByteData(44);
  void text(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  final byteRate = sampleRate * channels * 2;
  text(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  text(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}
