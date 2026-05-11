function [bit_stream, meta] = framer_mux(audio_bits_in, data_bits_in, params)
% FRAMER_MUX 组帧 + 信道编码（发送端）
%   将音频比特与数字业务比特按帧结构组装，数据部分经(7,4)汉明码编码

total_len = params.bits_per_frame;
len_sync = params.len_sync;
len_data_raw = params.len_data_raw;
len_audio = params.len_audio;
sync = params.sync_word(:);

if isempty(audio_bits_in)
    bits_per_sec = total_len / params.frame_duration;
    n_frames = ceil(params.duration * bits_per_sec / total_len);
else
    n_frames = ceil(length(audio_bits_in) / len_audio);
end

bit_stream = zeros(n_frames * total_len, 1);

for i = 1:n_frames
    % 数据提取与补齐
    idx_d_start = (i-1)*len_data_raw + 1;
    idx_d_end = min(i*len_data_raw, length(data_bits_in));

    if idx_d_start <= length(data_bits_in)
        chunk = data_bits_in(idx_d_start : idx_d_end);
        pad = zeros(len_data_raw - length(chunk), 1);
        data_chunk_raw = [chunk; pad];
        flag_data = 1;
    else
        data_chunk_raw = zeros(len_data_raw, 1);
        flag_data = 0;
    end

    % (7,4)汉明码编码
    data_encoded = encode(data_chunk_raw, 7, 4, 'hamming/binary');

    % 音频提取（不编码）
    idx_a_start = (i-1)*len_audio + 1;
    idx_a_end = min(i*len_audio, length(audio_bits_in));

    if idx_a_start <= length(audio_bits_in)
        chunk = audio_bits_in(idx_a_start : idx_a_end);
        pad = zeros(len_audio - length(chunk), 1);
        audio_chunk = [chunk; pad];
        flag_audio = 1;
    else
        audio_chunk = zeros(len_audio, 1);
        flag_audio = 0;
    end

    % 控制位编码（重复三次）
    flags_encoded = [repmat(flag_data, 3, 1); repmat(flag_audio, 3, 1)];

    % 组装帧
    frame = [sync; flags_encoded; data_encoded; audio_chunk];
    bit_stream((i-1)*total_len + 1 : i*total_len) = frame;
end
meta.n_frames = n_frames;
end
