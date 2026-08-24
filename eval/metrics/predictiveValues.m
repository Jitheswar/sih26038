function result = predictiveValues(sensitivity, specificity, prevalence)
%PREDICTIVEVALUES PPV and NPV at a stated screening prevalence.
%   RESULT = predictiveValues(SENSITIVITY, SPECIFICITY, PREVALENCE) returns
%   the positive and negative predictive values (§11.3).
%
%   These are what the number actually means to a patient: given a referral,
%   how likely is it that they have referable disease.  Both are strongly
%   prevalence-dependent, which is why PREVALENCE is a required argument
%   rather than a default.  A model validated on a split with 40% referable
%   prevalence will show a very different PPV in a community screening camp
%   where prevalence is nearer 10%, with no change to the model at all.
%
%   Always state the prevalence assumed alongside the value (§11.1).

rng(42);

validateScalarRate(sensitivity, 'sensitivity');
validateScalarRate(specificity, 'specificity');
validateScalarRate(prevalence, 'prevalence');

sensitivity = double(sensitivity);
specificity = double(specificity);
prevalence = double(prevalence);

truePositiveRate = sensitivity * prevalence;
falsePositiveRate = (1 - specificity) * (1 - prevalence);
trueNegativeRate = specificity * (1 - prevalence);
falseNegativeRate = (1 - sensitivity) * prevalence;

positivePredictive = truePositiveRate / (truePositiveRate + falsePositiveRate);
negativePredictive = trueNegativeRate / (trueNegativeRate + falseNegativeRate);

if truePositiveRate + falsePositiveRate == 0
    positivePredictive = NaN;
end
if trueNegativeRate + falseNegativeRate == 0
    negativePredictive = NaN;
end

result = struct( ...
    'positivePredictiveValue', positivePredictive, ...
    'negativePredictiveValue', negativePredictive, ...
    'ppv', positivePredictive, ...
    'npv', negativePredictive, ...
    'sensitivity', sensitivity, ...
    'specificity', specificity, ...
    'prevalence', prevalence, ...
    'falseOmissionRate', 1 - negativePredictive, ...
    'falseDiscoveryRate', 1 - positivePredictive);
end

function validateScalarRate(value, label)
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value < 0 || value > 1
    error('eval:InvalidRate', ...
        '%s must be a finite number between zero and one.', label);
end
end
