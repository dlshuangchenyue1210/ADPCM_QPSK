function [tx_signal, params] = mod_nbfm(audio_sig, params)
% MOD_NBFM 窄带调频调制器
% 输入:
%   audio_sig: 原始音频（8k采样，单声道）
%   params: 参数结构体（需包含 channel_bw, max_audio_freq, sim_fs, fc 等）
% 输出:
%   tx_signal: 调制后的射频信号
%   params: 更新后的参数（包含计算出的 freq_dev）

    % 1. 参数校验与频偏计算
    % 卡森带宽公式：B = 2 * (delta_f + fm)
    % 反推：delta_f = B/2 - fm
    if ~isfield(params, 'freq_dev')
        params.freq_dev = (params.channel_bw / 2) - params.max_audio_freq;
    end
    
    % 2. 预处理
    % 归一化输入音频，确保频偏受控 (对应模拟电台的麦克风增益控制)
    if max(abs(audio_sig)) > 0
        audio_sig = audio_sig / max(abs(audio_sig));
    end
    
    % 3. 上采样 (从 8k 到 200k)
    % 必须有足够的采样率来承载载波
    x_sim = resample(audio_sig, params.sim_fs, params.audio_fs);
    
    % 4. 积分 (FM 本质是对相位的积分)
    % phase(t) = 2*pi*kf * integral(m(t))
    phase_integral = cumsum(x_sim) / params.sim_fs;
    
    % 5. 生成正交调制信号
    t = (0:length(x_sim)-1)' / params.sim_fs;
    tx_signal = cos(2*pi*params.fc*t + 2*pi*params.freq_dev*phase_integral);
end