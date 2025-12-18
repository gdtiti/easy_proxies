# sing-box轻量级分组实施方案

## 🔍 sing-box架构限制分析

### 核心限制
1. **单一实例架构**：整个系统只有一个`*box.Box`实例
2. **静态配置**：outbound和inbound在启动时固定配置
3. **集中式管理**：所有节点属于同一个outbound pool
4. **监听器限制**：无法动态创建/销毁监听器

## 🛠️ 轻量级分组实现方案

### 方案一：多虚拟监听器（推荐）

**核心思路**：在单一sing-box实例中创建多个虚拟监听器，通过路由规则实现分组管理

#### 技术实现

```go
// 1. 扩展配置结构
type GroupConfig struct {
    ID            string            `yaml:"id"`
    Name          string            `yaml:"name"`
    Enabled       bool              `yaml:"enabled"`
    PortRange     PortRange         `yaml:"port_range"`     // 24000-24099
    ProbeTarget   string            `yaml:"probe_target"`
    NodeFilter    NodeFilter        `yaml:"node_filter"`     // 节点过滤规则
    OutboundTag   string            `yaml:"outbound_tag"`    // 对应的outbound tag
    RoutingRules  []RoutingRule     `yaml:"routing_rules"`   // 路由规则
}

type PortRange struct {
    Start uint16 `yaml:"start"`
    End   uint16 `yaml:"end"`
    Count int    `yaml:"count"`
}

type NodeFilter struct {
    Tags       []string `yaml:"tags"`         // 节点标签过滤
    Countries  []string `yaml:"countries"`    // 国家过滤
    Protocols  []string `yaml:"protocols"`    // 协议过滤
    Regex      string   `yaml:"regex"`        // 正则表达式过滤
    CustomFilter string  `yaml:"custom_filter"` // 自定义过滤函数
}

// 2. 动态配置生成器
type DynamicConfigBuilder struct {
    baseConfig    *config.Config
    groups        []GroupConfig
    nodeManager   *monitor.Manager
    portManager   *VirtualPortManager
}

func (dcb *DynamicConfigBuilder) BuildSingBoxConfig() (*sing_box.Config, error) {
    // 基础配置
    config := &sing_box.Config{
        Log:         dcb.baseConfig.LogConfig,
        DNS:         dcb.baseConfig.DNSConfig,
        Inbounds:    []inbound.Inbound{},
        Outbounds:   []outbound.Outbound{},
        Route:       route.Config{},
    }

    // 3. 为每个分组创建虚拟监听器
    for _, group := range dcb.groups {
        if !group.Enabled {
            continue
        }

        // 创建组内的监听器
        inbounds, err := dcb.createGroupInbounds(group)
        if err != nil {
            return nil, fmt.Errorf("failed to create inbounds for group %s: %w", group.ID, err)
        }
        config.Inbounds = append(config.Inbounds, inbounds...)

        // 创建组内的outbound pool
        outbound, err := dcb.createGroupOutbound(group)
        if err != nil {
            return nil, fmt.Errorf("failed to create outbound for group %s: %w", group.ID, err)
        }
        config.Outbounds = append(config.Outbounds, outbound)

        // 添加路由规则
        routingRules := dcb.createGroupRouting(group)
        config.Route.Rules = append(config.Route.Rules, routingRules...)
    }

    return config, nil
}

// 4. 虚拟监听器创建
func (dcb *DynamicConfigBuilder) createGroupInbounds(group GroupConfig) ([]inbound.Inbound, error) {
    var inbounds []inbound.Inbound

    // 获取该组的节点
    groupNodes := dcb.filterNodesForGroup(group)

    for i, node := range groupNodes {
        // 为每个节点分配端口
        port, err := dcb.portManager.AllocatePort(group.ID, node.Tag)
        if err != nil {
            return nil, err
        }

        // 创建HTTP代理监听器
        inbound := inbound.HTTP{
            Type: inbound.TypeHTTP,
            Listen: inbound.ListenOptions{
                Listen:     net.JoinHostPort("0.0.0.0", fmt.Sprintf("%d", port)),
                ListenPort: port,
            },
            Users: []auth.User{
                {
                    Username: group.ProxyUsername,
                    Password: group.ProxyPassword,
                },
            },
            // 指向特定的outbound
            OverrideDestination: &outbound.OverrideOptions{
                Outbound: group.OutboundTag,
            },
        }

        inbounds = append(inbounds, &inbound)
    }

    return inbounds, nil
}

// 5. 虚拟端口管理器
type VirtualPortManager struct {
    allocatedPorts map[string]map[uint16]string // group_id -> port -> node_tag
    portRanges     map[string]PortRange          // group_id -> port_range
    nextPort       map[string]uint16             // group_id -> next_available_port
    mu            sync.RWMutex
}

func (vpm *VirtualPortManager) AllocatePort(groupID, nodeTag string) (uint16, error) {
    vpm.mu.Lock()
    defer vpm.mu.Unlock()

    rangeInfo, exists := vpm.portRanges[groupID]
    if !exists {
        return 0, fmt.Errorf("group %s not found", groupID)
    }

    if vpm.allocatedPorts[groupID] == nil {
        vpm.allocatedPorts[groupID] = make(map[uint16]string)
        vpm.nextPort[groupID] = rangeInfo.Start
    }

    nextPort := vpm.nextPort[groupID]
    if nextPort > rangeInfo.End {
        return 0, fmt.Errorf("no available ports for group %s", groupID)
    }

    // 检查端口是否已被占用
    if _, occupied := vpm.allocatedPorts[groupID][nextPort]; occupied {
        // 寻找下一个可用端口
        for port := nextPort; port <= rangeInfo.End; port++ {
            if _, occupied := vpm.allocatedPorts[groupID][port]; !occupied {
                nextPort = port
                break
            }
        }
        if nextPort > rangeInfo.End {
            return 0, fmt.Errorf("no available ports for group %s", groupID)
        }
    }

    vpm.allocatedPorts[groupID][nextPort] = nodeTag
    vpm.nextPort[groupID] = nextPort + 1

    return nextPort, nil
}
```

### 方案二：标签化节点管理（简化版）

**核心思路**：不改变sing-box运行方式，只在管理层面实现分组逻辑

```go
// 1. 节点标签系统
type NodeMetadata struct {
    Tag         string            `json:"tag"`
    Name        string            `json:"name"`
    URI         string            `json:"uri"`
    GroupID     string            `json:"group_id"`
    GroupName   string            `json:"group_name"`
    Labels      map[string]string `json:"labels"`     // 自定义标签
    Country     string            `json:"country"`    // 国家
    City        string            `json:"city"`       // 城市
    ISP         string            `json:"isp"`        // ISP信息
    Score       int               `json:"score"`      // 质量评分
}

// 2. 分组过滤器
type GroupFilter struct {
    GroupID     string              `json:"group_id"`
    Name        string              `json:"name"`
    Filters     map[string][]string `json:"filters"`
    PortRange   PortRange           `json:"port_range"`
    ProbeTarget string              `json:"probe_target"`
}

// 3. 分组管理器（只读）
type ReadOnlyGroupManager struct {
    nodeMetadata   []NodeMetadata
    groupFilters   []GroupFilter
    singBoxManager *boxmgr.Manager
    monitorManager *monitor.Manager
}

func (rogm *ReadOnlyGroupManager) GetGroupNodes(groupID string) ([]NodeMetadata, error) {
    filter, exists := rogm.findGroupFilter(groupID)
    if !exists {
        return nil, fmt.Errorf("group %s not found", groupID)
    }

    var groupNodes []NodeMetadata
    for _, node := range rogm.nodeMetadata {
        if rogm.matchFilters(node, filter.Filters) {
            groupNodes = append(groupNodes, node)
        }
    }

    return groupNodes, nil
}

func (rogm *ReadOnlyGroupManager) ExportGroupNodes(groupID string, healthyOnly bool) ([]string, error) {
    // 获取sing-box当前快照
    snapshots := rogm.monitorManager.SnapshotFiltered(!healthyOnly)

    // 获取分组节点
    groupNodes, err := rogm.GetGroupNodes(groupID)
    if err != nil {
        return nil, err
    }

    // 构建节点标签映射
    nodeTagMap := make(map[string]NodeMetadata)
    for _, node := range groupNodes {
        nodeTagMap[node.Tag] = node
    }

    // 过滤导出节点
    var exportLines []string
    for _, snap := range snapshots {
        if nodeMeta, exists := nodeTagMap[snap.Tag]; exists {
            if snap.ListenAddress != "" && snap.Port != 0 {
                listenAddr := snap.ListenAddress
                if listenAddr == "0.0.0.0" {
                    // 获取外部IP
                    if extIP := rogm.getExternalIP(); extIP != "" {
                        listenAddr = extIP
                    }
                }

                proxyURI := fmt.Sprintf("http://%s:%d", listenAddr, snap.Port)
                exportLines = append(exportLines, proxyURI)
            }
        }
    }

    return exportLines, nil
}
```

## 🚀 推荐实施方案

### 阶段一：标签化分组（4-6周）

**目标**：在不改变sing-box运行方式的前提下实现分组管理

```yaml
# 新的配置结构
# config.yaml
mode: hybrid
log_level: info

# 现有配置保持不变
listener:
  address: 0.0.0.0
  port: 2323
  username: username
  password: password

# 新增分组配置（纯管理层面）
groups:
  - id: "hongkong"
    name: "香港节点"
    enabled: true
    probe_target: "www.google.com:80"
    export_port_base: 24000
    filters:
      tags: ["hk", "hongkong"]
      countries: ["HK"]
      protocols: ["vmess", "vless"]

  - id: "taiwan"
    name: "台湾节点"
    enabled: true
    probe_target: "www.yahoo.com:80"
    export_port_base: 24100
    filters:
      tags: ["tw", "taiwan"]
      countries: ["TW"]

  - id: "premium"
    name: "优质节点"
    enabled: true
    probe_target: "www.cloudflare.com:80"
    export_port_base: 24200
    filters:
      score: ">80"
      latency: "<200"
```

**实现步骤**：
1. 扩展`NodeInfo`结构添加标签字段
2. 实现节点标签解析和管理
3. 创建分组过滤器系统
4. 实现分组导出功能
5. 添加分组健康检查（独立探测URL）

### 阶段二：虚拟监听器（6-8周）

**目标**：为每个分组创建独立的虚拟监听器

```go
// 关键实现点
func (vm *VirtualManager) CreateGroupListeners(group GroupConfig) error {
    // 1. 基于现有sing-box实例动态添加监听器
    // 2. 为分组内的每个节点分配独立端口
    // 3. 创建路由规则指向分组特定outbound
    // 4. 独立的代理认证配置
}

// 虚拟监听器通过HTTP API管理
POST /api/virtual/listeners
{
  "group_id": "hongkong",
  "action": "create",
  "nodes": ["node1", "node2", "node3"]
}
```

### 阶段三：高级功能（4-6周）

**目标**：完整的分组管理功能

- 分组统计和监控
- 分组负载策略
- 自动故障转移
- 性能优化

## 💡 技术优势

### 标签化方案优势
1. **零侵入性**：不改变sing-box核心逻辑
2. **高性能**：无需多实例，资源消耗低
3. **灵活性**：支持复杂的标签过滤规则
4. **可维护性**：配置简单，故障排查容易

### 虚拟监听器优势
1. **功能完整**：每个分组独立的监听器和配置
2. **用户体验佳**：真正的分组隔离效果
3. **扩展性好**：便于后续功能扩展
4. **兼容性强**：与现有功能完全兼容

## 🎯 最终建议

**推荐采用"标签化分组 + 虚拟监听器"的混合方案**：

1. **先实现标签化分组**：快速获得分组管理功能
2. **逐步添加虚拟监听器**：提升用户体验
3. **保持单一实例**：避免架构复杂化

这样既能在现有架构下快速实现分组功能，又为未来扩展留有余地。