clc; clear; close all;

%% 1. 仿真参数设置
params.fs = 200000;      % 采样率
params.fc = 50000;       % 载波频率
params.sps = 4;          % 每符号采样数
params.rolloff = 0.5;    % 滚降系数

% --- 汉明码参数 ---
params.n = 7;            % 码字长度
params.k = 4;            % 信息位长度
% 汉明码 (7,4)

% --- 测试规模 ---
target_info_bits = 1e8;  
                         
% 分块大小必须是 k=4 的倍数，以便整块编码
batch_info_size = 1e6; 
if mod(batch_info_size, params.k) ~= 0
    error('分块大小必须是 k=%d 的倍数', params.k);
end

num_batches = ceil(target_info_bits / batch_info_size);
snr_range = -4:2:12;     % 信噪比范围 (dB)

% 结果存储
ber_pre_fec = zeros(size(snr_range));  % 编码前 (Raw BER)
ber_post_fec = zeros(size(snr_range)); % 解码后 (Coded BER)

%% 2. 并行计算准备
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
fprintf('开始仿真 (7,4)汉明码: 目标信息位 %.0e | 循环 %d 次\n', ...
    target_info_bits, num_batches);
fprintf('------------------------------------------------\n');
tic;

%% 3. 主仿真循环
parfor i_snr = 1:length(snr_range)
    current_snr = snr_range(i_snr);
    
    % 累加器
    err_pre = 0;  tot_pre = 0;   % 信道误码（编码后比特）
    err_post = 0; tot_post = 0;  % 信息误码（解码后信息比特）
    
    for i_batch = 1:num_batches
        
        % A. 生成信息比特
        tx_info = randi([0 1], batch_info_size, 1);
        
        % B. 汉明编码
        % (7,4) 编码: 输入必须是 k=4 的倍数
        tx_encoded = encode(tx_info, params.n, params.k, 'hamming/binary');
        
        % 3. 调制（QPSK）
        % 注意：mod_digital 会自动补零对齐偶数，这可能导致解调后多出比特
        tx_wave = mod_digital(tx_encoded, params);
        
        % D. 信道
        rx_signal = awgn(tx_wave, current_snr, 'measured');
        
        % 5. 解调
        rx_raw_bits = demod_digital(rx_signal, params);
        
        % --- F. 对齐与截断 ---
        % 1. 长度对齐：解调输出可能因滤波延迟或补零而变化
        %    截取与 tx_encoded 长度一致的部分进行编码前比较
        %    并截取 n=7 的倍数进行解码
        
        len_tx_code = length(tx_encoded);
        len_rx_raw = length(rx_raw_bits);
        
        % 取最小长度
        L_common = min(len_tx_code, len_rx_raw);
        
        % 确保解码长度是 n=7 的倍数（否则 decode 报错）
        L_decodable = floor(L_common / params.n) * params.n;
        
        if L_decodable == 0
            continue; % 异常保护
        end
        
        % 截取用于解码和比较的部分
        rx_code_valid = rx_raw_bits(1:L_decodable);
        tx_code_valid = tx_encoded(1:L_decodable);
        
        % 7. 统计编码前误码率
        num_err_raw = sum(rx_code_valid ~= tx_code_valid);
        err_pre = err_pre + num_err_raw;
        tot_pre = tot_pre + L_decodable;
        
        % 8. 汉明解码
        rx_decoded_info = decode(rx_code_valid, params.n, params.k, 'hamming/binary');
        
        % 对应的原始信息位
        % 解码输出长度是 input * (k/n)
        len_info_valid = L_decodable / params.n * params.k;
        tx_info_valid = tx_info(1:len_info_valid);
        
        % 9. 统计解码后误码率
        num_err_info = sum(rx_decoded_info ~= tx_info_valid);
        err_post = err_post + num_err_info;
        tot_post = tot_post + len_info_valid;
        
    end
    
    % 计算平均 BER
    ber_pre_fec(i_snr) = err_pre / tot_pre;
    ber_post_fec(i_snr) = err_post / tot_post;
    
    fprintf('SNR %2d dB | Pre-BER: %.5f | Post-BER: %.5f\n', ...
        current_snr, ber_pre_fec(i_snr), ber_post_fec(i_snr));
end

elapsed_time = toc;
fprintf('仿真完成！耗时: %.2f 秒\n', elapsed_time);

%% 4. 绘图与分析
figure('Color', 'w');

% 1. 编码前
semilogy(snr_range, ber_pre_fec, 'b--o', 'LineWidth', 1.5, ...
    'DisplayName', '编码前');
hold on;

% 2. 解码后（Hamming 7,4）
semilogy(snr_range, ber_post_fec, 'r-s', 'LineWidth', 2, ...
    'DisplayName', '(7,4)汉明码编码后');

% 3. 理论无编码 QPSK 参考
% 注意：理论值基于 Eb/N0。由于有编码，这里横坐标是信道 SNR。
% 简单的参考对比：编码前 BER 应该贴合理论曲线
theory_uncoded = 0.5 * erfc(sqrt(10.^(snr_range/10))); 
semilogy(snr_range, theory_uncoded, 'k:', 'LineWidth', 1.5, ...
    'DisplayName', 'Theory (Uncoded QPSK)');

grid on;
xlabel('Channel SNR (dB)');
ylabel('Bit Error Rate (BER)');
title('BER Performance: QPSK + Hamming(7,4)');
legend('Location', 'southwest');
ylim([1e-6 1]);

disp('--- 最终结果 ---');
results = table(snr_range', ber_pre_fec', ber_post_fec', ...
    'VariableNames', {'SNR_dB', 'Pre_FEC_BER', 'Post_FEC_BER'});
disp(results);