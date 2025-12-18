# 节点状态问题调试指南

## 问题描述
1. **导出健康节点**: 返回空的txt文件
2. **删除不健康节点**: 提示"没有找到不健康节点"，但总节点751，健康节点333

## 问题分析

### 根本原因
节点状态判断逻辑存在以下问题：

1. **SnapshotFiltered(true)** 的行为：
   - 返回：可用节点 + 未检查节点
   - 过滤掉：已检查但不可用的节点

2. **导出健康节点的问题**：
   ```go
   // 旧逻辑
   snapshots := s.mgr.SnapshotFiltered(true) // 包含未检查节点
   for _, snap := range snapshots {
       if !snap.Available || snap.ListenAddress == "" || snap.Port == 0 {
           continue // 跳过未检查节点（Available=false）且没有监听地址
       }
   }
   ```

3. **节点状态分类**：
   - **健康节点**: `InitialCheckDone=true && Available=true` (333个)
   - **不健康节点**: `InitialCheckDone=true && Available=false` (418个)
   - **未检查节点**: `InitialCheckDone=false` (数量未知)

## 修复方案

### 1. 修复导出健康节点逻辑
```go
// 新逻辑
snapshots := s.mgr.SnapshotFiltered(false) // 获取所有节点
for _, snap := range snapshots {
    // 明确筛选：已完成检查 + 可用 + 有监听地址
    if !snap.InitialCheckDone || !snap.Available || snap.ListenAddress == "" || snap.Port == 0 {
        continue
    }
}
```

### 2. 增强删除不健康节点的调试信息
```go
// 新增统计变量
var checkedNodes, availableNodes, uncheckedNodes int

// 详细分类统计
for _, snap := range snapshots {
    if snap.InitialCheckDone {
        checkedNodes++
        if snap.Available {
            availableNodes++
        } else {
            unhealthyNodes = append(unhealthyNodes, snap.Name)
        }
    } else {
        uncheckedNodes++
    }
}
```

## 测试验证

### 预期修复后行为

1. **导出健康节点**：
   - 应该导出333个健康节点的代理URI
   - 文件不应为空
   - 格式：`http://user:pass@ip:port` (每行一个)

2. **删除不健康节点**：
   - 应该识别并删除418个不健康节点
   - 显示详细统计信息：
     ```
     节点状态统计：
     总节点数：751
     已检查：751
     可用节点：333
     未检查：0
     ```

### 手动验证步骤

1. **检查节点状态**：
   ```bash
   # 获取所有节点状态
   curl -H "Authorization: Bearer <token>" http://localhost:9090/api/nodes
   ```

2. **测试健康节点导出**：
   ```bash
   curl -H "Authorization: Bearer <token>" http://localhost:9090/api/export-healthy
   ```

3. **测试删除不健康节点**：
   ```bash
   curl -X POST -H "Authorization: Bearer <token>" \
        http://localhost:9090/api/nodes/cleanup-unhealthy
   ```

### 故障排除

#### 如果导出仍为空：
1. 检查节点是否已完成健康检查
2. 验证健康节点是否有监听地址和端口
3. 确认节点状态API返回的数据

#### 如果删除仍显示"无不健康节点"：
1. 检查返回的详细统计信息
2. 验证`InitialCheckDone`和`Available`字段的值
3. 确认节点健康检查是否正常工作

## 可能的额外问题

### 1. 节点未分配监听地址
- **原因**: 节点虽然可用，但还未分配到具体端口
- **表现**: `Available=true` 但 `ListenAddress=""` 或 `Port=0`
- **解决**: 等待节点完全初始化，或检查配置模式

### 2. 健康检查未完成
- **原因**: 大量节点（418个）的健康检查可能仍在进行中
- **表现**: `InitialCheckDone=false`
- **解决**: 等待健康检查完成，或手动触发批量探测

### 3. 配置模式问题
- **检查**: 当前运行模式（pool/multi-port/hybrid）
- **影响**: 不同模式下的节点监听地址分配逻辑不同

## 调试命令

### 查看详细节点状态
```bash
# 启用调试模式
export LOG_LEVEL=debug
./easy-proxies --config config.yaml
```

### 检查健康检查进度
```bash
# 手动触发批量探测
curl -X POST -H "Authorization: Bearer <token>" \
     http://localhost:9090/api/nodes/probe-all
```

## 预期修复时间线

1. **立即修复**: 导出健康节点逻辑 ✅
2. **增强调试**: 删除功能增加详细统计 ✅
3. **测试验证**: 手动测试API响应 🔄
4. **用户反馈**: 观察实际使用效果 ⏳

修复完成后，两个功能都应该正常工作，用户可以获得准确的健康节点导出和有效的不健康节点清理功能。