clc; clear; close all;

%% 1. 仿真参数设置
params.fs = 200000;      % 采样率
params.fc = 50000;       % 载波频率
params.sps = 4;          % 每符号采样数
params.rolloff = 0.5;    % 滚降系数

% 测试规模
target_total_bits = 1e8; % 目标总比特数 (1亿)
batch_size = 1e6;        % 单次处理数据块大小 (100万) - 内存安全值
num_batches = ceil(target_total_bits / batch_size); % 需要循环的次数

snr_range = -4:2:14;     % 信噪比范围 (dB)
ber_results = zeros(size(snr_range));

%% 2. 并行计算准备
% 检查并行池
p = gcp('nocreate');
if isempty(p)
    try
        parpool;
        fprintf('并行池已启动。\n');
    catch
        fprintf('无法启动并行池，将使用单核运行。\n');
    end
else
    fprintf('正在使用现有的并行计算池 (%d Workers)。\n', p.NumWorkers);
end

fprintf('------------------------------------------------\n');
fprintf('开始仿真: 目标比特数 %.0e | 分块大小 %.0e | 循环次数 %d\n', ...
    target_total_bits, batch_size, num_batches);
fprintf('------------------------------------------------\n');

tic; % 开始计时

%% 3. 主仿真循环 (SNR 并行 + 数据分块)
% 使用 parfor 并行遍历 SNR 点
parfor i_snr = 1:length(snr_range)
    current_snr = snr_range(i_snr);

    % 每个 SNR 点内部的累加器
    total_errors_snr = 0;
    total_bits_snr = 0;

    % --- 分块循环 (串行处理以节省内存) ---
    for i_batch = 1:num_batches

        % A. 生成随机比特 (小块)
        tx_bits = randi([0 1], batch_size, 1);
        if mod(length(tx_bits), 2) ~= 0
            tx_bits = [tx_bits; 0];
        end

        % B. 调制
        tx_wave = mod_digital(tx_bits, params);

        % C. 信道（AWGN）
        rx_signal = awgn(tx_wave, current_snr, 'measured');

        % D. 解调
        rx_bits = demod_digital(rx_signal, params);

        % E. 误码统计
        len_tx = length(tx_bits);
        len_rx = length(rx_bits);
        L = min(len_tx, len_rx);

        tx_cmp = tx_bits(1:L);
        rx_cmp = rx_bits(1:L);

        % 累加当前块的错误数
        num_errors = sum(tx_cmp ~= rx_cmp);

        total_errors_snr = total_errors_snr + num_errors;
        total_bits_snr = total_bits_snr + L;
    end

    % 计算该 SNR 下的平均 BER
    ber_results(i_snr) = total_errors_snr / total_bits_snr;

    % 简单的进度提示
    fprintf('SNR %2d dB 完成。总误码: %d / %d\n', ...
        current_snr, total_errors_snr, total_bits_snr);
end

elapsed_time = toc;
fprintf('------------------------------------------------\n');
fprintf('仿真全部完成！耗时: %.2f 秒\n', elapsed_time);

%% 4. 结果展示与绘图
figure('Color', 'w');

% 仿真曲线
semilogy(snr_range, ber_results, 'b-o', 'LineWidth', 2, 'DisplayName', 'Simulation (1e8 bits)');
hold on;

% 理论曲线（QPSK），理论值计算假设 Eb/N0 = SNR
theory_ber = 0.5 * erfc(sqrt(10.^(snr_range/10)));
semilogy(snr_range, theory_ber, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Theory (AWGN)');

grid on;
xlabel('SNR (dB)');
ylabel('Bit Error Rate (BER)');
title('QPSK BER Performance (Total Bits: 1e8)');
legend('Location', 'southwest');
ylim([1e-7 1]); % 调整纵坐标范围以显示低误码率

% 输出表格
disp('--- 最终结果 ---');
T = table(snr_range', ber_results', 'VariableNames', {'SNR_dB', 'BER'});
disp(T);