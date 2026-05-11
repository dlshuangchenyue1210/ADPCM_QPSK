function audio_out = demod_nbfm(rx_signal, params)
% DEMOD_NBFM 窄带调频解调器
% 输入：rx_signal（射频信号），params
% 输出：audio_out（8k采样音频）

    % 1. Hilbert 变换提取瞬时相位 (即使在低信噪比下也比较鲁棒)
    hilb_rx = hilbert(rx_signal);
    inst_phase = unwrap(angle(hilb_rx));
    
    % 2. 微分相位得到瞬时频率
    % 瞬时频率公式：f(t) = (1/2π) * d(φ)/dt
    % diff 会导致长度减1，末尾补齐
    demod_raw = (diff(inst_phase) * params.sim_fs / (2*pi)) - params.fc;
    demod_raw = [demod_raw; demod_raw(end)]; 
    
    % 3. 低通滤波 (关键步骤)
    % 去除高频噪声和载波残留，模拟接收机的中频/音频滤波器
    % 截止频率设为略高于语音带宽（如 4kHz）
    % 使用 Butterworth 滤波器，比 designfilt 更快，适合循环调用
    Wn = (params.max_audio_freq * 1.2) / (params.sim_fs/2); 
    [b, a] = butter(5, Wn); 
    demod_filtered = filter(b, a, demod_raw);
    
    % 4. 下采样回 8kHz
    audio_out = resample(demod_filtered, params.audio_fs, params.sim_fs);
    
    % 5. 后处理 (去直流 + 归一化)
    audio_out = audio_out - mean(audio_out);
    if max(abs(audio_out)) > 0
        audio_out = audio_out / max(abs(audio_out));
    end
end