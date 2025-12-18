@echo off
echo 快速启动 Easy Proxies (调试版本)...

:: 编译
go build -tags "with_utls with_quic with_grpc" -o easy-proxies.exe ./cmd/easy_proxies
if %errorlevel% neq 0 (
    echo 编译失败
    pause
    exit /b 1
)

:: 启动
echo 启动服务...
echo Web界面: http://localhost:9090
echo.
easy-proxies.exe --config config.yaml