---
name: qyq-split-table-query
description: 使用 FilterSplitTablesByRange 扩展方法手动枚举分表进行查询，替代 SqlSugar 自动分表语句（.SplitTable()）。当用户需要查询任何带分表的实体时，必须使用此技能，而不得使用 .SplitTable() 自动生成语句。触发关键词：分表查询、SplitTable、按时间范围查询分表、FilterSplitTablesByRange、分季表、分月表、跨表查询、分表 Union、分表 Join。即使用户只说"帮我写一个分表查询"或"这个表是分表的怎么查"也应立即触发此技能。禁止在任何仓储方法中对分表实体使用 .SplitTable() 自动路由。
---

# QYQ 分表手动查询技能

**核心原则**：所有涉及分表实体的查询，必须通过 `FilterSplitTablesByRange` 确定具体分表表名，再使用 `.AS(tableName)` 指定表名查询。**禁止使用 `.SplitTable(start, end)` 自动路由**，原因是 SqlSugar 自动生成的 SQL 语句不可控，会造成索引失效。

---

## 依赖

- **NuGet**：`QYQ.Base.SqlSugar`（包含 `CustomSplitTableExtension`）
- **命名空间**：`using QYQ.Base.SqlSugar.Extension;`（引入 `FilterSplitTablesByRange` 扩展）
- **SqlSugar**：`using SqlSugar;`

---

## 核心查询模式

### 第一步：获取分表列表

**推荐写法**：使用泛型重载，自动从实体的 `[SplitTable]` 特性读取 `SplitType`，无需手动传入，不会因为写错类型导致过滤遗漏：

```csharp
// 推荐：自动读取实体上 [SplitTable(SplitType.xxx)] 特性
var tables = Db.SplitHelper<TEntity>().GetTables()
               .FilterSplitTablesByRange<TEntity>(start, end);
```

**兜底写法**：实体未标注 `[SplitTable]` 特性，或需要显式覆盖时，手动传入 `SplitType`：

```csharp
// 手动指定，仅在实体无特性标注时使用
var tables = Db.SplitHelper<TEntity>().GetTables()
               .FilterSplitTablesByRange(start, end, SplitType.Season);

// 其他可选类型：SplitType.Month / Year / Week / Day
```

> 泛型重载内部若未找到 `[SplitTable]` 特性，会自动回退到 `SplitType.Season`。

---

### 第二步：根据分表数量选择查询路径

`FilterSplitTablesByRange` 返回的列表可能包含一张或多张分表，**两种情况处理方式不同**：

#### 情况 A：明确只查单张分表（如按精确时间点、ID 定位）

直接取第一张表，用 `.AS()` 查询，**无需 foreach 和 UnionAll**：

```csharp
var tables = Db.SplitHelper<TEntity>().GetTables()
               .FilterSplitTablesByRange(start, end, SplitType.Season);

if (tables.Count == 0) return null;

var result = await Db.Queryable<TEntity>()
    .AS(tables[0].TableName)             // ← 直接指定表名
    .Where(x => x.Id == targetId)
    .FirstAsync();
```

#### 情况 B：时间范围可能跨多张分表（常见的范围查询、分页查询）

需要 foreach 遍历每张分表分别构建查询，再 `Db.UnionAll()` 合并：

```csharp
List<ISugarQueryable<TUnion>> unionQueries = [];

foreach (var table in tables)
{
    var query = Db.Queryable<TEntity>()
                  .AS(table.TableName)           // ← 每张分表单独指定
                  .Where(x => x.EndTime >= start && x.EndTime <= end)
                  // .WhereIF(...) 追加其他条件
                  .Select(x => new TUnion { ... });

    unionQueries.Add(query);
}

if (unionQueries.Count > 0)
{
    var result = await Db.UnionAll(unionQueries)
        .OrderBy(x => x.Id, OrderByType.Desc)
        .ToPageListAsync(pageIndex, pageSize);
}
```

> **判断依据**：业务上时间范围固定为单个分表周期内（如"查今天"、"查本季度"且入参已约束），可走情况 A。只要入参允许跨周期（如用户自选起止时间），一律走情况 B，由 `FilterSplitTablesByRange` 决定实际涉及几张表。

---

## 多表 Join 分表查询（主从表同步分表）

当主表和从表同步分表（如 `GameRecord` + `GameRecordUser` 都按季度分表）时，需要同时获取两张表的分表列表，并通过 `Date` 做对齐匹配，再进行 Join。

```csharp
var recordTables = Db.SplitHelper<GameRecordEntity>().GetTables()
                     .FilterSplitTablesByRange(start, end, SplitType.Season);
var userTables   = Db.SplitHelper<GameRecordUserEntity>().GetTables()
                     .FilterSplitTablesByRange(start, end, SplitType.Season);

// 将从表建立 Date → TableName 字典，方便按分表周期对齐
var userTableMap = userTables.ToDictionary(t => t.Date.Date, t => t.TableName);

List<ISugarQueryable<TUnion>> unionQueries = [];

foreach (var recordTable in recordTables)
{
    // 主从表必须同一分表周期才能 Join
    if (!userTableMap.TryGetValue(recordTable.Date.Date, out var userTableName))
    {
        continue; // 从表对应分表不存在，跳过
    }

    var query = Db.Queryable<GameRecordEntity>()
                  .AS(recordTable.TableName)
                  .InnerJoin<GameRecordUserEntity>(
                      (record, user) => record.GameNo == user.GameNo,
                      userTableName)                 // ← Join 时也需要指定从表表名
                  .Where((record, user) => record.EndTime >= start && record.EndTime <= end)
                  // .WhereIF(...) 其他条件
                  .Select((record, user) => new TUnion { ... });

    unionQueries.Add(query);
}
```

---

## UID 过滤分支

当有可选的 UID 过滤（`filterUids`）时，通常分为两个分支：有 UID 过滤走 Join，无过滤走单表。参考 `references/examples.md` 中的完整示例。

```csharp
var hasUidFilter = filterUids != null && filterUids.Count > 0;

foreach (var recordTable in recordTables)
{
    if (hasUidFilter)
    {
        // 必须 Join 从表才能按 UID 过滤
        if (!userTableMap.TryGetValue(recordTable.Date.Date, out var userTableName))
            continue;

        var query = BuildQueryWithJoin(recordTable.TableName, userTableName, ...)
            .Where((record, user) => filterUids!.Contains(user.Uid))
            .Select(...);
        unionQueries.Add(query);
    }
    else
    {
        var query = BuildQuerySingle(recordTable.TableName, ...)
            .Select(...);
        unionQueries.Add(query);
    }
}
```

---

## 私有 Build 方法规范

将"指定表名 + 追加 Where 条件"的逻辑封装为私有方法，避免 foreach 体过长。

```csharp
// 单表版
private ISugarQueryable<TEntity> BuildQuery(
    string tableName, DateTime start, DateTime end, /* 其他过滤参数 */)
{
    return Db.Queryable<TEntity>()
             .AS(tableName)
             .Where(x => x.EndTime >= start && x.EndTime <= end)
             .WhereIF(someCondition, x => ...);
}

// Join 版（主从表）
private ISugarQueryable<TEntity, TUserEntity> BuildQueryWithJoin(
    string tableName, string userTableName, DateTime start, DateTime end, /* 其他过滤参数 */)
{
    return Db.Queryable<TEntity>()
             .AS(tableName)
             .InnerJoin<TUserEntity>(
                 (record, user) => record.GameNo == user.GameNo,
                 userTableName)
             .Where((record, user) => record.EndTime >= start && record.EndTime <= end);
}
```

---

## 中间 Union 类规范

UnionAll 需要一个中间类承载各分表查询的 Select 结果，命名为 `{业务名}Union`，声明为 `private sealed class`，放在仓储类内部。

```csharp
private sealed class GameRecordHistoryUnion
{
    public long RecordId { get; set; }
    // ... 其他字段（与 Select 投影保持一致）
}
```

> 不要直接复用实体类作为 Union 类，避免字段缺失或 SqlSugar 映射冲突。

---

## 聚合去重（GroupBy + AggregateMax）

UnionAll 后如果多条记录可能同一主键（多从表用户记录），需要 GroupBy 去重：

```csharp
list = await Db.UnionAll(unionQueries)
    .GroupBy(x => x.RecordId)
    .OrderBy(x => SqlFunc.AggregateMax(x.RecordId), orderByType)
    .Select(x => new OutputDto
    {
        Id    = SqlFunc.AggregateMax(x.RecordId.ToString()),
        Field = SqlFunc.AggregateMax(x.Field),
        // ...
    })
    .ToPageListAsync(pageIndex, pageSize);
```

---

## 禁止事项 ⛔

| 禁止写法 | 原因 |
|----------|------|
| `Db.Queryable<T>().SplitTable(start, end)` | 生成 SQL 不可控，索引失效 |
| 直接在 `Queryable<T>()` 不指定 `.AS()` 就查分表实体 | 会查主表或报错 |
| 遍历时两张分表跨周期强行 Join | 数据错乱 |
| 将 `SplitType` 传错（与实体特性不一致） | 过滤出错，遗漏分表 |

---

## 详细完整示例

见 `references/examples.md`，包含：
1. 单张分表查询（单表直接 `.AS()`，无 foreach / UnionAll）
2. 单实体分表分页查询（跨表 UnionAll）
3. 双表 Join 分表查询（含 UID 过滤分支）
4. 带 Expression 传参的动态条件分表查询
