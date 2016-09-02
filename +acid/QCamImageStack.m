classdef QCamImageStack < acid.ImageStack
    properties (Access=protected)
        FileNames
        FileHandles
        FileHeaders
        FramesPerFile
        CumulativeFramesPerFile
    end
    
    methods (Access=public)
        function obj = QCamImageStack(files)
            assert(ischar(files) || iscellstr(files),'acid:QCamImageStack:BadConstructorInput','QCamImageStack needs a list of files.')
            
            if ischar(files)
                files = {files};
            end
            
            fileHandles = cellfun(@fopen,files);
            fileHeaders = arrayfun(@parseQCamHeader,fileHandles);
            
            height = unique(cellfun(@(r) r(4)-r(2),{fileHeaders.ROI}));
            
            assert(isscalar(height),'acid:ImageStack:MismatchedInputFiles','All images must have the same height');
            
            width = unique(cellfun(@(r) r(3)-r(1),{fileHeaders.ROI}));
            
            assert(isscalar(width),'acid:ImageStack:MismatchedInputFiles','All images must have the same width');
            
            numberOfSamples = 1;
            
            arrayfun(@(fin) fseek(fin,0,1),fileHandles);
            
            framesPerFile = arrayfun(@(fin,header) (ftell(fin)-header.FixedHeaderSize)/header.FrameSize,fileHandles,fileHeaders);
            
            numberOfFrames = sum(framesPerFile);
            
            obj = obj@acid.ImageStack(height,width,numberOfSamples,numberOfFrames);
            
            obj.CumulativeFramesPerFile = [0 cumsum(framesPerFile)];
            obj.FileNames = files;
            obj.FileHandles = fileHandles;
            obj.FileHeaders = fileHeaders;
        end
    end
       
    methods (Access=protected)
        function data = subsref_(obj,subs)
            % TODO : profile all this checking
            assert(numel(subs) == 1,'acid:ImageStack:CompoundIndexingNotSupported','Compound indexing a QCamImageStack is not supported unless the first index is a ''.''-type indexing operation');
                
            assert(subs.type(1) == '(' && subs.type(2) == ')','acid:ImageStack:BadIndexingOperation','Only dot and simple array indexing are supported for QCamImageStack objects');
            
            % TODO : a lot of this checking can probably be moved up into
            % the superclass, but in a helper method as it only makes sense
            % if we're doing a simple ()-type operation
            subs = subs.subs;
            
            toCheck = 1:numel(subs);
            subs(1,end+1:4) = num2cell(ones(1,4-numel(subs)));
            
            colonSubs = find(cellfun(@(s) ischar(s) && strcmp(s,':'),subs(toCheck)));
            subs(colonSubs) = arrayfun(@(ii) 1:size(obj,ii),colonSubs,'UniformOutput',false);
            
            toCheck = setdiff(toCheck,colonSubs);
            
            assert(all(cellfun(@(s) isnumeric(s) && all(isreal(s(:)) & isfinite(s(:)) & s(:) > 0 & round(s(:)) == s(:)),subs(toCheck))),'acid:ImageStack:BadIndexingOperation','ImageStack array indexes must real positive integers');
            
            assert(all(arrayfun(@(ii) all(subs{ii}(:) <= size(obj,ii)),toCheck)),'acid:ImageStack:BadIndexingOperation','Index exceeds image stack dimensions');
            
            data = zeros(cellfun(@numel,subs));
            
            frames = subs{4};
            
            for ii = 1:numel(frames)
                frame = frames(ii);
                
                cumulativeFramesPerFile = builtin('subsref',obj,substruct('.','CumulativeFramesPerFile'));
                fileIndex = find(frame > cumulativeFramesPerFile,1,'last');
                fin = builtin('subsref',obj,substruct('.','FileHandles','()',{fileIndex}));
                header = builtin('subsref',obj,substruct('.','FileHeaders','()',{fileIndex}));
                
                fseek(fin,header.FixedHeaderSize+header.FrameSize*(frame-cumulativeFramesPerFile(fileIndex)-1),-1);
                
                % get the height and width from the QCam header so I don't
                % rather than calling the builtin subsref manually
                frameData = fread(fin,[builtin('subsref',obj,substruct('.','Height')) builtin('subsref',obj,substruct('.','Width'))],'uint16'); % TODO : get precision from header
                
                data(:,:,1,ii) = frameData(subs{1},subs{2});
            end
        end
    end
end