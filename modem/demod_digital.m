function coded_bits = demod_digital(rx_signal, params)
log_msg(3, '--- 开始 QPSK 解调 ---', params);

% 1. 下变频
t = (0:length(rx_signal)-1)' / params.fs;
baseband = rx_signal .* exp(-1j * 2 * pi * params.fc * t);

% 2. 匹配滤波（仅滤波，不改变采样率）
span = 8;
rrcFilter = rcosdesign(params.rolloff, span, params.sps);
rx_syms_upsampled = upfirdn(baseband, rrcFilter, 1, 1);

% 3. 定时同步（早迟门，低带宽确保稳定锁相）
symSync = comm.SymbolSynchronizer(...
    'SamplesPerSymbol', params.sps, ...
    'DampingFactor', 0.707, ...
    'NormalizedLoopBandwidth', 0.001, ...
    'TimingErrorDetector', 'Early-Late (non-data-aided)', ...
    'Modulation', 'PAM/PSK/QAM');

[rx_syms, ~] = symSync(rx_syms_upsampled(:));

% 4. 硬判决解调
if isempty(rx_syms)
    warning('解调失败：无有效采样点，可能信号太短或符号率不匹配。');
    coded_bits = [];
    return;
end

decoded_idx = pskdemod(rx_syms, 4, pi/4);

% 5. 转比特
coded_bits_mat = de2bi(decoded_idx, 2, 'left-msb');
coded_bits = coded_bits_mat.';
coded_bits = coded_bits(:);

log_msg(3, '--- 解调完成 ---', params);
end
