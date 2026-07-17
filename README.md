# GitHub 仓库批量备份工具

adminlove520 全量仓库本地备份脚本，支持断点续传、失败重试。

## 使用方法（Windows）

### 方法一：直接运行 PowerShell（推荐）
```powershell
# 1. 克隆仓库
git clone https://github.com/adminlove520/github-backup-tool.git
cd github-backup-tool

# 2. 运行备份脚本
powershell -ExecutionPolicy Bypass -File backup.ps1
```

### 方法二：双击运行
下载仓库后双击 `run.bat` 即可启动备份。

## 使用方法（Linux / Mac）
```bash
git clone https://github.com/adminlove520/github-backup-tool.git
cd github-backup-tool
chmod +x backup.sh
./backup.sh
```

## 配置 Token（可选，加速克隆）

公共仓库也可以不填 Token 克隆，但有 Token 速度更快且不限速。

**方式一：运行时传入 Token**
```powershell
powershell -ExecutionPolicy Bypass -File backup.ps1 -Token "ghp_xxxx"
```

**方式二：编辑脚本，填到第 12 行**
```powershell
[string]$Token = "ghp_xxxx",   # 填你的 Token
```

Token 申请地址：https://github.com/settings/tokens
需要 `repo` 权限即可。

## 备份说明

- 脚本会自动创建 `github_backup_YYYYMMDD/` 目录
- 所有仓库以 `xxx.git` 镜像形式保存（包含所有分支和标签）
- 已存在的仓库会跳过（断点续传安全）
- 克隆失败会记录到 `.fail.txt`，稍后可以单独重试
- **不要修改 `repo_list.txt`**（仓库名列表）

## 仓库列表

共 **722** 个仓库（public），全部来自 adminlove520 账号。

## 常见问题

**Q: 提示"无法加载文件"？**
> 使用 `powershell -ExecutionPolicy Bypass -File backup.ps1` 运行。

**Q: 克隆失败/超时怎么办？**
> 脚本已自动处理失败仓库，记录在 `.fail.txt`，重新运行脚本即可继续。

**Q: 磁盘空间不够？**
> 722个仓库总大小预估 20-50GB，请确保有足够空间。

**Q: 可以只备份一部分吗？**
> 编辑 `repo_list.txt`，删除不需要的仓库名即可。
