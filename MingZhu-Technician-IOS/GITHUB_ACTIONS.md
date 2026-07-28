# GitHub Actions TestFlight 打包说明

## 仓库要求

把 `D:\RuoYiProjects2` 作为 GitHub 私有仓库根目录上传，至少需要包含：

- `.github/workflows/ios-technician-testflight.yml`
- `MingZhu-Technician-IOS/`

## 必填 Secrets

进入 GitHub 仓库：

`Settings -> Secrets and variables -> Actions -> New repository secret`

添加下面 3 个：

| Secret 名称 | 本地文件 |
| --- | --- |
| `IOS_P12_BASE64` | `D:\Codex\ios-certs\com.taimingzhu.ymz\github-secrets\IOS_P12_BASE64.txt` |
| `IOS_P12_PASSWORD` | `D:\Codex\ios-certs\com.taimingzhu.ymz\github-secrets\IOS_P12_PASSWORD.txt` |
| `IOS_MOBILEPROVISION_BASE64` | `D:\Codex\ios-certs\com.taimingzhu.ymz\github-secrets\IOS_MOBILEPROVISION_BASE64.txt` |

复制文件内容，不要复制文件路径。

## 可选：自动上传 TestFlight

如果只配置上面 3 个 Secrets，Actions 会打出 `.ipa`，需要你手动下载 artifact。

如果要自动上传 TestFlight，还要在 App Store Connect 生成 API Key，并添加：

| Secret 名称 | 内容 |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | API Key 的 Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | API Key 页面里的 Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `.p8` 私钥文件的 base64 内容 |

Windows 生成 `.p8` base64：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\path\AuthKey_XXXXXX.p8')) | Set-Content D:\path\APP_STORE_CONNECT_API_KEY_BASE64.txt -Encoding ascii
```

## 运行

GitHub 仓库页面：

`Actions -> iOS Technician TestFlight -> Run workflow`

成功后会生成 artifact：

`mingzhu-technician-ios-ipa`

如果配置了 App Store Connect API Key，会继续自动上传到 TestFlight。
