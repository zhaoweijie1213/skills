---
name: git-smart-commit
description: 智能 Git 提交技能。当用户想要提交代码、创建 PR、推送分支时触发。自动分析 git diff 生成符合 Conventional Commits 规范的中文提交说明（包含变动内容和原因），并基于当前检出分支（而非默认分支）进行操作。适用于 GitHub 和本地内网 Git 仓库。触发关键词：提交代码、commit、push、创建PR、推送分支、提交变更。
---

# Git Smart Commit 技能

帮助用户智能提交代码，自动分析代码差异生成规范的中文提交说明，并基于**当前检出分支**操作。

---

## 工作流程

### 第一步：收集环境信息

运行以下命令了解当前状态：

```bash
# 当前分支
git branch --show-current

# 暂存区和工作区状态
git status

# 查看未暂存的变更
git diff

# 查看已暂存的变更
git diff --staged

# 查看远程信息（判断是 GitHub 还是内网 Git）
git remote -v
```

如果暂存区为空（没有 `git add` 过的文件），询问用户：
- 是否要 `git add .` 暂存所有变更
- 还是只暂存部分文件

### 第二步：分析变更，生成提交说明

基于 `git diff --staged`（或 `git diff` 如果还未暂存）的输出，分析：

1. **变动了什么**：新增/修改/删除了哪些功能、文件、逻辑
2. **为什么变动**：从代码上下文推断目的（修复 bug、新增功能、重构、配置变更等）

#### Conventional Commits 格式规范

```
<类型>(<范围>): <中文简短描述>

<详细说明>
- 变动内容：...
- 变动原因：...
```

**类型对照表：**

| 类型 | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `refactor` | 重构（不影响功能） |
| `chore` | 构建/工具/依赖变更 |
| `docs` | 文档变更 |
| `style` | 代码格式（不影响逻辑） |
| `test` | 测试相关 |
| `perf` | 性能优化 |
| `ci` | CI/CD 配置 |
| `revert` | 回滚提交 |

**范围**：填写影响的模块/目录名，如 `auth`、`api`、`user`，可省略。

#### 示例提交说明

```
feat(auth): 新增手机号验证码登录功能

- 变动内容：在登录模块新增短信验证码发送和校验接口，前端增加验证码输入框
- 变动原因：原有账号密码登录方式安全性不足，用户反馈希望支持更便捷的登录方式
```

### 第三步：展示并确认

将生成的提交说明展示给用户，格式如下：

```
📋 建议的提交说明：
─────────────────────────────
[完整的 commit message]
─────────────────────────────
确认提交？还是需要修改说明？
```

**等待用户确认**后再执行提交。如用户要求修改，重新生成后再次确认。

### 第四步：执行提交

用户确认后：

```bash
# 如需先暂存
git add .   # 或指定文件

# 提交（使用 -F 避免 shell 转义问题）
git commit -m "<第一行>" -m "<详细说明部分>"
```

### 第五步：判断是否需要 Push 和 PR

询问用户下一步：
- **仅本地提交**：流程结束
- **Push + 创建 PR**：继续以下步骤

---

## Push 和创建 PR 流程

### Push 到远程

```bash
# 获取当前分支名
BRANCH=$(git branch --show-current)

# Push 当前分支（不是默认分支！）
git push origin "$BRANCH"

# 如果是首次推送该分支
git push -u origin "$BRANCH"
```

⚠️ **重要**：始终使用 `git branch --show-current` 获取当前分支，**绝不假设**目标分支是 `main` 或 `master`。

### 创建 PR

#### GitHub 仓库（使用 gh CLI）

```bash
# 检查是否安装了 gh
gh --version

# 获取默认分支作为目标（base）
BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")

# 创建 PR，source 是当前分支，target 是仓库默认分支
gh pr create \
  --base "$BASE" \
  --head "$BRANCH" \
  --title "<commit 第一行>" \
  --body "<详细说明，包含变动内容和原因>"
```

如果 `gh` 未安装，提示用户：
```
gh CLI 未安装。请访问 https://cli.github.com 安装，
或手动在 GitHub 页面创建 PR：从 <当前分支> → <目标分支>
```

#### 内网 Git 仓库

内网 Git 通常没有 `gh` CLI，改为：
1. 运行 `git push origin "$BRANCH"`
2. 输出远程仓库地址，提示用户手动在 Web 界面创建 PR
3. 如果远程是 GitLab，尝试使用 `glab` CLI（与 gh 类似）

```bash
# GitLab
glab mr create --source-branch "$BRANCH" --target-branch "$BASE" \
  --title "<标题>" --description "<描述>"
```

---

## 边界情况处理

| 情况 | 处理方式 |
|------|----------|
| 工作区干净，没有变更 | 提示"当前没有需要提交的变更" |
| 处于 detached HEAD 状态 | 警告用户，建议先切换到具名分支 |
| 当前分支与远程有冲突 | 提示先 `git pull --rebase` |
| 变更太大（diff > 500行） | 仍然分析，但建议用户考虑拆分提交 |
| 用户不满意生成的说明 | 重新生成，或引导用户补充上下文 |
| 暂存区与工作区都有变更 | 优先分析暂存区，询问是否一并提交工作区变更 |

---

## 注意事项

- **语言**：所有提交说明（commit message、PR title、PR description）均使用**中文**
- **分支**：永远基于 `git branch --show-current` 的结果操作，不硬编码分支名
- **确认**：提交、push、创建 PR 前必须展示内容并等待用户确认
- **最小权限**：不执行 `git push --force`，不修改远程分支保护设置
