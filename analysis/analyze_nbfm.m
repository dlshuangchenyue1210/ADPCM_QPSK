%% NBFM 系统深度性能评估 (多视角对比版)
clc; clear; close all;

%% 1. 系统参数定义
params.audio_fs = 8000;       % 语音采样率
params.max_audio_freq = 3400; % 语音带宽
params.channel_bw = 20000;    % 射频带宽限制（NBFM）
params.sim_fs = 200000;       % 仿真采样率
params.fc = 50000;            % 载波频率

%% 2. 选择并读取测试信号
fprintf('1. 选择测试音频文件...\n');
[filename, pathname] = uigetfile({'*.wav;*.mp3;*.flac;*.m4a;*.ogg', '音频文件'}, '选择音频文件');
if isequal(filename,0), error('未选择文件'); end
full_path = fullfile(pathname, filename);

[sig_orig, fs_orig] = audioread(full_path);
if size(sig_orig, 2) > 1, sig_orig = mean(sig_orig, 2); end % 转单声道
sig_src = resample(sig_orig, params.audio_fs, fs_orig);     % 重采样
sig_src = sig_src / max(abs(sig_src));                      % 归一化

% 时长限制
max_duration = 5; 
if length(sig_src)/params.audio_fs > max_duration
    sig_src = sig_src(1 : round(max_duration * params.audio_fs));
    fprintf('   文件已截取前 %d 秒...\n', max_duration);
end
params.duration = length(sig_src)/params.audio_fs;

% 调制（只做一次）
fprintf('2. 执行 NBFM 调制...\n');
[tx_signal_clean, params] = mod_nbfm(sig_src, params);

%% 3. 批量信道仿真
% 构造 SNR 列表：确保包含 5, 15, 25 以及绘图所需的范围
base_snr = -6:2:32; % 扩展到 32dB 以期达到更高的 SegSNR
target_snrs = [5, 15, 25]; 
snr_list = unique(sort([base_snr, target_snrs])); % 合并并去重

n_snr = length(snr_list);
segsnr_results = zeros(1, n_snr);

% 使用结构体数组存储需要绘图的波形数据
% 注意：parfor 中不能直接索引结构体数组字段，需用 cell 过渡
waveforms_cell = cell(1, n_snr);

fprintf('3. 开始并行仿真 (%d 个测试点)...\n', n_snr);
p = gcp('nocreate'); if isempty(p), parpool; end

tic;
parfor i = 1:n_snr
    curr_snr = snr_list(i);
    
    % (1) 信道 + 解调
    rx_signal = awgn(tx_signal_clean, curr_snr, 'measured');
    rx_audio_raw = demod_nbfm(rx_signal, params);
    
    % (2) 信号对齐
    [c, lags] = xcorr(rx_audio_raw, sig_src);
    [~, I] = max(abs(c));
    delay = lags(I);
    
    if delay >= 0
        start_idx = delay + 1;
        len_valid = min(length(sig_src), length(rx_audio_raw) - delay);
        ref_cut = sig_src(1 : len_valid);
        test_cut = rx_audio_raw(start_idx : start_idx + len_valid - 1);
    else
        start_idx = -delay + 1;
        len_valid = min(length(sig_src) - (-delay), length(rx_audio_raw));
        ref_cut = sig_src(start_idx : start_idx + len_valid - 1);
        test_cut = rx_audio_raw(1 : len_valid);
    end
    
    % (3) 幅度匹配
    scale_factor = (test_cut' * ref_cut) / (test_cut' * test_cut);
    test_cut = test_cut * scale_factor;
    
    % (4) 计算指标
    segsnr_results(i) = calc_segsnr(ref_cut, test_cut, params.audio_fs);
    
    % (5) 仅保存关键点的波形以节省内存 (5, 15, 25 dB)
    % 使用最小距离判断浮点数是否为目标信噪比
    if any(abs(curr_snr - target_snrs) < 0.01)
        % 封装成结构体存入元胞数组
        data_struct = struct();
        data_struct.ref = ref_cut;
        data_struct.rx = test_cut;
        data_struct.snr = curr_snr;
        data_struct.segsnr = segsnr_results(i);
        waveforms_cell{i} = data_struct;
    end
end
fprintf('仿真完成! 耗时: %.2f 秒\n', toc);

%% 4. 结果可视化 A：SegSNR 性能曲线
figure('Name', 'NBFM 性能曲线', 'Position', [100, 100, 800, 500]);
plot(snr_list, segsnr_results, 'b-o', 'LineWidth', 1.5, 'MarkerFaceColor', 'b', 'MarkerSize', 4);
hold on; grid on;

% === 标注 SegSNR = 0, 10, 20, 30 dB 的点 ===
target_levels = [0, 10, 20, 30];
colors = {'r', '#D95319', '#EDB120', 'g'}; % 红, 橙, 黄, 绿

for k = 1:length(target_levels)
    lvl = target_levels(k);
    yline(lvl, '--', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off'); % 辅助线
    
    % 寻找交叉点 (简单的线性插值查找)
    % 只有当曲线穿过该 level 时才标记
    if min(segsnr_results) < lvl && max(segsnr_results) > lvl
        % 找到第一个穿过该值的区间
        idx_cross = find(segsnr_results(1:end-1) <= lvl & segsnr_results(2:end) >= lvl, 1);
        if ~isempty(idx_cross)
            % 线性插值计算精确的 x (Channel SNR)
            y1 = segsnr_results(idx_cross); x1 = snr_list(idx_cross);
            y2 = segsnr_results(idx_cross+1); x2 = snr_list(idx_cross+1);
            x_target = x1 + (lvl - y1) * (x2 - x1) / (y2 - y1);
            
            % 绘图标注
            plot(x_target, lvl, 'p', 'MarkerSize', 12, 'MarkerFaceColor', colors{k}, 'MarkerEdgeColor', 'k');
            text(x_target + 0.5, lvl - 1.5, sprintf('SegSNR=%ddB\n(Ch:%.1fdB)', lvl, x_target), ...
                'FontSize', 9, 'Color', 'k', 'BackgroundColor', 'w', 'EdgeColor', 'none');
        end
    end
end
title('NBFM 系统性能: 分段信噪比 (SegSNR) vs 信道 SNR');
xlabel('信道 SNR (dB)'); ylabel('输出 SegSNR (dB)');
legend('性能曲线', '关键指标点 (0,10,20,30dB)', 'Location', 'best');


%% 5. 结果可视化 B：5/15/25 dB 时频域对比
figure('Name', '特定 SNR 时频分析', 'Position', [150, 50, 1200, 800]);

% 提取保存的数据
saved_indices = find(~cellfun(@isempty, waveforms_cell));
plot_data_list = [waveforms_cell{saved_indices}]; % 转换为结构体数组

% 确保按 SNR 排序 (5, 15, 25)
[~, sort_idx] = sort([plot_data_list.snr]);
plot_data_list = plot_data_list(sort_idx);

for i = 1:length(plot_data_list)
    D = plot_data_list(i);
    
    % --- 时域图 (左列) ---
    subplot(3, 2, (i-1)*2 + 1);
    
    % 取中间 30ms 观察波形细节
    center_idx = floor(length(D.ref)/2);
    win_len = round(0.03 * params.audio_fs); % 30ms
    idx_range = center_idx : min(center_idx + win_len, length(D.ref));
    t_axis = (0:length(idx_range)-1) / params.audio_fs * 1000; % ms
    
    plot(t_axis, D.ref(idx_range), 'k', 'LineWidth', 1.5); hold on;
    plot(t_axis, D.rx(idx_range), 'r--', 'LineWidth', 1.2);
    
    if i == 1, title('时域波形对比 (30ms 局部)'); end
    if i == 3, xlabel('时间 (ms)'); end
    ylabel(sprintf('SNR=%ddB\n幅度', D.snr), 'FontWeight', 'bold');
    legend('原始', '恢复', 'Location', 'northeast'); grid on;
    text(0, 0.8, sprintf('SegSNR: %.1f dB', D.segsnr), 'BackgroundColor', 'w');
    ylim([-1.1 1.1]);
    
    % --- 频域图 (右列) ---
    subplot(3, 2, (i-1)*2 + 2);
    
    % 使用 Welch 法计算功率谱密度
    [pxx_ref, f] = pwelch(D.ref, 512, 256, 512, params.audio_fs);
    [pxx_rx, ~]  = pwelch(D.rx,  512, 256, 512, params.audio_fs);
    
    plot(f/1000, 10*log10(pxx_ref), 'k', 'LineWidth', 1.5); hold on;
    plot(f/1000, 10*log10(pxx_rx),  'r', 'LineWidth', 1);
    
    if i == 1, title('频域特性对比 (PSD)'); end
    if i == 3, xlabel('频率 (kHz)'); end
    ylabel('功率谱 (dB/Hz)');
    xlim([0 4]); ylim([-100 -20]); grid on;
    
    % 标注底噪差异
    noise_floor_est = mean(10*log10(pxx_rx(f>3000 & f<3400))); % 高频段估算
    text(2.5, -30, sprintf('Est. Floor: %.0f dB', noise_floor_est), 'Color', 'r');
end

sgtitle('NBFM 系统在不同信道信噪比下的信号恢复质量对比');