import 'dart:io';
import 'dart:typed_data';

import 'package:admin_panel/core/admin_firebase_photo_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('reports initialization stage when upload is unavailable', () async {
    final directory = await Directory.systemTemp.createTemp('photo-upload-');
    try {
      final image = File('${directory.path}/photo.png');
      await image.writeAsBytes(Uint8List.fromList([1, 2, 3]));
      await expectLater(
        AdminFirebasePhotoStorage.upload(
          client: Dio(),
          apiOptions: Options(),
          scope: 'staff',
          objectId: '1',
          image: XFile(image.path),
        ),
        throwsA(
          isA<AdminFirebasePhotoUploadException>().having(
            (error) => error.stage,
            'stage',
            AdminFirebasePhotoUploadStage.initialize,
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('reports file-read failures with their upload stage', () async {
    await expectLater(
      AdminFirebasePhotoStorage.upload(
        client: Dio(),
        apiOptions: Options(),
        scope: 'staff',
        objectId: '1',
        image: XFile('missing-photo.png'),
      ),
      throwsA(
        isA<AdminFirebasePhotoUploadException>()
            .having(
              (error) => error.stage,
              'stage',
              AdminFirebasePhotoUploadStage.readImage,
            )
            .having((error) => error.errorType, 'errorType', isNotNull),
      ),
    );
  });

  test('includes Firebase error code in user-facing message', () {
    const error = AdminFirebasePhotoUploadException(
      stage: AdminFirebasePhotoUploadStage.upload,
      errorCode: 'unauthorized',
    );

    expect(error.userMessage, 'تعذر رفع الصورة إلى التخزين (unauthorized)');
  });
}