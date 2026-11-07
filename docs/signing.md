# 发布签名

release 包沿用 **debug keystore** 签名（`applicationId` 是自用包名，没上架商店）。
换机器、重新生成 debug keystore 都会导致证书变化，老用户就无法覆盖安装，所以这把文件必须长期保管。

## 证书指纹

```
主体 DN : C=US, O=Android, CN=Android Debug
SHA-1   : 26:07:CB:96:32:16:32:FC:FB:25:9D:EE:1B:6A:05:D1:61:2C:FB:E7
SHA-256 : D7:21:19:35:8E:40:62:2A:DC:14:39:35:A1:E9:CE:4A:04:96:58:B6:A8:FD:0C:7D:95:8E:EB:A7:02:77:82:FC
```

## 本地配置

在 `android/` 下放两个**不入库**的文件（都已在 `.gitignore` 里）：

```
android/key.properties
  storeFile=sakura-release.jks
  storePassword=android
  keyAlias=androiddebugkey
  keyPassword=android

android/sakura-release.jks
```

没有 `key.properties` 时 `android/app/build.gradle.kts` 会回落到 debug 签名，效果等价于本机 `~/.android/debug.keystore`。

## 校验收货

```bash
keytool -list -v -keystore android/sakura-release.jks -storepass android -alias androiddebugkey | grep SHA256
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

两者 SHA-256 一致 = 能覆盖安装线上 v1.2.x。

## versionCode 约定

发布一律用 `flutter build apk --release --split-per-abi`：AGP 会按 ABI 加偏移
（arm64 = 2000 + n、x86_64 = 4000 + n，例如 `1.2.5+62` → arm64 `2062`、x86_64 `4062`）。
改成不带 split 的单包构建会得到裸值 `62`，小于线上用户的 `2062`，安装时会
`INSTALL_FAILED_VERSION_DOWNGRADE`。

## 历史

| 版本 | 证书 SHA-256 | 说明 |
| --- | --- | --- |
| v1.0.0 – v1.1.0 | `ecbc3784…` | 早期构建机的 debug keystore，私钥已丢失 |
| v1.2.0 – v1.2.5 | `d7211935…` | 当前这把 |

v1.0.x / v1.1.0 的用户在 v1.2.0 时已经历过一次签名变更，只能卸载重装；旧私钥无法从已发布 APK 反推。
