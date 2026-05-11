function seg_snr = calc_segsnr(ref_sig, test_sig, fs)
% CALC_SEGSNR 计算分段信噪比
% 输入:
%   ref_sig: 参考信号（纯净）
%   test_sig: 测试信号（有噪）
%   fs: 采样率
% 输出:
%   seg_snr: 分段信噪比（dB）

% 1. 基础设置
frame_len_ms = 20; % 每帧 20ms
frame_len = floor(frame_len_ms * fs / 1000);

% 确保长度一致
L = min(length(ref_sig), length(test_sig));
ref_sig = ref_sig(1:L);
test_sig = test_sig(1:L);

% 2. 分帧处理
n_frames = floor(L / frame_len);
snr_sum = 0;
valid_frames = 0;

for i = 1:n_frames
    idx = (i-1)*frame_len + 1 : i*frame_len;

    s_frame = ref_sig(idx); % 信号帧
    n_frame = test_sig(idx) - ref_sig(idx); % 噪声帧 (误差)

    power_s = sum(s_frame.^2);
    power_n = sum(n_frame.^2);

    % 3. 阈值处理（关键步骤）
    % 如果原本就是静音帧(能量极小)，计算SNR没有意义，跳过
    if power_s > 1e-5
        % 计算当前帧 SNR
        % 防止 power_n 为零
        if power_n < 1e-10
            cur_snr = 100; % 完美帧
        else
            cur_snr = 10 * log10(power_s / power_n);
        end

        % 4. 钳位
        % 人耳对极好和极差的信噪比不敏感，限制范围 [-10dB, 35dB]
        % 这能显著提高与主观听感的相关性
        cur_snr = max(min(cur_snr, 35), -10);

        snr_sum = snr_sum + cur_snr;
        valid_frames = valid_frames + 1;
    end
end

if valid_frames > 0
    seg_snr = snr_sum / valid_frames;
else
    seg_snr = 0;
end
end