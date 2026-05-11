# 单载波 ADPCM+QPSK 数字混合传输系统

基于 MATLAB 的语音与数据混合传输通信系统仿真。在一路 25kHz 带宽信道内同时传输一路压缩语音（ADPCM 4-bit @ 8kHz）和一路数字业务（2kbps），采用 QPSK 调制和时分复用（TDM）组帧。

## 系统架构

```
音频文件 ──→ [重采样 8kHz] ──→ [ADPCM编码] ──→ 音频比特流 ──┐
                                                              ├──→ [TDM组帧] ──→ [QPSK调制] ──→ [AWGN信道]
随机数生成 ──→ [Hamming(7,4)编码] ──→ 数据比特流 ──┘                    │
                                                                        ↓
音频输出 ←── [低通滤波] ←── [ADPCM解码] ←── 音频比特 ←── [TDM解帧] ←── [相位试探+帧同步] ←── [QPSK解调+定时同步]
数据输出 ←─────────────────────────── 数据比特 ←── [Hamming解码] ←────┘
```

### 帧结构（730 bits/帧，帧长 20ms）

| 字段 | 长度 | 保护方式 | 说明 |
|------|------|----------|------|
| 同步字 | 14 bits | — | 巴克码变体，用于帧同步 |
| 控制位 | 6 bits | 3倍重复码 | 标记数据/音频帧有效性 |
| 数字业务 | 70 bits | Hamming(7,4) | 40 信息位 → 70 编码位 |
| 音频业务 | 640 bits | 无纠错 | ADPCM 4-bit，8000×0.02×4 |

所有字段长度由基本参数（`frame_duration`, `audio_fs`, `data_bps`）自动公式计算，修改基础参数后其余长度自动更新，并有合法性校验。

## 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 系统采样率 | 200 kHz | 仿真采样率 |
| 载波频率 | 45 kHz | 单载波 QPSK |
| 音频采样率 | 8 kHz | 语音带宽 ~3.4 kHz |
| 音频编码 | ADPCM 4-bit | IMA-ADPCM，泄露因子 0.98 |
| 数字业务速率 | 2 kbps | Hamming(7,4) 保护 |
| 调制方式 | QPSK | RRC 脉冲成形，滚降系数 0.35，sps=8 |
| 符号率 | 18.25 kHz | 自动计算 = 帧长/帧时长/2 |
| 定时同步 | 早迟门 | comm.SymbolSynchronizer |

## 项目结构

```
ADPCM_QPSK/
├── main.m                        # 系统主程序入口
├── get_params.m                  # 参数集中配置 + 自动公式计算 + 合法性校验
├── README.md
│
├── utils/
│   └── log_msg.m                 # 统一日志控制（支持 verbose 级别）
│
├── source/                       # 信源与信源编码
│   ├── read_audio_file.m         # 音频读取（支持 GUI 选择 / 直接路径输入）
│   ├── adpcm_codec.m             # IMA-ADPCM 编解码器
│   └── gen_digital_source.m      # 随机数字业务生成
│
├── framing/                      # 组帧与信道编解码
│   ├── framer_mux.m              # 组帧 + 汉明码编码
│   └── framer_demux.m            # 解帧 + 汉明码解码（返回结构体）
│
├── modem/                        # 调制解调
│   ├── mod_digital.m             # QPSK 调制 + RRC 脉冲成形 + 上变频
│   ├── demod_digital.m           # QPSK 解调（下变频 + 匹配滤波 + 定时同步）
│   ├── mod_nbfm.m                # NBFM 调制器（对比实验用）
│   └── demod_nbfm.m              # NBFM 解调器（对比实验用）
│
├── channel/
│   └── sim_channel.m             # AWGN 信道仿真
│
├── sync/                         # 同步
│   ├── frame_sync.m              # 自适应门限帧同步（峰均比+滑动相关）
│   └── demo_frame_sync.m         # 帧同步原理演示
│
└── analysis/                     # 性能分析
    ├── analyze_performance.m     # 端到端分析（BER/SNR/SegSNR/时频域）
    ├── analyze_qpsk.m            # QPSK 独立 BER 仿真
    ├── analyze_hamming.m         # Hamming(7,4) 编码增益分析
    ├── analyze_spectrum.m        # 音频频谱能量分布分析
    ├── analyze_nbfm.m            # NBFM vs 数字传输对比
    └── calc_segsnr.m             # 分段信噪比计算
```

## 环境依赖

- **MATLAB R2025b**（推荐）
- 必需工具箱：Communications Toolbox、Signal Processing Toolbox

## 使用方法

### 1. 运行完整链路仿真

```matlab
main
```

程序将自动添加子文件夹到 MATLAB 路径，然后：
1. 弹出文件选择框选择音频文件（支持 .wav/.mp3/.flac/.m4a）
2. 执行完整的发送-信道-接收链路
3. 显示性能分析图表（时域波形对比、频谱对比）
4. 弹出保存对话框保存恢复的音频

### 2. 批量/自动化模式

编辑 `get_params.m` 或运行时覆盖参数：

```matlab
params = get_params();
params.audio_file = 'E:\Music\song.flac';  % 指定音频路径（跳过GUI）
params.save_path  = 'D:\output.wav';        % 指定输出路径（跳过GUI）
params.snr_db = 15;                         % 信道信噪比
params.duration = 5;                        % 仿真时长
```

### 3. 独立分析脚本

```matlab
analyze_qpsk       % QPSK 理论 BER 对比
analyze_hamming    % Hamming(7,4) 编码增益分析
analyze_nbfm       % NBFM 模拟传输 vs 数字传输对比
analyze_spectrum   % 音频频谱能量分析
demo_frame_sync    % 帧同步原理演示
```

## 实测性能（爱在西元前.flac，AWGN 信道）

| 信道 SNR | 数据 BER | 音频 BER | 音频 SNR | SegSNR | 帧同步 |
|----------|----------|----------|----------|--------|--------|
| 0 dB | 4.90e-03 | 2.32e-02 | — | — | 250/250 |
| 5 dB | 0 | 2.12e-04 | — | — | 250/250 |
| **10 dB** | **0** | **0** | **19.5 dB** | **19.4 dB** | **250/250** |
| 15 dB | 0 | 0 | — | — | 250/250 |

## 技术要点

- **参数公式化**：所有帧结构长度由基础参数自动推导，修改 `frame_duration`/`audio_fs`/`data_bps` 后其余长度自动更新，杜绝魔法数字
- **参数合法性校验**：`validate_params()` 检查 10 项约束（采样率整数性、带宽限制、帧结构一致性等）
- **定时同步**：早迟门（Early-Late Gate）符号同步器取代理想采样，使仿真更接近实际接收机行为
- **自适应帧同步**：峰均比（PAR）+ 自适应门限替代固定阈值，输出同步质量度量供上层判断
- **相位模糊处理**：QPSK 的 0°/90°/180°/270° 模糊通过 4 次试探旋转 + 帧同步验证解决
- **不等差错保护（UEP）**：数字业务 Hamming(7,4) 纠错编码，音频不编码，优先保证数据可靠性
- **Leaky ADPCM**：解码器预测值引入 0.98 泄露因子，防止信道误码下的误差累积
- **后置低通滤波**：3.4kHz 低通滤波去除量化噪声高频分量，改善主观听感
- **批量/自动化支持**：支持直接指定文件路径，无需 GUI 交互，可集成到自动化测试脚本

## 许可证

MIT License
