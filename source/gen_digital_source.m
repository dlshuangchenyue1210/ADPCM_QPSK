function bits = gen_digital_source(len)
    rng(42); % 固定随机种子以便结果复现
    bits = randi([0, 1], len, 1);
end