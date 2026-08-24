function result = riskCoverage(correct, confidence)
%RISKCOVERAGE Accuracy as a function of the fraction handled autonomously.
%   RESULT = riskCoverage(CORRECT, CONFIDENCE) returns the risk-coverage
%   curve (§11.3).  CORRECT is a logical vector recording whether each case
%   was decided correctly; CONFIDENCE is the score used to rank cases for
%   autonomous handling, highest first.
%
%   This is how a deferral policy is presented honestly.  Raw accuracy on
%   the full set says nothing about a system that hands hard cases to a
%   human; what matters is the error rate on the subset it keeps.  §11.6
%   asks for exactly this comparison: A5 against A1 at equal coverage.
%
%   AURC (area under the risk-coverage curve) summarises the curve, lower
%   being better.  A perfect confidence ranking sorts every error to the
%   end of the queue, so its AURC is bounded below by the base error rate
%   concentrated at full coverage, not by zero.

rng(42);

correct = logical(correct(:));
confidence = double(confidence(:));
if numel(correct) ~= numel(confidence)
    error('eval:LengthMismatch', ...
        'Correctness and confidence must have the same number of elements.');
end

n = numel(correct);
if n == 0
    result = struct('coverage', [], 'risk', [], 'accuracy', [], ...
        'aurc', NaN, 'n', 0, 'baseRisk', NaN);
    return;
end

[~, order] = sort(confidence, 'descend');
orderedCorrect = correct(order);

cumulativeCorrect = cumsum(orderedCorrect);
coverage = (1:n)' / n;
accuracy = cumulativeCorrect ./ (1:n)';
risk = 1 - accuracy;

aurc = mean(risk);

result = struct( ...
    'coverage', coverage, ...
    'risk', risk, ...
    'accuracy', accuracy, ...
    'aurc', aurc, ...
    'n', n, ...
    'baseRisk', 1 - sum(correct) / n);
end
