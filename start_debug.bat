@echo off
chcp 65001 >nul
echo ===============================================
echo Easy Proxies 本地调试启动脚本
echo ===============================================
echo.

:: 检查Go环境
echo [1/4] 检查Go环境...
go version >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ 错误: 未找到Go环境，请先安装Go
    pause
    exit /b 1
)
echo ✅ Go环境检查通过
echo.

:: 检查配置文件
echo [2/4] 检查配置文件...
if not exist "config.yaml" (
    if exist "config.example.yaml" (
        echo 📋 发现示例配置文件，正在复制...
        copy "config.example.yaml" "config.yaml" >nul
        echo ✅ 已创建 config.yaml
        echo ⚠️  请根据需要修改 config.yaml 中的配置
    ) else (
        echo ❌ 错误: 未找到 config.yaml 或 config.example.yaml
        pause
        exit /b 1
    )
) else (
    echo ✅ 配置文件存在
)
echo.

:: 编译项目
echo [3/4] 编译项目...
echo 正在编译 easy-proxies (调试版本)...
go build -tags "with_utls with_quic with_grpc" -ldflags "-X main.debug=true" -o easy-proxies-debug.exe ./cmd/easy_proxies
if %errorlevel% neq 0 (
    echo ❌ 编译失败，请检查代码
    pause
    exit /b 1
)
echo ✅ 编译成功: easy-proxies-debug.exe
echo.

:: 启动服务
echo [4/4] 启动服务...
echo ===============================================
echo 🚀 正在启动 Easy Proxies 调试版本
echo ===============================================
echo 📊 Web管理界面: http://localhost:9090
echo 🔍 调试日志将显示在下方
echo.
echo 📝 测试步骤:
echo 1. 等待服务启动完成
echo 2. 打开浏览器访问: http://localhost:9090
echo 3. 登录后点击 "导出健康节点" 按钮
echo 4. 观察下方的调试日志输出
echo 5. 点击 "删除不健康节点" 按钮
echo 6. 观察下方的调试日志输出
echo.
echo 按 Ctrl+C 停止服务
echo ===============================================
echo.

:: 启动应用程序
easy-proxies-debug.exe --config config.yaml

:: 如果程序异常退出，显示错误信息
if %errorlevel% neq 0 (
    echo.
    echo ❌ 服务异常退出，错误代码: %errorlevel%
    echo.
    pause
)