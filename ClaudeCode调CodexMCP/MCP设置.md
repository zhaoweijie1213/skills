请在 PowerShell 执行：

```powershell
claude mcp add --scope user --transport stdio codex -- codex mcp-server
```

这里关键是：

```text
--scope user
```

这样 Codex MCP 会变成**用户级配置**，不是只绑定 `C:\Users\HIAPAD` 这个目录。

执行完以后，把完整输出发我。

先不要回 Desktop，也不要做其他配置。下一步我再带你验证 Desktop 是否能看到 Codex。