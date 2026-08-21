function weights = classWeights(classCounts)
%CLASSWEIGHTS Create normalized inverse-frequency weights for five grades.

classCounts = double(classCounts(:));
if numel(classCounts) ~= 5 || any(~isfinite(classCounts)) || any(classCounts <= 0)
    error('grade:InvalidClassCounts', ...
        'All five grades must have positive finite training counts.');
end
weights = sum(classCounts) ./ (numel(classCounts) * classCounts);
weights = weights(:);
end
