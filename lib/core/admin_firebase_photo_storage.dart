import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../firebase_options.dart';

enum AdminFirebasePhotoUploadStage {
  readImage,
  initialize,
  authenticate,
  createFileName,
  initializeStorage,
  createReference,
  upload,
  downloadUrl,
}

class AdminFirebasePhotoUploadException implements Exception {
  const AdminFirebasePhotoUploadException({
    required this.stage,
    this.errorCode,
    this.errorType,
  });

  final AdminFirebasePhotoUploadStage stage;
  final String? errorCode;
  final String? errorType;

  String get userMessage {
    final message = switch (stage) {
      AdminFirebasePhotoUploadStage.readImage => 'تعذرت قراءة ملف الصورة',
      AdminFirebasePhotoUploadStage.initialize => 'تعذر تهيئة خدمة الصور',
      AdminFirebasePhotoUploadStage.authenticate =>
        'تعذر التحقق من صلاحية رفع الصورة',
      AdminFirebasePhotoUploadStage.createFileName =>
        'تعذر إنشاء اسم الصورة',
      AdminFirebasePhotoUploadStage.initializeStorage =>
        'تعذر تهيئة مخزن الصور',
      AdminFirebasePhotoUploadStage.createReference =>
        'تعذر إنشاء مسار الصورة',
      AdminFirebasePhotoUploadStage.upload => 'تعذر رفع الصورة إلى التخزين',
      AdminFirebasePhotoUploadStage.downloadUrl =>
        'تم رفع الصورة لكن تعذر تجهيز رابطها',
    };
    final diagnostic = errorCode ?? errorType;
    return diagnostic == null ? message : '$message ($diagnostic)';
  }
}

class AdminFirebasePhotoStorage {
  static const _maxFileSize = 5 * 1024 * 1024;
  static const _appName = 'gofast-admin-web';
  static const _projectId = 'godrive-d7f94';
  static const _storageBucket = 'godrive-d7f94.firebasestorage.app';
  static Future<FirebaseApp>? _appInitialization;

  static Future<FirebaseApp> initialize() => _firebaseApp();

  static Future<String> upload({
    required Dio client,
    required Options apiOptions,
    required String scope,
    required String objectId,
    required XFile image,
  }) async {
    if (scope != 'staff' && scope != 'driver') {
      throw ArgumentError.value(scope, 'scope');
    }
    _validateObjectId(objectId);
    final bytes = await _runAtStage(
      AdminFirebasePhotoUploadStage.readImage,
      image.readAsBytes,
    );
    if (bytes.isEmpty || bytes.length > _maxFileSize) {
      throw const FormatException('حجم الصورة غير صالح أو يتجاوز 5 ميجابايت');
    }

    final extension = image.name.toLowerCase().split('.').last;
    const contentTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final contentType = contentTypes[extension];
    if (contentType == null) {
      throw const FormatException('امتداد الصورة غير مدعوم');
    }

    final app = await _runAtStage(
      AdminFirebasePhotoUploadStage.initialize,
      _firebaseApp,
    );
    final auth = await _runAtStage(
      AdminFirebasePhotoUploadStage.authenticate,
      () => _signInForTarget(
        app: app,
        client: client,
        apiOptions: apiOptions,
        scope: scope,
        objectId: objectId,
      ),
    );
    final storagePath = scope == 'staff' ? 'staff-profiles' : 'driver-profiles';
    try {
      final fileName = await _runAtStage(
        AdminFirebasePhotoUploadStage.createFileName,
        () async {
          final randomSuffix =
              Random.secure().nextInt(1 << 31).toRadixString(16);
          return '${DateTime.now().microsecondsSinceEpoch}_$randomSuffix.$extension';
        },
      );
      final storage = await _runAtStage(
        AdminFirebasePhotoUploadStage.initializeStorage,
        () async => FirebaseStorage.instanceFor(app: app),
      );
      final reference = await _runAtStage(
        AdminFirebasePhotoUploadStage.createReference,
        () async => storage.ref('$storagePath/$objectId/$fileName'),
      );
      await _runAtStage(
        AdminFirebasePhotoUploadStage.upload,
        () => reference.putData(
          bytes,
          SettableMetadata(contentType: contentType),
        ),
      );
      try {
        return await _runAtStage(
          AdminFirebasePhotoUploadStage.downloadUrl,
          reference.getDownloadURL,
        );
      } catch (_) {
        try {
          await reference.delete();
        } catch (_) {}
        rethrow;
      }
    } finally {
      try {
        await auth.signOut();
      } catch (_) {}
    }
  }

  static Future<T> _runAtStage<T>(
    AdminFirebasePhotoUploadStage stage,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on DioException {
      rethrow;
    } on AdminFirebasePhotoUploadException {
      rethrow;
    } catch (error, stackTrace) {
      final errorCode = error is FirebaseException ? error.code : null;
      Error.throwWithStackTrace(
        AdminFirebasePhotoUploadException(
          stage: stage,
          errorCode: errorCode,
          errorType: error.runtimeType.toString(),
        ),
        stackTrace,
      );
    }
  }

  static Future<void> deleteDownloadUrl({
    required Dio client,
    required Options apiOptions,
    required String scope,
    required String objectId,
    required String? value,
  }) async {
    if (scope != 'staff' && scope != 'driver') return;
    _validateObjectId(objectId);
    if (!_isTargetDownloadUrl(value, scope, objectId)) return;
    try {
      final app = await _firebaseApp();
      final auth = await _signInForTarget(
        app: app,
        client: client,
        apiOptions: apiOptions,
        scope: scope,
        objectId: objectId,
      );
      try {
        await FirebaseStorage.instanceFor(app: app).refFromURL(value!).delete();
      } finally {
        await auth.signOut();
      }
    } catch (_) {
      // The saved URL is authoritative; cleanup failure must not undo its update.
    }
  }

  static Future<FirebaseApp> _firebaseApp() async {
    if (!kIsWeb) {
      throw UnsupportedError('رفع صور الإدارة متاح من لوحة الويب فقط');
    }
    final existing = Firebase.apps.where((app) => app.name == _appName);
    if (existing.isNotEmpty) return _validateApp(existing.first);

    _appInitialization ??= Firebase.initializeApp(
      name: _appName,
      options: DefaultFirebaseOptions.web,
    );
    try {
      return _validateApp(await _appInitialization!);
    } catch (_) {
      _appInitialization = null;
      rethrow;
    }
  }

  static FirebaseApp _validateApp(FirebaseApp app) {
    if (app.options.projectId != _projectId ||
        app.options.storageBucket != _storageBucket) {
      throw StateError('Firebase مهيأ لمشروع أو Storage Bucket مختلف');
    }
    return app;
  }

  static Future<FirebaseAuth> _signInForTarget({
    required FirebaseApp app,
    required Dio client,
    required Options apiOptions,
    required String scope,
    required String objectId,
  }) async {
    final response = await client.post<Map<String, dynamic>>(
      '/api/admin/firebase-photo-token',
      data: {'scope': scope, 'objectId': objectId},
      options: apiOptions,
    );
    final customToken = response.data?['customToken']?.toString();
    if (customToken == null || customToken.isEmpty) {
      throw StateError('تعذر الحصول على صلاحية رفع الصورة');
    }
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.setPersistence(Persistence.NONE);
    await auth.signInWithCustomToken(customToken);
    return auth;
  }

  static bool _isTargetDownloadUrl(
    String? value,
    String scope,
    String objectId,
  ) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'firebasestorage.googleapis.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final storagePath = scope == 'staff' ? 'staff-profiles' : 'driver-profiles';
    final prefix =
        '/v0/b/$_storageBucket/o/${Uri.encodeComponent('$storagePath/$objectId/')}';
    return uri.path.startsWith(prefix);
  }

  static void _validateObjectId(String objectId) {
    if (!RegExp(r'^[1-9]\d{0,9}$').hasMatch(objectId)) {
      throw ArgumentError.value(objectId, 'objectId');
    }
  }
}
