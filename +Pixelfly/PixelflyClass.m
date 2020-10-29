classdef PixelflyClass < handle
    
    properties
        %-----Camera settings-----%
        triggerMode      = uint16(2); %  0 = auto-trigger, 1 = software-trigger, 2 = external-trigger
        dbShutterMode    = uint16(1); % 0 = no double shutter, 1 = double shutter
        recordingState   = uint16(0); % 0 = camera not recording, 1 = camera recording
        recorderSubmode  = uint16(1); % 1 = ringbuffer
        bitAlignment     = uint16(1); % 0 = MSB aligned, 1 = LSB aligned
        bufNumber        = uint16(2); % Number of buffers (maximum 8 buffers)
        
        %-----Timing settings-----%
        delayTime        = uint16(0);
        timeBaseDelay    = uint16(0);   % 0 = ns, 1 = us, 2 = ms
        timeBaseExposure = uint16(2);   % 0 = ns, 1 = us, 2 = ms
        
        %-----Camera settings (set by questionning the camera)-----%
        bitPerPixel      = uint16(0);
        pixelRate        = uint16(0);
        interface        = uint16(0);
        xSize            = uint16(0);
        ySize            = uint16(0);
        maxxSize         = uint16(0);
        maxySize         = uint16(0);
        
        %-----Dynamical objects shared by several methods-----%
        imagePtr;
        eventPtr;
        ml_buflist_1;
        buflist_1;
        imageStack = [];
        sBufNr     = [];
        out_ptr    = libpointer;
        
        %-----Settings to close the camera-----%
        doCloseCamera    = 0;
        doUnloadLibrary  = 0;
        isCameraOpen     = 0;
        isCameraArmed    = 0;
        
        %-----Settings to configure the listeners-----%
        isRunning        = 0;
        
        %-----Array to stock the pictures for the fluorescence/absorption imaging-----%
        tmp_array        = zeros(1392,4*1040);
        
        %-----Timer to get images-----%
        imagesTimer
        
        seq_duration
        
        %-----Parent class of the Pixelfly Class-----%
        parent
        
    end
    
    properties
       
        current_message
        
    end
    
    properties (SetObservable = true)
        
        imagingType;
        exposureTime     = uint16(137);
        
    end
    
    methods
        
        %*********************************************************%
        %* These methods are 'definitions' of the Pixelfly class *%
        %*********************************************************%
        
        %-----Constructor of the class-----%
        function obj = PixelflyClass ()
            obj = obj@handle;
            
            %-----Initialize listeners-----%
            addlistener(obj,'imagingType','PostSet',@obj.PostsetImagingType);
            
            %-----Initialize timer-----%
            
            obj.imagesTimer = timer(...
                'ExecutionMode','singleShot',...
                'StartFcn',@obj.ImageTimerStartFcn,...
                'TimerFcn',@obj.ImageTimerFcn,...
                'StopFcn',@obj.ImageTimerStopFcn...
                );
        end
 
        function [] = PostsetImagingType(obj,~,~)
            % The camera MUST BE turned off to modify its settings (except for the exposure time)
            switch obj.isRunning
                case 0
                    %-----Set the imaging type parameters-----%
                    switch obj.imagingType
                        case 'absorption'
                            obj.bufNumber = 2;
                            
                        case 'clean_abs'
                            obj.bufNumber = 2;
                            
                        case 'fluo_1pix'
                            obj.bufNumber = 1;
                            
                        case 'fluo_tof'
                            obj.bufNumber = 2;
                            
                        otherwise
                            display('Unknown imaging type !');
                    end
                    
                case 1
                    % The camera MUST BE turned off first (except if the modified parameter is the exposure time)
                    obj.StopAcquisition();
                    
                    %-----Set the imaging type parameters-----%
                    switch obj.imagingType
                        case 'absorption'
                            obj.bufNumber = 2;
                            
                        case 'clean_abs'
                            obj.bufNumber = 2;
                            
                        case 'fluo_1pix'
                            obj.bufNumber = 1;
                            
                        case 'fluo_tof'
                            obj.bufNumber = 2;
                            
                        otherwise
                            display('Unknown imaging type !');
                    end
                    
                    % Reboot the camera with the new settings
                    obj.StartAcquisition();
                    
                otherwise
                    display('Unknown running state !');
            end
        end
        
        function [] = PostsetExposureTime(obj,~,~)
            obj.SetTimings;
        end
        
        %********************************************************************************%
        %* These methods are 'definitions' that will be called to prepare the acquisition *%
        %********************************************************************************%
        
        %-----InitializePixelfly method to declare/open the camera-----%
        function [] = InitializePixelfly(obj)     
            %-----Load the library defining the C methods called to control the camera-----%
            fprintf('\n');
            disp('**********Loading the library**********');
            
            %-----Check whether the library is loaded or not-----%
            if (~libisloaded('PCO_CAM_SDK'))
                % Make sure that the '.dll' and '.h' specified below reside in the current folder
                loadlibrary('SC2_Cam', 'SC2_CamMatlab.h', 'addheader', 'SC2_CamExport.h', 'alias', 'PCO_CAM_SDK');
                disp('Camera library      -> loaded');
            else
                disp('Camera libraby already loaded !');
            end
            
            obj.doUnloadLibrary = 1;
            obj.isCameraOpen    = 0;
            obj.doCloseCamera   = 1;
            
            %-----Declare the camera and open it-----%
            fprintf('\n');
            disp('**********Initializing camera**********');
            
            ph_ptr = libpointer('voidPtrPtr'); % Declaration of the camera handle
            
            %-----Open the camera-----%
            if(obj.isCameraOpen == 0)
                [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_OpenCamera', ph_ptr, 0);
                % out_ptr is the camera handle, which must be used in all other libcalls !
                if(errorCode == 0)
                    disp('Camera status       -> opened');
                    obj.isCameraOpen = 1;
                else
                    disp(['PCO_OpenCamera failed with error ', num2str(errorCode,'%X')]);
                    if(obj.doUnloadLibrary)
                        unloadlibrary('PCO_CAM_SDK');
                        disp('Camera library         -> unloaded');
                    end
                end
            else
                disp('Camera already opened !');
            end
        end
        
        %-----GetPixelfly method to initiate some properties (pixel rate, bit per pixel, ...) according to the camera description-----%
        function [] = GetPixelflyParameters(obj)
            fprintf('\n');
            disp('**********Getting camera properties**********');
            
            %-----Camera description-----%
            ml_cam_desc.wSize = uint16(436); % 436 = size of the cam_desc structure
            cam_desc          = libstruct('PCO_Description', ml_cam_desc); % converts a matlab structure into a C-style structure
            [errorCode, obj.out_ptr, cam_desc] = calllib('PCO_CAM_SDK', 'PCO_GetCameraDescription', obj.out_ptr, cam_desc);
            if(errorCode)
                pco_errdisp('DescriptionPixelfly > GetCameraDescription -> failure ', errorCode);
            end
            
            obj.bitPerPixel = cam_desc.wDynResDESC;        % Number of bits per pixel
            obj.pixelRate   = cam_desc.dwPixelRateDESC(1);
                       
            %-----Camera type-----%
            ml_cam_type.wSize = uint16(1364); % 1364 = size of the cam_type structure
            cam_type          = libstruct('PCO_CameraType', ml_cam_type);
            [errorCode, obj.out_ptr, cam_type] = calllib('PCO_CAM_SDK', 'PCO_GetCameraType', obj.out_ptr, cam_type);
            if(errorCode)
                pco_errdisp('DescriptionPixelfly > GetCameraType -> failure ', errorCode);
            end
                        
            obj.interface = cam_type.wInterfaceType;
            
            %-----Get the x and y resolutions (because this always returns accurate image size for next recording)-----%
            [errorCode, obj.out_ptr, obj.xSize, obj.ySize, obj.maxxSize, obj.maxySize] = calllib('PCO_CAM_SDK', 'PCO_GetSizes', obj.out_ptr, obj.xSize, obj.ySize, obj.maxxSize, obj.maxySize);
            if(errorCode)
                pco_errdisp('DescriptionPixelfly > GetSizes -> failure ', errorCode);
            end
        end
        
        %-----Definition of the 'set' methods-----%
        function [] = SetTimings(obj)           % Set time/delay/time_base parameters
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetDelayExposureTime', obj.out_ptr, obj.delayTime, obj.exposureTime, obj.timeBaseDelay, obj.timeBaseExposure);
            if(errorCode)
                pco_errdisp('SetDelayExposureTime -> failure ', errorCode);
            else
                [errorCode, obj.out_ptr, obj.delayTime, obj.exposureTime, obj.timeBaseDelay, obj.timeBaseExposure] = calllib('PCO_CAM_SDK', 'PCO_GetDelayExposureTime', obj.out_ptr, obj.delayTime, obj.exposureTime, obj.timeBaseDelay, obj.timeBaseExposure);
                if(errorCode)
                    pco_errdisp('Get timings configuration -> failure ',errorCode);
                else
                    disp('Timings             -> set');
                end
            end
        end
        
        function [] = SetDoubleShutterMode(obj) % Set double shutter mode parameters
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetDoubleImageMode', obj.out_ptr, obj.dbShutterMode);
            if(errorCode)
                pco_errdisp('Double shutter mode settings -> failure ', errorCode);
            else
                [errorCode, obj.out_ptr, obj.dbShutterMode] = calllib('PCO_CAM_SDK', 'PCO_GetDoubleImageMode', obj.out_ptr, obj.dbShutterMode);
                if(errorCode)
                    pco_errdisp('Get double shutter configuration -> failure ',errorCode);
                else
                    disp('Double shutter mode -> set');
                end
            end
        end
        
        function [] = SetBitAlignement(obj)     % Set bit alignment parameters
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetBitAlignment', obj.out_ptr, obj.bitAlignment);
            if(errorCode)
                pco_errdisp('Bit alignment settings -> failure ', errorCode);
            else
                [errorCode, obj.out_ptr, obj.bitAlignment] = calllib('PCO_CAM_SDK', 'PCO_GetBitAlignment', obj.out_ptr, obj.bitAlignment);
                if(errorCode)
                    pco_errdisp('Get bit alignement configuration -> failure ',errorCode);
                else
                    disp('Bit alignement      -> set');
                end
            end
        end
        
        function [] = SetRecorderSubmode(obj)   % Set recorder submode parameters
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetRecorderSubmode', obj.out_ptr, obj.recorderSubmode);
            if(errorCode)
                pco_errdisp('Recorder submode settings -> failure ',errorCode);
            else
                [errorCode, obj.out_ptr, obj.recorderSubmode] = calllib('PCO_CAM_SDK', 'PCO_GetRecorderSubmode', obj.out_ptr, obj.recorderSubmode);
                if(errorCode)
                    pco_errdisp('Get recorder submode configuration -> failure ',errorCode);
                else
                    disp('Recorder submode    -> set');
                end
            end
        end
        
        function [] = SetPixelRate(obj)         % Set pixel rate parameters
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetPixelRate', obj.out_ptr, obj.pixelRate);
            if(errorCode)
                pco_errdisp('Pixel rate settings -> failure ', errorCode);
            else
                [errorCode, obj.out_ptr, obj.pixelRate] = calllib('PCO_CAM_SDK', 'PCO_GetPixelRate', obj.out_ptr, obj.pixelRate);
                if(errorCode)
                    pco_errdisp('Get pixel rate configuration -> failure ',errorCode);
                else
                    disp('Pixel rate          -> set');
                end
            end
        end
        
        function [] = SetTriggerMode(obj)       % Set the trigger mode
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetTriggerMode', obj.out_ptr, obj.triggerMode);
            if(errorCode)
                pco_errdisp('Trigger mode settings -> failure ', errorCode);
            else
                [errorCode, obj.out_ptr, obj.triggerMode] = calllib('PCO_CAM_SDK', 'PCO_GetTriggerMode', obj.out_ptr, obj.triggerMode);
                if(errorCode)
                    pco_errdisp('Get trigger mode configuration -> failure ',errorCode);
                else
                    disp('Trigger mode        -> set');
                end
            end
        end
        
        function [] = SetRecordingState(obj)    % Set the recording state
            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_SetRecordingState', obj.out_ptr, obj.recordingState);
            if(errorCode)
                pco_errdisp('Recording state settings -> failure ', errorCode);
            else
                [errorCode, obj.out_ptr, obj.recordingState] = calllib('PCO_CAM_SDK', 'PCO_GetRecordingState', obj.out_ptr, obj.recordingState);
                if(errorCode)
                    pco_errdisp('Get recording state configuration -> failure ',errorCode);
                else
                    disp('Recording mode      -> set');
                end
            end
        end
        
        %-----SettingsPixelfly method to prepare the camera settings for acquisition-----%
        function [] = SettingsPixelfly(obj)
            fprintf('\n');
            disp('**********Setting camera parameters**********');
            
            %-----Check the camera status-----%
            if(obj.isCameraOpen)
                disp('Camera status       -> opened');
            else
                disp('Camera status       -> closed');
            end
            
            %-----Check that the camera is not recording-----%
            [errorCode, obj.out_ptr, obj.recordingState] = calllib('PCO_CAM_SDK', 'PCO_GetRecordingState', obj.out_ptr, obj.recordingState);
            if(errorCode)
                pco_errdisp('Getting recording state configuration -> failure ', errorCode);
            else
                if(obj.recordingState)
                    disp('Camera state        -> recording');
                else
                    disp('Camera state        -> not recording');
                end
            end
            
            %-----If the camera is recording, we turn it off-----%
            if(obj.recordingState == 1)
                obj.recordingState = 0;
                obj.SetRecordingState();
            end
            
            %-----Call the 'Set' methods-----%
            obj.SetTimings;
            obj.SetDoubleShutterMode;
            obj.SetBitAlignement;
            obj.SetRecorderSubmode;
            obj.SetPixelRate;
            obj.SetTriggerMode;
        end
        
        %-----Memory allocation for the buffer(s)-----%
        function [] = AllocateBuffersMemory(obj)
            fprintf('\n');
            disp('**********Allocating memory for the buffer(s)**********');
            
            %-----Allocate memory for bufNumber buffers-----%
            imas    = uint32(fix((double(obj.bitPerPixel)+7)/8));
            imas    = imas*uint32(obj.xSize)* uint32(obj.ySize);
            imasize = imas;
            
            %-----Buffer allocation to receive the acquired image-----%
            obj.imageStack = ones(obj.xSize,obj.ySize, obj.bufNumber, 'uint16');
            obj.sBufNr     = zeros(1, obj.bufNumber, 'int16');
            
            for n=1:obj.bufNumber
                sBufNri   = int16(-1); % '-1' needed to create a new buffer
                im_ptr(n) = libpointer('uint16Ptr',obj.imageStack(:,:,n));
                ev_ptr(n) = libpointer('voidPtr');
                
                [errorCode, obj.out_ptr, sBufNri, obj.imageStack(:,:,n)] = calllib('PCO_CAM_SDK', 'PCO_AllocateBuffer', obj.out_ptr, sBufNri, imasize, im_ptr(n), ev_ptr(n));
                if(errorCode)
                    pco_errdisp('Buffer allocation -> failure ',errorCode);
                    return;
                end
                obj.sBufNr(n) = sBufNri;
                display(['Buffer #',int2str(obj.sBufNr(n)), '           -> allocated']);
            end
            
            obj.imagePtr = im_ptr;
            obj.eventPtr = ev_ptr;
            
        end
        
        %-----Set buffer queue-----%
        function [] = SetBufferQueue(obj)
            fprintf('\n');
            disp('**********Initialisation of the buffer queue**********');
            
            obj.ml_buflist_1.sBufNr = uint16(obj.sBufNr(1));
            obj.buflist_1           = libstruct('PCO_Buflist', obj.ml_buflist_1);
            obj.buflist_1.sBufnr    = uint16(obj.sBufNr(1));
            
            if(obj.recordingState == 1)
                %-----Add the allocated buffer to the driver queue-----%
                for n=1:obj.bufNumber
                    [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_AddBufferEx', obj.out_ptr, 0, 0, obj.sBufNr(n), obj.xSize, obj.ySize, obj.bitPerPixel);
                    if(errorCode)
                        pco_errdisp('Add buffer -> failure ', errorCode);
                    end
                end
                disp('Buffer queue        -> set');
            end
        end
        
        %-----Set camera state for acquisition-----%
        function [] = ArmPixelfly(obj)
            fprintf('\n');
            disp('**********Arming the camera**********');
            
            % All the previous settings are not done if the camera is actually in recording state ON
            obj.isCameraArmed = 0;
            if(obj.recordingState == 0)
                [errorCode] = calllib('PCO_CAM_SDK', 'PCO_ArmCamera', obj.out_ptr);
                if(errorCode)
                    pco_errdisp('Arm camera -> failure ', errorCode);
                else
                    obj.isCameraArmed = 1;
                    [errorCode] = calllib('PCO_CAM_SDK', 'PCO_CamLinkSetImageParameters', obj.out_ptr, obj.xSize, obj.ySize);
                    if(errorCode)
                        pco_errdisp('CamLinkSetImageParameters -> failure ', errorCode);
                    end
                    
                    obj.recordingState = 1;
                    obj.SetRecordingState();
                end
                
                [errorCode, obj.out_ptr, obj.recordingState] = calllib('PCO_CAM_SDK', 'PCO_GetRecordingState', obj.out_ptr, obj.recordingState);
                if(errorCode)
                    pco_errdisp('Get recording state configuration -> failure ', errorCode);
                end
                if(obj.recordingState)
                    disp('Camera state        -> recording');
                else
                    disp('Camera state        -> not recording');
                end
            end
        end
        
        %-----Close the camera-----%
        function [] = ClosePixelfly(obj)
            if((obj.doCloseCamera == 1) && (obj.isCameraOpen == 1))
                errorCode = calllib('PCO_CAM_SDK', 'PCO_CloseCamera', obj.out_ptr);
                if(errorCode)
                    pco_errdisp('Close camera -> failure ',errorCode);
                else
                    obj.isCameraOpen  = 0;
                    obj.doCloseCamera = 0;
                    obj.out_ptr       = [];
                    disp('Close camera        -> done');
                end
            end
            
            % Clear the PCO objects unload the library
            obj.imageStack = [];
            obj.sBufNr = [];
            obj.imagePtr = [];
            obj.eventPtr = [];
            obj.ml_buflist_1 = [];
            obj.buflist_1 = [];
            
            if((obj.doUnloadLibrary == 1) && (obj.isCameraOpen == 0))
                unloadlibrary('PCO_CAM_SDK');
                obj.doUnloadLibrary = 0;
                disp('Camera library      -> unloaded');
            end
        end  
        
        
        %************************************************************%
        %* These methods are the ones to be called to take pictures *%
        %************************************************************%
        
        %-----Start the camera-----%
        function [] = StartAcquisition(obj)
            if((obj.isCameraOpen == 0) && (obj.isCameraArmed == 0))
                obj.InitializePixelfly();
                obj.GetPixelflyParameters();
                obj.SettingsPixelfly();
                obj.AllocateBuffersMemory();
                obj.ArmPixelfly();
                obj.SetBufferQueue();
                
                obj.isRunning = 1;
            elseif ((obj.isCameraOpen == 1) && (obj.isCameraArmed == 0))
                disp('Camera already open but not armed !');
                disp('Skip the initialization step, go to the configuration steps');
                obj.GetPixelflyParameters();
                obj.SettingsPixelfly();
                obj.AllocateBuffersMemory();
                obj.ArmPixelfly();
                obj.SetBufferQueue();
                
                obj.isRunning = 1;
            else
                disp('Camera already open and armed !');
                disp('Camera should be dearmed/closed to change settings !');
            end
        end
        
        %-----Image acquisition-----%
        function ImageTimerStartFcn(obj,~,~)
            
            if((obj.isCameraOpen == 1) && (obj.isCameraArmed == 1))
                
                disp('**********Start pictures acquisition**********');
                
                %-----Define the hexadecimal codes giving the buffer status-----%
                bufEmpty       = 'E0000000';
                bufFull        = 'E0008000';
                bufNeverFilled = 0;
                bufStatus      = uint16(10);
                bufStatusDrv   = uint16(10);
                
                %-----Check the filling state of the buffers-----%
                for n=1:obj.bufNumber
                    
                    [errorCode, obj.out_ptr, bufStatus, bufStatusDrv] = calllib('PCO_CAM_SDK', 'PCO_GetBufferStatus', obj.out_ptr, obj.sBufNr(n), bufStatus, bufStatusDrv);
                    
                    if(errorCode)
                        pco_errdisp('GetBufferStatus -> failure ', errorCode);
                    end
                    
                    disp(['dwStatusDll = ', num2str(bufStatus), '        dwStatusDrv = ', num2str(bufStatusDrv)]);
                    
                    if( (bufStatus == hex2dec(bufEmpty)) && (bufStatusDrv == 0) )
                        disp(['Buffer #', num2str(obj.sBufNr(n)), '           -> empty']);
                        
                    elseif( (bufStatus == hex2dec(bufFull)) && (bufStatusDrv == 0) )
                        disp(['Buffer #', num2str(obj.sBufNr(n)), '           -> full']);
                        
                        [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK','PCO_AddBufferEx', obj.out_ptr, 0, 0, obj.sBufNr(n), obj.xSize, obj.ySize, obj.bitPerPixel);
                        if(errorCode)
                            pco_errdisp('Add buffer after transfer -> failure ',errorCode);
                            break;
                        end
                        
                        disp(['Buffer #', num2str(obj.sBufNr(n)), ' has been emptied !']);
                        
                    elseif( (bufStatus == hex2dec(bufNeverFilled)) && (bufStatusDrv == 0) )
                        disp(['Buffer #', num2str(obj.sBufNr(n)), '           -> has never been filled']);
                        
                    else
                        disp('Undefined error !');
                        
                    end
                end
                
            else
                disp('Error -> either camera not open and/or not armed !');
                
                stop(obj.imagesTimer)
                
            end
            
        end
        
        function ImageTimerFcn(obj,~,~)
            
            bufWaitTime = uint16(obj.seq_duration*1000); % timeout to check if the pictures are ready
            
            getImagesBool = true;
            
            switch obj.imagingType
                
                case 'fluo_tof'
                    
                    for n=1:obj.bufNumber
                        obj.buflist_1.sBufNr = obj.sBufNr(n);
                        [errorCode, obj.out_ptr, obj.buflist_1] = calllib('PCO_CAM_SDK', 'PCO_WaitforBuffer', obj.out_ptr, 1, obj.buflist_1, bufWaitTime);
                        if(errorCode)
                            pco_errdisp('Wait for buffer -> failure ', errorCode);
                            
                            getImagesBool = false;
                        end
                        
                        disp(['Image waiting in Buffer #', num2str(obj.sBufNr(n))]);
                        
                        %-----Buffer is now ready except if an error occurred-----%
                        
                        %-----Take the picture(s)-----%
                        % Some useful pieces of information :
                        %   - if dwStatusDll = 00008000 -> buffer event is set
                        %   - if dwStatusDrv = 0         -> no error occurred during the transfer
                        
                        if((bitand(obj.buflist_1.dwStatusDll,hex2dec('00008000')))&&(obj.buflist_1.dwStatusDrv==0))
                            %-----Copy the buffer data into the image stack-----%
                            [errorCode, obj.out_ptr, obj.imageStack(:,:,n)] = calllib('PCO_CAM_SDK', 'PCO_GetBuffer', obj.out_ptr, obj.sBufNr(n), obj.imagePtr(n), obj.eventPtr(n));
                            if(errorCode)
                                pco_errdisp('Get buffer -> failure ',errorCode);
                            end
                            obj.buflist_1.dwStatusDll = bitand(obj.buflist_1.dwStatusDll,hex2dec('FFFF7FFF'));
                            
                            %-----Save the pictures-----%
                            if( mod(n,2) == 1 )
                                pic_at     = obj.imageStack(:,1:(obj.ySize)/2,n);
                                pic_at_bg  = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                                
                                %save(['C:\Users\BEC\Documents\data\pixelfly\','pic_at.mat'],'pic_at');
                                %save(['C:\Users\BEC\Documents\data\pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at.mat'],'pic_at');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                                
                            else
                                pic_wat    = obj.imageStack(:,1:(obj.ySize)/2,n);
                                pic_wat_bg = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                                
                                %save(['C:\Users\BEC\Documents\data\pixelfly\','pic_wat.mat'],'pic_wat');
                                %save(['C:\Users\BEC\Documents\data\pixelfly\','pic_wat_bg.mat'],'pic_wat_bg');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_wat.mat'],'pic_wat');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_wat_bg.mat'],'pic_wat_bg');
                                
                            end
                            
                            disp('Image read and saved');
                            
                            %-----We add the already used buffer at the end of the driver queue for the next turn-----%
                            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK','PCO_AddBufferEx', obj.out_ptr, 0, 0, obj.sBufNr(n), obj.xSize, obj.ySize, obj.bitPerPixel);
                            if(errorCode)
                                pco_errdisp('Add buffer after transfer -> failure ',errorCode);
                                break;
                            end
                        end
                    end
                    
                case 'fluo_1pix'
                    
                    for n=1:obj.bufNumber
                        obj.buflist_1.sBufNr = obj.sBufNr(n);
                        [errorCode, obj.out_ptr, obj.buflist_1] = calllib('PCO_CAM_SDK', 'PCO_WaitforBuffer', obj.out_ptr, 1, obj.buflist_1, bufWaitTime);
                        if(errorCode)
                            pco_errdisp('Wait for buffer -> failure ', errorCode);
                            
                            getImagesBool = false;
                        end
                        
                        disp(['Image waiting in Buffer #', num2str(obj.sBufNr(n))]);
                        
                        %-----Buffer is now ready except if an error occurred-----%
                        
                        %-----Take the picture(s)-----%
                        % Some useful pieces of information :
                        %   - if dwStatusDll = 00008000 -> buffer event is set
                        %   - if dwStatusDrv = 0         -> no error occurred during the transfer
                        
                        if((bitand(obj.buflist_1.dwStatusDll,hex2dec('00008000')))&&(obj.buflist_1.dwStatusDrv==0))
                            %-----Copy the buffer data into the image stack-----%
                            [errorCode, obj.out_ptr, obj.imageStack(:,:,n)] = calllib('PCO_CAM_SDK', 'PCO_GetBuffer', obj.out_ptr, obj.sBufNr(n), obj.imagePtr(n), obj.eventPtr(n));
                            if(errorCode)
                                pco_errdisp('Get buffer -> failure ',errorCode);
                            end
                            obj.buflist_1.dwStatusDll = bitand(obj.buflist_1.dwStatusDll,hex2dec('FFFF7FFF'));
                            
                            %-----Update the boolean initiating the communication with the treatement computer-----%
                            isAcqDone = 1;
                            
                            %-----Save the pictures-----%
                            pic_at    = obj.imageStack(:,1:(obj.ySize)/2,n);
                            pic_at_bg = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                            
                            %save(['C:\Users\BEC\Documents\data\pixelfly\','pic_at.mat'],'pic_at');
                            %save(['C:\Users\BEC\Documents\data\pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                            save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at.mat'],'pic_at');
                            save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                            
                            disp('Image read and saved');
                            
                            %-----We add the already used buffer at the end of the driver queue for the next turn-----%
                            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK','PCO_AddBufferEx', obj.out_ptr, 0, 0, obj.sBufNr(n), obj.xSize, obj.ySize, obj.bitPerPixel);
                            if(errorCode)
                                pco_errdisp('Add buffer after transfer -> failure ',errorCode);
                                break;
                            end
                        end
                    end
                    
                case 'absorption'
                    
                    for n=1:obj.bufNumber
                        obj.buflist_1.sBufNr = obj.sBufNr(n);
                        [errorCode, obj.out_ptr, obj.buflist_1] = calllib('PCO_CAM_SDK', 'PCO_WaitforBuffer', obj.out_ptr, 1, obj.buflist_1, bufWaitTime);
                        if(errorCode)
                            pco_errdisp('Wait for buffer -> failure ', errorCode);
                            
                            getImagesBool = false;
                        end
                        
                        disp(['Image waiting in Buffer #', num2str(obj.sBufNr(n))]);
                        
                        %-----Buffer is now ready except if an error occurred-----%
                        
                        %-----Take the picture(s)-----%
                        % Some useful pieces of information :
                        %   - if dwStatusDll = 00008000 -> buffer event is set
                        %   - if dwStatusDrv = 0         -> no error occurred during the transfer
                        
                        if((bitand(obj.buflist_1.dwStatusDll,hex2dec('00008000')))&&(obj.buflist_1.dwStatusDrv==0))
                            %-----Copy the buffer data into the image stack-----%
                            [errorCode, obj.out_ptr, obj.imageStack(:,:,n)] = calllib('PCO_CAM_SDK', 'PCO_GetBuffer', obj.out_ptr, obj.sBufNr(n), obj.imagePtr(n), obj.eventPtr(n));
                            if(errorCode)
                                pco_errdisp('Get buffer -> failure ',errorCode);
                            end
                            obj.buflist_1.dwStatusDll = bitand(obj.buflist_1.dwStatusDll,hex2dec('FFFF7FFF'));
                            
                            %-----Save the pictures-----%
                            if( mod(n,2) == 1 )
                                pic_at    = obj.imageStack(:,1:(obj.ySize)/2,n);
                                pic_at_bg = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                                
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at.mat'],'pic_at');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                                %save(['\\TIBO-HP\Data\Tmp\Pixelfly\','pic_at.mat'],'pic_at');
                                %save(['\\TIBO-HP\Data\Tmp\Pixelfly\','pic_wat.mat'],'pic_wat');
                                
                            else
                                pic_wat    = obj.imageStack(:,1:(obj.ySize)/2,n);
                                pic_wat_bg = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                                
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_wat.mat'],'pic_wat');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_wat_bg.mat'],'pic_wat_bg');
                                %save(['\\TIBO-HP\Data\Tmp\Pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                                %save(['\\TIBO-HP\Data\Tmp\Pixelfly\','pic_wat_bg.mat'],'pic_wat_bg');
                            end
                            
                            disp('Image read and saved');
                            
                            %-----We add the already used buffer at the end of the driver queue for the next turn-----%
                            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK','PCO_AddBufferEx', obj.out_ptr, 0, 0, obj.sBufNr(n), obj.xSize, obj.ySize, obj.bitPerPixel);
                            if(errorCode)
                                pco_errdisp('Add buffer after transfer -> failure ',errorCode);
                                break;
                            end
                        end
                    end
                    
                case 'clean_abs'
                    
                    for n=1:obj.bufNumber
                        obj.buflist_1.sBufNr = obj.sBufNr(n);
                        [errorCode, obj.out_ptr, obj.buflist_1] = calllib('PCO_CAM_SDK', 'PCO_WaitforBuffer', obj.out_ptr, 1, obj.buflist_1, bufWaitTime);
                        if(errorCode)
                            pco_errdisp('Wait for buffer -> failure ', errorCode);
                            
                            getImagesBool = false;
                        end
                        
                        disp(['Image waiting in Buffer #', num2str(obj.sBufNr(n))]);
                        
                        %-----Buffer is now ready except if an error occurred-----%
                        
                        %-----Take the picture(s)-----%
                        % Some useful pieces of information :
                        %   - if dwStatusDll = 00008000 -> buffer event is set
                        %   - if dwStatusDrv = 0         -> no error occurred during the transfer
                        
                        if((bitand(obj.buflist_1.dwStatusDll,hex2dec('00008000')))&&(obj.buflist_1.dwStatusDrv==0))
                            %-----Copy the buffer data into the image stack-----%
                            [errorCode, obj.out_ptr, obj.imageStack(:,:,n)] = calllib('PCO_CAM_SDK', 'PCO_GetBuffer', obj.out_ptr, obj.sBufNr(n), obj.imagePtr(n), obj.eventPtr(n));
                            if(errorCode)
                                pco_errdisp('Get buffer -> failure ',errorCode);
                            end
                            obj.buflist_1.dwStatusDll = bitand(obj.buflist_1.dwStatusDll,hex2dec('FFFF7FFF'));
                            
                            %-----Save the pictures-----%
                            if( mod(n,2) == 1 )
                                pic_at  = obj.imageStack(:,1:(obj.ySize)/2,n);
                                pic_wat = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                                
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at.mat'],'pic_at');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_wat.mat'],'pic_wat');
                            else
                                pic_at_bg    = obj.imageStack(:,1:(obj.ySize)/2,n);
                                pic_wat_bg = obj.imageStack(:,(1+(obj.ySize)/2):(obj.ySize),n);
                                
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_at_bg.mat'],'pic_at_bg');
                                save(['\\E010-BEC-PC03\Data\Tmp\Pixelfly\','pic_wat_bg.mat'],'pic_wat_bg');
                            end
                            
                            disp('Image read and saved');
                            
                            %-----We add the already used buffer at the end of the driver queue for the next turn-----%
                            [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK','PCO_AddBufferEx', obj.out_ptr, 0, 0, obj.sBufNr(n), obj.xSize, obj.ySize, obj.bitPerPixel);
                            if(errorCode)
                                pco_errdisp('Add buffer after transfer -> failure ',errorCode);
                                break;
                            end
                        end
                    end
                    
                otherwise
                    display('Unknown type of imaging type !');
            end
            
            %-----Send Network message-----%
            
            if getImagesBool
                
                obj.parent.net.send_message('main',obj.current_message);
                
            end
            
        end
        
        function ImageTimerStopFcn(~,~,~)
            
            disp('**********Pictures acquisition ended**********');
            
        end
        
        %-----Stop the camera-----%
        function [] = StopAcquisition(obj)
            
            if( (obj.doUnloadLibrary == 1) && (obj.isCameraOpen == 1) )
                fprintf('\n');
                disp('**********Close camera/Deallocate the memory**********');
                
                %-----Set the running state to 0-----%
                obj.isRunning = 0;
                
                %-----Remove all pending buffers in the queue-----%
                [errorCode] = calllib('PCO_CAM_SDK', 'PCO_CancelImages', obj.out_ptr);
                if(errorCode)
                    pco_errdisp('Remove buffer(s) from queue -> failure ',errorCode);
                end
                
                if(obj.isCameraArmed == 1)
                    %set changed values back
                    %set saved RecoderSubmode
                    [errorCode] = calllib('PCO_CAM_SDK', 'PCO_SetRecordingState', obj.out_ptr, 0);
                    if(errorCode)
                        pco_errdisp('Set recording state -> failure ', errorCode);
                    else
                        [errorCode, obj.out_ptr, obj.recordingState] = calllib('PCO_CAM_SDK', 'PCO_GetRecordingState', obj.out_ptr, obj.recordingState);
                        if(errorCode)
                            pco_errdisp('Get recording state -> failure ',errorCode);
                        else
                            if(obj.recordingState)
                                disp('Camera state        -> recording');
                            else
                                disp('Camera state        -> not recording');
                            end
                        end
                    end
                    
                    [errorCode] = calllib('PCO_CAM_SDK', 'PCO_ArmCamera', obj.out_ptr);
                    if(errorCode)
                        pco_errdisp('Arm camera -> failure ', errorCode);
                    end
                    obj.isCameraArmed = 0; 
                end
                
                %-----Deallocate memory and clear several objects-----%
                for n=1:obj.bufNumber
                    [errorCode, obj.out_ptr, obj.imageStack(:,:,n)] = calllib('PCO_CAM_SDK', 'PCO_GetBuffer', obj.out_ptr, obj.sBufNr(n), obj.imagePtr(n), obj.eventPtr(n));
                    if(errorCode)
                        pco_errdisp('PCO_GetBuffer',errorCode);
                    end
                    
                    [errorCode, obj.out_ptr] = calllib('PCO_CAM_SDK', 'PCO_FreeBuffer', obj.out_ptr, obj.sBufNr(n));
                    if(errorCode)
                        pco_errdisp('PCO_FreeBuffer',errorCode);
                    else
                        disp(['Buffer #',num2str(obj.sBufNr(n)),'           -> deallocated']);
                    end
                end
                
                %-----Close the camera-----%
                obj.ClosePixelfly();
                
                clear obj.imageStack;
                clear obj.sBufNr;
                clear obj.imagePtr;
                clear obj.eventPtr;
                clear obj.ml_buflist_1;
                clear obj.buflist_1;
            else
                disp('Error -> either library not loaded and/or camera is not open');
            end
        end
        
    end
    
end
