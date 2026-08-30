function normalised = normaliseLesionPatch(patch)
%NORMALISELESIONPATCH Scale a native-resolution lesion patch for the network.
%   NORMALISED = normaliseLesionPatch(PATCH) maps uint8 pixels to single in
%   [0, 1].
%
%   Both segment.trainLesionSegmentation and segment.segmentLesions call
%   this, and nothing else may normalise a lesion patch.  The hard rule in
%   §5.4 exists because enhancement applied at inference but not at training
%   is self-inflicted domain shift that no metric reports; the rule binds
%   here for the same reason even though the function cannot be
%   common.preprocess itself.  common.preprocess resizes a whole frame to
%   the 448x448 grading input, and §6.4 forbids resizing a lesion patch at
%   all - the resize is precisely what destroys the microaneurysms this
%   network is being trained to find.

if isinteger(patch)
    normalised = single(patch) / 255;
elseif islogical(patch)
    normalised = single(patch);
else
    normalised = single(patch);
end
end
