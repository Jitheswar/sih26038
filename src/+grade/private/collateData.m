function [images, targets] = collateData(imageCells, targetCells)
%COLLATEDATA Concatenate lazy image records into a CNN mini-batch.

if iscell(imageCells)
    images = cat(4, imageCells{:});
else
    images = imageCells;
end

if iscell(targetCells)
    targets = reshape(single(cell2mat(targetCells)), 1, []);
else
    targets = reshape(single(targetCells), 1, []);
end
end
