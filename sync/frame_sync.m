function [aligned_bits, frame_start_idx, sync_quality] = frame_sync(rx_raw_bits, params)
log_msg(3, sprintf('[帧同步] 开始寻找帧头（输入长度：%d）...', length(rx_raw_bits)), params);

sync_word = params.sync_word(:);
L_sync = length(sync_word);
L_frame = params.bits_per_frame;

if length(rx_raw_bits) < L_frame * 2
    log_msg(2, '[帧同步] 数据过短，跳过', params);
    aligned_bits = []; frame_start_idx = -1; sync_quality = 0; return;
end

% 滑动相关
search_len = min(length(rx_raw_bits), 2 * L_frame);
correlations = zeros(search_len - L_sync + 1, 1);

rx_bipolar = 2*rx_raw_bits - 1;
sync_bipolar = 2*sync_word - 1;

for i = 1 : length(correlations)
    chunk = rx_bipolar(i : i + L_sync - 1);
    correlations(i) = sum(chunk .* sync_bipolar);
end

[max_val, peak_idx] = max(correlations);

% 峰均比计算（排除峰值邻近区域）
exclude_width = L_sync;
avg_mask = true(size(correlations));
avg_mask(max(1, peak_idx - exclude_width) : min(end, peak_idx + exclude_width)) = false;
noise_avg = mean(correlations(avg_mask));

if noise_avg > 0.01
    sync_quality = max_val / noise_avg;
else
    sync_quality = L_sync * 100;
end

log_msg(3, sprintf('[FrameSync] 最大相关峰值: %d (理论最大值: %d) | 峰均比: %.1f', ...
    max_val, L_sync, sync_quality), params);

% 自适应门限：峰均比 > 4 且 峰值 > 70% 理论最大值
if sync_quality > 4 && max_val > 0.7 * L_sync
    frame_start_idx = peak_idx;
    log_msg(3, sprintf('[FrameSync] 锁定帧头！Index: %d', frame_start_idx), params);

    aligned_bits = rx_raw_bits(frame_start_idx : end);
    num_full_frames = floor(length(aligned_bits) / L_frame);
    aligned_bits = aligned_bits(1 : num_full_frames * L_frame);
    log_msg(3, sprintf('[FrameSync] 截取有效帧数: %d', num_full_frames), params);
else
    log_msg(2, '[FrameSync] 警告: 未找到有效帧头！峰值过低。', params);
    aligned_bits = [];
    frame_start_idx = -1;
end
end
