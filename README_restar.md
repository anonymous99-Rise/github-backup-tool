# GitHub Starred Restorer

把 `starred_repos.json`（2877个仓库）一键 Star 回新账号。

## 使用方法

```powershell
git clone https://github.com/adminlove520/github-backup-tool.git
cd github-backup-tool
powershell -ExecutionPolicy Bypass -File restar.ps1 -Token "ghp_新账号的token"
```

## 工作流程

1. `starred_repos.json` — 所有 Star 仓库的元数据（名字、地址、Git URL）
2. `restar.ps1` — 遍历 JSON，用新账号的 Token 逐个 PUT star
3. `starred_restored_list.txt` — 成功 Star 的记录（追加，不覆盖）

## 特点

- 先检查是否已 Star，已 Star 的跳过（幂等）
- 失败自动记录，可反复重跑
- 300ms 间隔，不触发限速
- 2877 个仓库约需 **15-20 分钟**

## JSON 格式

```json
[
  {
    "name": "OfficeCLI",
    "owner": "iOfficeAI",
    "full_name": "iOfficeAI/OfficeCLI",
    "url": "https://github.com/iOfficeAI/OfficeCLI",
    "git_url": "https://github.com/iOfficeAI/OfficeCLI.git"
  },
  ...
]
```
