---
name: qyq-sqlsugar
description: 使用 QYQ.Base.SqlSugar 创建数据库仓储层代码。当用户需要创建仓储类、仓储接口、或涉及 BaseRepository、SqlSugar 数据库访问层的任何操作时，必须使用此技能。触发关键词包括：创建仓储、Repository、仓储层、数据库访问层、BaseRepository、SqlSugar、IRepository。即使用户只是说"帮我建一个仓储"或"新增数据库访问"也应触发此技能。
---

# QYQ SqlSugar 仓储技能

基于 `QYQ.Base.SqlSugar` NuGet 包，按照项目架构规范生成仓储相关代码。

---

## 核心依赖

- **NuGet 包**：`QYQ.Base.SqlSugar`
- **BaseRepository 构造函数签名**：
  ```csharp
  public BaseRepository(ILogger logger, string connectionString, DbType dbType = DbType.MySql)
  ```
- **默认数据库类型**：MySql（绝大多数项目，无需显式传入 DbType）

---

## 第一步：判断项目架构

在生成代码前，先确认项目架构类型：

| 架构 | 实体位置 | 接口位置 | 实现位置 |
|------|----------|----------|----------|
| **DDD** | Domain 层 | Domain 层 | Infrastructure 层 |
| **三层** | Models 层 → `Entities/{数据库名}/` | Repository 层 → `{数据库名}/Interface/` | Repository 层 → `{数据库名}/` |

如果用户没有说明架构，询问后再生成。

---

## 第二步：确认连接字符串

根据实体所属数据库，从项目的 `DatabaseOptions` 中选择对应属性。

**规则**：
- 询问或根据上下文判断该实体属于哪个数据库（Log、User、Shop、Club、Game 等）
- 构造函数中通过 `IOptionsMonitor<DatabaseOptions>` 注入，取 `databaseOptions.CurrentValue.{对应属性}`
- 若项目只有单库或配置类结构不同，以用户实际提供的为准

---

## 第三步：生成代码

### DDD 架构

**Domain 层 — 实体**（文件名：`{Name}Entity.cs`）
```csharp
/// <summary>
/// {描述}
/// </summary>
public sealed class {Name}Entity
{
    // 属性根据需求填写
}
```

**Domain 层 — 仓储接口**（文件名：`I{Name}Repository.cs`）
```csharp
/// <summary>
/// {描述}仓储接口。
/// </summary>
public interface I{Name}Repository : {生命周期接口}
{
    // 自定义方法（若无则留空）
}
```

**Infrastructure 层 — 仓储实现**（文件名：`{Name}Repository.cs`）
```csharp
/// <summary>
/// 基于 SqlSugar 的{描述}仓储实现。
/// </summary>
public sealed class {Name}Repository(
    ILogger<{Name}Repository> logger,
    IOptionsMonitor<DatabaseOptions> databaseOptions)
    : BaseRepository<{Name}Entity>(logger, databaseOptions.CurrentValue.{DbProperty}), I{Name}Repository
{ }
```

---

### 三层架构

**Models 层** — 路径：`Entities/{数据库名}/{Name}Entity.cs`
```csharp
/// <summary>
/// {描述}
/// </summary>
public sealed class {Name}Entity
{
    // 属性根据需求填写
}
```

**Repository 层 — 接口** — 路径：`{数据库名}/Interface/I{Name}Repository.cs`
```csharp
/// <summary>
/// {描述}仓储接口。
/// </summary>
public interface I{Name}Repository : {生命周期接口}
{
    // 自定义方法（若无则留空）
}
```

**Repository 层 — 实现** — 路径：`{数据库名}/{Name}Repository.cs`
```csharp
/// <summary>
/// 基于 SqlSugar 的{描述}仓储实现。
/// </summary>
public sealed class {Name}Repository(
    ILogger<{Name}Repository> logger,
    IOptionsMonitor<DatabaseOptions> databaseOptions)
    : BaseRepository<{Name}Entity>(logger, databaseOptions.CurrentValue.{DbProperty}), I{Name}Repository
{ }
```

---

## 生命周期接口选择

| 场景 | 接口 | 说明 |
|------|------|------|
| 绝大多数仓储 | `IScopeDependency` | 每次请求一个实例，**默认选择** |
| 轻量无状态仓储 | `ITransientDependency` | 每次注入新实例 |

> 若用户未指定，默认使用 `IScopeDependency`，并说明原因。仓储层一般不使用 `ISingletonDependency`。

---

## 代码规范要点

1. **类必须是 `sealed`**
2. **使用主构造函数语法**（C# 12+），不写构造函数体
3. **XML 注释必须完整**，类和接口都需要 `<summary>`
4. **命名规范**：
   - 实体：`{业务名}Entity`
   - 接口：`I{业务名}Repository`
   - 实现：`{业务名}Repository`
5. **接口方法**：若仅做基础 CRUD 无需额外方法，接口体留空即可

---

## 示例参考

详见 `references/examples.md`，包含 DDD 和三层架构的完整示例。
