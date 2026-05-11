%% 主程序：单载波数字混合传输仿真 (Scheme 1: 相位自适应版)
% 自动添加项目子文件夹到 MATLAB 路径
script_path = which(mfilename);
if ~isempty(script_path)
    root_dir = fileparts(script_path);
    subdirs = {'utils', 'source', 'framing', 'modem', 'channel', 'sync', 'analysis'};
    for d = subdirs
        addpath(fullfile(root_dir, d{1}));
    end
end
clc; clear; close all;

% 1. 初始化
params = get_params();
log_msg(3, '=== 系统初始化 (8k ADPCM + QPSK 混合传输) ===', params);

% 2. 信源产生
log_msg(3, '1. 读取并预处理音频...', params);
[sig_audio_8k, fs_orig] = read_audio_file(params, params.audio_file);

log_msg(3, '   执行 ADPCM 编码 (4-bit)...', params);
adpcm_codes = adpcm_codec(sig_audio_8k, 'enc', params);
audio_bits = int2bit(adpcm_codes, 4);

log_msg(3, '2. 生成随机数字业务...', params);
num_data_bits = round(params.duration * params.data_bps);
data_bits_src = gen_digital_source(num_data_bits);

% 3. 组帧
log_msg(3, '3. 混合组帧 (TDM)...', params);
[tx_bitstream, frame_info] = framer_mux(audio_bits, data_bits_src, params);

% 4. 发射
log_msg(3, '4. QPSK 调制与发射...', params);
params.fc_digital = params.fc;
tx_signal = mod_digital(tx_bitstream, params);

% 5. 信道
log_msg(3, sprintf('5. 信道传输 (SNR = %d dB)...', params.snr_db), params);
rx_signal = sim_channel(tx_signal, params.snr_db);

% 6. 相位试探解调与帧同步
log_msg(3, '6. QPSK 相位试探与同步...', params);

found_sync = false;
best_rx_bits = [];
best_start_idx = -1;
best_sync_quality = 0;

for phase_shift_idx = 0:3
    phase_offset = phase_shift_idx * (pi/2);
    rx_rotated = rx_signal * exp(1j * phase_offset);

    temp_bits = demod_digital(rx_rotated, params);
    if isempty(temp_bits)
        continue;
    end

    [aligned_bits, start_idx, sync_quality] = frame_sync(temp_bits, params);

    if ~isempty(aligned_bits)
        fprintf('   >> 试探相位 %d°: 同步成功！(Index: %d, 峰均比: %.1f)\n', ...
            rad2deg(phase_offset), start_idx, sync_quality);
        best_rx_bits = aligned_bits;
        best_start_idx = start_idx;
        best_sync_quality = sync_quality;
        found_sync = true;
        break;
    end
end

if ~found_sync
    error('所有相位均未找到同步字。请增大SNR、检查载波频率偏差或信号长度。');
end

% 7. 解帧
log_msg(3, '7. 解帧分离业务...', params);
rx = framer_demux(best_rx_bits, params);
rx_audio_bits = rx.audio_bits;
rx_data_bits = rx.data_bits;

% 8. 恢复
log_msg(3, '8. 业务恢复...', params);
len_codes = floor(length(rx_audio_bits)/4);
rx_codes = bit2int(rx_audio_bits(1:len_codes*4), 4);
rx_audio_8k = adpcm_codec(rx_codes, 'dec', params);
rx_audio_final = lowpass(rx_audio_8k, 3400, params.audio_fs);

% 9. 性能分析
log_msg(3, '9. 性能分析...', params);
analyze_performance(data_bits_src, rx_data_bits, ...
    audio_bits, rx_audio_bits, ...
    sig_audio_8k, rx_audio_final, ...
    params);

%% 10. 保存接收到的音频
log_msg(3, '10. 保存结果...', params);

audio_to_save = rx_audio_final;
max_val = max(abs(audio_to_save));
if max_val > 0
    audio_to_save = audio_to_save / max_val * 0.95;
end

if ~isempty(params.save_path)
    % 批量模式：直接写入指定路径
    try
        audiowrite(params.save_path, audio_to_save, params.audio_fs);
        fprintf('成功保存音频至: %s\n', params.save_path);
    catch ME
        fprintf('保存失败: %s\n', ME.message);
    end
else
    % 交互模式：弹出保存对话框
    default_name = sprintf('Rx_Audio_8k_SNR%ddB.wav', params.snr_db);
    [filename, pathname] = uiputfile('*.wav', '保存接收音频', default_name);

    if isequal(filename, 0)
        disp('用户取消保存');
    else
        full_path = fullfile(pathname, filename);
        try
            audiowrite(full_path, audio_to_save, params.audio_fs);
            fprintf('成功保存音频至: %s\n', full_path);
            fprintf('采样率: %d Hz\n', params.audio_fs);
        catch ME
            fprintf('保存失败: %s\n', ME.message);
        end
    end
end
