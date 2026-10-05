function city_pair_model(weight_file, data_file, city_a, city_b, prefix)
% CITY_PAIR_MODEL 双城市综合实力比较通用模型
%
% 输入：
%   weight_file : 权重表CSV，需含列：
%                 原表指标,规范指标,类别,实力类型,指标方向,重要性权重
%   data_file   : 数据表CSV，需含列：
%                 原表指标,规范指标,城市A值,城市B值,数据年份,数据来源,单位,是否更新
%   city_a      : 前一个城市的名称，如 '北京'
%   city_b      : 后一个城市的名称，如 '上海'
%   prefix      : 输出文件前缀，如 '京沪'
%
% 输出：
%   <prefix>综合实力总览.csv
%   <prefix>综合实力结果.csv
%   <prefix>综合实力摘要.txt
%   <prefix>综合实力分类图.png
%
% 模型：
%   正向指标：log2(A/B)
%   反向指标：log2(B/A)
%   含负值指标：2*(A-B)/(|A|+|B|)
%   单项差距截断于 [-3, 3]
%   综合优势 = 0.7*硬实力加权优势 + 0.3*软实力加权优势

if nargin < 5
    error('需要提供权重表、数据表、两个城市名称和输出前缀。');
end

W = readtable(weight_file, 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
D = readtable(data_file, 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');

W.Properties.VariableNames = {'raw', 'name', 'category', 'type', 'direction', 'weight', 'share', 'rule'};
D.Properties.VariableNames = {'raw', 'name', 'A', 'B', 'year', 'source', 'unit', 'updated'};

W.weight = str2double(string(W.weight));
D.A = str2double(string(D.A));
D.B = str2double(string(D.B));

[~, ia, ib] = intersect(W.raw, D.raw, 'stable');
w = W(ia, :);
d = D(ib, :);

valid = isfinite(d.A) & isfinite(d.B) & (d.A ~= 0) & (d.B ~= 0) & isfinite(w.weight);
w = w(valid, :);
d = d(valid, :);
if isempty(w)
    error('没有可用于计算的完整数据行。');
end

is_reverse = string(w.direction) == "反向";
positive = (d.A > 0) & (d.B > 0);
score = zeros(height(d), 1);
score(positive) = log2(d.A(positive) ./ d.B(positive));
score(~positive) = 2 * (d.A(~positive) - d.B(~positive)) ./ ...
    (abs(d.A(~positive)) + abs(d.B(~positive)));
score(is_reverse & positive) = -score(is_reverse & positive);
score(is_reverse & ~positive) = -score(is_reverse & ~positive);
score = max(-3, min(3, score));

is_hard = string(w.type) == "硬实力";
hard_idx = find(is_hard);
soft_idx = find(~is_hard);

hard_adv = sum(w.weight(hard_idx) .* score(hard_idx)) / sum(w.weight(hard_idx));
soft_adv = sum(w.weight(soft_idx) .* score(soft_idx)) / sum(w.weight(soft_idx));
total_adv = 0.7 * hard_adv + 0.3 * soft_adv;
relative_strength = 2 ^ total_adv;

categories = unique(w.category, 'stable');
n_cat = numel(categories);
cat_name = cell(n_cat, 1);
cat_type = cell(n_cat, 1);
cat_n = zeros(n_cat, 1);
cat_adv = zeros(n_cat, 1);
cat_a_wins = zeros(n_cat, 1);
cat_b_wins = zeros(n_cat, 1);

for k = 1:n_cat
    idx = string(w.category) == categories(k);
    sub_w = w(idx, :);
    sub_score = score(idx);
    cat_name{k} = char(categories(k));
    cat_type{k} = char(unique(sub_w.type));
    cat_n(k) = sum(idx);
    cat_adv(k) = sum(sub_w.weight .* sub_score) / sum(sub_w.weight);
    cat_a_wins(k) = sum(sub_score > 0);
    cat_b_wins(k) = sum(sub_score < 0);
end

updated = sum(string(d.updated) == "是");
a_wins = sum(score > 0);
b_wins = sum(score < 0);
ties = sum(score == 0);
coverage = height(w);

summary = table( ...
    categorical(["硬实力"; "软实力"]), ...
    ["硬实力加权优势"; "软实力加权优势"], ...
    [hard_adv; soft_adv], ...
    'VariableNames', {'实力类型', '指标', '加权优势'});
summary = [summary; table( ...
    categorical(repmat("综合", 1, 1)), ...
    "软3硬7综合优势", total_adv, ...
    'VariableNames', {'实力类型', '指标', '加权优势'})];

category_table = table(string(cat_name), string(cat_type), cat_n, cat_adv, cat_a_wins, cat_b_wins, ...
    'VariableNames', {'类别', '实力类型', '计算项目数', '加权优势', [city_a '胜项'], [city_b '胜项']});

writetable(summary, [prefix '综合实力总览.csv'], 'Encoding', 'UTF-8');
writetable(category_table, [prefix '综合实力结果.csv'], 'Encoding', 'UTF-8');

fid = fopen([prefix '综合实力摘要.txt'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s%s综合实力模型结果\n', city_a, city_b);
fprintf(fid, '规则：软实力30%%，硬实力70%%；优势按 log2(%s/%s) 计算\n', city_a, city_b);
fprintf(fid, '计算项目数：%d；有更新来源项目：%d\n', coverage, updated);
fprintf(fid, '硬实力加权优势：%+.5f\n', hard_adv);
fprintf(fid, '软实力加权优势：%+.5f\n', soft_adv);
fprintf(fid, '综合优势：%+.5f\n', total_adv);
fprintf(fid, '%s相对%s综合强度：%.4f\n', city_a, city_b, relative_strength);
fprintf(fid, '若%s=100，%s综合指数：%.2f\n', city_b, city_a, 100 * relative_strength);
fprintf(fid, '%s胜项：%d；%s胜项：%d；打平：%d\n', city_a, a_wins, city_b, b_wins, ties);
fclose(fid);

figure('Color', 'w', 'Units', 'normalized', 'Position', [0.1 0.15 0.72 0.65]);
bar(cat_adv);
set(gca, 'XTick', 1:n_cat, 'XTickLabel', cat_name, 'XTickLabelRotation', 45);
ylabel(sprintf('Weighted advantage (log2 %s/%s)', city_a, city_b));
title(sprintf('%s vs %s: total %.3f, relative %.3f', city_a, city_b, total_adv, relative_strength));
grid on;
saveas(gcf, [prefix '综合实力分类图.png']);
close(gcf);

fprintf('硬实力加权优势：%+.5f\n', hard_adv);
fprintf('软实力加权优势：%+.5f\n', soft_adv);
fprintf('综合优势：%+.5f\n', total_adv);
fprintf('%s相对%s综合强度：%.4f\n', city_a, city_b, relative_strength);
fprintf('若%s=100，%s综合指数：%.2f\n', city_b, city_a, 100 * relative_strength);
end
