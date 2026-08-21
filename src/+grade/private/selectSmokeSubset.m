function subset = selectSmokeSubset(data, examplesPerClass)
%SELECTSMOKESUBSET Select a deterministic, class-complete smoke subset.

examplesPerClass = max(1, floor(double(examplesPerClass)));
selected = zeros(0, 1);
for level = 0:4
    candidates = find(data.grades == level);
    if numel(candidates) < examplesPerClass
        error('grade:InsufficientSmokeData', ...
            'Split %s has too few examples for grade %d.', data.split, level);
    end
    selected = [selected; candidates(1:examplesPerClass)]; %#ok<AGROW>
end

subset = data;
subset.table = data.table(selected, :);
subset.files = data.files(selected);
subset.grades = data.grades(selected);
subset.classCounts = arrayfun(@(level) sum(subset.grades == level), 0:4).';
subset.count = numel(subset.grades);
end
