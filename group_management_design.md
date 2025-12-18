# 分组管理功��设计方案

## 功能概述

为 easy_proxies 项目增加分组管理功能，支持：
- 分组管理（创建、编辑、删除分组）
- 每个分组独立的端口配置
- 分组批量导入代理列表
- 分组独立的健康检查URL配置
- 分组统计和状态监控

## 数据模型设计

### 1. 配置文件结构扩展

```yaml
# config.yaml 扩展
mode: hybrid  # 保持现有模式，或新增 group-mode
log_level: info

management:
  enabled: true
  listen: 0.0.0.0:9090
  password: ""

# 分组管理配置
groups:
  - name: "香港组"
    id: "hk-group"
    enabled: true
    mode: "multi-port"  # pool | multi-port | hybrid
    base_port: 24000
    max_ports: 100
    probe_target: "www.google.com:80"
    proxy_username: "hkuser"
    proxy_password: "hkpass"
    nodes_source:
      type: "subscription"  # subscription | file | manual
      url: "https://example.com/hk-sub"
      file_path: "nodes/hk.txt"

  - name: "台湾组"
    id: "tw-group"
    enabled: true
    mode: "multi-port"
    base_port: 24100  # 不同的起始端口
    max_ports: 50
    probe_target: "www.yahoo.com:80"  # 不同的测试URL
    proxy_username: "twuser"
    proxy_password: "twpass"
    nodes_source:
      type: "manual"
      nodes:
        - uri: "vless://uuid@server:443#台湾节点1"
        - uri: "ss://base64@server:8388#台湾节点2"

# 全局监听器配置（兼容性）
listener:
  address: 0.0.0.0
  port: 2323
  username: username
  password: password
```

### 2. 数据结构定义

```go
// GroupConfig 分组配置
type GroupConfig struct {
    ID            string         `yaml:"id" json:"id"`
    Name          string         `yaml:"name" json:"name"`
    Enabled       bool           `yaml:"enabled" json:"enabled"`
    Mode          string         `yaml:"mode" json:"mode"`  // pool | multi-port | hybrid
    BasePort      uint16         `yaml:"base_port" json:"base_port"`
    MaxPorts      int            `yaml:"max_ports" json:"max_ports"`
    ProbeTarget   string         `yaml:"probe_target" json:"probe_target"`
    ProxyUsername string         `yaml:"proxy_username" json:"proxy_username"`
    ProxyPassword string         `yaml:"proxy_password" json:"proxy_password"`
    NodesSource   NodesSource    `yaml:"nodes_source" json:"nodes_source"`
    CreatedAt     time.Time      `yaml:"created_at" json:"created_at"`
    UpdatedAt     time.Time      `yaml:"updated_at" json:"updated_at"`
}

// NodesSource 节点来源配置
type NodesSource struct {
    Type     string            `yaml:"type" json:"type"`           // subscription | file | manual
    URL      string            `yaml:"url,omitempty" json:"url,omitempty"`
    FilePath string            `yaml:"file_path,omitempty" json:"file_path,omitempty"`
    Nodes    []config.NodeConfig `yaml:"nodes,omitempty" json:"nodes,omitempty"`
}

// GroupStatus 分组状态
type GroupStatus struct {
    GroupConfig
    TotalNodes     int    `json:"total_nodes"`
    AvailableNodes int    `json:"available_nodes"`
    FailedNodes    int    `json:"failed_nodes"`
    UnknownNodes   int    `json:"unknown_nodes"`
    LastProbeTime  string `json:"last_probe_time"`
    Status         string `json:"status"`  // running | stopped | error
}
```

## 后端API设计

### 1. 分组管理API

```go
// 路由注册
mux.HandleFunc("/api/groups", s.withAuth(s.handleGroups))                    // GET/POST
mux.HandleFunc("/api/groups/", s.withAuth(s.handleGroupItem))              // GET/PUT/DELETE
mux.HandleFunc("/api/groups/", s.withAuth(s.handleGroupAction))            // POST actions

// API端点设计
GET    /api/groups                    // 获取所有分组
POST   /api/groups                    // 创建新分组
GET    /api/groups/{id}               // 获取指定分组
PUT    /api/groups/{id}               // 更新分组
DELETE /api/groups/{id}               // 删除分组
POST   /api/groups/{id}/start         // 启动分组
POST   /api/groups/{id}/stop          // 停止分组

# 分组节点管理API (独立功能)
GET    /api/groups/{id}/nodes         // 获取分组节点列表
GET    /api/groups/{id}/nodes/probe-all // 探测分组所有节点
POST   /api/groups/{id}/nodes/probe-all // 批量探测分组节点 (SSE流式)
POST   /api/groups/{id}/nodes/cleanup-unhealthy // 清除分组不健康节点
GET    /api/groups/{id}/nodes/export  // 导出分组所有节点
GET    /api/groups/{id}/nodes/export-healthy // 导出分组健康节点
POST   /api/groups/{id}/nodes/import  // 批量导入节点到分组
GET    /api/groups/{id}/nodes/{nodeId}/probe // 探测单个节点
POST   /api/groups/{id}/nodes/{nodeId}/release // 释放节点拉黑状态
GET    /api/groups/{id}/status        // 获取分组状态
```

### 2. 节点导入API

```go
// 批量导入请求结构
type BatchImportRequest struct {
    GroupID string   `json:"group_id"`
    Type    string   `json:"type"`    // text | url | file
    Content string   `json:"content"`  // 文本内容或URL
    Format  string   `json:"format"`   // auto | v2ray | clash | ss
}

// 响应结构
type BatchImportResponse struct {
    Success     bool     `json:"success"`
    Total       int      `json:"total"`
    Imported    int      `json:"imported"`
    Skipped     int      `json:"skipped"`
    Failed      int      `json:"failed"`
    Errors      []string `json:"errors"`
    ImportTime  string   `json:"import_time"`
}
```

## 前端界面设计

### 1. 分组管理页面

```html
<!-- 分组管理主界面 -->
<div class="groups-container">
    <!-- 分组列表 -->
    <div class="groups-sidebar">
        <div class="groups-header">
            <h3>分组管理</h3>
            <button class="btn btn-primary" onclick="showCreateGroupModal()">
                <svg>...</svg>
                新建分组
            </button>
        </div>
        <div class="groups-list" id="groupsList">
            <!-- 分组项列表 -->
        </div>
    </div>

    <!-- 分组详情 -->
    <div class="groups-content">
        <div class="group-overview" id="groupOverview">
            <!-- 分组统计信息 -->
        </div>

        <!-- 节点管理 -->
        <div class="group-nodes">
            <div class="nodes-header">
                <h4>节点列表</h4>
                <div class="nodes-stats">
                    <span class="stat-item">
                        <span class="stat-label">总计:</span>
                        <span class="stat-value" id="totalNodes">0</span>
                    </span>
                    <span class="stat-item">
                        <span class="stat-label">可用:</span>
                        <span class="stat-value healthy" id="availableNodes">0</span>
                    </span>
                    <span class="stat-item">
                        <span class="stat-label">不可用:</span>
                        <span class="stat-value unhealthy" id="unhealthyNodes">0</span>
                    </span>
                </div>
                <div class="nodes-actions">
                    <button class="btn btn-secondary" onclick="showImportModal()">
                        <svg>...</svg>
                        批量导入
                    </button>
                    <button class="btn btn-secondary" onclick="probeGroupNodes()">
                        <svg>...</svg>
                        探测全部
                    </button>
                    <button class="btn btn-secondary" onclick="cleanupGroupUnhealthy()">
                        <svg>...</svg>
                        清除不健康节点
                    </button>
                    <div class="btn-group">
                        <button class="btn btn-secondary" onclick="exportGroupNodes()">
                            <svg>...</svg>
                            导出节点
                        </button>
                        <button class="btn btn-success" onclick="exportGroupHealthyNodes()">
                            <svg>...</svg>
                            导出健康节点
                        </button>
                    </div>
                </div>
            </div>
            <div class="nodes-table" id="nodesTable">
                <!-- 节点表格 -->
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>节点名称</th>
                            <th>类型</th>
                            <th>地址</th>
                            <th>端口</th>
                            <th>状态</th>
                            <th>延迟</th>
                            <th>最后检查</th>
                            <th>操作</th>
                        </tr>
                    </thead>
                    <tbody id="nodesTableBody">
                        <!-- 动态生成节点行 -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</div>
```

### 2. 分组创建/编辑模态框

```html
<!-- 分组配置模态框 -->
<div class="modal" id="groupModal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 id="modalTitle">新建分组</h3>
            <button class="modal-close" onclick="closeGroupModal()">&times;</button>
        </div>
        <div class="modal-body">
            <form id="groupForm">
                <div class="form-group">
                    <label>分组名称 *</label>
                    <input type="text" name="name" required>
                </div>

                <div class="form-group">
                    <label>分组ID *</label>
                    <input type="text" name="id" required pattern="[a-z0-9-]+">
                </div>

                <div class="form-group">
                    <label>运行模式 *</label>
                    <select name="mode">
                        <option value="pool">Pool模式</option>
                        <option value="multi-port">Multi-port模式</option>
                        <option value="hybrid">混合模式</option>
                    </select>
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label>起始端口 *</label>
                        <input type="number" name="base_port" min="1024" max="65535" required>
                    </div>
                    <div class="form-group">
                        <label>最大端口数</label>
                        <input type="number" name="max_ports" min="1" value="100">
                    </div>
                </div>

                <div class="form-group">
                    <label>探测目标 *</label>
                    <input type="text" name="probe_target" placeholder="www.google.com:80" required>
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label>代理用户名</label>
                        <input type="text" name="proxy_username">
                    </div>
                    <div class="form-group">
                        <label>代理密码</label>
                        <input type="password" name="proxy_password">
                    </div>
                </div>

                <div class="form-group">
                    <label>节点来源</label>
                    <select name="nodes_source_type" onchange="toggleNodesSource()">
                        <option value="manual">手动配置</option>
                        <option value="subscription">订阅链接</option>
                        <option value="file">文件导入</option>
                    </select>
                </div>

                <div id="manualNodes" class="nodes-source">
                    <label>节点列表</label>
                    <textarea name="manual_nodes" rows="5" placeholder="每行一个节点URI"></textarea>
                </div>

                <div id="subscriptionSource" class="nodes-source" style="display:none;">
                    <label>订阅链接</label>
                    <input type="url" name="subscription_url" placeholder="https://example.com/subscribe">
                </div>

                <div id="fileSource" class="nodes-source" style="display:none;">
                    <label>文件路径</label>
                    <input type="text" name="file_path" placeholder="nodes/group.txt">
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-secondary" onclick="closeGroupModal()">取消</button>
            <button type="button" class="btn btn-primary" onclick="saveGroup()">保存</button>
        </div>
    </div>
</div>
```

### 3. 批量导入模态框

```html
<!-- 批量导入模态框 -->
<div class="modal" id="importModal">
    <div class="modal-content">
        <div class="modal-header">
            <h3>批量导入节点</h3>
            <button class="modal-close" onclick="closeImportModal()">&times;</button>
        </div>
        <div class="modal-body">
            <div class="import-tabs">
                <button class="tab active" onclick="switchImportTab('text')">文本导入</button>
                <button class="tab" onclick="switchImportTab('url')">URL导入</button>
                <button class="tab" onclick="switchImportTab('file')">文件上传</button>
            </div>

            <div id="textImport" class="import-content">
                <div class="form-group">
                    <label>节点列表 (每行一个)</label>
                    <textarea id="importText" rows="10" placeholder="vless://uuid@server:443#节点1&#10;ss://base64@server:8388#节点2"></textarea>
                </div>
                <div class="form-group">
                    <label>格式</label>
                    <select id="importFormat">
                        <option value="auto">自动检测</option>
                        <option value="v2ray">V2Ray订阅</option>
                        <option value="clash">Clash配置</option>
                        <option value="ss">Shadowsocks</option>
                        <option value="text">纯文本</option>
                    </select>
                </div>
            </div>

            <div id="urlImport" class="import-content" style="display:none;">
                <div class="form-group">
                    <label>订阅链接</label>
                    <input type="url" id="importUrl" placeholder="https://example.com/subscribe">
                </div>
            </div>

            <div id="fileImport" class="import-content" style="display:none;">
                <div class="form-group">
                    <label>选择文件</label>
                    <input type="file" id="importFile" accept=".txt,.yaml,.yml">
                </div>
            </div>

            <div class="import-options">
                <label>
                    <input type="checkbox" id="skipDuplicates">
                    跳过重复节点
                </label>
                <label>
                    <input type="checkbox" id="autoTest">
                    导入后自动测试
                </label>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" onclick="closeImportModal()">取消</button>
            <button class="btn btn-primary" onclick="importNodes()">导入</button>
        </div>
    </div>
</div>
```

## 核心功能实现

### 1. 分组管理器

```go
// GroupManager 分组管理器
type GroupManager struct {
    groups map[string]*GroupInstance
    mu     sync.RWMutex
    logger log.Logger
}

// GroupInstance 分组实例
type GroupInstance struct {
    Config     GroupConfig
    Manager    *Manager  // 复用现有的monitor.Manager
    BoxManager *boxmgr.Manager
    Status     GroupStatus
    mu         sync.RWMutex
}

// 创建分组
func (gm *GroupManager) CreateGroup(config GroupConfig) error

// 启动分组
func (gm *GroupManager) StartGroup(groupID string) error

// 停止分组
func (gm *GroupManager) StopGroup(groupID string) error

// 获取分组状态
func (gm *GroupManager) GetGroupStatus(groupID string) (*GroupStatus, error)

// 批量导入节点
func (gm *GroupManager) BatchImport(groupID string, request BatchImportRequest) (*BatchImportResponse, error)

// 分组节点管理方法
func (gm *GroupManager) GetGroupNodes(groupID string) ([]monitor.Snapshot, error)

func (gm *GroupManager) ProbeGroupNode(groupID, nodeID string) (time.Duration, error)

func (gm *GroupManager) ProbeGroupAllNodes(groupID string, ctx context.Context) (<-chan monitor.ProbeResult, error)

func (gm *GroupManager) CleanupGroupUnhealthy(groupID string) (*CleanupResponse, error)

func (gm *GroupManager) ExportGroupNodes(groupID string) (string, error)

func (gm *GroupManager) ExportGroupHealthyNodes(groupID string) (string, error)

func (gm *GroupManager) ReleaseGroupNode(groupID, nodeID string) error
```

### 2. 端口分配管理

```go
// PortManager 端口管理器
type PortManager struct {
    allocatedPorts map[uint16]string  // port -> group_id
    groupPorts     map[string][]uint16 // group_id -> ports
    mu             sync.RWMutex
}

// 分配端口
func (pm *PortManager) AllocatePorts(groupID string, basePort, count int) ([]uint16, error)

// 释放端口
func (pm *PortManager) ReleasePorts(groupID string)

// 检查端口可用性
func (pm *PortManager) IsPortAvailable(port uint16) bool
```

### 3. 导入解析器

```go
// NodeParser 节点解析器接口
type NodeParser interface {
    Parse(content string) ([]config.NodeConfig, error)
    DetectFormat(content string) string
}

// V2RayParser V2Ray订阅解析器
type V2RayParser struct{}

// ClashParser Clash配置解析器
type ClashParser struct{}

// TextParser 纯文本解析器
type TextParser struct{}

// 统一解析入口
func ParseNodes(content, format string) ([]config.NodeConfig, error) {
    var parser NodeParser

    if format == "auto" {
        format = DetectFormat(content)
    }

    switch format {
    case "v2ray":
        parser = &V2RayParser{}
    case "clash":
        parser = &ClashParser{}
    case "text":
        parser = &TextParser{}
    default:
        return nil, fmt.Errorf("unsupported format: %s", format)
    }

    return parser.Parse(content)
}
```

## 前端JavaScript实现

### 1. 分组管理

```javascript
// 分组管理类
class GroupManager {
    constructor() {
        this.currentGroup = null;
        this.groups = {};
    }

    // 获取所有分组
    async getGroups() {
        const response = await fetch('/api/groups');
        return await response.json();
    }

    // 创建分组
    async createGroup(config) {
        const response = await fetch('/api/groups', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config)
        });
        return await response.json();
    }

    // 更新分组
    async updateGroup(id, config) {
        const response = await fetch(`/api/groups/${id}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config)
        });
        return await response.json();
    }

    // 删除分组
    async deleteGroup(id) {
        const response = await fetch(`/api/groups/${id}`, {
            method: 'DELETE'
        });
        return await response.json();
    }

    // 启动分组
    async startGroup(id) {
        const response = await fetch(`/api/groups/${id}/start`, {
            method: 'POST'
        });
        return await response.json();
    }

    // 停止分组
    async stopGroup(id) {
        const response = await fetch(`/api/groups/${id}/stop`, {
            method: 'POST'
        });
        return await response.json();
    }
}

// 渲染分组列表
function renderGroupsList(groups) {
    const container = document.getElementById('groupsList');
    container.innerHTML = '';

    groups.forEach(group => {
        const item = createGroupItem(group);
        container.appendChild(item);
    });
}

// 创建分组项
function createGroupItem(group) {
    const div = document.createElement('div');
    div.className = `group-item ${group.enabled ? 'enabled' : 'disabled'}`;
    div.innerHTML = `
        <div class="group-info">
            <h4>${group.name}</h4>
            <span class="group-status ${group.status}">${getStatusText(group.status)}</span>
        </div>
        <div class="group-stats">
            <span>${group.total_nodes || 0} 节点</span>
            <span>${group.available_nodes || 0} 可用</span>
        </div>
        <div class="group-actions">
            <button onclick="editGroup('${group.id}')" class="btn btn-sm">编辑</button>
            <button onclick="deleteGroup('${group.id}')" class="btn btn-sm btn-danger">删除</button>
        </div>
    `;

    div.onclick = () => selectGroup(group.id);
    return div;
}

// 分组节点管理方法
class GroupNodeManager {
    constructor(groupId) {
        this.groupId = groupId;
    }

    // 获取分组节点列表
    async getNodes() {
        const response = await fetch(`/api/groups/${this.groupId}/nodes`);
        return await response.json();
    }

    // 探测单个节点
    async probeNode(nodeId) {
        const response = await fetch(`/api/groups/${this.groupId}/nodes/${nodeId}/probe`, {
            method: 'POST'
        });
        return await response.json();
    }

    // 批量探测所有节点 (SSE流)
    async probeAllNodes(onProgress) {
        const response = await fetch(`/api/groups/${this.groupId}/nodes/probe-all`, {
            method: 'POST'
        });

        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            const lines = decoder.decode(value, { stream: true }).split('\n');
            for (const line of lines) {
                if (line.trim()) {
                    const result = JSON.parse(line);
                    onProgress(result);
                }
            }
        }
    }

    // 清除不健康节点
    async cleanupUnhealthy() {
        const response = await fetch(`/api/groups/${this.groupId}/nodes/cleanup-unhealthy`, {
            method: 'POST'
        });
        return await response.json();
    }

    // 导出所有节点
    async exportNodes() {
        const response = await fetch(`/api/groups/${this.groupId}/nodes/export`);
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = `group_${this.groupId}_nodes.txt`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
    }

    // 导出健康节点
    async exportHealthyNodes() {
        const response = await fetch(`/api/groups/${this.groupId}/nodes/export-healthy`);
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = `group_${this.groupId}_healthy_nodes.txt`;
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
    }

    // 释放节点拉黑状态
    async releaseNode(nodeId) {
        const response = await fetch(`/api/groups/${this.groupId}/nodes/${nodeId}/release`, {
            method: 'POST'
        });
        return await response.json();
    }
}

// 全局分组节点管理器实例
let currentNodeManager = null;

// 初始化分组节点管理
function initGroupNodeManager(groupId) {
    currentNodeManager = new GroupNodeManager(groupId);
}

// 分组节点操作函数
function probeGroupNodes() {
    if (!currentNodeManager) {
        showToast('请先选择分组', 'error');
        return;
    }

    showToast('开始探测分组节点...', 'info');

    currentNodeManager.probeAllNodes((result) => {
        if (result.error) {
            showToast(`探测失败: ${result.error}`, 'error');
        } else {
            showToast(`节点 ${result.node} 探测完成，延迟: ${result.latency_ms}ms`, 'success');
        }
        // 更新节点状态显示
        refreshGroupNodes();
    });
}

function cleanupGroupUnhealthy() {
    if (!currentNodeManager) {
        showToast('请先选择分组', 'error');
        return;
    }

    if (!confirm('确定要清除该分组中的所有不健康节点吗？\n\n这将删除已完成检查但不可用的节点。')) {
        return;
    }

    currentNodeManager.cleanupUnhealthy().then(result => {
        if (result.deleted > 0) {
            showToast(`已清除 ${result.deleted} 个不健康节点`, 'success');
            // 询问是否重载配置
            setTimeout(() => {
                if (confirm('是否重载分组配置以使更改生效？')) {
                    reloadGroupConfig();
                }
            }, 1000);
        } else {
            const details = `\n\n节点状态统计：\n总节点数：${result.total_nodes || 0}\n已检查：${result.checked_nodes || 0}\n可用节点：${result.available_nodes || 0}\n未检查：${result.unchecked_nodes || 0}`;
            showToast('没有发现不健康节点' + details, 'info');
        }
        refreshGroupNodes();
    }).catch(err => {
        showToast('清除失败: ' + err.message, 'error');
    });
}

function exportGroupNodes() {
    if (!currentNodeManager) {
        showToast('请先选择分组', 'error');
        return;
    }

    currentNodeManager.exportNodes();
    showToast('分组节点导出完成', 'success');
}

function exportGroupHealthyNodes() {
    if (!currentNodeManager) {
        showToast('请先选择分组', 'error');
        return;
    }

    currentNodeManager.exportHealthyNodes();
    showToast('分组健康节点导出完成', 'success');
}

function probeNode(nodeId) {
    if (!currentNodeManager) {
        showToast('请先选择分组', 'error');
        return;
    }

    currentNodeManager.probeNode(nodeId).then(result => {
        if (result.error) {
            showToast(`探测失败: ${result.error}`, 'error');
        } else {
            showToast(`探测成功，延迟: ${result.latency_ms}ms`, 'success');
        }
        refreshGroupNodes();
    }).catch(err => {
        showToast('探测失败: ' + err.message, 'error');
    });
}

function releaseNode(nodeId) {
    if (!currentNodeManager) {
        showToast('请先选择分组', 'error');
        return;
    }

    currentNodeManager.releaseNode(nodeId).then(result => {
        showToast('已解除节点拉黑状态', 'success');
        refreshGroupNodes();
    }).catch(err => {
        showToast('释放失败: ' + err.message, 'error');
    });
}

// 渲染分组节点表格
function renderGroupNodesTable(nodes) {
    const tbody = document.getElementById('nodesTableBody');
    tbody.innerHTML = '';

    nodes.forEach(node => {
        const row = createNodeRow(node);
        tbody.appendChild(row);
    });

    // 更新统计信息
    document.getElementById('totalNodes').textContent = nodes.length;
    document.getElementById('availableNodes').textContent = nodes.filter(n => n.available).length;
    document.getElementById('unhealthyNodes').textContent = nodes.filter(n => n.initial_check_done && !n.available).length;
}

function createNodeRow(node) {
    const row = document.createElement('tr');
    const statusClass = node.available ? 'healthy' : (node.initial_check_done ? 'unhealthy' : 'unknown');
    const statusText = node.available ? '可用' : (node.initial_check_done ? '不可用' : '未检查');

    row.innerHTML = `
        <td>${node.name}</td>
        <td>${node.mode}</td>
        <td>${node.listen_address || '-'}</td>
        <td>${node.port || '-'}</td>
        <td><span class="status ${statusClass}">${statusText}</span></td>
        <td>${node.last_latency_ms >= 0 ? node.last_latency_ms + 'ms' : '-'}</td>
        <td>${formatTime(node.last_success || node.last_failure)}</td>
        <td>
            <button onclick="probeNode('${node.tag}')" class="btn btn-sm">探测</button>
            ${node.blacklisted ? `<button onclick="releaseNode('${node.tag}')" class="btn btn-sm btn-warning">释放</button>` : ''}
        </td>
    `;
    return row;
}
```

### 2. 批量导入

```javascript
// 批量导入节点
async function importNodes() {
    const groupId = getCurrentGroupId();
    const importType = getActiveImportTab();
    let content, format;

    switch (importType) {
        case 'text':
            content = document.getElementById('importText').value;
            format = document.getElementById('importFormat').value;
            break;
        case 'url':
            content = await fetchSubscription(document.getElementById('importUrl').value);
            format = 'auto';
            break;
        case 'file':
            content = await readFile(document.getElementById('importFile').files[0]);
            format = 'auto';
            break;
    }

    const request = {
        group_id: groupId,
        type: importType,
        content: content,
        format: format,
        skip_duplicates: document.getElementById('skipDuplicates').checked,
        auto_test: document.getElementById('autoTest').checked
    };

    try {
        const response = await fetch('/api/groups/import', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(request)
        });

        const result = await response.json();
        showImportResult(result);

        if (result.success) {
            closeImportModal();
            refreshGroupNodes(groupId);
        }
    } catch (error) {
        showToast('导入失败: ' + error.message, 'error');
    }
}

// 显示导入结果
function showImportResult(result) {
    const message = `
        导入完成！
        总计: ${result.total}
        成功: ${result.imported}
        跳过: ${result.skipped}
        失败: ${result.failed}
    `;

    if (result.success) {
        showToast(message, 'success');
    } else {
        showToast(message + '\n错误: ' + result.errors.join(', '), 'error');
    }
}
```

## 兼容性处理

### 1. 保持全局功能兼容

现有的全局功能将继续正常工作，与新的分组功能并存：

**全局API端点（保持不变）**：
```go
// 现有的全局节点管理API
GET    /api/nodes                    // 获取所有节点（全局视图）
POST   /api/nodes/probe-all          // 批量探测所有节点
POST   /api/nodes/cleanup-unhealthy  // 清除全局不健康节点
GET    /api/export                    // 导出全局所有节点
GET    /api/export-healthy            // 导出全局健康节点
GET    /api/nodes/{tag}/probe         // 探测单个节点
POST   /api/nodes/{tag}/release       // 释放节点拉黑状态
```

**全局与分组功能的关系**：
- **全局功能**：管理所有节点的统一视图和操作
- **分组功能**：按业务需求管理特定分组节点
- **数据隔离**：每个分组有独立的配置和管理范围
- **操作隔离**：分组操作不影响其他分组或全局节点

### 2. 配置文件兼容

```go
// ConfigV2 新的配置结构
type ConfigV2 struct {
    Mode        string        `yaml:"mode"`
    LogLevel    string        `yaml:"log_level"`
    Management  ManagementConfig `yaml:"management"`
    Groups      []GroupConfig `yaml:"groups"`
    // 保留现有字段以确保兼容性
    Listener    ListenerConfig     `yaml:"listener,omitempty"`
    Nodes       []NodeConfig       `yaml:"nodes,omitempty"`
    Pool        PoolConfig         `yaml:"pool,omitempty"`
    MultiPort   MultiPortConfig    `yaml:"multi_port,omitempty"`
}

// 配置迁移函数
func MigrateConfig(oldConfig *config.Config) *ConfigV2 {
    newConfig := &ConfigV2{
        Mode:       oldConfig.Mode,
        LogLevel:   oldConfig.LogLevel,
        Management: oldConfig.Management,
        Groups:     []GroupConfig{},
    }

    // 如果没有分组配置，创建默认分组
    if len(oldConfig.Nodes) > 0 {
        defaultGroup := GroupConfig{
            ID:            "default",
            Name:          "默认分组",
            Enabled:       true,
            Mode:          oldConfig.Mode,
            BasePort:      oldConfig.MultiPort.BasePort,
            MaxPorts:      100,
            ProbeTarget:   oldConfig.Management.ProbeTarget,
            ProxyUsername: oldConfig.ProxyUsername,
            ProxyPassword: oldConfig.ProxyPassword,
            NodesSource: NodesSource{
                Type:  "manual",
                Nodes: oldConfig.Nodes,
            },
        }
        newConfig.Groups = append(newConfig.Groups, defaultGroup)
    }

    return newConfig
}
```

### 2. API兼容性

```go
// 保持现有API端点正常工作
// 新的分组功能通过新的端点提供
// 现有的 /api/nodes, /api/export 等端点继续支持
```

## 部署和测试计划

### 阶段一：核心功能 (2-3周)
1. 数据模型和配置结构调整
2. 分组CRUD API实现
3. 基础前端界面开发
4. 端口管理器实现

### 阶段二：导入导出 (2周)
1. 多格式节点解析器
2. 批量导入功能
3. 分组导出功能
4. 前端导入界面

### 阶段三：高级功能 (1-2周)
1. 分组独立健康检查
2. 实时统计和监控
3. 分组操作日志
4. 性能优化

### 阶段四：测试和文档 (1周)
1. 单元测试和集成测试
2. 用户文档编写
3. 兼容性测试
4. 性能测试

## 总结

这个分组管理功能设计提供了：

### 🎯 **核心分组功能**
1. **��整的分组管理**：创建、编辑、删除、启停分组
2. **独立的分组配置**：每个分组独立的端口、测试URL、认证配置
3. **批量节点管理**：支持多种导入方式和格式
4. **分组隔离运行**：每个分组独立的运行环境和管理范围

### 🔧 **分组节点管理功能**
1. **独立检测**：每个分组独立的健康检测机制和测试URL
2. **独立清理**：每个分组独立的"清除不健康节点"功能
3. **独立导出**：每个分组独立的"导出节点"和"导出健康节点"功能
4. **实时统计**：每个分组独立的节点状态统计和监控

### 🔄 **全局功能保持**
1. **现有API完全兼容**：所有现有的 `/api/nodes/*` 和 `/api/export*` 端点保持不变
2. **现有功能继续工作**：全局的检测、清除、导出功能继续正常工作
3. **数据视图共存**：用户可以同时使用全局视图和分组视图
4. **操作互不影响**：分组操作不影响全局节点，全局操作不影响分组内部管理

### 🎨 **用户体验优化**
1. **直观的分组界面**：清晰的分组管理和节点管理界面
2. **一致的操作体验**：分组内操作与全局操作保持一致的交互模式
3. **详细的状态反馈**：每个分组独立的操作状态和进度提示
4. **灵活的管理模式**：支持全局管理和分组管理两种模式

### 🏗️ **技术架构优势**
1. **向后兼容性**：现有配置和API继续工作，无需迁移
2. **可扩展架构**：便于后续功能扩展和性能优化
3. **数据隔离**：每个分组独立的配置和状态管理
4. **操作安全**：分组操作有完整的权限控制和错误处理

该方案不仅提供了强大的分组管理能力，还完全保持了现有功能的稳定性，为用户提供了更灵活和强大的代理节点管理选择。

该方案保持了与现有代码的一致性，同时提供了强大的分组管理能力。