import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' show LocaleName;

import '../services/voice_service.dart';

/// Push-to-talk button: hold to speak, release to put the recognized text in
/// [controller] (and send it when auto-send is on).
class VoiceMicButton extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const VoiceMicButton({
    super.key,
    required this.controller,
    required this.onSend,
  });

  Future<void> _start(BuildContext context) async {
    final voice = VoiceService();
    final messenger = ScaffoldMessenger.maybeOf(context);
    HapticFeedback.mediumImpact();
    final ok = await voice.startListening(
      onFinal: (text) {
        final existing = controller.text.trim();
        controller.text = existing.isEmpty ? text : '$existing $text';
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        if (voice.autoSend) {
          HapticFeedback.lightImpact();
          onSend();
        }
      },
    );
    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Spraakherkenning niet beschikbaar (${voice.lastError}). '
            'Controleer de microfoonrechten en het offline taalpakket.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: VoiceService(),
      builder: (context, _) {
        final listening = VoiceService().isListening;
        return GestureDetector(
          onLongPressStart: (_) => _start(context),
          onLongPressEnd: (_) => VoiceService().stopListening(),
          onLongPressCancel: () => VoiceService().stopListening(),
          child: Tooltip(
            message: 'Houd ingedrukt om te praten',
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening ? Colors.red : scheme.secondaryContainer,
              ),
              child: Icon(
                listening ? Icons.mic : Icons.mic_none,
                size: 22,
                color: listening ? Colors.white : scheme.onSecondaryContainer,
              ),
            ),
          ),
        );
      },
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
