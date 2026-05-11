function rx = framer_demux(rx_bits, params)
% FRAMER_DEMUX 解帧 + 信道解码（接收端）
%   返回结构体 rx，含 .audio_bits, .data_bits, .meta

total_len = params.bits_per_frame;
len_sync = params.len_sync;
len_data_raw = params.len_data_raw;
len_data_coded = params.len_data_coded;
len_flags_coded = params.len_flags_coded;
len_audio = params.len_audio;

n_frames = floor(length(rx_bits) / total_len);
out_audio = zeros(n_frames * len_audio, 1);
out_data = zeros(n_frames * len_data_raw, 1);
ptr_audio = 1;
ptr_data = 1;
valid_data_cnt = 0;
valid_audio_cnt = 0;

for i = 1:n_frames
    frame_start = (i-1)*total_len;

    % 提取 Flags（3次重复码 + 多数表决）
    idx_flags = frame_start + len_sync + 1 : frame_start + len_sync + len_flags_coded;
    flags_rx_coded = rx_bits(idx_flags);
    is_data_valid = sum(flags_rx_coded(1:3)) >= 2;
    is_audio_valid = sum(flags_rx_coded(4:6)) >= 2;

    % 提取 Data + 汉明码解码
    idx_d = idx_flags(end) + 1 : idx_flags(end) + len_data_coded;
    if is_data_valid
        data_rx_coded = rx_bits(idx_d);
        data_decoded = decode(data_rx_coded, 7, 4, 'hamming/binary');
        out_data(ptr_data : ptr_data + len_data_raw - 1) = data_decoded;
        ptr_data = ptr_data + len_data_raw;
        valid_data_cnt = valid_data_cnt + 1;
    end

    % 提取 Audio
    idx_a = idx_d(end) + 1 : idx_d(end) + len_audio;
    if is_audio_valid
        out_audio(ptr_audio : ptr_audio + len_audio - 1) = rx_bits(idx_a);
        ptr_audio = ptr_audio + len_audio;
        valid_audio_cnt = valid_audio_cnt + 1;
    end
end

% 截断预分配空间
rx.audio_bits = out_audio(1 : ptr_audio - 1);
rx.data_bits = out_data(1 : ptr_data - 1);
rx.meta.valid_audio_frames = valid_audio_cnt;
rx.meta.valid_data_frames = valid_data_cnt;

log_msg(3, sprintf('解帧统计: 总帧数 %d | 有效音频帧: %d | 有效数据帧: %d', ...
    n_frames, valid_audio_cnt, valid_data_cnt), params);
end
