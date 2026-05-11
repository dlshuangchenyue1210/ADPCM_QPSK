function [audio_out, fs_orig] = read_audio_file(params, file_path)
% READ_AUDIO_FILE 读取音频文件（支持 GUI 选择或直接路径输入）
%   当 file_path 为空或未提供时，弹出文件选择对话框；
%   否则直接读取指定路径的文件。

if nargin < 2 || isempty(file_path)
    [filename, pathname] = uigetfile( ...
        {'*.wav;*.mp3;*.m4a;*.flac', '音频文件'; '*.*', '所有文件'}, ...
        '选择要读取的音频文件');

    if isequal(filename, 0)
        error('用户取消了文件选择，程序终止。');
    end
    file_path = fullfile(pathname, filename);
end

% 检查文件是否存在
if ~isfile(file_path)
    error('音频文件不存在: %s', file_path);
end

% 读取音频
try
    [y_raw, fs_orig] = audioread(file_path);
    [~, fname, ext] = fileparts(file_path);
    fprintf('成功读取文件: %s%s (采样率: %d Hz)\n', fname, ext, fs_orig);
catch ME
    error('无法读取文件 %s: %s', file_path, ME.message);
end

% 转单声道
if size(y_raw, 2) > 1
    y_raw = mean(y_raw, 2);
end

% 重采样到系统采样率
[P, Q] = rat(params.audio_fs / fs_orig);
y_resampled = resample(y_raw, P, Q);

% 幅度归一化
audio_out = y_resampled / max(abs(y_resampled));

% 截断或补零以匹配系统时长
req_len = round(params.duration * params.audio_fs);
if length(audio_out) > req_len
    audio_out = audio_out(1:req_len);
end
end
