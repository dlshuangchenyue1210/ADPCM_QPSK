function analyze_performance(tx_data_bits, rx_data_bits, tx_audio_bits, rx_audio_bits, tx_audio_wav, rx_audio_wav, params)
% ANALYZE_PERFORMANCE 综合性能分析（BER、SNR、时/频域对比）
% 输入参数更新说明：
% tx_data_bits / rx_data_bits：数字业务的发送和接收比特（用于计算数字 BER）
% tx_audio_bits / rx_audio_bits：音频业务的 ADPCM 比特（用于计算音频 BER）
% tx_audio_wav / rx_audio_wav：原始音频波形和解码后的音频波形（用于 SNR 和绘图）

fprintf('\n=== 性能详细分析报告 ===\n');

%% 1. 误码率分析 (BER)

% 1) 数字业务误码率
L_data = min(length(tx_data_bits), length(rx_data_bits));
if L_data == 0
    data_ber = 1.0; num_data_err = -1;
else
    [num_data_err, data_ber] = biterr(tx_data_bits(1:L_data), rx_data_bits(1:L_data));
end

% 2) 音频业务误码率
L_audio_bits = min(length(tx_audio_bits), length(rx_audio_bits));
if L_audio_bits == 0
    audio_ber = 1.0; num_audio_err = -1;
else
    [num_audio_err, audio_ber] = biterr(tx_audio_bits(1:L_audio_bits), rx_audio_bits(1:L_audio_bits));
end

fprintf('1. [误码率]\n');
fprintf('   - 数字信号误码率: %.2e (%d/%d bits)\n', data_ber, num_data_err, L_data);
fprintf('   - 音频信号误码率: %.2e (%d/%d bits)\n', audio_ber, num_audio_err, L_audio_bits);

%% 2. 音频信号对齐与 SNR 计算

% 截断长尾
len_min_wav = min(length(tx_audio_wav), length(rx_audio_wav));
tx_audio_wav = tx_audio_wav(1:len_min_wav);
rx_audio_wav = rx_audio_wav(1:len_min_wav);

% 计算延迟 (Rx 通常滞后)
[c, lags] = xcorr(rx_audio_wav, tx_audio_wav);
[~, I] = max(abs(c));
delay = lags(I);

% 对齐信号
if delay >= 0
    start_idx = delay + 1;
    len = min(length(tx_audio_wav), length(rx_audio_wav) - delay);
    s_ref = tx_audio_wav(1 : len);
    s_rec = rx_audio_wav(start_idx : start_idx + len - 1);
else
    start_idx = -delay + 1;
    len = min(length(tx_audio_wav) - (-delay), length(rx_audio_wav));
    s_ref = tx_audio_wav(start_idx : start_idx + len - 1);
    s_rec = rx_audio_wav(1 : len);
end

% 幅度归一化 (最小二乘匹配)
denom = s_rec' * s_rec;
if denom < 1e-10, alpha = 1; else, alpha = (s_rec' * s_ref) / denom; end
s_rec_scaled = s_rec * alpha;

% 计算 SNR
noise = s_rec_scaled - s_ref;
signal_power = sum(s_ref.^2);
noise_power = sum(noise.^2);
if noise_power < 1e-10
    snr_audio = 100; 
else
    snr_audio = 10 * log10(signal_power / noise_power);
end

fprintf('2. [信号质量]\n');
fprintf('   - 音频信噪比 (SNR): %.2f dB\n', snr_audio);

%% 3. 语音质量客观评价 (SegSNR)

seg_snr_score = calc_segsnr(s_ref, s_rec_scaled, params.audio_fs);

fprintf('   - 分段信噪比 (SegSNR): %.2f dB\n', seg_snr_score);

quality_str = sprintf('分段 SNR=%.2fdB', seg_snr_score);
%% 4. 绘图分析
figure('Name', '系统性能综合分析', 'Position', [150, 150, 1000, 800]);

% 子图1：时域波形对比（取中间段）
subplot(2,1,1);
mid_point = floor(length(s_ref) / 2);
win_len = 400; % 显示 400 个点 (约 50ms)
if length(s_ref) > win_len
    idx_range = mid_point : mid_point + win_len - 1;
else
    idx_range = 1 : length(s_ref);
end

t_axis = (0:length(idx_range)-1) / params.audio_fs * 1000; % ms
plot(t_axis, s_ref(idx_range), 'k', 'LineWidth', 1.5); hold on;
plot(t_axis, s_rec_scaled(idx_range), 'r--', 'LineWidth', 1.2);
legend('发送原音频', '接收恢复音频');
title(sprintf('时域波形对比 (中间 50ms) | 全局 SNR=%.2fdB | %s', snr_audio, quality_str));
xlabel('时间 (ms)'); ylabel('幅度');
grid on;

% 子图2：频域对比（0-4kHz）
subplot(2,1,2);
% 使用 Welch 法估计功率谱
nfft = 1024;
[pxx_ref, f] = pwelch(s_ref, [], [], nfft, params.audio_fs);
[pxx_rec, ~] = pwelch(s_rec_scaled, [], [], nfft, params.audio_fs);

plot(f/1000, 10*log10(pxx_ref), 'k', 'LineWidth', 1.5); hold on;
plot(f/1000, 10*log10(pxx_rec), 'r--', 'LineWidth', 1.2);
xlim([0, 4]); % 限制在 0-4kHz
legend('发送信号频谱', '接收信号频谱');
title('频域特性对比 (0-4 kHz)');
xlabel('频率 (kHz)'); ylabel('功率谱密度 (dB/Hz)');
grid on;

end