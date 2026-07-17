# GitHub 仓库批量备份工具

adminlove520 全量仓库本地备份脚本，支持断点续传、失败重试。

## 使用方法

### Windows
```powershell
# 1. 克隆本仓库
git clone https://github.com/adminlove520/github-backup-tool.git
cd github-backup-tool

# 2. 运行备份脚本
bash backup.sh
# 或者用 Git Bash
./backup.sh
```

### Linux / Mac
```bash
git clone https://github.com/adminlove520/github-backup-tool.git
cd github-backup-tool
chmod +x backup.sh
./backup.sh
```

## 备份说明

- 脚本会自动创建 `github_backup_YYYYMMDD/` 目录
- 所有仓库以 `xxx.git` 镜像形式保存（包含所有分支和标签）
- 已存在的仓库会跳过（断点续传安全）
- 克隆失败会记录到 `.fail.txt`，稍后可以单独重试
- **不要修改 `repo_list.txt`**（仓库名列表）

## 仓库列表

共 **722** 个仓库（public），全部来自 adminlove520 账号。

## 常见问题

**Q: 克隆失败/超时怎么办？**
> 脚本已自动处理失败仓库，记录在 `.fail.txt`，重新运行脚本即可继续。

**Q: 磁盘空间不够？**
> 722个仓库总大小预估 20-50GB，请确保有足够空间。

**Q: 可以只备份一部分吗？**
> 编辑 `repo_list.txt`，删除不需要的仓库名即可。
