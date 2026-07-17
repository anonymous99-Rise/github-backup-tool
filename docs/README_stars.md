# GitHub Backup Tools

> 批量备份/恢复 GitHub 仓库和 Stars，一键搞定

## 功能

| 脚本 | 作用 |
|------|------|
| `fetch_stars.ps1` | 动态抓取任意账号的 Stars，输出 JSON |
| `restore_stars.ps1` | 读取 JSON，把 Stars 恢复到自己账号 |
| `backup.ps1` | 备份仓库（Windows PowerShell 版） |
| `backup_stars.ps1` | 备份 Stars 镜像（完整 clone） |

## 使用方法

### 1. 抓取 Stars

```powershell
# 无 Token（只能获取 public stars，有 rate limit）
powershell -ExecutionPolicy Bypass -File fetch_stars.ps1 "adminlove520"

# 有 Token（更快，可以获取 private stars）
powershell -ExecutionPolicy Bypass -File fetch_stars.ps1 "adminlove520" -Token "ghp_xxx"

# 指定输出文件
powershell -ExecutionPolicy Bypass -File fetch_stars.ps1 "adminlove520" -OutputFile "my_stars.json"
```

输出文件：`stars_adminlove520.json`

### 2. 恢复 Stars

```powershell
# JSON 文件放在脚本同目录下，会自动识别
powershell -ExecutionPolicy Bypass -File restore_stars.ps1 "ghp_xxx"

# 或手动指定 JSON 和日志
powershell -ExecutionPolicy Bypass -File restore_stars.ps1 -Token "ghp_xxx" -JsonFile "my_stars.json" -LogFile "restore.log"
```

### 3. 备份仓库

```powershell
# 用 Token 备份速度快
powershell -ExecutionPolicy Bypass -File backup.ps1 -Token "ghp_xxx"

# 不用 Token（匿名，速度慢）
powershell -ExecutionPolicy Bypass -File backup.ps1
```

## 实时查看日志

```powershell
# 另开一个窗口
Get-Content restore_stars.log -Wait -Tail 20
```

## JSON 格式

```json
[
  {
    "full_name": "owner/repo",
    "html_url": "https://github.com/owner/repo",
    "updated_at": "2024-01-01T00:00:00Z"
  },
  ...
]
```

## 注意事项

- **Token 权限**：需要 `repo` scope 才能 star private 仓库
- **Rate Limit**：无 Token 每小时 60 次，有 Token 每小时 5000 次
- **Star 恢复**：重复 star 会返回 304，属于正常跳过
- **数据安全**：Token 只存储在本地脚本参数中，不会传给他人
