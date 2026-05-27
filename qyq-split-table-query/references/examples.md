# 分表手动查询完整示例

以下示例均来自 `GameRecordRepository`，是项目 v2 接口的标准实现方式。

---

## 示例 0：单张分表查询（无需 foreach / UnionAll）

**场景**：按 ID 或精确时间点查询，业务上确定只落在一张分表内，直接 `.AS()` 查询即可。

```csharp
public async Task<GameRecordEntity?> GetByIdAsync(long id, DateTime recordTime)
{
    var tables = Db.SplitHelper<GameRecordEntity>().GetTables()
                   .FilterSplitTablesByRange<GameRecordEntity>(recordTime, recordTime);

    if (tables.Count == 0) return null;

    return await Db.Queryable<GameRecordEntity>()
        .AS(tables[0].TableName)       // ← 单表，直接取第一张
        .Where(x => x.Id == id)
        .FirstAsync();
}
```

> 同理适用于 `.ToListAsync()`、`.CountAsync()` 等，只要业务语义上确保不跨分表周期，就不需要 UnionAll。

---

## 示例 1：单实体分表分页查询（无 Join）

**场景**：按时间范围分页查询 `GameRecordEntity`，支持多个可选过滤条件。

```csharp
public async Task<List<GameRecordHistoryOutput>> SelectGameRecordHistoryAsync(
    DateTime start, DateTime end, int pageIndex, int pageSize,
    int? clubId, List<int>? gameIds, int? ruleId, int? isSeason,
    OrderByType orderByType = OrderByType.Desc)
{
    List<GameRecordHistoryOutput> list = [];
    try
    {
        // 第一步：获取时间范围内的所有分表
        var recordTables = Db.SplitHelper<GameRecordEntity>().GetTables()
                             .FilterSplitTablesByRange<GameRecordEntity>(start, end);

        List<ISugarQueryable<GameRecordHistoryUnion>> unionQueries = [];

        foreach (var recordTable in recordTables)
        {
            var query = BuildGameRecordQuery(recordTable.TableName, start, end, clubId, gameIds, ruleId, isSeason)
                .Select(record => new GameRecordHistoryUnion
                {
                    RecordId  = record.Id,
                    GameNo    = record.GameNo,
                    StartTime = record.StartTime,
                    EndTime   = record.EndTime,
                    ClubId    = record.ClubId,
                    // ... 其他字段
                });
            unionQueries.Add(query);
        }

        if (unionQueries.Count > 0)
        {
            list = await Db.UnionAll(unionQueries)
                .GroupBy(x => x.RecordId)
                .OrderBy(x => SqlFunc.AggregateMax(x.RecordId), orderByType)
                .Select(x => new GameRecordHistoryOutput
                {
                    Id        = SqlFunc.AggregateMax(x.RecordId.ToString()),
                    GameNo    = SqlFunc.AggregateMax(x.GameNo),
                    StartTime = SqlFunc.AggregateMax(x.StartTime),
                    EndTime   = SqlFunc.AggregateMax(x.EndTime),
                    ClubId    = SqlFunc.AggregateMax(x.ClubId),
                    // ... 其他字段
                })
                .ToPageListAsync(pageIndex, pageSize);
        }
    }
    catch (Exception ex)
    {
        logger.BaseErrorLog("SelectGameRecordHistoryAsync", ex);
    }

    return list;
}

// 私有 Build 方法：封装指定表名 + 条件追加逻辑
private ISugarQueryable<GameRecordEntity> BuildGameRecordQuery(
    string tableName, DateTime start, DateTime end,
    int? clubId, List<int>? gameIds, int? ruleId, int? isSeason)
{
    var query = Db.Queryable<GameRecordEntity>().AS(tableName);

    if (clubId.HasValue)
        query = query.Where(x => x.ClubId == clubId.Value);

    query = query.Where(x => x.EndTime >= start && x.EndTime <= end);

    if (gameIds != null && gameIds.Count > 0)
        query = query.Where(x => gameIds.Contains(x.GameId));

    if (ruleId.HasValue)
        query = query.Where(x => x.RuleId == ruleId.Value);

    if (isSeason is 1)
        query = query.Where(x => x.OpenSeason == false);
    else if (isSeason is 2)
        query = query.Where(x => x.OpenSeason);

    return query;
}
```

---

## 示例 2：双表 Join 分表查询（含可选 UID 过滤分支）

**场景**：`GameRecordEntity`（主）+ `GameRecordUserEntity`（从）同步按季度分表，Join 查询，支持可选的 UID 过滤。

```csharp
public async Task<List<GameRecordHistoryOutput>> SelectGameRecordHistoryAsync(
    DateTime start, DateTime end, int pageIndex, int pageSize,
    int? clubId, List<int>? gameIds, int? ruleId, int? isSeason,
    List<long>? filterUids, OrderByType orderByType = OrderByType.Desc)
{
    List<GameRecordHistoryOutput> list = [];
    try
    {
        var recordTables = Db.SplitHelper<GameRecordEntity>().GetTables()
                             .FilterSplitTablesByRange<GameRecordEntity>(start, end);
        var userTables   = Db.SplitHelper<GameRecordUserEntity>().GetTables()
                             .FilterSplitTablesByRange<GameRecordUserEntity>(start, end);

        // 从表建立 Date → TableName 字典，用于按分表周期对齐
        var userTableMap = userTables.ToDictionary(t => t.Date.Date, t => t.TableName);
        var hasUidFilter = filterUids != null && filterUids.Count > 0;

        List<ISugarQueryable<GameRecordHistoryUnion>> unionQueries = [];

        foreach (var recordTable in recordTables)
        {
            if (hasUidFilter)
            {
                // 有 UID 过滤：必须 Join 从表
                if (!userTableMap.TryGetValue(recordTable.Date.Date, out var userTableName))
                    continue; // 从表对应分表不存在，跳过

                var query = BuildQueryWithJoin(recordTable.TableName, userTableName, start, end, clubId, gameIds, ruleId, isSeason)
                    .Where((record, user) => filterUids!.Contains(user.Uid))
                    .Select((record, user) => new GameRecordHistoryUnion
                    {
                        RecordId  = record.Id,
                        GameNo    = record.GameNo,
                        Uid       = record.Uid,
                        StartTime = record.StartTime,
                        EndTime   = record.EndTime,
                        ClubId    = record.ClubId,
                        IsSeason  = SqlFunc.IIF(record.OpenSeason, 1, 0),
                        // ... 其他字段
                    });
                unionQueries.Add(query);
            }
            else
            {
                // 无 UID 过滤：单表查询
                var query = BuildQuerySingle(recordTable.TableName, start, end, clubId, gameIds, ruleId, isSeason)
                    .Select(record => new GameRecordHistoryUnion
                    {
                        RecordId  = record.Id,
                        GameNo    = record.GameNo,
                        Uid       = record.Uid,
                        StartTime = record.StartTime,
                        EndTime   = record.EndTime,
                        ClubId    = record.ClubId,
                        IsSeason  = SqlFunc.IIF(record.OpenSeason, 1, 0),
                        // ... 其他字段
                    });
                unionQueries.Add(query);
            }
        }

        if (unionQueries.Count > 0)
        {
            list = await Db.UnionAll(unionQueries)
                .GroupBy(x => x.RecordId)
                .OrderBy(x => SqlFunc.AggregateMax(x.RecordId), orderByType)
                .Select(x => new GameRecordHistoryOutput
                {
                    Id       = SqlFunc.AggregateMax(x.RecordId.ToString()),
                    GameNo   = SqlFunc.AggregateMax(x.GameNo),
                    Uid      = SqlFunc.AggregateMax(x.Uid),
                    ClubId   = SqlFunc.AggregateMax(x.ClubId),
                    IsSeason = SqlFunc.AggregateMax(x.IsSeason),
                    // ...
                })
                .ToPageListAsync(pageIndex, pageSize);
        }
    }
    catch (Exception ex)
    {
        logger.BaseErrorLog("SelectGameRecordHistoryAsync", ex);
    }

    return list;
}

// 单表 Build 方法
private ISugarQueryable<GameRecordEntity> BuildQuerySingle(
    string tableName, DateTime start, DateTime end,
    int? clubId, List<int>? gameIds, int? ruleId, int? isSeason)
{
    var query = Db.Queryable<GameRecordEntity>().AS(tableName)
                  .Where(x => x.EndTime >= start && x.EndTime <= end);

    if (clubId.HasValue)   query = query.Where(x => x.ClubId == clubId.Value);
    if (gameIds?.Count > 0) query = query.Where(x => gameIds.Contains(x.GameId));
    if (ruleId.HasValue)   query = query.Where(x => x.RuleId == ruleId.Value);
    if (isSeason is 1)     query = query.Where(x => x.OpenSeason == false);
    else if (isSeason is 2) query = query.Where(x => x.OpenSeason);

    return query;
}

// Join Build 方法
private ISugarQueryable<GameRecordEntity, GameRecordUserEntity> BuildQueryWithJoin(
    string tableName, string userTableName, DateTime start, DateTime end,
    int? clubId, List<int>? gameIds, int? ruleId, int? isSeason)
{
    var query = Db.Queryable<GameRecordEntity>()
                  .AS(tableName)
                  .InnerJoin<GameRecordUserEntity>(
                      (record, user) => record.GameNo == user.GameNo,
                      userTableName)                          // ← Join 时指定从表表名
                  .Where((record, user) => record.EndTime >= start && record.EndTime <= end);

    if (clubId.HasValue)    query = query.Where((r, u) => r.ClubId == clubId.Value);
    if (gameIds?.Count > 0) query = query.Where((r, u) => gameIds.Contains(r.GameId));
    if (ruleId.HasValue)    query = query.Where((r, u) => r.RuleId == ruleId.Value);
    if (isSeason is 1)      query = query.Where((r, u) => r.OpenSeason == false);
    else if (isSeason is 2) query = query.Where((r, u) => r.OpenSeason);

    return query;
}
```

---

## 示例 3：带 Expression 动态条件的分表查询

**场景**：调用方传入 `Expression<Func<TEntity, bool>>` 动态条件，仓储方法原样应用到每个分表。

```csharp
public async Task<List<OutputDto>> SelectByExpressionAsync(
    DateTime start, DateTime end, int pageIndex, int pageSize,
    Expression<Func<GameRecordEntity, bool>> whereExpression,
    List<long>? filterUids, OrderByType orderByType = OrderByType.Desc)
{
    List<OutputDto> list = [];
    try
    {
        var recordTables = Db.SplitHelper<GameRecordEntity>().GetTables()
                             .FilterSplitTablesByRange<GameRecordEntity>(start, end);
        var userTables   = Db.SplitHelper<GameRecordUserEntity>().GetTables()
                             .FilterSplitTablesByRange<GameRecordUserEntity>(start, end);

        var userTableMap = userTables.ToDictionary(t => t.Date.Date, t => t);
        List<ISugarQueryable<TUnion>> unionQuery = [];

        foreach (var recordTable in recordTables)
        {
            if (!userTableMap.TryGetValue(recordTable.Date.Date, out var userTable))
                continue;

            var query = Db.Queryable<GameRecordEntity>()
                .AS(recordTable.TableName)
                .Where(whereExpression)                   // ← 直接应用 Expression
                .InnerJoin<GameRecordUserEntity>(
                    (record, user) => record.GameNo == user.GameNo,
                    userTable.TableName)
                .Where((record, user) => record.EndTime >= start && record.EndTime <= end)
                .WhereIF(filterUids != null && filterUids.Count > 0,
                    (record, user) => filterUids!.Contains(user.Uid))
                .Select((record, user) => new TUnion { ... });

            unionQuery.Add(query);
        }

        if (unionQuery.Count > 0)
        {
            list = await Db.UnionAll(unionQuery)
                .GroupBy(x => x.RecordId)
                .OrderBy(x => SqlFunc.AggregateMax(x.SomeField), orderByType)
                .Select(x => new OutputDto { ... })
                .ToPageListAsync(pageIndex, pageSize);
        }
    }
    catch (Exception ex)
    {
        logger.BaseErrorLog(nameof(SelectByExpressionAsync), ex);
    }

    return list;
}
```

---

## 中间 Union 类模板

```csharp
/// <summary>
/// {业务名}分表 Union 查询中间承载类。
/// </summary>
private sealed class {BusinessName}Union
{
    public long   RecordId  { get; set; }
    public int    AppId     { get; set; }
    public int    GameId    { get; set; }
    public string GameNo    { get; set; } = string.Empty;
    public long   Uid       { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime EndTime   { get; set; }
    public int    ClubId    { get; set; }
    // 根据实际 Select 字段添加或删减
}
```
