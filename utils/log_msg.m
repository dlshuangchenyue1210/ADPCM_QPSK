function log_msg(level, msg, params)
% LOG_MSG 统一日志输出
%   level: 消息级别 (1=错误, 2=警告, 3=信息, 4=调试)
%   msg: 日志内容字符串
%   params: 系统参数结构体，需含 verbose 字段
    if isfield(params, 'verbose') && params.verbose >= level
        fprintf('%s\n', msg);
    end
end
