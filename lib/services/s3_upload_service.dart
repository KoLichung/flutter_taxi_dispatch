import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import '../config/aws_config.dart';

/// S3 图片上传服务
/// 
/// 使用 Minio 客户端（兼容 AWS S3）上传图片到 S3
class S3UploadService {
  /// 上传图片到 S3
  /// 
  /// 参数：
  /// - imageFile: 要上传的图片文件
  /// - caseId: 案件 ID
  /// - userId: 用户 ID
  /// - onProgress: 上传进度回调（可选）
  /// 
  /// 返回：包含 image_key 和 image_url 的 Map
  /// 
  /// 示例：
  /// ```dart
  /// final result = await S3UploadService.uploadImage(
  ///   imageFile: file,
  ///   caseId: 123,
  ///   userId: 456,
  ///   onProgress: (progress) => print('进度: $progress%'),
  /// );
  /// print('Image Key: ${result['image_key']}');
  /// print('Image URL: ${result['image_url']}');
  /// ```
  static Future<Map<String, String>> uploadImage({
    required File imageFile,
    required int caseId,
    required int userId,
    Function(double)? onProgress,
  }) async {
    try {
      // 1. 检查文件是否存在
      if (!await imageFile.exists()) {
        throw Exception('图片文件不存在');
      }

      // 2. 获取文件信息
      final fileSize = await imageFile.length();
      final fileName = path.basename(imageFile.path);
      final fileExtension = path.extension(imageFile.path).toLowerCase();
      
      debugPrint('========== S3 上传开始 ==========');
      debugPrint('文件名: $fileName');
      debugPrint('文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('文件扩展名: $fileExtension');

      // 3. 验证文件大小（限制 5MB）
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('图片大小不能超过 5MB');
      }

      // 4. 验证文件类型
      final validExtensions = ['.jpg', '.jpeg', '.png', '.gif'];
      if (!validExtensions.contains(fileExtension)) {
        throw Exception('不支持的图片格式，仅支持: ${validExtensions.join(', ')}');
      }

      // 5. 生成 S3 key
      final s3Key = AWSConfig.generateS3Key(
        caseId: caseId,
        userId: userId,
        fileExtension: fileExtension,
      );
      
      debugPrint('S3 Key: $s3Key');
      debugPrint('Bucket: ${AWSConfig.bucketName}');
      debugPrint('Region: ${AWSConfig.region}');

      // 6. 创建 Minio 客户端
      final minio = Minio(
        endPoint: AWSConfig.endpoint,
        accessKey: AWSConfig.accessKeyId,
        secretKey: AWSConfig.secretAccessKey,
        useSSL: true,
        region: AWSConfig.region, // 显式指定区域
      );

      // 7. 获取 MIME 类型
      final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
      debugPrint('MIME Type: $mimeType');

      // 8. 读取文件内容并转换为 Uint8List Stream
      final stream = imageFile.openRead().map((chunk) => Uint8List.fromList(chunk));
      
      // 9. 上传到 S3
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

      // 10. 生成图片 URL
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
      
      // 转换 Minio 错误为更友好的消息
      if (e.toString().contains('NoSuchBucket')) {
        throw Exception('S3 Bucket 不存在');
      } else if (e.toString().contains('InvalidAccessKeyId')) {
        throw Exception('AWS 访问密钥无效');
      } else if (e.toString().contains('SignatureDoesNotMatch')) {
        throw Exception('AWS 密钥签名错误');
      } else if (e.toString().contains('AccessDenied')) {
        throw Exception('S3 访问被拒绝，请检查权限');
      } else {
        throw Exception('上传失败: $e');
      }
    }
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
        region: AWSConfig.region, // 显式指定区域
      );

      // 尝试列出 bucket（验证凭证和权限）
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

