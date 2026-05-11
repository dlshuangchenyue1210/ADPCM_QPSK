function [out_signal, state] = adpcm_codec(in_signal, mode, params, state)
% ADPCM_CODEC 简易 IMA-ADPCM 编解码器（带泄露因子）

% 1. 核心量化表
step_table = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, ...
    41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, ...
    190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, ...
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, ...
    2272, 2499, 2749, 3024, 3326, 3658, 4024, 4426, 4869, 5355, 5892, 6482, ...
    7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, ...
    18500, 20350, 22385, 24623, 27086, 29794, 32767];
index_table = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];

% 2. 处理泄露因子 (容错：如果未定义则为 1.0)
if isfield(params, 'adpcm_leak')
    leak = params.adpcm_leak;
else
    leak = 1.0; 
end

% 3. 初始化状态 (注意 nargin 变为 4)
if nargin < 4
    state.valprev = 0;
    state.index = 1;
end

valprev = state.valprev;
index = state.index;

if strcmp(mode, 'enc')
    % === 编码 ===
    len = length(in_signal);
    out_signal = zeros(len, 1);
    pcm_in = round(in_signal * 32767);

    for i = 1:len
        step = step_table(index);
        diff = pcm_in(i) - valprev; % 计算差值 (注意这里不需要 leak)

        % 量化
        if diff < 0, code = 8; diff = -diff; else, code = 0; end
        if diff >= step, code = code + 4; diff = diff - step; end
        if diff >= step/2, code = code + 2; diff = diff - step/2; end
        if diff >= step/4, code = code + 1; end
        out_signal(i) = code;

        % 更新预测值 (应用泄露因子)
        step_diff = floor(step/8);
        if bitand(code, 4), step_diff = step_diff + step; end
        if bitand(code, 2), step_diff = step_diff + floor(step/2); end
        if bitand(code, 1), step_diff = step_diff + floor(step/4); end
        

        if bitand(code, 8)
            valprev = floor(valprev * leak) - step_diff; 
        else
            valprev = floor(valprev * leak) + step_diff; 
        end

        % 钳位
        if valprev > 32767, valprev = 32767; elseif valprev < -32768, valprev = -32768; end

        index = index + index_table(bitand(code, 7) + 1);
        if index < 1, index = 1; elseif index > 89, index = 89; end
    end

else
    % === 解码 ===
    codes = in_signal;
    len = length(codes);
    out_pcm = zeros(len, 1);

    for i = 1:len
        code = codes(i);
        step = step_table(index);

        step_diff = floor(step/8);
        if bitand(code, 4), step_diff = step_diff + step; end
        if bitand(code, 2), step_diff = step_diff + floor(step/2); end
        if bitand(code, 1), step_diff = step_diff + floor(step/4); end
        

        if bitand(code, 8)
            valprev = floor(valprev * leak) - step_diff; 
        else
            valprev = floor(valprev * leak) + step_diff; 
        end

        if valprev > 32767, valprev = 32767; elseif valprev < -32768, valprev = -32768; end

        index = index + index_table(bitand(code, 7) + 1);
        if index < 1, index = 1; elseif index > 89, index = 89; end

        out_pcm(i) = valprev;
    end
    out_signal = out_pcm / 32768;
end

state.valprev = valprev;
state.index = index;
end