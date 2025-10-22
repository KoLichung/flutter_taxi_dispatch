# AWS S3 配置说明

## 🔐 安全配置

`aws_config.dart` 包含 AWS 凭证，已加入 `.gitignore`，**不会被提交到 Git**。

---

## 📝 初始设置

### **1. 复制示例文件**

```bash
cp lib/config/aws_config.dart.example lib/config/aws_config.dart
```

### **2. 编辑配置**

打开 `lib/config/aws_config.dart`，填入实际的 AWS 凭证：

```dart
class AWSConfig {
  static const String accessKeyId = 'AKIAXXXXXXXXXXXXX';
  static const String secretAccessKey = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
  static const String region = 'ap-northeast-1';
  static const String bucketName = 'your-bucket-name';
  // ...
}
```

### **3. 测试连接**

在 app 中运行：

```dart
final success = await S3UploadService.testConnection();
print('S3 连接: ${success ? "成功 ✅" : "失败 ❌"}');
```

---

## 🔑 获取 AWS 凭证

### **方法 1：使用现有凭证**

如果你有 AWS 凭证，直接填入即可。

### **方法 2：创建新的 IAM 用户**

1. 登录 [AWS IAM Console](https://console.aws.amazon.com/iam/)
2. 创建新用户，勾选"Programmatic access"
3. 附加权限：`AmazonS3FullAccess`（或自定义限制权限）
4. 记录 **Access Key ID** 和 **Secret Access Key**

---

## ⚠️ 重要提示

### **不要提交凭证到 Git**

```bash
# 检查 .gitignore 是否包含
git check-ignore lib/config/aws_config.dart

# 应该输出：lib/config/aws_config.dart
```

### **生产环境安全建议**

1. **不要硬编码密钥**
   - 使用环境变量
   - 使用后端生成的临时凭证

2. **限制 IAM 权限**
   ```json
   {
     "Effect": "Allow",
     "Action": ["s3:PutObject", "s3:GetObject"],
     "Resource": "arn:aws:s3:::your-bucket/case_messages/*"
   }
   ```

3. **定期轮换密钥**
   - 每 3-6 个月更换一次
   - 发现泄露立即轮换

---

## 📂 文件说明

- `aws_config.dart.example` - 配置模板（已提交到 Git）
- `aws_config.dart` - 实际配置（不提交到 Git）
- `README.md` - 本说明文档

---

## 🆘 问题排查

### **问题：编译错误 - 找不到 aws_config.dart**

```
Error: Cannot find 'lib/config/aws_config.dart'
```

**解决方案**：
```bash
cp lib/config/aws_config.dart.example lib/config/aws_config.dart
# 然后编辑填入凭证
```

### **问题：上传失败 - 权限错误**

```
AccessDenied: S3 访问被拒绝
```

**解决方案**：
- 检查 IAM 用户权限
- 检查 Bucket Policy
- 验证 Access Key 是否正确

---

## 🔄 团队协作

### **新成员加入**

1. 获取 AWS 凭证（询问团队负责人）
2. 复制 `aws_config.dart.example` 为 `aws_config.dart`
3. 填入凭证并测试

### **凭证更新**

当 AWS 凭证更新时：
1. 更新本地 `aws_config.dart`
2. **不要提交到 Git**
3. 通知团队成员更新

