# 06 · 硬件 · AMD 显卡状态监控

> 监控本机 AMD 双显卡（独显 + 核显）的运行状态：温度、功耗、显存、利用率、风扇。
> 适用于纯 AMD 平台，不用 nvidia-smi，用 rocm-smi + nvtop。

---

## 基本信息

| 项目 | 内容 |
|------|------|
| 显卡平台 | AMD（无 NVIDIA） |
| 监控驱动 | amdgpu（内核自带，已加载） |
| ROCm 版本 | 7.8（注意：较新，会触发旧 nvtop bug，见下文） |
| 已装工具 | `rocm-smi`（快照型）、**`nvtop 3.3.2`（源码编译，实时 TUI）** |
| nvtop 路径 | `/usr/local/bin/nvtop`（编译安装，非 apt） |
| 信息时效 | 2026-08-07 |

## 显卡识别（实测示例）

| rocm-smi 设备号 | PCI ID | 型号 | 角色 | GFX 架构 | 功耗上限 |
|----------------|--------|------|------|---------|---------|
| **GPU[0]** | `0x7551` | **AMD Radeon AI PRO R9700** | 独立显卡 | gfx1201 | 300W |
| GPU[1] | `0x13c0` | AMD Radeon Graphics | 集成显卡（核显） | - | - |

> **重要**：rocm-smi 的设备号 ≠ 物理位置。GPU[0] 是独显（AI PRO R9700），GPU[1] 是核显。
> 看功率一眼分辨：独显 300W 上限，核显功耗极低（0.0x W 级）。

对应 Linux 设备节点：
- GPU[0] (独显) → `/sys/class/drm/card2` (PCI 1002:13C0... 注意映射不直观，以 rocm-smi 为准)
- GPU[1] (核显) → `/sys/class/drm/card1`

## 工具一：nvtop（推荐，实时监控）⭐

类似 `htop` 的全屏实时监控，能看每张卡的温度/功耗/显存/利用率 + 每个进程占用了多少 GPU。

### 安装

⚠️ **不要用 `apt install nvtop`**——Ubuntu 仓库的 3.0.2 在 ROCm 7.x 下有崩溃 bug（见下方「已知坑」）。**必须从源码编译 3.3.2**。

```bash
# 1. 装编译依赖
sudo apt install -y cmake libncurses-dev libsystemd-dev build-essential

# 2. 下载源码（用 gh-proxy 国内镜像，直连 GitHub 常超时）
cd /tmp
aria2c -x8 -o nvtop.tar.gz \
  "https://gh-proxy.com/https://github.com/Syllo/nvtop/archive/refs/tags/3.3.2.tar.gz"

# 3. 解压、编译、安装
tar xzf nvtop.tar.gz && cd nvtop-3.3.2
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
sudo make install           # 装到 /usr/local/bin/nvtop

# 4. 验证
nvtop --version             # 应显示 3.3.2

# 5. 清理
cd / && rm -rf /tmp/nvtop* /tmp/nvtop.tar.gz
```

### 使用

```bash
nvtop                       # 进入实时监控（全屏 TUI）
```

**界面操作**：
| 按键 | 作用 |
|------|------|
| `q` 或 `Ctrl+C` | 退出 |
| `↑` `↓` | 选择进程 |
| `+`/`-` | 调整刷新间隔 |
| `F2` | 设置（可选显示哪些卡、哪些列）|
| `F6` | 切换排序字段 |
| `F9` | kill 选中的进程 |

**它会同时显示两张卡**：上面是独显 R9700，下面是核显，各自独立面板。

## 工具二：rocm-smi（快照查询）

ROCm 自带，适合脚本化、查一次状态。

### 常用命令

```bash
rocm-smi                              # 一览所有 GPU（温度/功耗/显存/利用率/风扇）
rocm-smi --showuse                    # 只看 GPU 利用率
rocm-smi --showmeminfo vram           # 只看显存使用
rocm-smi --showtemp                   # 只看温度
rocm-smi --showpower                 # 只看功耗
rocm-smi --showclocks                # 只看频率
rocm-smi --showproductname           # 看显卡型号信息
rocm-smi -d 0                        # 只看 0 号设备（独显）
rocm-smi --showall                   # 全部信息（很长）
```

### 持续刷新（类似 nvtop 但更原始）

```bash
watch -n 1 rocm-smi                   # 每秒刷新一次
watch -n 1 'rocm-smi --showuse'       # 每秒刷新利用率
```

### 字段含义（rocm-smi 表头）

```
Device  Node  IDs         Temp    Power   SCLK    MCLK    Fan    Perf  PwrCap  VRAM%  GPU%
                          (Edge)  (Avg)   (GPU频) (显存频)
```

| 字段 | 含义 | 健康范围 |
|------|------|---------|
| Temp (Edge) | 边缘温度 | < 85°C 正常，> 95°C 报警 |
| Power (Avg) | 平均功耗 | 看负载，独显满载可达 300W |
| SCLK | GPU 核心频率 | 待机几百 MHz，满载加速 |
| MCLK | 显存频率 | - |
| Fan | 风扇转速 % | 独显才有，核显为 0 |
| Perf | 性能等级 | auto 表示自动调节 |
| PwrCap | 功耗上限 | 独显 300W |
| VRAM% | 显存占用率 | - |
| GPU% | GPU 计算利用率 | - |

## 典型场景

### 场景 1：跑 AI 推理/训练时看独显占用

```bash
# 开两个终端窗口
nvtop                          # 窗口1：实时看
# 跑你的 AI 任务...           # 窗口2
```
重点关注独显 GPU[0]的 GPU% 和 VRAM%。如果 VRAM% 接近 100% 会 OOM。

### 场景 2：排查"显卡是不是在工作"

```bash
rocm-smi --showuse
# GPU[0] use > 0% 说明独显在干活
# 如果一直 0%，可能任务跑在核显或 CPU 上
```

### 场景 3：温度告警监控（脚本化）

```bash
# 简单温度监控（超过 90°C 报警）
while true; do
  temp=$(rocm-smi --showtemp -d 0 | grep -oP 'Temperature:\s+\K[0-9.]+')
  echo "$(date +%T) 独显温度: ${temp}°C"
  (( $(echo "$temp > 90" | bc -l) )) && notify-send "⚠️ GPU 过热: ${temp}°C"
  sleep 5
done
```

### 场景 4：找到占 GPU 的进程

```bash
nvtop                           # 直接看进程列表
# 或
rocm-smi --showprocesses        # rocm-smi 也能看进程
```

## 工具对比

| 特性 | nvtop | rocm-smi | radeontop |
|------|-------|----------|-----------|
| 类型 | 实时 TUI | 快照命令 | 实时 TUI |
| 进程级占用 | ✅ | ✅ | ❌ |
| 多卡同屏 | ✅ | ✅ | 需指定 |
| 适合脚本 | ❌（TUI） | ✅ | ❌ |
| 安装 | apt | 随 ROCm | apt |
| **推荐场景** | **日常实时监控** | **脚本/查一次** | 备选 |

## 已知坑：apt 版 nvtop 3.0.2 在本机崩溃 ⚠️

### 现象
跑 AI 任务时（有 python 进程占用 GPU 显存），`nvtop` 启动秒崩：
```
nvtop: ./src/extract_gpuinfo.c:222: gpuinfo_populate_process_info:
Assertion `device->processes[j].gpu_memory_percentage <= 100' failed.
已中止 (核心已转储)
```

### 根本原因
实测环境 **ROCm 7.8**（较新），而 Ubuntu 仓库的 **nvtop 3.0.2 是旧版**：
- ROCm 7.8 把 `rocm-smi --showprocesses` 改成了 `--showpids`，进程信息返回格式也变了
- nvtop 3.0.2 用旧接口解析，把显存占用百分比算成了 >100，触发断言崩溃
- **触发条件**：必须有进程在用 GPU（有进程占用显存时）；平时没进程用 GPU 不会崩

### 解决：源码编译 nvtop 3.3.2
见上方「安装」章节。3.3.2 已修复对 ROCm 7.x 的兼容。

### 教训
- ROCm 升级后，配套工具（nvtop/radeontop）可能需要重新评估兼容性
- Ubuntu 仓库的 GPU 工具版本常滞后，遇到崩溃优先考虑从源码编译最新版
- 判断"是否真崩溃"：看 exit code（134=断言崩溃，139=段错误，124=被 timeout 正常杀）

## 常见问题

### Q1：nvtop 只显示一张卡 / 没显示 AMD

确认 amdgpu 驱动加载了：
```bash
lsmod | grep amdgpu        # 应有输出
```
如果核显/独显一张没显示，可能是显卡被 `vfio-pci` 占用了（虚拟化直通场景）。

### Q2：rocm-smi 报错 "Unable to interact with AMD GPU"

权限问题。把用户加入 `video` 和 `render` 组：
```bash
sudo usermod -aG video,render $USER
# 然后注销重登
```

### Q3：独显 GPU% 一直是 0%，但程序确实在跑

可能程序用的是 CPU 模式，或没用 GPU 加速。检查：
- PyTorch：`torch.cuda.is_available()`（注意 ROCm 用 `torch.cuda` 接口，不是 `torch.hip`）
- TensorFlow：`tf.config.list_physical_devices('GPU')`

### Q4：想监控 NVIDIA 显卡（其他机器）

```bash
nvidia-smi                       # 快照（类似 rocm-smi）
nvidia-smi -l 1                  # 每秒刷新
nvtop                            # nvtop 也支持 NVIDIA
```

## 进阶：装 radeontop（备选轻量工具）

如果想要更原始的传感器读数（不依赖 ROCm）：
```bash
sudo apt install radeontop
radeontop                        # 实时 TUI，看 GPU 利用率/显存带宽/温度
radeontop -d 0                   # 指定设备
```
它在 ROCm 没装/没生效时也能工作（直接读 amdgpu sysfs）。

