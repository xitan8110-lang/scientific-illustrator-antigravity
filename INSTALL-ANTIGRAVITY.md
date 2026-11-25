# Scientific Illustrator Agent — Antigravity Windows 一键迁移与安装指南

本仓库打包了完整可用的 `scientific-illustrator-agent` skill（含 Windows Antigravity 隔离桌面绕过规范）、配套的 `agent-desktop` MCP 工具（v1.3.1），以及一键安装脚本 `install-antigravity.ps1`，确保在新电脑上获得与原电脑**完全一致**的 Adobe Illustrator 绘图功能。

## 新电脑前置条件
- **Windows 10 / 11**
- 已安装并激活 **Adobe Illustrator**（建议先手动打开一次确认无弹窗）
- 已安装 **Antigravity**
- 已安装 **Python 3.9+** 或 **`uv`**（如果都没装，脚本会给出一条命令自动安装 `uv`，由 `uv` 自动拉取 Python 3.12）

---

## 新电脑安装步骤（二选一）

### 方式 A：直接 `git clone` 到全局 skills 目录（推荐，以后 `git pull` 就能同步更新）

打开 PowerShell，依次运行：

```powershell
mkdir "$env:USERPROFILE\.gemini\config\skills" -Force
git clone https://github.com/xitan8110-lang/scientific-illustrator-antigravity.git "$env:USERPROFILE\.gemini\config\skills\scientific-illustrator-agent"
cd "$env:USERPROFILE\.gemini\config\skills\scientific-illustrator-agent"
powershell -ExecutionPolicy Bypass -File .\install-antigravity.ps1
```

### 方式 B：直接从 GitHub 下载 ZIP 解压

1. 在 GitHub 仓库页面点击 **Code → Download ZIP** 并解压到任意文件夹。
2. 在解压后的文件夹里打开 PowerShell，运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-antigravity.ps1
```

脚本会自动把 skill 安装到 `%USERPROFILE%\.gemini\config\skills\scientific-illustrator-agent\`。

---

## 脚本自动完成的工作
1. 将 skill 安装到 `%USERPROFILE%\.gemini\config\skills\scientific-illustrator-agent\`；
2. 在该目录下创建干净的 `.venv` 并安装 `requirements.txt`（`pywin32`、`pydantic`、`Pillow`）；
3. 将 `agent-desktop.exe`（v1.3.1）安装到 `%USERPROFILE%\.local\bin\agent-desktop.exe`；
4. 安全合并 `agent-desktop` 配置到 `%USERPROFILE%\.gemini\config\mcp_config.json`（保留你原有的其他 MCP 配置）；
5. 自动校验 Python 虚拟环境与本地 `render_spec.py --validate-only`。

如需同时测试本机 Illustrator COM 连接，可追加 `-TestIllustrator` 参数：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-antigravity.ps1 -TestIllustrator
```

---

## 最后一步
安装完成后，**完全重启 Antigravity**（确保新写入的 `agent-desktop` MCP 与 skill 被重新加载），之后即可直接让 Antigravity 调用 Adobe Illustrator 绘图、逐元素叠加或生成多鼠标集群动画。
