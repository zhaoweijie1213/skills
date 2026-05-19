# QYQ Common 代码示例

## 一、依赖注入示例

### Scoped — 有接口（最常见）
```csharp
/// <summary>
/// 活动服务接口。
/// </summary>
public interface IActivityService : IScopeDependency
{
    Task<ActivityDto> GetByIdAsync(int id);
}

/// <summary>
/// 活动服务实现。
/// </summary>
public sealed class ActivityService : IActivityService
{
    public async Task<ActivityDto> GetByIdAsync(int id)
    {
        // 实现
    }
}
```

---

### Singleton — 有接口
```csharp
/// <summary>
/// 缓存管理接口。
/// </summary>
public interface ICacheManager : ISingletonDependency
{
    void Set(string key, object value);
    T? Get<T>(string key);
}

/// <summary>
/// 缓存管理实现。
/// </summary>
public sealed class CacheManager : ICacheManager
{
    public void Set(string key, object value) { /* 实现 */ }
    public T? Get<T>(string key) { /* 实现 */ }
}
```

---

### Transient — 有接口
```csharp
/// <summary>
/// 报表生成器接口。
/// </summary>
public interface IReportGenerator : ITransientDependency
{
    byte[] Generate(ReportRequest request);
}

/// <summary>
/// 报表生成器实现。
/// </summary>
public sealed class ReportGenerator : IReportGenerator
{
    public byte[] Generate(ReportRequest request)
    {
        // 实现
    }
}
```

---

### 无接口 — 直接注册实现类
```csharp
/// <summary>
/// 短信发送工具。
/// </summary>
public sealed class SmsHelper : IScopeDependency
{
    public Task SendAsync(string phone, string message)
    {
        // 实现
    }
}
```

---

### 不适用场景 — 需手动注册

**委托/工厂注册**（AddMultipleService 无法处理）：
```csharp
// 需要在 Program.cs 手动写
builder.Services.AddScoped<IPaymentService>(sp =>
{
    var config = sp.GetRequiredService<IOptions<PaymentOptions>>().Value;
    return new PaymentService(config.ApiKey, config.Secret);
});
```

**HttpClient**：
```csharp
builder.Services.AddHttpClient<IWechatClient, WechatClient>(client =>
{
    client.BaseAddress = new Uri("https://api.weixin.qq.com/");
});
```

---

## 二、Program.cs 完整示例

```csharp
var builder = WebApplication.CreateBuilder(args);

// 1. 日志（放最前面）
builder.AddQYQSerilog();

// 2. 框架服务
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// 3. 配置绑定
builder.Services.Configure<DatabaseOptions>(
    builder.Configuration.GetSection("Database"));

// 4. 手动注册的复杂服务
builder.Services.AddHttpClient<IWechatClient, WechatClient>();

// 5. 批量扫描注册（放在手动注册之后，确保不覆盖特殊注册）
builder.Services.AddMultipleService("^Activity|^Activity.Infrastructure");

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();
app.Run();
```

---

## 三、AddMultipleService 正则示例

| 项目结构 | 正则参数 |
|---------|---------|
| 单项目 `Activity.Api` | `"^Activity"` |
| 多项目 `Activity.*` + `Common.*` | `"^Activity\|^Common"` |
| DDD 分层 `Shop.Api` + `Shop.Infrastructure` | `"^Shop"` |
| 三层 `UserCenter.Api` + `UserCenter.Repository` + `UserCenter.Service` | `"^UserCenter"` |
