# GitHub Backup Tools

> 批量备份/恢复 GitHub 仓库和 Stars，开源通用工具

## 目录结构

```
github-backup-tool/
├── scripts/
│   ├── backup/
│   │   ├── backup.sh          # Linux/Mac 备份脚本
│   │   ├── backup.ps1         # Windows 备份脚本
│   │   └── backup_stars.sh    # Linux Stars 全量备份
│   ├── restore/
│   │   ├── restore_stars.ps1  # Stars 恢复（一键）
│   │   └── restore_repos.ps1  # 仓库批量恢复（断点续传）
│   └── fetch/
│       └── fetch_stars.ps1     # 抓取 Stars 为 JSON
├── data/
│   ├── repo_list.txt          # 仓库列表
│   ├── starred_repos.json     # Stars JSON
│   └── starred_list.txt       # Stars 列表
└── docs/
    └── README_stars.md        # Stars 工具详细说明
```

## 快速开始

### 备份（任意 GitHub 账号）

```powershell
# Windows - 备份仓库
powershell -ExecutionPolicy Bypass -File scripts/backup/backup.ps1 -Token "ghp_xxx"

# Windows - 备份 Stars
powershell -ExecutionPolicy Bypass -File scripts/backup/backup_stars.ps1 -Token "ghp_xxx"
```

```bash
# Linux/Mac - 备份仓库
bash scripts/backup/backup.sh -t "ghp_xxx"

# Linux/Mac - 备份 Stars
bash scripts/backup/backup_stars.sh -t "ghp_xxx"
```

### 恢复（恢复到任意账号）

```powershell
# Stars 恢复 - 只需传 Token，自动识别账号+找JSON
powershell -ExecutionPolicy Bypass -File scripts/restore/restore_stars.ps1 "ghp_xxx"

# 仓库批量恢复 - 断点续传，大仓库超时重试
powershell -ExecutionPolicy Bypass -File scripts/restore/restore_repos.ps1 "ghp_xxx"
```

### 抓取 Stars JSON（给其他人用）

```powershell
# 抓取任意账号的 Stars
powershell -ExecutionPolicy Bypass -File scripts/fetch/fetch_stars.ps1 "username" -Token "ghp_xxx"
```

## 功能对比

| 工具 | 作用 | 速度 |
|------|------|------|
| `backup.ps1/sh` | 备份仓库镜像到本地 | 慢（逐个 clone） |
| `backup_stars.ps1/sh` | 备份 Stars 全量镜像 | 很慢（2877 个） |
| `restore_stars.ps1` | 从 JSON 恢复 Stars | 快（API star） |
| `restore_repos.ps1` | 从备份恢复到新账号 | 中等（push mirror） |
| `fetch_stars.ps1` | 抓取 Stars 为 JSON | 快 |

## 常见问题

**Q: 服务器被注销了，本地备份还能用吗？**
可以。`.git` 目录是完整镜像，重新 push 到新账号：
```powershell
cd 备份目录
git push --mirror https://github.com/新账号/仓库名.git
```

**Q: 断网了怎么办？**
`restore_repos.ps1` 有断点续传，`.state` 文件记录进度，重跑自动跳过已完成的。

**Q: 大仓库推送超时？**
```powershell
# 调大超时时间（秒）
powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx" -PushTimeoutSec 1800
```

## License

MIT
