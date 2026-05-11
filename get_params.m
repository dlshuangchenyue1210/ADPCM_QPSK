function params = get_params()

% === 系统基础配置 ===
params.fs = 200000;             % 仿真系统采样率 200kHz
params.duration = 5;            % 仿真时长 (秒)
params.verbose = 3;             % 日志级别: 0=静默 1=错误 2=警告 3=信息 4=调试
params.audio_file = '';         % 音频文件路径，空则弹窗选择
params.save_path = '';          % 输出文件路径，空则弹窗选择

% === 载波参数 (单载波方案) ===
params.fc = 45000;              % 载波频率 45kHz
params.bw_limit = 25000;        % 绝对带宽限制 25kHz

% === 音频源编码参数 ===
params.audio_fs = 8000;         % 音频采样率 8kHz
params.audio_bits_per_sample = 4; % 4-bit ADPCM
params.adpcm_leak = 0.98;       % 泄露因子

% === 数字业务参数 ===
params.data_bps = 2000;         % 数字业务速率 2kbps

% === 物理层帧结构（所有长度由基本参数自动计算） ===
params.frame_duration = 0.02;   % 帧时长 (秒)

% 同步字 (14-bit巴克码变体)
params.sync_word = [1 1 1 1 1 0 0 1 1 0 1 0 1 0];
params.len_sync = length(params.sync_word);

% 控制位: 2个标志位 × 3次重复编码
params.len_flags_raw = 2;
params.len_flags_coded = params.len_flags_raw * 3;

% 音频字段（不编码）
params.len_audio = params.audio_fs * params.frame_duration * params.audio_bits_per_sample;

% 数字数据字段（原始，汉明码编码前）
params.len_data_raw = params.data_bps * params.frame_duration;

% 汉明码(7,4)编码后长度
params.len_data_coded = params.len_data_raw * 7 / 4;

% 总帧长
params.bits_per_frame = params.len_sync + params.len_flags_coded + ...
                        params.len_data_coded + params.len_audio;

% QPSK 调制参数
params.sps = 8;
params.rolloff = 0.35;
params.symbol_rate = params.bits_per_frame / params.frame_duration / 2;

% === 信道 ===
params.snr_db = 10;

% === 参数校验 ===
validate_params(params);

% === 打印配置摘要 ===
if params.verbose >= 3
    fprintf('\n========== 系统参数配置 ==========\n');
    fprintf(' 帧时长: %.0f ms | 帧长: %d bits | 符号率: %.0f Baud\n', ...
        params.frame_duration*1000, params.bits_per_frame, params.symbol_rate);
    fprintf(' 音频: %d bits/帧 (%d Hz × %.0f ms × %d bit)\n', ...
        params.len_audio, params.audio_fs, params.frame_duration*1000, params.audio_bits_per_sample);
    fprintf(' 数据: %d → %d bits (汉明7,4编码)\n', ...
        params.len_data_raw, params.len_data_coded);
    fprintf(' 同步字: %d bits | 控制位: %d bits\n', ...
        params.len_sync, params.len_flags_coded);
    fprintf('===================================\n\n');
end
end


function validate_params(params)
% VALIDATE_PARAMS 检查所有参数约束，发现问题立即报错

% 1. 采样率×帧时长必须为整数（保证整数个音频样本）
if mod(params.audio_fs * params.frame_duration, 1) ~= 0
    error('音频采样率(%d)×帧时长(%.3f)必须为整数。', ...
        params.audio_fs, params.frame_duration);
end

% 2. 符号率×2×帧时长必须为整数（保证每帧整数个比特）
if mod(params.symbol_rate * 2 * params.frame_duration, 1) ~= 0
    error('符号率×2×帧时长必须为整数。');
end

% 3. 数据信息位长度必须是4的倍数（汉明码(7,4)要求）
assert(mod(params.len_data_raw, 4) == 0, ...
    '数据信息位长度(%d)必须是4的倍数（汉明码(7,4)要求）。', params.len_data_raw);

% 4. 音频比特数应为4的倍数（便于ADPCM码流对齐）
assert(mod(params.len_audio, 4) == 0, ...
    '音频比特数(%d)应为4的倍数，便于ADPCM码流对齐。', params.len_audio);

% 5. 编码后长度一致性
assert(params.len_data_coded == params.len_data_raw * 7/4, ...
    '数据编码后长度与(7,4)汉明码不符。');

% 6. 总帧长一致性
assert(params.bits_per_frame == params.len_sync + params.len_flags_coded + ...
    params.len_data_coded + params.len_audio, ...
    '总帧长与各字段之和不匹配。');

% 7. 带宽约束
nyquist_bw = (1 + params.rolloff) * params.symbol_rate;
if nyquist_bw > params.bw_limit
    error('调制信号带宽(%.1f Hz)超出信道带宽限制(%.1f Hz)。', ...
        nyquist_bw, params.bw_limit);
end

% 8. 帧时长合理范围
assert(params.frame_duration > 0 && params.frame_duration <= 0.1, ...
    '帧时长建议在 5~100 ms 之间，当前值为 %.3f s。', params.frame_duration);

% 9. 同步字长度应适中
assert(params.len_sync >= 8 && params.len_sync <= 32, ...
    '同步字长度(%d)建议在 8~32 之间。', params.len_sync);

% 10. SNR 合理范围
assert(params.snr_db >= -10 && params.snr_db <= 60, ...
    'SNR(%.1f dB)应在 -10~60 dB 范围内。', params.snr_db);
end
