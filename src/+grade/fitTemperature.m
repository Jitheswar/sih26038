function result = fitTemperature(firstInput, secondInput, varargin)
%FITTEMPERATURE Fit one positive temperature by multiclass NLL.
%   RESULT = grade.fitTemperature(LOGITS, LABELS, NAME, VALUE, ...) fits
%   temperature scaling on classes-by-samples logits and ICDR labels.
%   RESULT = grade.fitTemperature(CHECKPOINT, CALIBRATIONCSV, CONFIG, ...)
%   obtains logits through grade.infer using only the committed calibration
%   split, evaluates raw and calibrated probabilities, and writes results.

rng(42, 'twister');
if localIsPath(firstInput) && localIsPath(secondInput)
    result = localFitFromCalibrationSplit(firstInput, secondInput, varargin{:});
    return;
end

if ~isnumeric(firstInput) || ~isnumeric(secondInput)
    error('grade:InvalidTemperatureInputs', ...
        'Direct fitting requires numeric logits and numeric ICDR labels.');
end
logits = double(firstInput);
labels = double(secondInput(:));
localValidateLogitsAndLabels(logits, labels);

options = localDirectOptions(varargin{:});
temperatureBounds = [exp(-20), exp(20)];
objective = @(logTemperature) localNegativeLogLikelihood( ...
    logits, labels, exp(logTemperature));
optimizationOptions = optimset('Display', 'off', ...
    'TolX', 1e-8, 'MaxFunEvals', 1000, 'MaxIter', 1000);
initialNegativeLogLikelihood = objective(0);
[fittedLogTemperature, finalNegativeLogLikelihood, exitFlag, output] = ...
    fminbnd(objective, log(temperatureBounds(1)), ...
    log(temperatureBounds(2)), optimizationOptions);
temperature = exp(fittedLogTemperature);

result = localFitMetadata(temperature, options, exitFlag, output, ...
    initialNegativeLogLikelihood, finalNegativeLogLikelihood);
result.logTemperature = fittedLogTemperature;
result.temperatureBounds = temperatureBounds;
result.fittedNegativeLogLikelihood = finalNegativeLogLikelihood;
if strlength(options.savePath) > 0
    localSaveFit(result, options.savePath);
end
end

function result = localFitFromCalibrationSplit(checkpointInput, splitInput, varargin)
checkpointPath = char(checkpointInput);
splitPath = char(splitInput);
if ~isfile(checkpointPath)
    error('grade:MissingCheckpoint', ...
        'Checkpoint does not exist: %s', checkpointPath);
end
localValidateCalibrationPath(splitPath);

configInput = [];
remaining = varargin;
isPositionalConfig = ~isempty(remaining) && (isstruct(remaining{1}) || ...
    ((ischar(remaining{1}) || (isstring(remaining{1}) && isscalar(remaining{1}))) && ...
    ~ismember(lower(string(remaining{1})), localOptionNames())));
if isPositionalConfig
    configInput = remaining{1};
    remaining = remaining(2:end);
end
parser = inputParser;
parser.addParameter('ResultsRoot', '', @(value) ischar(value) || ...
    (isstring(value) && isscalar(value)));
parser.addParameter('NumBins', 10, @(value) isnumeric(value) && isscalar(value) && ...
    isfinite(value) && value >= 2 && value == floor(value));
parser.parse(remaining{:});

checkpoint = load(checkpointPath, 'net', 'config');
if isempty(configInput)
    configInput = checkpoint.config;
end
[config, configText, projectRoot] = gradePrivateReadConfiguration(configInput);
if canUseGPU
    checkpoint.net = dlupdate(@gpuArray, checkpoint.net);
end
calibrationTable = readtable(splitPath, 'TextType', 'string');
localValidateCalibrationTable(calibrationTable, splitPath);

sampleCount = height(calibrationTable);
images = cell(sampleCount, 1);
for sampleIndex = 1:sampleCount
    imagePath = fullfile(projectRoot, char(calibrationTable.relative_path(sampleIndex)));
    if ~isfile(imagePath)
        error('grade:MissingCalibrationImage', ...
            'Calibration image does not exist: %s', imagePath);
    end
    images{sampleIndex} = imread(imagePath);
end
inference = grade.infer(checkpoint, images, config, 'ReturnLogits', true);
logits = inference.logits;
labels = double(calibrationTable.grade(:));

resultsRoot = char(parser.Results.ResultsRoot);
if isempty(resultsRoot)
    resultsRoot = fullfile(projectRoot, 'results');
end
resultsDirectory = localDatedDirectory(resultsRoot);
mkdir(resultsDirectory);

fit = grade.fitTemperature(logits, labels, ...
    'CalibrationSplitIdentifier', 'calibration.csv', ...
    'ModelCheckpointPath', checkpointPath, ...
    'TrainingConfiguration', config, ...
    'SavePath', fullfile(resultsDirectory, 'temperature_fit.mat'));
rawProbabilities = grade.applyTemperature(logits, 1);
calibratedProbabilities = grade.applyTemperature(logits, fit.temperature);
metrics = eval.calibrationMetrics(labels, rawProbabilities, ...
    calibratedProbabilities, 'NumBins', parser.Results.NumBins);

reliabilityDiagramPath = fullfile(resultsDirectory, 'reliability_diagram.mat');
reliabilityDiagram = struct( ...
    'raw', metrics.raw.reliabilityDiagram, ...
    'calibrated', metrics.calibrated.reliabilityDiagram, ...
    'rawReferableDR', metrics.raw.referableDR.reliabilityDiagram, ...
    'calibratedReferableDR', metrics.calibrated.referableDR.reliabilityDiagram);
save(reliabilityDiagramPath, 'reliabilityDiagram', '-v7');

calibrationResult = fit;
calibrationResult.status = "completed";
calibrationResult.metrics = metrics;
calibrationResult.rawProbabilities = rawProbabilities;
calibrationResult.calibratedProbabilities = calibratedProbabilities;
calibrationResult.logits = logits;
calibrationResult.labels = labels;
calibrationResult.numberCalibrationSamples = sampleCount;
calibrationResult.samplesPerGrade = arrayfun(@(grade) sum(labels == grade), 0:4).';
calibrationResult.reliabilityDiagram = reliabilityDiagram;
calibrationResult.reliabilityDiagramOutputPath = string(reliabilityDiagramPath);
calibrationResult.resultsDirectory = string(resultsDirectory);
calibrationResult.trainingConfigurationText = string(configText);
calibrationResult.calibrationSplitPath = string(splitPath);
calibrationResult.testSplitUsed = false;
calibrationResult.sealedDataAccessed = false;
save(fullfile(resultsDirectory, 'calibration_results.mat'), ...
    'calibrationResult', '-v7.3');
localWriteConfiguration(fullfile(resultsDirectory, 'config.json'), configText);
result = calibrationResult;
end

function options = localDirectOptions(varargin)
parser = inputParser;
parser.addParameter('CalibrationSplitIdentifier', 'calibration.csv', ...
    @(value) ischar(value) || (isstring(value) && isscalar(value)));
parser.addParameter('ModelCheckpointPath', '', ...
    @(value) ischar(value) || (isstring(value) && isscalar(value)));
parser.addParameter('TrainingConfiguration', struct(), ...
    @(value) isstruct(value) && isscalar(value));
parser.addParameter('FittingDate', datestr(now, 'yyyy-mm-ddTHH:MM:SS'), ...
    @(value) ischar(value) || (isstring(value) && isscalar(value)));
parser.addParameter('SavePath', '', ...
    @(value) ischar(value) || (isstring(value) && isscalar(value)));
parser.parse(varargin{:});
options = struct( ...
    'calibrationSplitIdentifier', string(parser.Results.CalibrationSplitIdentifier), ...
    'modelCheckpointPath', string(parser.Results.ModelCheckpointPath), ...
    'trainingConfiguration', parser.Results.TrainingConfiguration, ...
    'fittingDate', string(parser.Results.FittingDate), ...
    'savePath', string(parser.Results.SavePath));
identifier = lower(char(options.calibrationSplitIdentifier));
if contains(identifier, 'test') || contains(identifier, 'sealed') || ...
        (contains(identifier, '.csv') && ~contains(identifier, 'calibration.csv'))
    error('grade:InvalidCalibrationSplit', ...
        'Temperature fitting accepts only the calibration split, never test or sealed data.');
end
end

function result = localFitMetadata(temperature, options, exitFlag, output, initialNLL, finalNLL)
if exitFlag > 0
    optimizationStatus = "converged";
else
    optimizationStatus = "not_converged";
end
result = struct( ...
    'temperature', temperature, ...
    'calibrationSplitIdentifier', options.calibrationSplitIdentifier, ...
    'modelCheckpointPath', options.modelCheckpointPath, ...
    'trainingConfiguration', options.trainingConfiguration, ...
    'fittingDate', options.fittingDate, ...
    'optimizationStatus', optimizationStatus, ...
    'optimizationExitFlag', exitFlag, ...
    'optimizationIterations', output.iterations, ...
    'optimizationFunctionCount', output.funcCount, ...
    'initialNegativeLogLikelihood', initialNLL, ...
    'finalNegativeLogLikelihood', finalNLL);
end

function value = localNegativeLogLikelihood(logits, labels, temperature)
scaledLogits = logits ./ temperature;
maximum = max(scaledLogits, [], 1);
logNormalizer = maximum + log(sum(exp(scaledLogits - maximum), 1));
targetIndices = sub2ind([size(logits, 1), size(logits, 2)], ...
    labels + 1, (1:numel(labels)).');
logProbabilities = scaledLogits - logNormalizer;
value = -mean(logProbabilities(targetIndices));
if ~isfinite(value)
    value = realmax('double');
end
end

function localValidateLogitsAndLabels(logits, labels)
if ndims(logits) ~= 2 || isempty(logits) || size(logits, 1) ~= 5 || ...
        size(logits, 2) ~= numel(labels) || any(~isfinite(logits(:)))
    error('grade:InvalidTemperatureInputs', ...
        'Logits must be finite, five-class, and classes-by-samples.');
end
if isempty(labels) || any(~isfinite(labels)) || any(labels ~= floor(labels)) || ...
        any(~ismember(labels, 0:4))
    error('grade:InvalidTemperatureLabels', ...
        'Labels must be non-empty integer ICDR grades from 0 through 4.');
end
end

function localValidateCalibrationPath(splitPath)
normalizedPath = lower(strrep(splitPath, '\\', '/'));
[~, name, extension] = fileparts(splitPath);
if ~strcmpi(string(name) + string(extension), "calibration.csv") || ...
        ~(contains(normalizedPath, '/data/splits/') || ...
        startsWith(normalizedPath, 'data/splits/')) || ...
        contains(normalizedPath, 'test') || contains(normalizedPath, 'sealed')
    error('grade:InvalidCalibrationSplit', ...
        'Temperature fitting accepts only data/splits/calibration.csv.');
end
end

function localValidateCalibrationTable(tableData, splitPath)
requiredColumns = ["image_id", "patient_id", "grade", "relative_path"];
if ~all(ismember(requiredColumns, string(tableData.Properties.VariableNames)))
    error('grade:InvalidCalibrationSplit', ...
        'Calibration split has an unexpected schema: %s', splitPath);
end
relativePaths = lower(string(tableData.relative_path));
if any(contains(relativePaths, 'sealed')) || ...
        any(~contains(relativePaths, 'data/raw/aptos2019'))
    error('grade:InvalidCalibrationSplit', ...
        'Calibration split may contain only APTOS paths.');
end
grades = double(tableData.grade);
if isempty(grades) || any(~ismember(grades, 0:4))
    error('grade:InvalidCalibrationSplit', ...
        'Calibration grades must be integers from 0 through 4.');
end
end

function result = localIsPath(value)
result = ischar(value) || (isstring(value) && isscalar(value));
end

function names = localOptionNames()
names = ["resultsroot", "numbins", "calibrationsplitidentifier", ...
    "modelcheckpointpath", "trainingconfiguration", "fittingdate", "savepath"];
end

function directory = localDatedDirectory(resultsRoot)
stamp = datestr(now, 'yyyymmdd_HHMMSS');
directory = fullfile(resultsRoot, stamp);
suffix = 1;
while isfolder(directory)
    directory = fullfile(resultsRoot, sprintf('%s_%02d', stamp, suffix));
    suffix = suffix + 1;
end
end

function localSaveFit(result, savePath)
savePath = char(savePath);
parentDirectory = fileparts(savePath);
if ~isempty(parentDirectory) && ~isfolder(parentDirectory)
    mkdir(parentDirectory);
end
temperatureFit = result; %#ok<NASGU>
save(savePath, 'temperatureFit', '-v7');
end

function localWriteConfiguration(filename, configText)
fileIdentifier = fopen(filename, 'w');
if fileIdentifier < 0
    error('grade:ResultsWriteFailed', ...
        'Could not write configuration: %s', filename);
end
cleanup = onCleanup(@() fclose(fileIdentifier)); %#ok<NASGU>
fwrite(fileIdentifier, configText, 'char');
end

function [config, configText, projectRoot] = gradePrivateReadConfiguration(inputConfig)
% Keep configuration validation in one place without exposing a second API.
thisFile = which('grade.fitTemperature');
projectRoot = fileparts(fileparts(fileparts(thisFile)));
if ischar(inputConfig) || (isstring(inputConfig) && isscalar(inputConfig))
    configText = fileread(char(inputConfig));
    config = jsondecode(configText);
elseif isstruct(inputConfig) && isscalar(inputConfig)
    config = inputConfig;
    configText = jsonencode(config);
else
    error('grade:InvalidConfig', ...
        'The calibration configuration must be a JSON file or scalar structure.');
end
end
