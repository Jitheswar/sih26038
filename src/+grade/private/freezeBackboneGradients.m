function gradients = freezeBackboneGradients(gradients)
%FREEZEBACKBONEGRADIENTS Keep smoke training focused on the new output head.

for index = 1:height(gradients)
    if string(gradients.Layer(index)) ~= "fc1000"
        value = gradients.Value{index};
        data = extractdata(value);
        gradients.Value{index} = dlarray(zeros(size(data), 'like', data), dims(value));
    end
end
end
