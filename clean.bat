@echo off
echo 清理 Easy Proxies 编译文件...

:: 删除可执行文件
if exist "easy-proxies.exe" (
    del easy-proxies.exe
    echo 已删除 easy-proxies.exe
)

if exist "easy-proxies-debug.exe" (
    del easy-proxies-debug.exe
    echo 已删除 easy-proxies-debug.exe
)

echo 清理完成！
pause