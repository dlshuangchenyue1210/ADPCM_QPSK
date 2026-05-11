%% 帧同步原理演示：滑动相关法在噪声中寻找巴克码

%% 1. 准备数据
params = get_params(); % 加载参数

% 获取同步字
sync_word = params.sync_word'; % 转为列向量
L_sync = length(sync_word);

% 构造符合真实结构的单帧载荷
% 1. Flags (6 bits)
flags_bits = randi([0 1], params.len_flags_coded, 1);
% 2. Data (70 bits)
data_bits = randi([0 1], params.len_data_coded, 1);
% 3. Audio (640 bits)
audio_bits = randi([0 1], params.len_audio, 1);

% 组合成完整的载荷 = Flags + Data + Audio (共 716 bits)
real_payload = [flags_bits; data_bits; audio_bits];
L_payload = length(real_payload);

% 模拟接收流
rng(10); % 固定随机种子
noise_pre = randi([0 1], 100, 1);    % 前导随机噪声
noise_mid = randi([0 1], 50, 1);     % 帧间随机噪声

% 构造总信号: [噪声] + [帧1] + [噪声] + [帧2部分]
% 帧结构 = 同步字(14) + 载荷(716)
rx_bits = [noise_pre; ...
           sync_word; real_payload; ...
           noise_mid; ...
           sync_word; real_payload(1:100)]; % 模拟第二帧只收到一部分

%% 2. 核心算法：滑动相关
% 转换为双极性 (0→-1, 1→+1)
rx_bipolar = 2*rx_bits - 1;
sync_bipolar = 2*sync_word - 1;

L_total = length(rx_bits);
correlation_out = zeros(L_total - L_sync + 1, 1);

% 滑动计算点积相似度
for i = 1 : length(correlation_out)
    chunk = rx_bipolar(i : i + L_sync - 1);
    correlation_out(i) = sum(chunk .* sync_bipolar);
end

%% 3. 可视化
figure('Color', 'w', 'Position', [100, 100, 1000, 600]);

% 子图1: 接收到的原始比特流
subplot(2, 1, 1);
stairs(rx_bits, 'k', 'LineWidth', 1);
title('接收到的原始比特流');
ylabel('逻辑值');
ylim([-0.2 1.2]);
xlim([1 length(rx_bits)]);
grid on;

% 标注真实的同步字位置（绿色半透明区域）
hold on;
start_indices = [length(noise_pre)+1, ...
    length(noise_pre)+L_sync+L_payload+length(noise_mid)+1];
for idx = start_indices
    x_patch = [idx, idx+L_sync, idx+L_sync, idx];
    y_patch = [-0.2, -0.2, 1.2, 1.2];
    patch(x_patch, y_patch, 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
end
legend('比特流', '真实帧头位置');

% 子图2: 滑动相关结果
subplot(2, 1, 2);
plot(correlation_out, 'b', 'LineWidth', 1.5);
hold on;
title('滑动相关输出');
xlabel('滑动窗口索引');
ylabel('相关值');
grid on;
xlim([1 length(rx_bits)]);

% 判决门限（允许 2 位错码）
threshold = L_sync - 2;
yline(threshold, 'r--', 'Label', '判决门限', 'LabelHorizontalAlignment', 'left');

% 标记检测到的峰值
[pks, locs] = findpeaks(correlation_out, 'MinPeakHeight', threshold);
plot(locs, pks, 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
for k = 1:length(locs)
    text(locs(k), pks(k)+1, sprintf('峰值:%d 位置:%d', pks(k), locs(k)), ...
        'HorizontalAlignment', 'center', 'Color', 'b', 'FontWeight', 'bold');
end
legend('相关曲线', '检测到的帧头');

sgtitle('帧同步原理演示：在随机噪声中识别特定的 14 位同步字');
