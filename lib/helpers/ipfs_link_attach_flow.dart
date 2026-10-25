import 'dart:convert';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import 'ipfs_upload_helper.dart';
import 'snack_bar_builder.dart';

/// Shared "send image via IPFS" flow for the direct-message and channel chat
/// screens: picks a file, uploads it with the configured IPFS settings and
/// puts the resulting link at the start of the composer draft.
///
/// [maxBytes] is the screen's outbound byte limit and [encodeOutbound] turns
/// draft text into what the radio would actually send, so the limit is
/// checked against the encoded form.
Future<void> attachIpfsLinkToDraft({
  required BuildContext context,
  required TextEditingController controller,
  required FocusNode focusNode,
  required int maxBytes,
  required String Function(String text) encodeOutbound,
}) async {
  final l10n = context.l10n;
  final settings = context.read<AppSettingsService>().settings;
  if (settings.uploadIpfsEndpoint.trim().isEmpty) {
    showDismissibleSnackBar(
      context,
      content: Text(l10n.chat_ipfsUploadNotConfigured),
    );
    return;
  }

  void showFailure(Object error) {
    if (!context.mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(l10n.chat_ipfsUploadFailed('$error')),
    );
  }

  final file_selector.XFile? file;
  try {
    file = await file_selector.openFile();
  } on Exception catch (error) {
    showFailure(error);
    return;
  }
  if (file == null || !context.mounted) return;

  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } on Exception catch (error) {
    showFailure(error);
    return;
  }
  if (!context.mounted) return;
  if (bytes.isEmpty) {
    showFailure('The selected file is empty.');
    return;
  }

  final String messageUrl;
  try {
    messageUrl = await IpfsUploadHelper.uploadImageWithSettings(
      settings: settings,
      bytes: bytes,
      fileName: file.name,
      mimeType: IpfsUploadHelper.mimeTypeForFileName(file.name),
    );
  } on Exception catch (error) {
    showFailure(error);
    return;
  }
  if (!context.mounted) return;

  final messageText = composeIpfsLinkDraft(
    messageUrl: messageUrl,
    existingText: controller.text.trim(),
    maxBytes: maxBytes,
    encodeOutbound: encodeOutbound,
  );
  if (messageText == null) {
    showDismissibleSnackBar(
      context,
      content: Text(l10n.chat_messageTooLong(maxBytes)),
    );
    return;
  }

  controller.value = TextEditingValue(
    text: messageText,
    selection: TextSelection.collapsed(offset: messageText.length),
  );
  focusNode.requestFocus();
}

/// Builds the draft with [messageUrl] in front of [existingText], trimming
/// [existingText] from the end until the encoded result fits [maxBytes].
/// Returns null when even the link alone does not fit.
@visibleForTesting
String? composeIpfsLinkDraft({
  required String messageUrl,
  required String existingText,
  required int maxBytes,
  required String Function(String text) encodeOutbound,
}) {
  bool fits(String text) =>
      utf8.encode(encodeOutbound(text)).length <= maxBytes;

  final messageText = existingText.isEmpty
      ? '$messageUrl '
      : '$messageUrl\n$existingText';
  if (fits(messageText)) return messageText;
  if (existingText.isEmpty) return null;

  final originalCharacters = existingText.characters.toList();
  for (var count = originalCharacters.length - 1; count >= 0; count--) {
    final candidate = '$messageUrl\n${originalCharacters.take(count).join()}';
    if (fits(candidate)) return candidate;
  }
  return null;
}
