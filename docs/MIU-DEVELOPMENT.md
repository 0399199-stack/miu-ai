# 换电脑继续开发 Miu AI

当前维护 Windows A 控制端与 B 被控端。默认分支 `main`，本次版本标签 `v2.4.1`。
`master` 是旧上游分支；不要从它继续 Miu 开发。安卓开发已停止。

## 1. 获取完整项目和历史

安装 Git；然后在新电脑的 PowerShell 执行（目录可自行更换）：

```powershell
New-Item -ItemType Directory -Path 'E:\Codex' -Force
git clone --recurse-submodules --branch main https://github.com/0399199-stack/miu-ai.git 'E:\Codex\Miu AI'
Set-Location 'E:\Codex\Miu AI'
git status
git log -5 --oneline
git submodule status
```

不要使用 `--depth 1`，这样能保留历史。GitHub 的普通源码 ZIP 不包含子模块内容和 Git 历史，不能替代这一步。
如果已经克隆但缺少子模块：`git submodule update --init --recursive`。

继续开发前先读 `AGENTS.md`、本文件、`docs/MIU-V2.4.1.md` 和 Release 验证报告。
本机旧路径 `E:\Codex\Miu AI\work\rustdesk-upstream` 只是之前的工作目录，不是代码依赖。

```powershell
# 已有仓库更新；先确认本地改动已提交或另存。
git switch main
git pull --ff-only
git submodule update --init --recursive

# 从确切的 V2.4.1 创建后续开发分支。
git switch -c dev/my-change v2.4.1
```

## 2. 推荐构建方式：GitHub Actions

不必将旧电脑的工具链和缓存全部搬走。当前可复用的完整构建流程在
`.github/workflows/miu-ai-test-windows-x64.yml`。

1. 将改动提交到你自己的分支并推送到此仓库。
2. GitHub → Actions → **Miu AI unsigned Windows x64 build** → Run workflow → 选择该分支。
3. 等待界面测试、Rust 测试、构建和打包完成。
4. 下载 `miu-ai-test-windows-x64-unsigned` artifact，其中包含便携 ZIP、MSI、源码提交信息和 SHA256。
5. 验证后再发布新 Release。便携包用作 A，MSI 用作 B；它们来自同一份 Windows 程序。

本仓库已停用旧安卓 CI，以及上游的 F-Droid、Tag、Nightly、Full Flutter CI 和 playground 多平台构建入口，避免标签发布时重新生成 APK。保留 Miu Windows 构建、桥接、窗口组件及安装验证流程；不要为 Windows 构建重新启用旧安卓流程。

已安装 GitHub CLI 时也可运行：

```powershell
gh auth login
gh workflow run miu-ai-test-windows-x64.yml --repo 0399199-stack/miu-ai --ref main
gh run list --repo 0399199-stack/miu-ai --workflow miu-ai-test-windows-x64.yml --limit 5
# 把 RUN_ID 替换成上一步实际编号。
gh run watch RUN_ID --repo 0399199-stack/miu-ai
gh run download RUN_ID --repo 0399199-stack/miu-ai --name miu-ai-test-windows-x64-unsigned --dir .\dist
```

构建会生成桥接代码、编译原生依赖、下载引擎和显示驱动资源，需要网络。
流程使用固定的主要工具链版本；不是离线构建，也没有宣称位级可复现。

## 3. 本地开发所需工具

以工作流中的具体步骤为准：Windows x64、Visual Studio C++ 桌面开发工具和 Windows SDK、Git、Python 3、Flutter 3.24.5、Rust 1.75、LLVM 15.0.6、CMake、Ninja、NASM、vcpkg（提交 `9e593bb18ea69cc5095e012465dcd675a822ed0d`，triplet `x64-windows-static`）。
辅助播放器使用 .NET Framework 4.8 / .NET SDK；MSI 打包使用 MSBuild、NuGet 和仓库 WiX 项目。
Windows Flutter 引擎需要按工作流替换为 RustDesk 引擎，并应用相同的 Flutter 补丁，不能省略。

桥接文件没有提交到仓库。第一次本地构建需按 `.github/workflows/bridge.yml` 生成，或从**同一源码提交**的构建下载 `bridge-artifact` 并解压到仓库根目录。
不要用另一个提交的桥接文件。资源、子模块和桥接完成后，核心构建命令为：

```powershell
python .\build.py --portable --flutter --skip-portable-pack --hwcodec --vram
```

这条命令不等同于完整 Miu 交付包。还必须执行工作流中的 MiuOverlay、MiuNotice、MiuBoot、WindowInjection、虚拟显示文件、授权文件和 MSI 打包步骤。
调色相关界面测试：在 `flutter` 目录执行 `flutter test test/miu_boot_controls_test.dart test/miu_toolbar_surface_test.dart test/miu_notice_composer_test.dart`。

## 4. 哪些数据不要上传 GitHub

源码仓库不包含你的 GitHub 登录、连接密码、主控私钥、DeepSeek Key、聊天记录或 Windows 用户配置。
换开发电脑只需克隆代码；若同时更换 A 使用电脑，需单独按应用的配对流程配置，不能把本机凭据当作源码提交。
B 的 Windows 受保护凭据不能靠复制普通配置文件保证迁移成功；必要时在 B 本机重新输入 Key。
旧 APK、安卓签名备份与本机构建缓存不参与 Windows 构建。
如果此前把 B 的唯一主控公钥改成了手机公钥，停止 APK 开发不会自动改变 B 的信任设置；需在 B 恢复 Windows A 的主控公钥。

## 5. 版本更新位置

同步修改 `Cargo.toml` 根包版本、`Cargo.lock` 中 `rustdesk` 根包版本、`flutter/pubspec.yaml` 的版本和 build number。
CI 的 MSI 版本从构建程序读取，revision 固定为 0；发布前核对 EXE、MSI 属性、Release 标签与文件名。
保留 `LICENCE` 与对应源码链接；不要提交配置、密钥、缓存或已安装程序目录。
