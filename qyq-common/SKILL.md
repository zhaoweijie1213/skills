---
name: qyq-common
description: 使用 QYQ.Base.Common 实现依赖注入和日志配置。当用户需要注册依赖注入、配置 IOC 容器、添加日志、在 Program.cs 中批量扫描注册服务、或任何类需要通过继承接口实现自动注入时，必须使用此技能。触发关键词：依赖注入、IOC、注册服务、IScopeDependency、ISingletonDependency、ITransientDependency、AddMultipleService、AddQYQSerilog、Program.cs 注册、批量扫描、Serilog、日志配置。即使用户只是说"帮我注册一下这个服务"或"配置一下日志"也应触发此技能。
---

# QYQ Common 技能

基于 `QYQ.Base.Common` NuGet 包，处理依赖注入接口继承和 Program.cs 服务注册配置。

---

## 核心依赖

- **NuGet 包**：`QYQ.Base.Common`
- **命名空间**：`QYQ.Base.Common.IOCExtensions`

---

## 一、依赖注入接口继承

### 三个生命周期接口

| 接口 | 对应生命周期 | .NET 原生等价 |
|------|-------------|--------------|
| `IScopeDependency` | Scoped | `AddScoped` |
| `ISingletonDependency` | Singleton | `AddSingleton` |
| `ITransientDependency` | Transient | `AddTransient` |

### 使用规则

1. **生命周期必须根据实际业务情况决定**，不做默认推断，不自行假设
2. 如果用户未指定生命周期，**必须询问**，不能擅自选择
3. 类和接口都不需要额外注册代码，`AddMultipleService` 会自动扫描

### 适用场景

- Service 层、Repository 层、Helper 类、Manager 类等所有需要 DI 的类
- **例外**：以下情况不适用，需手动注册：
  - 注册时需要传委托（工厂方法）
  - `IHostedService`、`IHttpClientFactory` 等框架特殊类型
  - 需要条件注册、装饰器模式等复杂场景

### 代码模式

**有接口的情况**（推荐）：
```csharp
// 接口
public interface I{Name}Service : {生命周期接口}
{
    // 方法声明
}

// 实现
public sealed class {Name}Service : I{Name}Service
{
    // 实现
}
```

**无接口的情况**（直接注册实现类）：
```csharp
public sealed class {Name}Service : {生命周期接口}
{
    // 实现
}
```

> `AddMultipleService` 的匹配逻辑：扫描所有继承 `IDependency` 的类型，找到类对应的第一个接口自动配对注册；若无接口则直接注册实现类。

---

## 二、Program.cs 配置

### 1. 日志配置 — AddQYQSerilog

```csharp
builder.AddQYQSerilog();
```

- 位置：在 `builder.Build()` 之前调用
- 无需任何参数
- 替代手动配置 Serilog 的所有样板代码

### 2. 批量扫描注册 — AddMultipleService

```csharp
builder.Services.AddMultipleService("{正则表达式}");
```

**正则规则**：
- 匹配目标是 `.dll` 文件名（含扩展名），不区分大小写
- 多个程序集用 `|` 分隔
- 格式通常为 `^{项目名前缀}`

**典型写法**：
```csharp
// 单个前缀
builder.Services.AddMultipleService("^Activity");

// 多个前缀
builder.Services.AddMultipleService("^Activity|^Common");
```

**正则参数如何填写**：
- 根据项目实际程序集名称决定，询问用户项目名称/前缀
- 目标是覆盖所有包含需注册类的程序集
- 避免过于宽泛（匹配到无关程序集）或过于精确（漏掉某些程序集）

### 3. Program.cs 典型结构

```csharp
var builder = WebApplication.CreateBuilder(args);

// 日志
builder.AddQYQSerilog();

// 其他服务注册...
builder.Services.AddControllers();

// 批量扫描注册（放在其他注册之后）
builder.Services.AddMultipleService("^{项目前缀}");

var app = builder.Build();

// 中间件配置...
app.Run();
```

---

## 三、生成代码时的决策流程

```
用户需要某个类支持 DI？
    ↓
是否属于复杂注册场景（委托、工厂、框架特殊类型）？
    → 是：提示用户需手动注册，给出手动注册示例
    → 否：继续
        ↓
    用户是否指定了生命周期？
        → 否：询问用户
        → 是：继承对应接口
            ↓
        是否需要接口？
            → 是：接口继承生命周期接口，类实现接口（类不再继承生命周期接口）
            → 否：类直接继承生命周期接口
```

---

## 参考示例

详见 `references/examples.md`，包含各生命周期、有无接口的完整代码示例及 Program.cs 完整写法。
