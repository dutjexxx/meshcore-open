import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' show LocaleName;

import '../services/voice_service.dart';

/// Push-to-talk button: press and hold to speak, release to put the
/// recognized text in [controller] (and send it when auto-send is on).
///
/// Uses a raw pointer [Listener] (no gesture arena, no tooltip) so it reacts
/// the moment the finger touches the button.
class VoiceMicButton extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const VoiceMicButton({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  bool _held = false;

  static String _explain(String error) {
    if (error.contains('language')) {
      return 'Taalpakket ontbreekt of wordt niet ondersteund ($error). '
          'Download het offline pakket of zet "Alleen offline herkenning" '
          'uit in Spraakinstellingen.';
    }
    if (error.contains('permission')) {
      return 'Geen microfoonrechten. Geef ze in Instellingen → Apps → '
          'MeshCore Open → Rechten.';
    }
    if (error.contains('network') || error.contains('server')) {
      return 'Geen internet voor spraakherkenning ($error). Download het '
          'offline pakket voor je taal.';
    }
    if (error.contains('busy')) {
      return 'Spraakherkenning is bezig ($error). Probeer het zo opnieuw.';
    }
    if (error.isEmpty ||
        error.contains('no_match') ||
        error.contains('timeout')) {
      return 'Niets verstaan. Houd de knop ingedrukt, wacht tot hij rood is '
          'en praat dan.';
    }
    return 'Niets herkend (fout: $error).';
  }

  Future<void> _down() async {
    _held = true;
    final voice = VoiceService();
    final messenger = ScaffoldMessenger.maybeOf(context);
    HapticFeedback.mediumImpact();
    final ok = await voice.startListening(
      onFinal: (text) {
        final c = widget.controller;
        final existing = c.text.trim();
        c.text = existing.isEmpty ? text : '$existing $text';
        c.selection = TextSelection.collapsed(offset: c.text.length);
        if (voice.autoSend) {
          HapticFeedback.lightImpact();
          widget.onSend();
        }
      },
      onNothing: (error) {
        messenger?.showSnackBar(SnackBar(content: Text(_explain(error))));
      },
    );
    if (!ok) {
      _held = false;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Spraakherkenning niet beschikbaar (${voice.lastError}). '
            'Controleer de microfoonrechten en het offline taalpakket.',
          ),
        ),
      );
      return;
    }
    // Finger already lifted while the engine was starting (e.g. during the
    // first-time permission dialog): stop right away.
    if (!_held) await voice.stopListening();
  }

  Future<void> _up() async {
    if (!_held) return;
    _held = false;
    await VoiceService().stopListening();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Houd ingedrukt om te praten',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: ListenableBuilder(
          listenable: VoiceService(),
          builder: (context, _) {
            final listening = VoiceService().isListening;
            return Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening ? Colors.red : scheme.secondaryContainer,
              ),
              child: Icon(
                listening ? Icons.mic : Icons.mic_none,
                size: 24,
                color: listening ? Colors.white : scheme.onSecondaryContainer,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dialog with the voice options (reading aloud, language, offline mode).
Future<void> showVoiceSettingsDialog(BuildContext context) async {
  final voice = VoiceService();
  final locales = await voice.availableLocales();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: voice,
      builder: (context, _) => AlertDialog(
        title: const Text('Spraak'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Berichten voorlezen'),
                value: voice.ttsEnabled,
                onChanged: voice.setTtsEnabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatisch verzenden na inspreken'),
                value: voice.autoSend,
                onChanged: voice.setAutoSend,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alleen offline herkenning'),
                subtitle: const Text(
                  'Vereist het offline taalpakket in Android-instellingen',
                ),
                value: voice.onDevice,
                onChanged: voice.setOnDevice,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: locales.any((l) => l.localeId == voice.locale)
                    ? voice.locale
                    : '',
                decoration: const InputDecoration(labelText: 'Taal'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Standaard van toestel'),
                  ),
                  for (final LocaleName l in locales)
                    DropdownMenuItem(
                      value: l.localeId,
                      child: Text(l.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => voice.setLocale(v ?? ''),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => voice.speakIncoming(
                  sender: 'Test',
                  text: 'Dit is een test van de voorleesstem.',
                ),
                child: const Text('Test voorlezen'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    ),
  );
}
