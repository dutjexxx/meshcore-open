import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/helpers/ipfs_upload_helper.dart';

void main() {
  group('IpfsUploadHelper', () {
    tearDown(() => IpfsUploadHelper.httpClient = null);

    test('does not upload when the upload endpoint is empty', () async {
      var requestCount = 0;
      IpfsUploadHelper.httpClient = MockClient((request) async {
        requestCount++;
        return http.Response('{}', 200);
      });

      await expectLater(
        IpfsUploadHelper.uploadImage(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          fileName: 'image.png',
          mimeType: 'image/png',
          uploadEndpoint: '',
          uploadApiKey: '',
        ),
        throwsArgumentError,
      );
      expect(requestCount, 0);
    });

    test(
      'uploads and returns an ipfs scheme when upload gateway is empty',
      () async {
        final requests = <http.BaseRequest>[];
        IpfsUploadHelper.httpClient = MockClient((request) async {
          requests.add(request);
          expect(request.method, 'POST');
          return http.Response(
            '{"Hash":"bafybeibq75ws6nwk6wi473dch42wwy6woyj4dwdfy7nfz3buqx2caieoly"}',
            200,
          );
        });

        final message = await IpfsUploadHelper.uploadImage(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          fileName: 'image.png',
          mimeType: 'image/png',
          uploadEndpoint: 'http://127.0.0.1:5001/api/v0/add',
          uploadApiKey: '',
        );

        expect(
          message,
          'ipfs://bafybeibq75ws6nwk6wi473dch42wwy6woyj4dwdfy7nfz3buqx2caieoly',
        );
        expect(requests.first.url.path, '/api/v0/add');
        expect(requests.first.url.queryParameters, {
          'cid-version': '1',
          'pin': 'true',
        });
      },
    );

    test('sends the Pinata request to the endpoint unchanged', () async {
      late http.BaseRequest upload;
      IpfsUploadHelper.httpClient = MockClient((request) async {
        upload = request;
        return http.Response('{"IpfsHash":"bafytest"}', 200);
      });

      final message = await IpfsUploadHelper.uploadImage(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        fileName: 'image.png',
        mimeType: 'image/png',
        uploadEndpoint: 'https://api.pinata.cloud/pinning/pinFileToIPFS',
        uploadApiKey: 'jwt',
        uploadGateway: 'https://gateway.example.com',
      );

      expect(
        upload.url.toString(),
        'https://api.pinata.cloud/pinning/pinFileToIPFS',
      );
      expect(upload.headers['Authorization'], 'Bearer jwt');
      expect(message, 'https://gateway.example.com/ipfs/bafytest');
    });
  });
}
