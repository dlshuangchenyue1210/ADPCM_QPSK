function analyze_spectrum()
% 音频信号频谱能量累积分析工具
% 功能：
% 1. 调用文件选择框选取音频文件（支持.wav/.mp3/.flac/.m4a/.ogg等）
% 2. 分析音频频谱能量累积分布，绘制0~100%折线图
% 3. 标注10%/50%/80%/90%/95%/99%累积能量对应的频率竖线
% 4. 输出关键频率信息，鲁棒处理各类异常情况

%% 1. 初始化与文件选择
clearvars except audioSpectralEnergyAnalysis;

% 调用文件选择框，支持常见音频格式
[fileName, filePath] = uigetfile(...
    {'*.wav;*.mp3;*.flac;*.m4a;*.ogg','Audio Files (*.wav,*.mp3,*.flac,*.m4a,*.ogg)';...
    '*.*','All Files (*.*)'},...
    '选择要分析的音频文件',...
    pwd); % 默认路径为当前工作目录

% 处理用户取消选择的情况
if isequal(fileName, 0) || isequal(filePath, 0)
    fprintf('用户取消了文件选择，程序退出。\n');
    return;
end
audioFullPath = fullfile(filePath, fileName); % 拼接完整音频路径
fprintf('正在分析音频文件：%s\n', audioFullPath);

%% 2. 读取音频文件
try
    [y, Fs] = audioread(audioFullPath);     % 读取音频数据和采样率
catch ME
    fprintf('读取音频失败：%s\n请确认文件格式是否支持，或尝试转换为WAV格式。\n', ME.message);
    return;
end

% 处理立体声→单声道，归一化幅值（避免削波）
if size(y, 2) > 1
    y = mean(y, 2);
end
y = y / max(abs(y) + eps); % 加 eps 避免除以零

%% 3. 频谱分析参数设置
frameLen = 2048;          % FFT帧长（频率分辨率）
frameShift = frameLen/2;  % 帧移（重叠50%）
win = hanning(frameLen);  % 汉宁窗减少频谱泄漏
freqAxis = (0:frameLen/2) * Fs / frameLen;  % 频率轴（0~Fs/2）

%% 4. 计算整体频谱能量（修正版：先平均后转dB）
% 短时傅里叶变换计算每帧频谱
numFrames = floor((length(y) - frameLen) / frameShift) + 1;

% 初始化累积能量容器（直接存储线性能量，而非dB）
totalEnergyLinearAccumulator = zeros(1, length(freqAxis));

for i = 1:numFrames
    startIdx = (i-1)*frameShift + 1;
    endIdx = startIdx + frameLen - 1;
    frame = y(startIdx:endIdx) .* win;
    fftFrame = fft(frame);
    fftFrame = fftFrame(1:frameLen/2+1);

    % 计算当前帧线性能量
    energyLinear = abs(fftFrame).^2;

    % 累加线性能量
    totalEnergyLinearAccumulator = totalEnergyLinearAccumulator + energyLinear';
end

% 计算平均线性能量（总能量 / 帧数）
totalEnergyLinear = totalEnergyLinearAccumulator / numFrames;

% (可选) 转dB仅用于调试查看，不参与累积计算
% totalEnergydB = 10*log10(totalEnergyLinear + eps);
%% 5. 计算累积能量百分比（防插值报错）
% 按频率从低到高累加能量，归一化到0~100%
cumEnergyLinear = cumsum(totalEnergyLinear);  % 累积和
cumEnergyNorm = cumEnergyLinear / max(cumEnergyLinear + eps) * 100;  % 0~100%

% 关键防护：避免interp1采样点重复/非单调（彻底解决报错）
cumEnergyNorm(cumEnergyNorm > 100) = 100;
cumEnergyNorm(cumEnergyNorm < 0) = 0;
cumEnergyNorm = cumEnergyNorm + (0:length(cumEnergyNorm)-1)*1e-8; % 强制单调递增
[uniqueCumEnergy, uniqueIdx] = unique(round(cumEnergyNorm, 6), 'first'); % 去重
uniqueFreqAxis = freqAxis(uniqueIdx);
[uniqueCumEnergy, sortIdx] = sort(uniqueCumEnergy); % 强制排序
uniqueFreqAxis = uniqueFreqAxis(sortIdx);

% 定义需要标注的累积能量百分比（新增95%、99%）
targetPercents = [10, 50, 80, 90, 95, 99];
% 插值计算每个百分比对应的频率（允许外推）
targetFrequencies = interp1(uniqueCumEnergy, uniqueFreqAxis, targetPercents, 'linear', 'extrap');

%% 6. 可视化：累积能量折线图 + 关键百分比竖线
figure('Color','w','Position',[100,100,1200,700]);

% 绘制累积能量折线
plot(freqAxis, cumEnergyNorm, 'Color',[0.1,0.4,0.8],'LineWidth',2);
hold on; grid on; grid minor;

% 定义各百分比对应颜色（新增95%紫色、99%深灰色）
colors = [0.8,0.2,0.2;   % 10% 红色
    0.2,0.7,0.2;   % 50% 绿色
    0.2,0.2,0.8;   % 80% 蓝色
    0.8,0.5,0.1;   % 90% 橙色
    0.7,0.2,0.8;   % 95% 紫色
    0.3,0.3,0.3];  % 99% 深灰色

% 绘制各百分比竖线+标注
for i = 1:length(targetPercents)
    % 绘制竖线
    xline(targetFrequencies(i), 'Color', colors(i,:), 'LineWidth',1.5, 'LineStyle','--');
    % 标注百分比和对应频率（自适应位置，避免重叠）
    textX = targetFrequencies(i) + 50 * (1 + mod(i,2)); % 奇偶偏移，避免重叠
    textY = targetPercents(i) + 2;
    text(textX, textY, ...
        [num2str(targetPercents(i)) '% (' num2str(round(targetFrequencies(i))) 'Hz)'], ...
        'FontSize',11, 'Color',colors(i,:), 'FontWeight','bold');
end

% 图表样式优化
xlabel('频率 (Hz)','FontSize',14);
ylabel('累积能量 (%)','FontSize',14);
[~, audioName, ~] = fileparts(fileName); % 提取音频文件名（无后缀）
title([audioName ' 频谱能量累积分布（0%→100%）'],'FontSize',16,'FontWeight','bold');
xlim([20, 20000]);  % 聚焦人耳可听范围
ylim([0, 105]);     % 纵坐标留余量
set(gca, 'XScale', 'log');  % 频率轴对数刻度（符合听觉感知）
xticks([20, 50, 100, 500, 1000, 5000, 10000, 20000]);  % 自定义刻度
xticklabels({'20','50','100','500','1k','5k','10k','20k'});  % 简化标签
box on;

%% 7. 输出关键信息
fprintf('\n===== 累积能量关键频率 =====\n');
for i = 1:length(targetPercents)
    fprintf('  %d%% 累积能量对应频率：%.1f Hz\n', targetPercents(i), targetFrequencies(i));
end
fprintf('============================\n');
fprintf('总能量90%%集中在 %.1f Hz 以下\n', targetFrequencies(4));
fprintf('总能量99%%集中在 %.1f Hz 以下\n', targetFrequencies(6));
end