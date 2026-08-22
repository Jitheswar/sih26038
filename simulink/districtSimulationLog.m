function varargout = districtSimulationLog(action, varargin)
%DISTRICTSIMULATIONLOG Collect event-level outputs from the SimEvents model.
%   The logger is intentionally small and only records capacity-model events.

persistent state

if nargin == 0
    action = 'snapshot';
end

if strcmp(action, 'reset')
    state = localInitialState();
    varargout = {};
    return
end

if isempty(state)
    state = localInitialState();
end

switch action
    case 'generated'
        state.totalGenerated = state.totalGenerated + 1;
        state.nextPatientId = state.nextPatientId + 1;
        varargout{1} = state.nextPatientId;
    case 'quality'
        failed = logical(varargin{1});
        attempt = double(varargin{2});
        if numel(varargin) >= 3
            maximumAttempts = double(varargin{3});
        else
            maximumAttempts = 2;
        end
        state.totalCaptureAttempts = state.totalCaptureAttempts + 1;
        if attempt > 1
            state.totalRecaptureAttempts = state.totalRecaptureAttempts + 1;
        end
        if failed
            state.failedCaptureAttempts = state.failedCaptureAttempts + 1;
            if attempt > 0 && attempt > maximumAttempts
                state.totalEscalated = state.totalEscalated + 1;
            end
        end
    case 'decision'
        route = double(varargin{1});
        if route == 1
            state.totalAutoCleared = state.totalAutoCleared + 1;
        elseif route == 2
            state.totalReferred = state.totalReferred + 1;
        elseif route == 3
            state.totalEscalated = state.totalEscalated + 1;
            state.totalDeferralEscalations = state.totalDeferralEscalations + 1;
        end
    case 'completed'
        state.totalCompleted = state.totalCompleted + 1;
        turnaround = double(varargin{1});
        state.turnaroundCount = state.turnaroundCount + 1;
        state.turnaroundSeconds(state.turnaroundCount) = turnaround;
        state.graderServiceSeconds(state.turnaroundCount) = double(varargin{2});
    case 'queue'
        queueId = double(varargin{1});
        delta = double(varargin{2});
        now = double(varargin{3});
        index = max(1, min(3, queueId));
        state.queueArea(index) = state.queueArea(index) + ...
            state.queueCurrent(index) * (now - state.queueLastTime(index));
        state.queueCurrent(index) = max(0, state.queueCurrent(index) + delta);
        state.queueMaximum(index) = max(state.queueMaximum(index), ...
            state.queueCurrent(index));
        state.queueLastTime(index) = now;
        state.queueTraceCount(index) = state.queueTraceCount(index) + 1;
        traceIndex = state.queueTraceCount(index);
        if traceIndex <= size(state.queueTraceTime, 2)
            state.queueTraceTime(index, traceIndex) = now;
            state.queueTraceValue(index, traceIndex) = state.queueCurrent(index);
        end
    case 'snapshot'
        now = double(varargin{1});
        for index = 1:3
            state.queueArea(index) = state.queueArea(index) + ...
                state.queueCurrent(index) * (now - state.queueLastTime(index));
            state.queueLastTime(index) = now;
        end
        varargout{1} = state;
    otherwise
        error('districtSimulationLog:UnknownAction', 'Unknown action: %s.', action);
end
end

function state = localInitialState()
state = struct();
state.nextPatientId = 0;
state.totalGenerated = 0;
state.totalCompleted = 0;
state.totalAutoCleared = 0;
state.totalReferred = 0;
state.totalEscalated = 0;
state.totalDeferralEscalations = 0;
state.totalCaptureAttempts = 0;
state.totalRecaptureAttempts = 0;
state.failedCaptureAttempts = 0;
state.turnaroundCount = 0;
state.turnaroundSeconds = zeros(1, 1000000);
state.graderServiceSeconds = zeros(1, 1000000);
state.queueCurrent = zeros(1, 3);
state.queueMaximum = zeros(1, 3);
state.queueArea = zeros(1, 3);
state.queueLastTime = zeros(1, 3);
state.queueTraceCount = zeros(1, 3);
state.queueTraceTime = zeros(3, 1000000);
state.queueTraceValue = zeros(3, 1000000);
end
