#请先阅读脚本内容，再执行远程脚本命令。

## 高性能
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1 | iex

## 恢复
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/restore-default.ps1 | iex

## 更安全的方式
```
$u = "https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1"
$f = Join-Path $env:TEMP "cpu-high-performance.ps1"
iwr $u -OutFile $f
powershell -ExecutionPolicy Bypass -File $f

```

