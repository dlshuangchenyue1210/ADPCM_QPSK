function tx_wave = mod_digital(bits, params)

log_msg(3, sprintf('QPSK调制：输入比特数 %d', length(bits)), params);

% 1. 符号生成（QPSK: 2 bits/symbol）
if mod(length(bits), 2) ~= 0, bits = [bits; 0]; end

sym_idx = bi2de(reshape(bits, 2, []).', 'left-msb');
symbols = pskmod(sym_idx, 4, pi/4);
log_msg(3, sprintf('生成 QPSK 符号数: %d', length(symbols)), params);

% 2. 脉冲成形 (RRC)
span = 8;
rrcFilter = rcosdesign(params.rolloff, span, params.sps);
baseband = upfirdn(symbols, rrcFilter, params.sps);

% 3. 上变频
t = (0:length(baseband)-1)' / params.fs;
carrier = exp(1j * 2 * pi * params.fc * t);
tx_wave = real(baseband .* carrier);

% 功率归一化
tx_wave = tx_wave / std(tx_wave) * 0.5;

log_msg(3, sprintf('发射波形长度: %d 采样点', length(tx_wave)), params);
end
