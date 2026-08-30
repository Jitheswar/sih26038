function summary = lesionThresholdTransfer(varargin)
%LESIONTHRESHOLDTRANSFER Re-select lesion operating thresholds on APTOS.
%   SUMMARY = lesionThresholdTransfer() runs the trained Track B lesion
%   network over the APTOS calibration split, records how many lesions of
%   each type survive at every threshold on a grid, and searches that grid
%   for the per-type thresholds that best separate referable from
%   non-referable cases through the ICDR rules.
%
%   Why this exists.  The thresholds currently shipped in the checkpoint
%   were selected to maximise PIXEL F1 on the IDRiD validation split
%   (§6.4), and §11.7 measured what happens when they are applied to APTOS:
%   ten of ten frames were called referable, including all five healthy
%   eyes, for a channel specificity of 0.00.  §11.7 names two compounding
%   causes.  A probability threshold does not carry across a distribution
%   shift, and the ICDR criteria are written on counts, so a channel that
%   is merely noisy converts directly into a severity level.
%
%   What this changes.  The first cause is addressable and has never been
%   tested: nobody has asked whether ANY threshold set separates the two
%   classes on APTOS.  The §11.7 measurement rests on ten frames.  This
%   runs 365.
%
%   Split discipline (§10.2).  Thresholds are selected on the CALIBRATION
%   split and nowhere else.  That split exists to fit operating parameters
%   after training, which is what §7.6 already does with temperature; a
%   second operating parameter is the same use.  Validation stays clean for
%   the read-out, the test split is touched once, and the sealed set is not
%   touched at all.  Pass 'Split','validation' only to read out a threshold
%   set that was already chosen on calibration.
%
%   Honest outcomes.  Three are possible and all three are results.  A
%   threshold set separates, and the learned channel becomes usable
%   evidence.  None does, and the finding is that thresholding is not the
%   remedy - the count-based rule needs a notion of lesion burden rather
%   than presence, measured over 365 frames instead of ten.  Or only the
%   strong heads transfer, which the per-type sweep shows directly.
%
%   Name-value arguments:
%     'Split'       split name, default 'calibration'
%     'Limit'       cap on images, default Inf (use a small value to time it)
%     'Config'      configuration file, default config/default.json
%     'Checkpoint'  lesion checkpoint, default the one named by the config
%     'Grid'        candidate thresholds, default dense above 0.4
%     'Rounds'      coordinate-search passes, default 3
%
%   See also segment.countLesionType, grade.icdrRule, eval/ablationHarness.

parser = inputParser();
parser.addParameter('Split', 'calibration');
parser.addParameter('Limit', Inf);
parser.addParameter('Config', '');
parser.addParameter('Checkpoint', '');
parser.addParameter('Grid', []);
parser.addParameter('Rounds', 3);
parser.addParameter('Cache', '');
parser.addParameter('Heads', {});
parser.addParameter('FixedThresholds', []);
parser.parse(varargin{:});
options = parser.Results;

projectRoot = localProjectRoot();

configPath = options.Config;
if isempty(configPath)
    configPath = fullfile(projectRoot, 'config', 'default.json');
end
config = jsondecode(fileread(configPath));

% §13.2: every entry point seeds, or its result is not a result.
seed = 42;
if isfield(config, 'grading') && isfield(config.grading, 'seed')
    seed = config.grading.seed;
end
rng(seed, 'twister');

checkpointPath = options.Checkpoint;
if isempty(checkpointPath)
    checkpointPath = localLesionCheckpoint(config, projectRoot);
end

grid = options.Grid;
if isempty(grid)
    % Dense above 0.4 because the measured failure is over-detection, so the
    % informative direction is upward from the shipped thresholds
    % [0.031 0.438 0.375 0.969].  A grid that stopped at 0.9 could not
    % express the soft-exudate threshold the checkpoint already uses.
    grid = [0.05 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 ...
        0.85 0.90 0.95 0.975 0.99];
end
grid = sort(double(grid(:)'));

split = localReadSplit(projectRoot, options.Split, options.Limit);
imageCount = numel(split.files);

model = load(checkpointPath);
lesionTypes = model.config.lesion_segmentation.lesion_types;
if ischar(lesionTypes)
    lesionTypes = {lesionTypes};
end
typeCount = numel(lesionTypes);
shippedThresholds = double(model.validation.bestF1Threshold(:))';

fprintf('Lesion threshold transfer on the %s split: %d images.\n', ...
    options.Split, imageCount);
fprintf('Checkpoint: %s\n', checkpointPath);
fprintf('Shipped IDRiD thresholds: %s\n', mat2str(shippedThresholds, 4));
fprintf('Grid: %s\n', mat2str(grid, 4));
fprintf('Referable is ICDR grade >= 2. Selection split: %s.\n\n', options.Split);

if isempty(options.Cache)
    [counts, quadrantCounts, grades, failedCount] = ...
        localRunInferencePass(split, model, lesionTypes, grid);
else
    % The inference pass is the only expensive part and its output does not
    % depend on any selection choice, so a cached pass is replayed rather
    % than repeated. This is what makes the head-subset study free.
    fprintf('Replaying cached inference pass: %s\n', options.Cache);
    [counts, quadrantCounts, grades, grid, lesionTypes] = ...
        localLoadCache(options.Cache);
    typeCount = numel(lesionTypes);
    failedCount = 0;
end

actualReferable = grades >= 2;
scoredCount = numel(grades);
gridCount = numel(grid);

% Per-type sweep: hold every other type at its shipped threshold and move
% one. This is what shows whether a single head carries the channel, and it
% is reported whatever the joint search finds.
perType = struct('lesionType', {}, 'threshold', {}, 'sensitivity', {}, ...
    'specificity', {}, 'youden', {});
shippedIndices = localNearestGridIndex(shippedThresholds, grid);
activeHeads = localActiveHeads(options.Heads, lesionTypes);
if ~all(activeHeads)
    fprintf('Active heads: %s (others are declared capability gaps)\n\n', ...
        strjoin(lesionTypes(activeHeads), '+'));
end
for typeIndex = 1:typeCount
    for gridIndex = 1:gridCount
        candidate = shippedIndices;
        candidate(typeIndex) = gridIndex;
        [sensitivity, specificity] = localScore(candidate, counts, ...
            quadrantCounts, lesionTypes, actualReferable);
        perType(end + 1) = struct('lesionType', lesionTypes{typeIndex}, ...
            'threshold', grid(gridIndex), 'sensitivity', sensitivity, ...
            'specificity', specificity, ...
            'youden', sensitivity + specificity - 1); %#ok<AGROW>
    end
end

% Coordinate-wise search from the shipped thresholds. Not exhaustive: the
% full grid is 14^4 combinations and each one scores every image, so the
% search is reported as coordinate-wise rather than dressed up as optimal.
readOut = ~isempty(options.FixedThresholds);
if readOut
    % A read-out scores a configuration selected on another split and must
    % not search here. Selecting on the split you report is how a held-out
    % number stops being held out (§10.2, §11.1).
    fixed = double(options.FixedThresholds(:))';
    if numel(fixed) ~= typeCount
        error('eval:InvalidFixedThresholds', ...
            'FixedThresholds needs one entry per lesion type (%d).', typeCount);
    end
    % The cached counts are indexed by grid position, so the grid cannot be
    % extended here. Requiring an exact grid member refuses to silently
    % snap a requested threshold to a neighbour and report the neighbour's
    % number as though it were the requested one.
    current = localNearestGridIndex(fixed, grid);
    offGrid = abs(grid(current) - fixed) > 1e-9;
    if any(offGrid)
        error('eval:FixedThresholdOffGrid', ...
            ['FixedThresholds %s are not on the grid %s. Pass them in ' ...
            '''Grid'' as well so the cached counts cover them.'], ...
            mat2str(fixed(offGrid), 4), mat2str(grid, 4));
    end
    fprintf(['\nRead-out mode: scoring fixed thresholds %s, no search on ' ...
        'this split.\n'], mat2str(fixed, 4));
else
    current = localSearch(shippedIndices, grid, counts, quadrantCounts, ...
        lesionTypes, actualReferable, activeHeads, options.Rounds, true);
end

selectedThresholds = grid(current);
predictedLevels = localPredictedLevels(current, counts, quadrantCounts, ...
    lesionTypes, activeHeads);
shippedLevels = localPredictedLevels(shippedIndices, counts, ...
    quadrantCounts, lesionTypes, true(1, typeCount));

selectedMetrics = referableMetrics(grades, predictedLevels);
shippedMetrics = referableMetrics(grades, shippedLevels);

summary = struct();
summary.split = options.Split;
summary.imageCount = scoredCount;
summary.failedCount = failedCount;
summary.referableCount = sum(actualReferable);
summary.grid = grid;
summary.lesionTypes = lesionTypes;
summary.shippedThresholds = shippedThresholds;
summary.selectedThresholds = selectedThresholds;
summary.shippedMetrics = shippedMetrics;
summary.selectedMetrics = selectedMetrics;
summary.perTypeSweep = perType;
summary.checkpoint = checkpointPath;
summary.seed = seed;

% Head-subset study. The separation diagnostic shows that a single weak head
% can cap the whole channel, because ICDR Level 2 fires on the PRESENCE of
% any non-microaneurysm finding: the channel ORs its heads together, so its
% specificity is bounded by the worst of them. That makes "which heads
% should the channel use" a real question and not a tuning detail, and the
% cached counts answer it without another inference pass.
headStudy = struct('heads', {}, 'thresholds', {}, 'sensitivity', {}, ...
    'specificity', {}, 'youden', {});
if ~readOut
fprintf('\n===== Head-subset study =====\n');
subsets = localHeadSubsets(typeCount);
headStudy = struct('heads', {}, 'thresholds', {}, 'sensitivity', {}, ...
    'specificity', {}, 'youden', {});
for subsetIndex = 1:size(subsets, 1)
    activeMask = subsets(subsetIndex, :);
    [subsetIndices, subsetSensitivity, subsetSpecificity] = ...
        localSearch(shippedIndices, grid, counts, quadrantCounts, ...
        lesionTypes, actualReferable, activeMask, options.Rounds);
    headStudy(end + 1) = struct( ...
        'heads', strjoin(lesionTypes(activeMask), '+'), ...
        'thresholds', grid(subsetIndices) .* activeMask, ...
        'sensitivity', subsetSensitivity, ...
        'specificity', subsetSpecificity, ...
        'youden', subsetSensitivity + subsetSpecificity - 1); %#ok<AGROW>
end
[~, order] = sort([headStudy.youden], 'descend');
headStudy = headStudy(order);
localReportHeadStudy(headStudy);
end
summary.headStudy = headStudy;
summary.readOut = readOut;
summary.activeHeads = lesionTypes(activeHeads);

% The separation diagnostic answers the question the search cannot: if no
% threshold set works, is that because the counts of the two classes
% overlap, or because the rule converts any non-zero count into Level 2?
% Level 2 fires on presence, so a healthy eye is only ever called clear
% when its non-microaneurysm counts reach exactly zero. The clearedFraction
% column is therefore the ceiling on this channel's specificity, per type.
separation = localSeparation(counts, quadrantCounts, lesionTypes, grid, ...
    actualReferable);
summary.separation = separation;

resultsDir = localNewResultsDirectory(projectRoot, options.Split);
save(fullfile(resultsDir, 'threshold_transfer.mat'), 'summary', 'counts', ...
    'quadrantCounts', 'grades', 'grid', 'lesionTypes', '-v7.3');
copyfile(configPath, fullfile(resultsDir, 'config.json'));
localWriteSweepTable(fullfile(resultsDir, 'per_type_sweep.csv'), perType);
localWriteSeparationTable(fullfile(resultsDir, 'separation.csv'), separation);
localWriteHeadStudyTable(fullfile(resultsDir, 'head_study.csv'), headStudy);

localReport(shippedThresholds, shippedMetrics, selectedThresholds, ...
    selectedMetrics, scoredCount, sum(actualReferable), options.Split, readOut);
localReportSeparation(separation, lesionTypes);
fprintf('\nResults written to %s\n', resultsDir);
end


function separation = localSeparation(counts, quadrantCounts, lesionTypes, ...
    grid, actualReferable)
%LOCALSEPARATION Can any threshold clear a healthy eye, and at what cost?
%   For each lesion type and threshold this records the fraction of
%   non-referable images whose count falls to zero (the specificity ceiling
%   this type can contribute) and the fraction of referable images that
%   still show something (the sensitivity that survives at the same point).
separation = struct('lesionType', {}, 'threshold', {}, ...
    'clearedFraction', {}, 'retainedFraction', {}, ...
    'medianHealthyCount', {}, 'medianReferableCount', {});
for typeIndex = 1:numel(lesionTypes)
    for gridIndex = 1:numel(grid)
        typeCounts = counts(:, typeIndex, gridIndex);
        healthy = typeCounts(~actualReferable);
        referable = typeCounts(actualReferable);
        separation(end + 1) = struct( ...
            'lesionType', lesionTypes{typeIndex}, ...
            'threshold', grid(gridIndex), ...
            'clearedFraction', mean(healthy == 0), ...
            'retainedFraction', mean(referable > 0), ...
            'medianHealthyCount', median(healthy), ...
            'medianReferableCount', median(referable)); %#ok<AGROW>
    end
end
end


function localWriteSeparationTable(path, separation)
fid = fopen(path, 'w');
closer = onCleanup(@() fclose(fid));
fprintf(fid, ['lesion_type,threshold,cleared_fraction,retained_fraction,' ...
    'median_healthy_count,median_referable_count\n']);
for index = 1:numel(separation)
    fprintf(fid, '%s,%.4f,%.6f,%.6f,%.2f,%.2f\n', ...
        separation(index).lesionType, separation(index).threshold, ...
        separation(index).clearedFraction, separation(index).retainedFraction, ...
        separation(index).medianHealthyCount, ...
        separation(index).medianReferableCount);
end
end


function localReportSeparation(separation, lesionTypes)
fprintf('\n===== Separation diagnostic =====\n');
fprintf(['Level 2 fires on presence, so a healthy eye is called clear only ' ...
    'when its\ncount reaches zero. "cleared" is the fraction of ' ...
    'non-referable images at zero,\nwhich is the specificity ceiling this ' ...
    'type can contribute on its own;\n"retained" is the fraction of ' ...
    'referable images still showing something.\n\n']);
fprintf('%-6s %-10s %-10s %-10s %-14s %-14s\n', 'Type', 'Threshold', ...
    'cleared', 'retained', 'med healthy', 'med referable');
for typeIndex = 1:numel(lesionTypes)
    rows = separation(strcmp({separation.lesionType}, lesionTypes{typeIndex}));
    for index = 1:numel(rows)
        fprintf('%-6s %-10.4f %-10.4f %-10.4f %-14.1f %-14.1f\n', ...
            rows(index).lesionType, rows(index).threshold, ...
            rows(index).clearedFraction, rows(index).retainedFraction, ...
            rows(index).medianHealthyCount, rows(index).medianReferableCount);
    end
    fprintf('\n');
end
end


function [current, bestSensitivity, bestSpecificity] = localSearch( ...
    startIndices, grid, counts, quadrantCounts, lesionTypes, ...
    actualReferable, activeMask, rounds, verbose)
%LOCALSEARCH Coordinate-wise threshold search over the active heads only.
%   Not exhaustive: the full grid is 14^4 combinations and each one scores
%   every image, so this moves one head at a time from the shipped
%   thresholds and is reported as coordinate-wise rather than dressed up as
%   optimal. Inactive heads keep their start index and are never scored,
%   because localPredictedLevels drops them from the evidence entirely.
if nargin < 9
    verbose = false;
end
gridCount = numel(grid);
current = startIndices;
[bestSensitivity, bestSpecificity] = localScore(current, counts, ...
    quadrantCounts, lesionTypes, actualReferable, activeMask);
bestYouden = bestSensitivity + bestSpecificity - 1;
activeIndices = find(activeMask);

for searchRound = 1:rounds
    improved = false;
    for position = 1:numel(activeIndices)
        for gridIndex = 1:gridCount
            candidate = current;
            candidate(activeIndices(position)) = gridIndex;
            [sensitivity, specificity] = localScore(candidate, counts, ...
                quadrantCounts, lesionTypes, actualReferable, activeMask);
            youden = sensitivity + specificity - 1;
            if youden > bestYouden + 1e-12
                bestYouden = youden;
                bestSensitivity = sensitivity;
                bestSpecificity = specificity;
                current = candidate;
                improved = true;
            end
        end
    end
    if verbose
        fprintf('Search round %d: Youden J %.4f at %s\n', searchRound, ...
            bestYouden, mat2str(grid(current), 4));
    end
    if ~improved
        break;
    end
end
end


function [counts, quadrantCounts, grades, failedCount] = ...
    localRunInferencePass(split, model, lesionTypes, grid)
%LOCALRUNINFERENCEPASS Segment every frame once, count at every threshold.
%   The network runs once per image and its probability maps are then
%   thresholded across the whole grid before being discarded. Retaining the
%   maps instead would cost gigabytes, and re-running inference once per
%   candidate threshold would cost hours; the counts are a few hundred bytes
%   per image and are all any later selection step reads.
imageCount = numel(split.files);
typeCount = numel(lesionTypes);
gridCount = numel(grid);
counts = nan(imageCount, typeCount, gridCount);
quadrantCounts = nan(imageCount, gridCount, 4);
failed = false(imageCount, 1);
minimumArea = segment.defaultLesionMinimumArea(lesionTypes);
haemorrhageIndex = find(strcmp('HE', lesionTypes), 1);

startTime = tic();
for index = 1:imageCount
    try
        image = imread(char(split.files(index)));
        prediction = segment.segmentLesions(image, model);
        imageSize = prediction.imageSize;

        for typeIndex = 1:typeCount
            probabilityMap = prediction.probabilityMaps(:, :, typeIndex);
            for gridIndex = 1:gridCount
                [count, centroids] = segment.countLesionType( ...
                    probabilityMap, grid(gridIndex), minimumArea(typeIndex));
                counts(index, typeIndex, gridIndex) = count;

                % ICDR Level 3 is a per-quadrant haemorrhage criterion, so
                % the haemorrhage head needs its counts split by quadrant at
                % every threshold, not just a total (§3.3).
                if typeIndex == haemorrhageIndex
                    [~, quadrants] = segment.assignQuadrants(centroids, ...
                        struct(), imageSize);
                    quadrantCounts(index, gridIndex, :) = [quadrants.ST, ...
                        quadrants.IT, quadrants.SN, quadrants.IN];
                end
            end
        end
    catch caught
        failed(index) = true;
        fprintf('  image %d failed: %s\n', index, caught.message);
    end

    if mod(index, 25) == 0 || index == imageCount
        elapsed = toc(startTime);
        fprintf('  %d/%d (%d%%), %.1f s elapsed, %.1f s/image\n', index, ...
            imageCount, round(100 * index / imageCount), elapsed, ...
            elapsed / index);
    end
end

keep = ~failed;
failedCount = sum(failed);
fprintf('\nInference pass complete: %d scored, %d failed.\n', sum(keep), ...
    failedCount);

grades = split.grades(keep);
counts = counts(keep, :, :);
quadrantCounts = quadrantCounts(keep, :, :);
end


function [counts, quadrantCounts, grades, grid, lesionTypes] = ...
    localLoadCache(cachePath)
%LOCALLOADCACHE Replay the counts saved by an earlier inference pass.
cached = load(cachePath, 'counts', 'quadrantCounts', 'grades', 'grid', ...
    'lesionTypes');
counts = cached.counts;
quadrantCounts = cached.quadrantCounts;
grades = cached.grades;
grid = cached.grid;
lesionTypes = cached.lesionTypes;
end


function activeHeads = localActiveHeads(requested, lesionTypes)
%LOCALACTIVEHEADS Which lesion heads supply evidence. Default: all of them.
if isempty(requested)
    activeHeads = true(1, numel(lesionTypes));
    return;
end
if ischar(requested)
    requested = {requested};
end
activeHeads = ismember(lesionTypes(:)', requested(:)');
if ~any(activeHeads)
    error('eval:NoActiveHeads', ...
        'None of the requested heads (%s) exist in the checkpoint (%s).', ...
        strjoin(requested, ','), strjoin(lesionTypes, ','));
end
end


function subsets = localHeadSubsets(typeCount)
%LOCALHEADSUBSETS Every non-empty combination of lesion heads.
combinations = dec2bin(1:(2^typeCount - 1)) - '0';
subsets = logical(combinations);
end


function localReportHeadStudy(headStudy)
fprintf(['Each row switches a set of heads on and searches thresholds for ' ...
    'that set alone.\nA head that is off is a declared capability gap, ' ...
    'not a per-case unknown (§8.5).\n\n']);
fprintf('%-14s %-10s %-12s %-12s %s\n', 'Heads', 'Youden J', ...
    'Sensitivity', 'Specificity', 'Thresholds');
for index = 1:numel(headStudy)
    fprintf('%-14s %-10.4f %-12.4f %-12.4f %s\n', ...
        headStudy(index).heads, headStudy(index).youden, ...
        headStudy(index).sensitivity, headStudy(index).specificity, ...
        mat2str(headStudy(index).thresholds, 4));
end
end


function localWriteHeadStudyTable(path, headStudy)
fid = fopen(path, 'w');
closer = onCleanup(@() fclose(fid));
fprintf(fid, 'heads,sensitivity,specificity,youden,thresholds\n');
for index = 1:numel(headStudy)
    fprintf(fid, '%s,%.6f,%.6f,%.6f,%s\n', headStudy(index).heads, ...
        headStudy(index).sensitivity, headStudy(index).specificity, ...
        headStudy(index).youden, ...
        strrep(mat2str(headStudy(index).thresholds, 4), ',', ' '));
end
end


function [sensitivity, specificity] = localScore(gridIndices, counts, ...
    quadrantCounts, lesionTypes, actualReferable, activeMask)
%LOCALSCORE Sensitivity and specificity of one candidate threshold set.
if nargin < 6
    activeMask = [];
end
levels = localPredictedLevels(gridIndices, counts, quadrantCounts, ...
    lesionTypes, activeMask);
predictedReferable = levels >= 2;
positive = sum(actualReferable);
negative = sum(~actualReferable);
sensitivity = sum(actualReferable & predictedReferable) / positive;
specificity = sum(~actualReferable & ~predictedReferable) / negative;
end


function levels = localPredictedLevels(gridIndices, counts, quadrantCounts, ...
    lesionTypes, activeMask)
%LOCALPREDICTEDLEVELS Run the cached counts through the real ICDR rules.
%   The counts are replayed through grade.icdrEvidenceFromLesionSegmentation
%   and grade.icdrRule rather than re-deciding a level here, because §8.5
%   puts the rule engine in exactly one place and a sweep that reimplemented
%   the criteria would be measuring its own copy of them.
imageCount = size(counts, 1);
typeCount = numel(lesionTypes);
levels = zeros(imageCount, 1);
if nargin < 5 || isempty(activeMask)
    activeMask = true(1, typeCount);
end

% A head that is switched off is not reported as a per-case unknown, it is
% simply absent from lesionTypes. grade.icdrEvidenceFromLesionSegmentation
% then marks its field as a capability gap, which is the distinction §8.5
% depends on: a permanent gap must not escalate every patient the way a
% per-case unknown does.
activeTypes = lesionTypes(activeMask);
activeIndices = find(activeMask);
haemorrhageIndex = find(strcmp('HE', lesionTypes), 1);
haemorrhageActive = ~isempty(haemorrhageIndex) && activeMask(haemorrhageIndex);

for index = 1:imageCount
    typeCounts = struct();
    for position = 1:numel(activeIndices)
        typeIndex = activeIndices(position);
        typeCounts.(lesionTypes{typeIndex}) = ...
            counts(index, typeIndex, gridIndices(typeIndex));
    end

    evidence = struct('lesionTypes', {activeTypes}, 'counts', typeCounts);
    if haemorrhageActive
        quadrants = quadrantCounts(index, gridIndices(haemorrhageIndex), :);
        evidence.haemorrhageQuadrantCounts = struct( ...
            'ST', quadrants(1), 'IT', quadrants(2), ...
            'SN', quadrants(3), 'IN', quadrants(4));
    end

    rule = grade.icdrRule( ...
        grade.icdrEvidenceFromLesionSegmentation(evidence));
    levels(index) = rule.level;
end
end


function indices = localNearestGridIndex(thresholds, grid)
indices = zeros(1, numel(thresholds));
for index = 1:numel(thresholds)
    [~, indices(index)] = min(abs(grid - thresholds(index)));
end
end


function split = localReadSplit(projectRoot, splitName, limit)
if strcmpi(splitName, 'sealed')
    error('eval:SealedSplitRefused', ...
        ['The sealed external set is opened once by the human key-holder ' ...
        'after the operating point is frozen (§10.4), never by a sweep.']);
end
splitFile = fullfile(projectRoot, 'data', 'splits', [splitName '.csv']);
if ~isfile(splitFile)
    error('eval:MissingSplit', 'Split file does not exist: %s', splitFile);
end
tableData = readtable(splitFile, 'TextType', 'string');
relativePaths = string(tableData.relative_path);
split.grades = double(tableData.grade);
split.files = fullfile(projectRoot, relativePaths);
if isfinite(limit) && limit < numel(split.files)
    split.files = split.files(1:limit);
    split.grades = split.grades(1:limit);
end
end


function checkpointPath = localLesionCheckpoint(config, projectRoot)
if ~isfield(config, 'lesion_segmentation') || ...
        ~isfield(config.lesion_segmentation, 'checkpoint') || ...
        isempty(config.lesion_segmentation.checkpoint)
    error('eval:MissingLesionCheckpoint', ...
        'lesion_segmentation.checkpoint is not set in the configuration.');
end
checkpointPath = char(config.lesion_segmentation.checkpoint);
if ~isfile(checkpointPath)
    checkpointPath = fullfile(projectRoot, checkpointPath);
end
if ~isfile(checkpointPath)
    error('eval:MissingLesionCheckpoint', ...
        'Lesion checkpoint does not exist: %s', checkpointPath);
end
end


function resultsDir = localNewResultsDirectory(projectRoot, splitName)
resultsDir = fullfile(projectRoot, 'results', ...
    sprintf('%s_threshold_transfer_%s', ...
    datestr(now, 'yyyymmdd_HHMMSS'), splitName)); %#ok<TNOW1,DATST>
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end
end


function localWriteSweepTable(path, perType)
fid = fopen(path, 'w');
closer = onCleanup(@() fclose(fid));
fprintf(fid, 'lesion_type,threshold,sensitivity,specificity,youden\n');
for index = 1:numel(perType)
    fprintf(fid, '%s,%.4f,%.6f,%.6f,%.6f\n', perType(index).lesionType, ...
        perType(index).threshold, perType(index).sensitivity, ...
        perType(index).specificity, perType(index).youden);
end
end


function localReport(shippedThresholds, shippedMetrics, selectedThresholds, ...
    selectedMetrics, imageCount, referableCount, splitName, readOut)
fprintf('\n===== Lesion evidence channel on the %s split =====\n', splitName);
fprintf('n = %d (%d referable, %d not referable)\n', imageCount, ...
    referableCount, imageCount - referableCount);
fprintf('\n%-28s %-10s %-24s %-24s\n', 'Thresholds', 'Youden J', ...
    'Sensitivity (95% Wilson)', 'Specificity (95% Wilson)');
localReportRow('IDRiD-selected (shipped)', shippedThresholds, shippedMetrics);
localReportRow('APTOS-selected', selectedThresholds, selectedMetrics);
fprintf(['\nSensitivity and specificity are reported rather than accuracy ' ...
    '(§11.1).\n']);
if readOut
    fprintf(['These thresholds were selected on another split and only ' ...
        'scored here,\nso this row is a held-out read-out.\n']);
else
    fprintf(['The thresholds above were selected on this split, so these ' ...
        'are\nselection numbers and not a held-out read-out.\n']);
end
end


function localReportRow(label, thresholds, metrics)
fprintf('%-28s %-10.4f %.4f (%.4f-%.4f)     %.4f (%.4f-%.4f)\n', label, ...
    metrics.sensitivity + metrics.specificity - 1, ...
    metrics.sensitivity, metrics.sensitivityCILower, metrics.sensitivityCIUpper, ...
    metrics.specificity, metrics.specificityCILower, metrics.specificityCIUpper);
fprintf('  %s\n', mat2str(thresholds, 4));
end


function projectRoot = localProjectRoot()
projectRoot = fileparts(fileparts(mfilename('fullpath')));
end
