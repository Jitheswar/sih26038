function config = validateDistrictConfig(configOrPath)
%VALIDATEDISTRICTCONFIG Load and validate named district simulation inputs.

if nargin == 0 || isempty(configOrPath)
    configOrPath = fullfile(fileparts(mfilename('fullpath')), 'district_config.json');
end
if ischar(configOrPath) || isstring(configOrPath)
    config = jsondecode(fileread(char(configOrPath)));
else
    config = configOrPath;
end

required = { ...
    'annualScreeningVolume', 'simulationDurationDays', 'numberOfPHCs', ...
    'arrivalMode', 'arrivalRate', 'campBurstMultiplier', ...
    'captureTimeSeconds', 'qualityGateTimeSeconds', 'qualityRejectionRate', ...
    'maximumRecaptureAttempts', 'inferenceTimeSeconds', 'imageSizeMegabytes', ...
    'bandwidthMegabitsPerSecond', 'connectivityAvailability', ...
    'uploadRetryIntervalSeconds', 'numberOfGraders', 'graderServiceTimeSeconds', ...
    'modelSensitivity', 'modelSpecificity', 'deferralRate', ...
    'turnaroundTargetHours', 'randomSeed'};
for i = 1:numel(required)
    if ~isfield(config, required{i})
        error('district:MissingConfigurationField', ...
            'Missing required configuration field: %s.', required{i});
    end
end

positiveFields = {'simulationDurationDays', 'arrivalRate', 'captureTimeSeconds', ...
    'qualityGateTimeSeconds', 'inferenceTimeSeconds', 'imageSizeMegabytes', ...
    'bandwidthMegabitsPerSecond', 'uploadRetryIntervalSeconds', ...
    'graderServiceTimeSeconds', 'turnaroundTargetHours'};
for i = 1:numel(positiveFields)
    name = positiveFields{i};
    if ~isscalar(config.(name)) || ~isfinite(config.(name)) || config.(name) <= 0
        error('district:InvalidPositiveParameter', ...
            '%s must be a finite positive scalar.', name);
    end
end

integerFields = {'annualScreeningVolume', 'numberOfPHCs', ...
    'maximumRecaptureAttempts', 'numberOfGraders', 'randomSeed'};
for i = 1:numel(integerFields)
    name = integerFields{i};
    value = config.(name);
    if ~isscalar(value) || ~isfinite(value) || value < 0 || value ~= floor(value)
        error('district:InvalidIntegerParameter', ...
            '%s must be a non-negative integer.', name);
    end
end
if config.annualScreeningVolume <= 0 || config.numberOfPHCs <= 0 || ...
        config.maximumRecaptureAttempts < 0 || config.numberOfGraders <= 0
    error('district:InvalidCountParameter', ...
        'Annual volume, PHC count, and grader count must be positive.');
end

probabilityFields = {'qualityRejectionRate', 'connectivityAvailability', ...
    'modelSensitivity', 'modelSpecificity', 'deferralRate'};
for i = 1:numel(probabilityFields)
    name = probabilityFields{i};
    value = config.(name);
    if ~isscalar(value) || ~isfinite(value) || value < 0 || value > 1
        error('district:InvalidProbability', '%s must be in [0, 1].', name);
    end
end

if isfield(config, 'referablePrevalence') && ...
        (config.referablePrevalence < 0 || config.referablePrevalence > 1)
    error('district:InvalidProbability', 'referablePrevalence must be in [0, 1].');
end
if isfield(config, 'connectivityCycleSeconds') && config.connectivityCycleSeconds <= 0
    error('district:InvalidPositiveParameter', ...
        'connectivityCycleSeconds must be positive.');
end
if ~ismember(lower(char(config.arrivalMode)), {'smooth', 'bursty', 'camp'})
    error('district:InvalidArrivalMode', 'arrivalMode must be smooth or bursty.');
end
if ~strcmpi(char(config.arrivalMode), 'smooth') && config.campBurstMultiplier <= 0
    error('district:InvalidBurstMultiplier', 'campBurstMultiplier must be positive.');
end
if isfield(config, 'failedCaptureRouting') && ...
        ~ismember(lower(char(config.failedCaptureRouting)), {'escalate', 'refer'})
    error('district:InvalidFailedCaptureRouting', ...
        'failedCaptureRouting must be escalate or refer.');
end

derivedVolume = config.arrivalRate * config.simulationDurationDays * 86400;
config.derivedAnnualVolume = derivedVolume;
config.annualVolumeDifference = derivedVolume - config.annualScreeningVolume;
end
