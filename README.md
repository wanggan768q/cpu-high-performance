# CPU High Performance

在 Windows 10 / 11 上快速应用 CPU 高性能相关电源设置。  
Quickly apply CPU high-performance related power settings on Windows 10 / 11.

---

## 目录 / Table of Contents

- [简介 / Overview](#简介--overview)
- [功能 / Features](#功能--features)
- [系统要求 / Requirements](#系统要求--requirements)
- [快速开始 / Quick Start](#快速开始--quick-start)
- [更安全的执行方式 / Safer Way to Run](#更安全的执行方式--safer-way-to-run)
- [脚本行为 / What the Scripts Do](#脚本行为--what-the-scripts-do)
- [常见问题 / FAQ](#常见问题--faq)
- [注意事项 / Notes](#注意事项--notes)
- [安全提示 / Security Note](#安全提示--security-note)
- [许可证 / License](#许可证--license)

---

## 简介 / Overview

这个仓库提供两个 PowerShell 脚本：

This repository provides two PowerShell scripts:

- `cpu-high-performance.ps1`  
  启用 CPU 高性能相关设置  
  Enable CPU high-performance related settings

- `restore-default.ps1`  
  恢复默认电源设置  
  Restore default power settings

这些脚本适合希望快速切换性能相关电源配置的用户。  
These scripts are intended for users who want to quickly switch performance-related power settings.

---

## 功能 / Features

### `cpu-high-performance.ps1`

启用以下设置：  
Enables the following:

- 关闭电源节流  
  Disable Power Throttling
- 恢复默认电源方案  
  Restore default power schemes
- 切换到高性能模式  
  Switch to High Performance mode
- 如果系统支持，设置异类线程调度策略为“首选高性能处理器”  
  If supported, set heterogeneous thread scheduling policies to “Prefer performant processors”
- 导出当前处理器电源设置到 `a.txt`  
  Export current processor power settings to `a.txt`

### `restore-default.ps1`

恢复以下设置：  
Restores the following:

- 移除 `PowerThrottlingOff`  
  Remove `PowerThrottlingOff`
- 恢复默认电源方案  
  Restore default power schemes
- 切换到平衡模式  
  Switch to Balanced mode

---

## 系统要求 / Requirements

- Windows 10 / Windows 11 桌面版  
  Windows 10 / Windows 11 desktop editions
- PowerShell 5.1 或更高版本  
  PowerShell 5.1 or later
- 管理员权限  
  Administrator privileges

> 注意 / Note  
> - “关闭电源节流”仅适用于 Windows 10 1709 / Build 16299 及以上，以及 Windows 11。  
>   “Disable Power Throttling” only applies to Windows 10 1709 / Build 16299 and later, and Windows 11.
> - “异类线程调度策略”仅在系统实际暴露该设置时才会生效。  
>   Heterogeneous scheduling policies only apply if the system actually exposes those settings.

---

## 快速开始 / Quick Start

### 启用高性能设置 / Enable high-performance settings

```powershell
irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/cpu-high-performance.ps1 | iex

irm https://raw.githubusercontent.com/wanggan768q/cpu-high-performance/refs/heads/main/restore-default.ps1 | iex

