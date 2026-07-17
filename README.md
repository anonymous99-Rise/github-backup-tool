# GitHub 仓库备份工具箱

> 适用于 adminlove520 账号护网期间仓库备份，支持：新仓库镜像备份、Star 仓库一键恢复。

---

## 目录

- [一、仓库构成](#一仓库构成)
- [二、快速开始](#二快速开始)
- [三、backup.ps1（备份自有仓库）](#三backupps1备份自有仓库)
- [四、restar.ps1（恢复 Star 仓库）](#四restarps1恢复-star-仓库)
- [五、常见问题](#五常见问题)

---

## 一、仓库构成

| 仓库类型 | 数量 | 说明 |
|---------|------|------|
| 自有仓库 | 722 个 | `adminlove520` 名下的所有 public 仓库 |
| Star 仓库 | 2877 个 | `adminlove520` 账号 Star 过的所有仓库 |

---

## 二、快速开始

### 2.1 克隆备份工具箱

```powershell
# 任意目录执行
git clone https://github.com/adminlove520/github-backup-tool.git
cd github-backup-tool
```

### 2.2 查看工具箱内容

```
github-backup-tool/
├── backup.ps1           # 备份自有仓库（PowerShell版）
├── backup.sh           # 备份自有仓库（Bash版，Linux/Mac用）
├── restar.ps1          # 一键恢复 Star 仓库
├── repo_list.txt       # 722个自有仓库列表
├── starred_list.txt    # 2877个 Star 仓库列表（纯名字）
├── starred_repos.json  # 2877个 Star 仓库元数据（JSON格式）
└── README.md           # 本文件
```

---

## 三、backup.ps1（备份自有仓库）

### 3.1 功能说明

将 `adminlove520` 名下的 **722 个自有仓库**以 `git clone --mirror` 形式完整克隆到本地，包含所有分支、历史记录、标签。

### 3.2 参数说明

```powershell
powershell -ExecutionPolicy Bypass -File backup.ps1 `
    -Token "ghp_你的Token" `
    -BackupBaseDir "D:\github_repos\github_backup"
```

| 参数 | 必须 | 默认值 | 说明 |
|------|------|--------|------|
| `-Token` | ✅ | 无 | GitHub Personal Access Token，用于加速克隆 |
| `-BackupBaseDir` | ❌ | `D:\github_repos\github_backup` | 备份存放根目录 |

### 3.3 获取 Token

1. 打开：https://github.com/settings/tokens
2. 点击 **Generate new token (classic)**
3. 勾选 `repo` 权限（完全访问私有仓库）
4. 生成后复制 Token

> Token 格式：`ghp_xxxxxxxxxxxxxxxxxxxx`

### 3.4 运行示例

```powershell
cd D:\github_repos\github-backup-tool
powershell -ExecutionPolicy Bypass -File backup.ps1 -Token "ghp_xxxxxxxxxxxxxxxxxxxx"
```

### 3.5 输出说明

运行后会创建目录：`D:\github_repos\github_backup\github_backup_20250717`

每个仓库对应一个 `.git` 目录：
```
D:\github_repos\github_backup\
└── github_backup_20250717\
    ├── adminlove520_micro-agent.git\      # 仓库镜像
    ├── adminlove520_multi-agent-tasks.git\
    ├── adminlove520_multi-Cybersecurity.git\
    ├── ...
    ├── .done.txt       # 克隆成功的仓库列表
    ├── .fail.txt       # 克隆失败的仓库列表
    └── backup.log      # 完整日志
```

### 3.6 磁盘空间要求

- **722 个仓库** 总计约 **3.7 GB**
- 建议预留 **10 GB** 以上安全空间

---

## 四、restar.ps1（恢复 Star 仓库）

### 4.1 功能说明

将 `starred_repos.json` 中的 **2877 个 Star 仓库**一键 Star 到**新账号**。不需要 clone，只需要 API 权限。

### 4.2 适用场景

- 账号注销前导出 Star 列表
- 换新账号后一键恢复所有 Star
- 多账号管理、批量操作

### 4.3 参数说明

```powershell
powershell -ExecutionPolicy Bypass -File restar.ps1 `
    -Token "ghp_新账号的Token" `
    -JsonFile "$PSScriptRoot\starred_repos.json"
```

| 参数 | 必须 | 默认值 | 说明 |
|------|------|--------|------|
| `-Token` | ✅ | 无 | **新账号**的 GitHub Token |
| `-JsonFile` | ❌ | `$PSScriptRoot\starred_repos.json` | Star 仓库元数据文件 |

### 4.4 运行示例

```powershell
cd D:\github_repos\github-backup-tool
powershell -ExecutionPolicy Bypass -File restar.ps1 -Token "ghp_yyyy_新账号Token_yyyy"
```

### 4.5 工作原理

1. 读取 `starred_repos.json`
2. 遍历 2877 个仓库，调用 GitHub API：
   ```
   PUT https://api.github.com/user/starred/{owner}/{repo}
   ```
3. 先检查是否已经 Star，已有的跳过（幂等操作）
4. 成功的记录到 `starred_restored_list.txt`
5. 失败的记录到控制台，可重跑

### 4.6 运行时间

- 2877 个仓库，约需 **15-20 分钟**
- 300ms 间隔，不会触发 GitHub API 限速

### 4.7 Star 后的记录

```
starred_restored_list.txt  — 成功 Star 的仓库列表（追加，不覆盖）
```

---

## 五、常见问题

### Q1: 提示"无法加载文件，因为在此系统上禁止运行脚本"？

使用 `-ExecutionPolicy Bypass` 参数：
```powershell
powershell -ExecutionPolicy Bypass -File backup.ps1 -Token "..."
```

### Q2: Token 怎么填？

填你 GitHub 账号的 Personal Access Token，不是仓库地址里的 token。

格式：`ghp_` 开头的一串字符

### Q3: 克隆/Star 失败了怎么办？

脚本会自动记录失败内容：
- 克隆失败：`D:\github_backup\github_backup_日期\.fail.txt`
- Star 失败：控制台显示红色 `[FAIL]`，重新运行脚本即可重试

### Q4: 磁盘空间不够怎么办？

修改 `-BackupBaseDir` 参数，改到空间更大的盘：
```powershell
-BackupBaseDir "E:\Backup\github_backup"
```

### Q5: 可以只备份一部分仓库吗？

可以。编辑 `repo_list.txt` 或 `starred_list.txt`，删除不需要的行即可。

### Q6: 服务器被注销了，本地备份还能用吗？

可以。`.git` 目录就是完整镜像，重新 push 到新账号：
```powershell
cd D:\github_repos\github_backup\github_backup_日期\
git push --mirror https://github.com/新账号/仓库名.git
```

### Q7: git clone 速度很慢怎么办？

确保 Token 填对了，有 Token 和没 Token 速度差很多。

### Q8: restar.ps1 显示很多 [FAIL]？

仓库可能已被作者删除或改名，继续跑完，之后手动补 Star 即可。

---

## 更新日志

| 日期 | 内容 |
|------|------|
| 2025-07-17 | 初始版本：backup.ps1 + restar.ps1 + 722仓库 + 2877 Stars |
