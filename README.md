# Windows High Performance Power Scripts / Windows 高性能电源脚本

## English

### Overview

This repository provides:

- `cpu-high-performance.ps1`: the main entry script for GitHub Raw and local execution. It starts by asking whether you want to apply High performance mode or restore the previous/default state.
- `Set-HighPerformance.ps1`: a local convenience wrapper that directly applies High performance mode.
- `Restore-DefaultPower.ps1`: a local convenience wrapper that directly restores the previous/default state.

### Repository contents

Files at the repository root:

- `cpu-high-performance.ps1` — canonical script for GitHub Raw usage
- `Set-HighPerformance.ps1` — local apply wrapper
- `Restore-DefaultPower.ps1` — local restore wrapper
- `README.md` — bilingual documentation
- `.gitignore` — prevents backup/state artifacts from being committed

The main script is designed for this usage pattern:

```powershell
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1 | iex
```

When it starts, it prompts you to choose:

- apply High performance mode
- restore defaults / previous values

### What the apply flow changes

The apply flow does all of the following:

1. Captures the current active scheme GUID.
2. Activates the built-in **High performance** scheme (`8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`).
3. Sets the computer to never sleep automatically by changing:
   - `standby-timeout-ac = 0`
   - `standby-timeout-dc = 0`
   - `hibernate-timeout-ac = 0`
   - `hibernate-timeout-dc = 0`
   - `HYBRIDSLEEP` AC/DC = `0`
4. Reads `powercfg /qh SCHEME_CURRENT SUB_PROCESSOR` and searches for these localized names:
   - `异类线程调度策略`
   - `异类短运行线程调度策略`
   - `Heterogeneous thread scheduling policy`
   - `Heterogeneous short running thread scheduling policy`
5. Extracts the matching GUIDs from the `powercfg /qh` output.
6. For each discovered heterogeneous scheduling GUID, runs:

```powershell
powercfg -attributes SUB_PROCESSOR {GUID} -ATTRIB_HIDE
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR {GUID} 2
```

### Resolved GUIDs on the reference machine

The reference machine used during implementation returned:

- `异类线程调度策略` / `Heterogeneous thread scheduling policy` → `93b8b6dc-0698-4d1c-9ee4-0644e900c85d`
- `异类短运行线程调度策略` / `Heterogeneous short running thread scheduling policy` → `bae08b81-2d5e-4688-ad6a-13243356654b`

The script still resolves them dynamically at runtime.

### Requirements

- Windows 10 or Windows 11
- PowerShell running **as Administrator**
- `powercfg.exe` available in the system path

### GitHub Raw usage

Recommended:

```powershell
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1 | iex
```

After startup, the script asks whether you want to:

- apply High performance mode
- restore defaults / previous values

### Local usage

Interactive entry script:

```powershell
.\cpu-high-performance.ps1
```

Direct apply wrapper:

```powershell
.\Set-HighPerformance.ps1
```

Direct restore wrapper:

```powershell
.\Restore-DefaultPower.ps1
```

Preview the apply flow without changing anything:

```powershell
.\Set-HighPerformance.ps1 -WhatIf
```

Preview the restore flow without changing anything:

```powershell
.\Restore-DefaultPower.ps1 -WhatIf
```

### Backup and restore behavior

The main script stores its backup state in a stable machine-wide path instead of a script-relative path:

```text
$env:ProgramData\CpuHighPerformance\state.json
```

That is what makes restore work even when the script is started with `irm ... | iex`.

It stores:

- the previously active power scheme GUID
- the original High performance values for the sleep-related settings that are changed
- the original High performance AC/DC values for the two heterogeneous scheduling settings

The restore flow uses that file to restore the modified **High performance** values and then re-activates the previously active scheme when it still exists. After a successful restore, the backup file is removed.

If the backup file is missing, the restore flow does a safe fallback instead of reconstructing old values:

- it hides the two exposed processor settings again with `+ATTRIB_HIDE`
- it activates the built-in **Balanced** scheme
- it does **not** reconstruct the old High performance values without the backup file

For backward compatibility, the restore flow also checks the older local backup location if it exists:

```text
.powercfg-backup\state.json
```

### Verification commands

Check the active plan:

```powershell
powercfg /getactivescheme
```

Check the processor subgroup, including hidden settings:

```powershell
powercfg /qh SCHEME_CURRENT SUB_PROCESSOR
```

Check the two heterogeneous scheduling settings directly:

```powershell
powercfg /q SCHEME_CURRENT SUB_PROCESSOR 93b8b6dc-0698-4d1c-9ee4-0644e900c85d
powercfg /q SCHEME_CURRENT SUB_PROCESSOR bae08b81-2d5e-4688-ad6a-13243356654b
```

Check the sleep timeout directly:

```powershell
powercfg /q SCHEME_CURRENT SUB_SLEEP 29f6c1db-86da-48c5-9fdb-f2b67b1f44da
```

### Notes and caveats

- These scripts change local machine power settings and should be run intentionally.
- The heterogeneous scheduling settings only matter on systems that expose those processor policies.
- The script searches Chinese and English display names first, then falls back to stable aliases `SCHEDPOLICY` and `SHORTSCHEDPOLICY` if needed.
- `-ATTRIB_HIDE` is used to expose the settings; `+ATTRIB_HIDE` is used in the restore flow to hide them again.
- `cpu-high-performance.ps1` is the canonical implementation. The other two scripts are wrappers for local convenience.

---

## 中文

### 概述

这个仓库提供了 3 个脚本：

- `cpu-high-performance.ps1`：主入口脚本，适合 GitHub Raw 和本地执行。启动后会先询问你是要开启高性能模式，还是恢复默认 / 之前的设置。
- `Set-HighPerformance.ps1`：本地方便用的包装脚本，直接应用高性能模式。
- `Restore-DefaultPower.ps1`：本地方便用的包装脚本，直接恢复默认 / 之前的设置。

### 仓库内容

仓库根目录下的文件如下：

- `cpu-high-performance.ps1` —— GitHub Raw 使用时的主脚本
- `Set-HighPerformance.ps1` —— 本地直接应用高性能的包装脚本
- `Restore-DefaultPower.ps1` —— 本地直接恢复默认的包装脚本
- `README.md` —— 中英双语说明文档
- `.gitignore` —— 防止备份 / 状态文件被误提交

主脚本就是为下面这种方式准备的：

```powershell
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1 | iex
```

脚本启动后，会让用户选择：

- 启用高性能模式
- 恢复默认 / 之前的设置

### 应用高性能流程会做什么

应用流程会执行以下操作：

1. 记录当前活动电源方案 GUID。
2. 激活系统内置的**高性能**方案（`8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`）。
3. 通过以下设置让计算机不再自动进入睡眠：
   - `standby-timeout-ac = 0`
   - `standby-timeout-dc = 0`
   - `hibernate-timeout-ac = 0`
   - `hibernate-timeout-dc = 0`
   - `HYBRIDSLEEP` 的 AC/DC 都设置为 `0`
4. 读取 `powercfg /qh SCHEME_CURRENT SUB_PROCESSOR`，并搜索以下中英文名称：
   - `异类线程调度策略`
   - `异类短运行线程调度策略`
   - `Heterogeneous thread scheduling policy`
   - `Heterogeneous short running thread scheduling policy`
5. 从 `powercfg /qh` 输出中提取对应 GUID。
6. 对每一个解析出来的异类调度 GUID 执行：

```powershell
powercfg -attributes SUB_PROCESSOR {GUID} -ATTRIB_HIDE
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR {GUID} 2
```

### 参考机器上解析到的 GUID

开发时参考机器返回的结果如下：

- `异类线程调度策略` / `Heterogeneous thread scheduling policy` → `93b8b6dc-0698-4d1c-9ee4-0644e900c85d`
- `异类短运行线程调度策略` / `Heterogeneous short running thread scheduling policy` → `bae08b81-2d5e-4688-ad6a-13243356654b`

脚本运行时仍然会动态解析，不会把结果硬编码死。

### 运行要求

- Windows 10 或 Windows 11
- 以**管理员身份**运行 PowerShell
- 系统路径中可用 `powercfg.exe`

### GitHub Raw 使用方式

推荐这样执行：

```powershell
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1 | iex
```

启动之后，脚本会让你选择：

- 启用高性能模式
- 恢复默认 / 之前的设置

### 本地使用方式

交互式主入口：

```powershell
.\cpu-high-performance.ps1
```

直接应用高性能包装脚本：

```powershell
.\Set-HighPerformance.ps1
```

直接恢复默认包装脚本：

```powershell
.\Restore-DefaultPower.ps1
```

只预览应用流程、不实际修改：

```powershell
.\Set-HighPerformance.ps1 -WhatIf
```

只预览恢复流程、不实际修改：

```powershell
.\Restore-DefaultPower.ps1 -WhatIf
```

### 备份与恢复逻辑

主脚本会把备份状态写到一个稳定的全局路径，而不是脚本所在目录：

```text
$env:ProgramData\CpuHighPerformance\state.json
```

这就是为什么在 `irm ... | iex` 这种内存执行方式下，恢复仍然能正常工作。

其中保存了：

- 修改前的活动电源方案 GUID
- 被修改的睡眠相关设置在高性能方案中的原始值
- 两个异类调度设置在高性能方案中的原始 AC/DC 值

恢复流程会优先使用这个文件，把被修改的**高性能**方案设置值恢复回去，并在原先活动方案仍然存在时重新激活它。恢复成功后，备份文件会被删除。

如果没有找到备份文件，恢复流程会执行安全回退，而不是尝试凭空重建旧值：

- 使用 `+ATTRIB_HIDE` 把两个处理器设置重新隐藏
- 激活系统内置的**平衡**方案
- 在没有备份文件时，它**不会**重建之前高性能方案里的旧值

为了兼容旧版本，恢复流程也会检查旧的本地备份位置：

```text
.powercfg-backup\state.json
```

### 验证命令

查看当前活动电源方案：

```powershell
powercfg /getactivescheme
```

查看处理器子组（包含隐藏项）：

```powershell
powercfg /qh SCHEME_CURRENT SUB_PROCESSOR
```

直接查看这两个异类调度设置：

```powershell
powercfg /q SCHEME_CURRENT SUB_PROCESSOR 93b8b6dc-0698-4d1c-9ee4-0644e900c85d
powercfg /q SCHEME_CURRENT SUB_PROCESSOR bae08b81-2d5e-4688-ad6a-13243356654b
```

直接查看睡眠超时：

```powershell
powercfg /q SCHEME_CURRENT SUB_SLEEP 29f6c1db-86da-48c5-9fdb-f2b67b1f44da
```

### 说明与注意事项

- 这些脚本会修改本机电源设置，请在确认需求后执行。
- 只有在系统暴露这些异类调度策略的情况下，这两个处理器设置才有实际意义。
- 脚本会先按中文/英文显示名称搜索；如果没找到，再退回到稳定别名 `SCHEDPOLICY` 和 `SHORTSCHEDPOLICY`。
- 在这里，`-ATTRIB_HIDE` 用来取消隐藏，`+ATTRIB_HIDE` 用来在恢复时重新隐藏。
- `cpu-high-performance.ps1` 是真正的主实现，另外两个脚本只是为了本地方便使用的包装器。
