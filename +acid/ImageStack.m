classdef (Abstract) ImageStack
    properties (Abstract,GetAccess=public,SetAccess=protected) % TODO : or immutable?
        Height
        Width
        NumberOfSamples
        NumberOfFrames
    end
end