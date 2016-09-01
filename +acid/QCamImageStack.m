classdef QCamImageStack < acid.ImageStack
    properties (GetAccess=public,SetAccess=protected)
        Height
        Width
        NumberOfSamples
        NumberOfFrames
    end
    
    properties (Access=protected)
        FileNames
        FileHandles
        FileHeaders
        FramesPerFile
        CumulativeFramesPerFile
    end
    
    methods
        function obj = QCamImageStack(files)
            assert(ischar(files) || iscellstr(files),'acid:QCamImageStack:BadConstructorInput','QCamImageStack needs a list of files.')
            
            if ischar(files)
                files = {files};
            end
            
            obj.FileNames = files;
            obj.FileHandles = cellfun(@fopen,files);
            obj.FileHeaders = arrayfun(@parseQCamHeader,obj.FileHandles);
            
            obj.Height = unique(cellfun(@(r) r(4)-r(2),{obj.FileHeaders.ROI}));
            
            assert(isscalar(obj.Height),'acid:ImageStack:MismatchedInputFiles','All images must have the same height');
            
            obj.Width = unique(cellfun(@(r) r(3)-r(1),{obj.FileHeaders.ROI}));
            
            assert(isscalar(obj.Width),'acid:ImageStack:MismatchedInputFiles','All images must have the same width');
            
            obj.NumberOfSamples = 1;
            
            arrayfun(@(fin) fseek(fin,0,1),obj.FileHandles);
            
            obj.FramesPerFile = arrayfun(@(fin,header) (ftell(fin)-header.FixedHeaderSize)/header.FrameSize,obj.FileHandles,obj.FileHeaders);
            
            obj.CumulativeFramesPerFile = [0 cumsum(obj.FramesPerFile)];
            
            obj.NumberOfFrames = sum(obj.FramesPerFile);
        end
    end
end