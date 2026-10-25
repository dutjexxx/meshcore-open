import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../helpers/gif_helper.dart';
import '../storage/prefs_manager.dart';

/// Voice layer: reads incoming messages aloud (text-to-speech) and turns
/// speech into text for sending (speech-to-text). Everything uses the
/// phone's own engines, so it works offline when the language packs are
/// downloaded in Android settings.
class VoiceService extends ChangeNotifier {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  static const _kTtsEnabled = 'voice_tts_enabled';
  static const _kLocale = 'voice_locale';
  static const _kOnDevice = 'voice_on_device';
  static const _kAutoSend = 'voice_auto_send';
  static const _maxSpokenChars = 300;

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _ttsReady = false;
  bool _sttReady = false;
  bool _listening = false;
  String _lastError = '';

  /// Called with the final recognized text when listening ends.
  void Function(String text)? _onFinal;
  String _latestWords = '';
  bool _finalDelivered = false;

  bool get ttsEnabled =>
      PrefsManager.instance.getBool(_kTtsEnabled) ?? true;

  /// Locale id such as `nl_NL` or `en_US`. Empty = device default.
  String get locale => PrefsManager.instance.getString(_kLocale) ?? '';

  /// Force on-device recognition (needs offline language pack).
  bool get onDevice => PrefsManager.instance.getBool(_kOnDevice) ?? true;

  /// Send the dictated text right away when the talk button is released.
  bool get autoSend => PrefsManager.instance.getBool(_kAutoSend) ?? true;

  bool get isListening => _listening;
  String get lastError => _lastError;

  Future<void> setTtsEnabled(bool value) async {
    await PrefsManager.instance.setBool(_kTtsEnabled, value);
    if (!value) await _tts.stop();
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    await PrefsManager.instance.setString(_kLocale, value);
    _ttsReady = false; // re-apply language on next speak
    notifyListeners();
  }

  Future<void> setOnDevice(bool value) async {
    await PrefsManager.instance.setBool(_kOnDevice, value);
    notifyListeners();
  }

  Future<void> setAutoSend(bool value) async {
    await PrefsManager.instance.setBool(_kAutoSend, value);
    notifyListeners();
  }

  // ───────────────────────── Text to speech ─────────────────────────

  Future<void> _initTts() async {
    if (_ttsReady) return;
    try {
      final tag = locale.replaceAll('_', '-');
      if (tag.isNotEmpty) await _tts.setLanguage(tag);
      await _tts.setSpeechRate(0.5);
      await _tts.setQueueMode(1); // queue messages instead of cutting off
      await _tts.awaitSpeakCompletion(false);
      _ttsReady = true;
    } catch (e) {
      debugPrint('[Voice] TTS init failed: $e');
    }
  }

  /// Reads an incoming message aloud. [sender] is spoken first when given.
  Future<void> speakIncoming({String? sender, required String text}) async {
    if (!ttsEnabled) return;
    var body = text.trim();
    if (body.isEmpty) return;
    // Skip things that make no sense spoken (GIFs, bare links).
    if (GifHelper.parseGif(body) != null) return;
    body = body.replaceAll(RegExp(r'https?://\S+'), 'link');
    if (body.length > _maxSpokenChars) {
      body = '${body.substring(0, _maxSpokenChars)}…';
    }
    final who = (sender ?? '').trim();
    final line = who.isEmpty ? body : '$who: $body';
    try {
      await _initTts();
      await _tts.speak(line);
    } catch (e) {
      debugPrint('[Voice] speak failed: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  // ───────────────────────── Speech to text ─────────────────────────

  Future<bool> _initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onError: _onSttError,
        onStatus: _onSttStatus,
      );
    } catch (e) {
      _lastError = '$e';
      _sttReady = false;
    }
    return _sttReady;
  }

  void _onSttError(SpeechRecognitionError error) {
    _lastError = error.errorMsg;
    debugPrint('[Voice] STT error: ${error.errorMsg}');
    // "no match"/"speech timeout" just mean nothing was heard.
    _finishListening();
  }

  void _onSttStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _finishListening();
    }
  }

  void _finishListening() {
    final wasListening = _listening;
    _listening = false;
    if (wasListening) notifyListeners();
    if (!_finalDelivered) {
      _finalDelivered = true;
      final text = _latestWords.trim();
      if (text.isNotEmpty) _onFinal?.call(text);
    }
  }

  /// Starts listening. Returns false (and sets [lastError]) if the
  /// microphone permission or speech engine is not available.
  Future<bool> startListening({
    required void Function(String text) onFinal,
  }) async {
    if (_listening) return true;
    await stopSpeaking(); // never listen while talking
    _lastError = '';
    if (!await _initStt()) {
      if (_lastError.isEmpty) _lastError = 'speech_unavailable';
      return false;
    }
    _onFinal = onFinal;
    _latestWords = '';
    _finalDelivered = false;
    _listening = true;
    notifyListeners();
    try {
      await _stt.listen(
        onResult: _onSttResult,
        localeId: locale.isEmpty ? null : locale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          onDevice: onDevice,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _lastError = '$e';
      _listening = false;
      notifyListeners();
      return false;
    }
    return true;
  }

  void _onSttResult(SpeechRecognitionResult result) {
    _latestWords = result.recognizedWords;
    if (result.finalResult) _finishListening();
  }

  /// Stops listening; the recognized text is delivered to the callback.
  Future<void> stopListening() async {
    if (!_listening) return;
    try {
      await _stt.stop();
    } catch (_) {}
    // Give the engine a moment to flush the final result.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _finishListening();
  }

  /// Languages the speech engine offers, for the settings dialog.
  Future<List<LocaleName>> availableLocales() async {
    if (!await _initStt()) return const [];
    return _stt.locales();
  }
}
