function result = quadraticWeightedKappa(trueLabels, predictedLabels)
%QUADRATICWEIGHTEDKAPPA Ordinal agreement on the 5-class ICDR grade.
%   RESULT = quadraticWeightedKappa(TRUELABELS, PREDICTEDLABELS) returns
%   the quadratic weighted kappa, the standard ordinal agreement metric for
%   DR grading and the APTOS competition metric (§11.3).
%
%   Quadratic weights penalise distant confusions more than adjacent ones,
%   so calling a Level 4 image Level 0 costs far more than calling it
%   Level 3.  That matches the clinical cost structure in a way plain
%   accuracy does not.
%
%   What this measures is agreement with a single human rater's grade, so
%   that rater's own reliability is the ceiling.  A kappa below published
%   inter-rater agreement is not necessarily a model failure.

rng(42);

matrix = confusionMatrix(trueLabels, predictedLabels);
numberClasses = size(matrix, 1);
total = sum(matrix, 'all');

if total == 0
    result = struct('kappa', NaN, 'observedAgreement', NaN, ...
        'expectedAgreement', NaN, 'n', 0, 'confusionMatrix', matrix, ...
        'weights', zeros(numberClasses));
    return;
end

levels = (0:numberClasses - 1)';
weights = (levels - levels').^2 / (numberClasses - 1)^2;

observed = matrix / total;
rowMarginal = sum(observed, 2);
columnMarginal = sum(observed, 1);
expected = rowMarginal * columnMarginal;

observedDisagreement = sum(weights .* observed, 'all');
expectedDisagreement = sum(weights .* expected, 'all');

if expectedDisagreement == 0
    % Every prediction and every label sits on one grade. Agreement is
    % perfect but kappa is undefined, so report it as such rather than
    % returning a flattering 1.
    kappa = NaN;
else
    kappa = 1 - observedDisagreement / expectedDisagreement;
end

result = struct( ...
    'kappa', kappa, ...
    'observedAgreement', 1 - observedDisagreement, ...
    'expectedAgreement', 1 - expectedDisagreement, ...
    'n', total, ...
    'confusionMatrix', matrix, ...
    'weights', weights);
end
