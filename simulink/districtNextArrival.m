function dt = districtNextArrival(configOrAction, modeCode, multiplier)
%DISTRICTNEXTARRIVAL Return the next configured event-calendar interarrival time.

persistent elapsedSeconds

if (ischar(configOrAction) || isstring(configOrAction)) && strcmp(configOrAction, 'reset')
    elapsedSeconds = 0;
    dt = [];
    return
end

if isempty(elapsedSeconds)
    elapsedSeconds = 0;
end

baseRate = double(configOrAction);
if baseRate <= 0
    error('districtNextArrival:InvalidRate', 'arrivalRate must be positive.');
end

if nargin >= 2 && double(modeCode) > 0
    cycle = 7 * 86400;
    campDay = 86400;
    multiplier = double(multiplier);
    if multiplier >= 7
        error('districtNextArrival:InvalidMultiplier', ...
            'campBurstMultiplier must be below seven for volume preservation.');
    end
    phase = mod(elapsedSeconds, cycle);
    if phase < campDay
        rate = baseRate * multiplier;
    else
        offCampRate = baseRate * (7 - multiplier) / 6;
        rate = offCampRate;
    end
else
    rate = baseRate;
end

dt = 1 / rate;
elapsedSeconds = elapsedSeconds + dt;
end
