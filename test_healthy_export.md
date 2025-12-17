# 导出健康节点功能测试指南

## 功能概述
本次更新为 easy_proxies 项目添加了只导出健康节点的功能，包括：
1. 新的 API 端点 `/api/export-healthy`
2. Web界面新增"导出健康节点"按钮

## 后端API变更

### 新增端点
- **GET** `/api/export-healthy` - 导出当前健康的代理节点

### 与现有导出端点的区别
- `/api/export` - 导出所有通过初始检查的节点（包括不可用的）
- `/api/export-healthy` - 只导出当前状态健康的节点（`Available=true`）

### 过滤逻辑
```go
// 只导出当前健康且有监听地址和端口的节点
if !snap.Available || snap.ListenAddress == "" || snap.Port == 0 {
    continue
}
```

## 前端界面变更

### 新��按钮
在Web管理界面导出节点按钮旁边添加了"导出健康节点"按钮，具有：
- 不同的图标（包含健康状态指示器）
- 独立的点击处理函数 `exportHealthyNodes()`
- 下载文件名为 `healthy_nodes.txt`

### 新增JavaScript函数
```javascript
async function exportHealthyNodes() {
    // 调用 /api/export-healthy API
    // 处理认证和错误
    // 下载文件为 healthy_nodes.txt
}
```

## 测试方法

### 1. API测试
```bash
# 假设服务运行在localhost:9090
curl -H "Authorization: Bearer <token>" \
     http://localhost:9090/api/export-healthy \
     -o healthy_proxies.txt
```

### 2. 界面测试
1. 启动 easy_proxies 服务
2. 访问 Web 管理界面
3. 确保有部分节点健康，部分节点不健康
4. 点击"导出健康节点"按钮
5. 验证下载的文件只包含健康的节点

### 3. 功能对比测试
1. 使用"导出节点"功能下载所有节点
2. 使用"导出健康节点"功能下载健康节点
3. 比较两个文件，验证健康节点导出是现有导出的子集

## 预期结果

### 健康节点文件格式
```
http://user:pass@1.2.3.4:24000
http://user:pass@5.6.7.8:24001
...
```

### 文件差异
- `nodes.txt`: 包含所有通过初始检查的节点
- `healthy_nodes.txt`: 只包含当前可用的节点

## 部署说明

### Docker部署
现有的Docker配置无需修改，新功能会自动生效。

### 本地构建
```bash
go build -tags "with_utls with_quic with_grpc" -o easy-proxies ./cmd/easy_proxies
```

## 安全考虑
- 新端点使用相同的认证中间件 `withAuth`
- 不会泄露额外的敏感信息
- 遵循现有的权限控制机制

## 向后兼容性
- 完全向后兼容，不影响现有的导出功能
- 现有API端点和行为保持不变