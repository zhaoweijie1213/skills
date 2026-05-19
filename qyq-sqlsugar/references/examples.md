# 仓储代码示例

## DDD 架构示例

**场景**：俱乐部返利模块，实体属于 Club 数据库

### Domain 层 — 实体
```csharp
/// <summary>
/// 俱乐部返利基础配置实体。
/// </summary>
public sealed class ClubRebateBaseConfigEntity
{
    public int Id { get; set; }
    public string ClubId { get; set; } = string.Empty;
    public decimal RebateRate { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

### Domain 层 — 仓储接口
```csharp
/// <summary>
/// 俱乐部返利仓储接口。
/// </summary>
public interface IClubRebateRepository : IScopeDependency
{
}
```

### Infrastructure 层 — 仓储实现
```csharp
/// <summary>
/// 基于 SqlSugar 的俱乐部返利仓储实现。
/// </summary>
public sealed class ClubRebateRepository(
    ILogger<ClubRebateRepository> logger,
    IOptionsMonitor<DatabaseOptions> databaseOptions)
    : BaseRepository<ClubRebateBaseConfigEntity>(logger, databaseOptions.CurrentValue.Club), IClubRebateRepository
{ }
```

---

## 三层架构示例

**场景**：用户积分模块，实体属于 User 数据库

### Models 层
路径：`Entities/User/UserPointEntity.cs`
```csharp
/// <summary>
/// 用户积分实体。
/// </summary>
public sealed class UserPointEntity
{
    public int Id { get; set; }
    public string UserId { get; set; } = string.Empty;
    public decimal Points { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

### Repository 层 — 接口
路径：`User/Interface/IUserPointRepository.cs`
```csharp
/// <summary>
/// 用户积分仓储接口。
/// </summary>
public interface IUserPointRepository : IScopeDependency
{
}
```

### Repository 层 — 实现
路径：`User/UserPointRepository.cs`
```csharp
/// <summary>
/// 基于 SqlSugar 的用户积分仓储实现。
/// </summary>
public sealed class UserPointRepository(
    ILogger<UserPointRepository> logger,
    IOptionsMonitor<DatabaseOptions> databaseOptions)
    : BaseRepository<UserPointEntity>(logger, databaseOptions.CurrentValue.User), IUserPointRepository
{ }
```

---

## 含自定义方法的接口示例

当仓储需要声明特定查询方法时：

```csharp
/// <summary>
/// 游戏数据仓储接口。
/// </summary>
public interface IGameDataRepository : IScopeDependency
{
    /// <summary>
    /// 根据用户ID查询游戏记录。
    /// </summary>
    Task<List<GameDataEntity>> GetByUserIdAsync(string userId);
}
```

---

## DatabaseOptions 常用属性速查

| 属性名 | 说明 |
|--------|------|
| `Log` | 日志库 |
| `User` | 用户库 |
| `Shop` | 商城库 |
| `Club` | 战队/俱乐部库 |
| `Game` | 游戏库 |
| `Share` | 分享库 |
| `Active` | 活动数据库 |
| `GameDataAnalytics` | 游戏数据分析库 |
| `GameDataRaw` | 游戏数据原始库 |
