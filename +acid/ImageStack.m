classdef (Abstract) ImageStack
    properties (Abstract)
        Height
        Width
        NumberOfSamples
        NumberOfFrames
    end
end