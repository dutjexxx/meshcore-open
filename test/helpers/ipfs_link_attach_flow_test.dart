import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/ipfs_link_attach_flow.dart';

void main() {
  const url = 'ipfs://cid';
  String identity(String text) => text;

  test('puts the link before an empty draft with a trailing space', () {
    expect(
      composeIpfsLinkDraft(
        messageUrl: url,
        existingText: '',
        maxBytes: 100,
        encodeOutbound: identity,
      ),
      '$url ',
    );
  });

  test('keeps a draft that fits after the link', () {
    expect(
      composeIpfsLinkDraft(
        messageUrl: url,
        existingText: 'hello',
        maxBytes: 100,
        encodeOutbound: identity,
      ),
      '$url\nhello',
    );
  });

  test('trims the draft until the encoded text fits', () {
    expect(
      composeIpfsLinkDraft(
        messageUrl: url,
        existingText: 'hello',
        maxBytes: url.length + 3,
        encodeOutbound: identity,
      ),
      '$url\nhe',
    );
  });

  test('measures the encoded form', () {
    expect(
      composeIpfsLinkDraft(
        messageUrl: url,
        existingText: 'hello',
        maxBytes: url.length + 3,
        encodeOutbound: (text) => 'x$text',
      ),
      '$url\nh',
    );
  });

  test('returns null when the link alone does not fit', () {
    expect(
      composeIpfsLinkDraft(
        messageUrl: url,
        existingText: 'hello',
        maxBytes: 4,
        encodeOutbound: identity,
      ),
      isNull,
    );
    expect(
      composeIpfsLinkDraft(
        messageUrl: url,
        existingText: '',
        maxBytes: 4,
        encodeOutbound: identity,
      ),
      isNull,
    );
  });
}
