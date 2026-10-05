function city_pair_model_v2(weight_file, data_file, city_a, city_b, prefix)
% 城市综合实力双城比较模型 v2
% 特点：
% 1. 使用“基准权重 × 冗余折扣系数 = 最终有效权重”；
% 2. 硬实力70%、软实力30%；
% 3. 正向指标用log2(A/B)，反向指标反向计算；
% 4. 缺失值和零值项目不参与计算。

if nargin < 5
    error('需要：权重表、数据表、城市A、城市B、输出前缀');
end

W = readtable(weight_file, 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');
D = readtable(data_file, 'Encoding', 'UTF-8', 'VariableNamingRule', 'preserve');

W.Properties.VariableNames = {'raw','name','category','type','direction','base','redundancy','weight','rule'};
D.Properties.VariableNames = {'raw','name','A','B','year','source','unit','updated'};

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
    error('没有可用于计算的完整数据行');
end

is_reverse = string(w.direction) == "反向";
positive = (d.A > 0) & (d.B > 0);
score = zeros(height(d), 1);
score(positive) = log2(d.A(positive) ./ d.B(positive));
score(~positive) = 2 * (d.A(~positive) - d.B(~positive)) ./ (abs(d.A(~positive)) + abs(d.B(~positive)));
score(is_reverse & positive) = -score(is_reverse & positive);
score(is_reverse & ~positive) = -score(is_reverse & ~positive);
score = max(-3, min(3, score));

is_hard = string(w.type) == "硬实力";
hard_idx = find(is_hard);
soft_idx = find(~is_hard);

hard_adv = sum(w.weight(hard_idx) .* score(hard_idx)) / sum(w.weight(hard_idx));
soft_adv = sum(w.weight(soft_idx) .* score(soft_idx)) / sum(w.weight(soft_idx));
total_adv = 0.7 * hard_adv + 0.3 * soft_adv;
relative = 2 ^ total_adv;

cats = unique(w.category, 'stable');
n = numel(cats);
cn = cell(n,1); ct = cell(n,1); nn = zeros(n,1); ca = zeros(n,1); aw = zeros(n,1); bw = zeros(n,1);
for k = 1:n
    idx = string(w.category) == cats(k);
    sub = w(idx,:);
    ss = score(idx);
    cn{k} = char(cats(k));
    ct{k} = char(unique(sub.type));
    nn(k) = sum(idx);
    ca(k) = sum(sub.weight .* ss) / sum(sub.weight);
    aw(k) = sum(ss > 0);
    bw(k) = sum(ss < 0);
end

coverage = height(w);
updated = sum(string(d.updated) == "是");
a_wins = sum(score > 0);
b_wins = sum(score < 0);
ties = sum(score == 0);

summary = table(categorical(["硬实力";"软实力"]), ["硬实力加权优势";"软实力加权优势"], [hard_adv;soft_adv], 'VariableNames',{'实力类型','指标','加权优势'});
summary = [summary; table(categorical(repmat("综合",1,1)), "软3硬7综合优势", total_adv, 'VariableNames',{'实力类型','指标','加权优势'})];
cat_table = table(string(cn), string(ct), nn, ca, aw, bw, 'VariableNames',{'类别','实力类型','计算项目数','加权优势',[city_a '胜项'],[city_b '胜项']});

writetable(summary, [prefix '综合实力总览v2.csv'], 'Encoding','UTF-8');
writetable(cat_table, [prefix '综合实力结果v2.csv'], 'Encoding','UTF-8');

fid = fopen([prefix '综合实力摘要v2.txt'], 'w','n','UTF-8');
fprintf(fid, '%s%s综合实力模型v2结果\n', city_a, city_b);
fprintf(fid, '硬实力权重70%%，软实力权重30%%；采用冗余折扣后的有效权重\n');
fprintf(fid, '计算项目数：%d；有更新来源项目：%d\n', coverage, updated);
fprintf(fid, '硬实力加权优势：%+.5f\n', hard_adv);
fprintf(fid, '软实力加权优势：%+.5f\n', soft_adv);
fprintf(fid, '综合优势：%+.5f\n', total_adv);
fprintf(fid, '%s相对%s综合强度：%.4f\n', city_a, city_b, relative);
fprintf(fid, '若%s=100，%s综合指数：%.2f\n', city_b, city_a, 100*relative);
fprintf(fid, '%s胜项：%d；%s胜项：%d；打平：%d\n', city_a, a_wins, city_b, b_wins, ties);
fclose(fid);

figure('Color','w','Units','normalized','Position',[0.1 0.15 0.72 0.65]);
bar(ca);
set(gca,'XTick',1:n,'XTickLabel',cn,'XTickLabelRotation',45);
ylabel(sprintf('Weighted advantage (log2 %s/%s)', city_a, city_b));
title(sprintf('%s vs %s v2: total %.3f, relative %.3f', city_a, city_b, total_adv, relative));
grid on;
saveas(gcf,[prefix '综合实力分类图v2.png']);
close(gcf);

fprintf('硬实力加权优势：%+.5f\n', hard_adv);
fprintf('软实力加权优势：%+.5f\n', soft_adv);
fprintf('综合优势：%+.5f\n', total_adv);
fprintf('%s相对%s综合强度：%.4f\n', city_a, city_b, relative);
fprintf('若%s=100，%s综合指数：%.2f\n', city_b, city_a, 100*relative);
end
