import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import '../config/aws_config.dart';

class _CompressStep {
  final int edge;
  final int quality;

  const _CompressStep(this.edge, this.quality);
}

/// S3 图片上传服务
///
/// 使用 Minio 客户端（兼容 AWS S3）上传图片到 S3。
/// 小于 5MB 的原档直接上传；达到 5MB 时转成 JPEG 再压，直到小于 5MB。
class S3UploadService {
  static const int _maxUploadBytes = 5 * 1024 * 1024;

  /// 只在原档达到 5MB 时使用。长边最高 1280，品质由高到低，直到小于 5MB。
  static const List<_CompressStep> _compressSteps = [
    _CompressStep(1280, 80),
    _CompressStep(1280, 65),
    _CompressStep(1024, 55),
    _CompressStep(800, 45),
    _CompressStep(640, 40),
    _CompressStep(480, 30),
  ];

  /// 上传图片到 S3
  ///
  /// 参数：
  /// - imageFile: 要上传的图片文件
  /// - caseId: 案件 ID
  /// - userId: 用户 ID
  /// - onProgress: 上传进度回调（可选）
  ///
  /// 返回：包含 image_key 和 image_url 的 Map
  static Future<Map<String, String>> uploadImage({
    required File imageFile,
    required int caseId,
    required int userId,
    Function(double)? onProgress,
  }) async {
    File? compressedFile;
    try {
      if (!await imageFile.exists()) {
        throw Exception('图片文件不存在');
      }

      final uploadFile = await _fileUnderLimit(imageFile);
      if (uploadFile == null) {
        throw Exception('图片无法压缩到 5MB 以下');
      }
      if (uploadFile.path != imageFile.path) {
        compressedFile = uploadFile;
      }

      final fileSize = await uploadFile.length();
      final fileName = path.basename(uploadFile.path);
      final fileExtension = path.extension(uploadFile.path).toLowerCase();

      debugPrint('========== S3 上传开始 ==========');
      debugPrint('文件名: $fileName');
      debugPrint('文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('文件扩展名: $fileExtension');

      if (fileSize >= _maxUploadBytes) {
        throw Exception('图片无法压缩到 5MB 以下');
      }

      final validExtensions = ['.jpg', '.jpeg', '.png', '.gif'];
      if (!validExtensions.contains(fileExtension)) {
        throw Exception('不支持的图片格式，仅支持: ${validExtensions.join(', ')}');
      }

      final s3Key = AWSConfig.generateS3Key(
        caseId: caseId,
        userId: userId,
        fileExtension: fileExtension,
      );

      debugPrint('S3 Key: $s3Key');
      debugPrint('Bucket: ${AWSConfig.bucketName}');
      debugPrint('Region: ${AWSConfig.region}');

      final minio = Minio(
        endPoint: AWSConfig.endpoint,
        accessKey: AWSConfig.accessKeyId,
        secretKey: AWSConfig.secretAccessKey,
        useSSL: true,
        region: AWSConfig.region,
      );

      final mimeType = lookupMimeType(uploadFile.path) ?? 'image/jpeg';
      debugPrint('MIME Type: $mimeType');

      final stream =
          uploadFile.openRead().map((chunk) => Uint8List.fromList(chunk));

      debugPrint('开始上传...');
      await minio.putObject(
        AWSConfig.bucketName,
        s3Key,
        stream,
        size: fileSize,
        onProgress: onProgress != null
            ? (bytesUploaded) => onProgress(bytesUploaded / fileSize)
            : null,
        metadata: {
          'Content-Type': mimeType,
          'caseId': caseId.toString(),
          'userId': userId.toString(),
        },
      );

      final imageUrl = AWSConfig.getImageUrl(s3Key);

      debugPrint('上传成功！');
      debugPrint('Image URL: $imageUrl');
      debugPrint('===================================');

      return {
        'image_key': s3Key,
        'image_url': imageUrl,
      };
    } catch (e, stackTrace) {
      debugPrint('========== S3 上传失败 ==========');
      debugPrint('错误: $e');
      debugPrint('堆栈: $stackTrace');
      debugPrint('===================================');

      final message = e.toString();
      if (message.contains('图片文件不存在') ||
          message.contains('图片无法压缩到 5MB 以下') ||
          message.contains('不支持的图片格式')) {
        if (e is Exception) rethrow;
        throw Exception(message);
      } else if (message.contains('NoSuchBucket')) {
        throw Exception('S3 Bucket 不存在');
      } else if (message.contains('InvalidAccessKeyId')) {
        throw Exception('AWS 访问密钥无效');
      } else if (message.contains('SignatureDoesNotMatch')) {
        throw Exception('AWS 密钥签名错误');
      } else if (message.contains('AccessDenied')) {
        throw Exception('S3 访问被拒绝，请检查权限');
      } else {
        throw Exception('上传失败: $e');
      }
    } finally {
      if (compressedFile != null && await compressedFile.exists()) {
        try {
          await compressedFile.delete();
        } catch (e) {
          debugPrint('删除暂存压缩档失败: $e');
        }
      }
    }
  }

  /// 小于 5MB 的档案原样上传。达到 5MB 时转成 JPEG 再压，长边不超过 1280。
  static Future<File?> _fileUnderLimit(File source) async {
    final length = await source.length();
    debugPrint('原始大小: ${(length / 1024).toStringAsFixed(2)} KB');
    if (length < _maxUploadBytes) {
      return source;
    }

    debugPrint('超过 5MB，开始压缩');
    final encodedSize = await _encodedSize(source);
    for (final step in _compressSteps) {
      final width = encodedSize?.width.round() ?? 0;
      final height = encodedSize?.height.round() ?? 0;
      final box = encodedSize == null
          ? step.edge
          : _compressBox(width, height, step.edge);
      final sampleSize = encodedSize == null
          ? 1
          : _sampleSize(math.max(width, height), step.edge);
      Uint8List? bytes;
      try {
        // minWidth/minHeight 会把短边对齐这个值。传正方形、边长为
        // 目标长边 × 短边 / 长边，长边才会落在 step.edge。
        bytes = await FlutterImageCompress.compressWithFile(
          source.absolute.path,
          minWidth: box,
          minHeight: box,
          quality: step.quality,
          inSampleSize: sampleSize,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
      } catch (e) {
        debugPrint('压缩失败 edge=${step.edge} quality=${step.quality}: $e');
        continue;
      }

      if (bytes == null || bytes.isEmpty) {
        debugPrint('压缩无结果 edge=${step.edge} quality=${step.quality}');
        continue;
      }

      debugPrint(
        '压缩结果 edge=${step.edge} box=$box quality=${step.quality} '
        'size=${(bytes.length / 1024).toStringAsFixed(2)} KB',
      );
      if (bytes.length < _maxUploadBytes) {
        final temp = File(
          '${Directory.systemTemp.path}/s3_upload_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await temp.writeAsBytes(bytes, flush: true);
        return temp;
      }
    }

    return null;
  }

  static Future<ui.Size?> _encodedSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final size = ui.Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
        descriptor.dispose();
        if (size.width <= 0 || size.height <= 0) return null;
        return size;
      } finally {
        buffer.dispose();
      }
    } catch (e) {
      debugPrint('读取图片尺寸失败: $e');
      return null;
    }
  }

  /// 套件会把短边对齐 [box]。[box] = 目标长边 × 短边 / 长边时，长边才是 [longEdge]。
  static int _compressBox(int width, int height, int longEdge) {
    final longSide = math.max(width, height);
    final shortSide = math.min(width, height);
    if (longSide <= longEdge) return shortSide;
    return math.max(1, (longEdge * shortSide) ~/ longSide);
  }

  /// 解码时先缩小，避免超大原图在压到目标长边前吃满内存。
  static int _sampleSize(int longSide, int longEdge) {
    var sample = 1;
    while (sample < 32 && longSide / (sample * 2) >= longEdge) {
      sample *= 2;
    }
    return sample;
  }

  /// 测试 S3 连接
  ///
  /// 返回：是否连接成功
  static Future<bool> testConnection() async {
    try {
      debugPrint('测试 S3 连接...');

      final minio = Minio(
        endPoint: AWSConfig.endpoint,
        accessKey: AWSConfig.accessKeyId,
        secretKey: AWSConfig.secretAccessKey,
        useSSL: true,
        region: AWSConfig.region,
      );

      final exists = await minio.bucketExists(AWSConfig.bucketName);

      if (exists) {
        debugPrint('✅ S3 连接成功！Bucket 存在。');
        return true;
      } else {
        debugPrint('❌ Bucket 不存在');
        return false;
      }
    } catch (e) {
      debugPrint('❌ S3 连接失败: $e');
      return false;
    }
  }
}
