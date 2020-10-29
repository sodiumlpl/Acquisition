classdef ImagSourceClass < handle
    
    
    properties
        %-----IMAQ objects-----%
        
        vid
        src
        imaqinfo = imaqhwinfo;
        
        %-----Camera settings-----%
        
        recordingState   = uint16(0); % 0 = camera not recording, 1 = camera recording
        
        %-----Timing settings-----%
        delayTime        = uint16(0);
        timeBaseDelay    = uint16(0);   % 0 = ns, 1 = us, 2 = ms
        timeBaseExposure = uint16(2);   % 0 = ns, 1 = us, 2 = ms
        
        
        %-----Dynamical objects shared by several methods-----%
        imagePtr;
        eventPtr;

        sBufNr     = [];
        
        getImagesBool
        
        %-----Settings to close the camera-----%
        doCloseCamera    = 0;
        doUnloadLibrary  = 0;
        isCameraOpen     = 0;
        isCameraArmed    = 0;
        
        %-----Settings to configure the listeners-----%
        isRunning        = 0;
        
        %-----Array to stock the pictures for the fluorescence/absorption imaging-----%
        A       = zeros(1280,960,4);
        
        %-----Timer to get images-----%
        imagesTimer
        
        seq_duration
        
        %-----Parent class of the Imagingsource Class-----%
        
        parent

        

    end
    
    properties (SetObservable = true)
        imagingType;
        framecount
    end
    
    properties
       
        current_message
        
    end
    
    methods
        
        %**************************************************************%
        %* These methods are 'definitions' of the Imagingsource class *%
        %**************************************************************%

        %-----Constructor of the class-----%
        
        function obj = ImagSourceClass()
            
            obj = obj@handle;
            
            %-----Listeners-----%
            
            addlistener(obj,'framecount','PostSet',@obj.listenFcn);
            
        end
        
        function init(obj)
            
            imaqregister('C:\Program Files (x86)\TIS IMAQ for MATLAB R2013b\x64\TISImaq_R2013_64.dll');
            
            obj.vid = videoinput('tisimaq_r2013', 1, 'y800 (1280x960)');
            obj.src = getselectedsource(obj.vid);
            
            obj.set_default_params;

            disp('*** ImagingSource camera - initialized ***')
            
        end
        
        function set_default_params(obj,~,~)
            
            % set source parameters
            
            obj.src.Trigger = 'Enable';
            obj.src.ColorEnhancement = 'Disable';
            obj.src.Brightness = 0;
            obj.src.Contrast = 0;
            obj.src.Denoise = 0;
            obj.src.ExposureAuto = 'Off';
            obj.src.Exposure = 0.004;
            obj.src.Gain = 34;
            obj.src.GainAuto = 'Off';
            obj.src.Gamma = 100;
            obj.src.Highlightreduction = 'Disable';
            obj.src.Hue = 0;
            obj.src.Saturation = 0;
            obj.src.Sharpness = 0;
            obj.src.Strobe = 'Disable';
            obj.src.WhiteBalanceAuto = 'Off';
            obj.src.WhiteBalanceBlue = 64;
            obj.src.WhiteBalanceGreen = 64;
            obj.src.WhiteBalanceRed = 64;
            
            % set video parameters
            
            obj.vid.FramesPerTrigger = 1;
            obj.vid.FrameGrabInterval = 1;
            obj.vid.LoggingMode = 'memory';
            obj.vid.TimerPeriod = 0.01;
            obj.vid.TriggerRepeat = Inf;
            obj.vid.FramesAcquiredFcnCount = 1;
            obj.vid.FramesAcquiredFcn = @obj.FrameCountUp;
            obj.vid.ReturnedColorSpace = 'grayscale';
            
            disp('*** ImagingSource camera - set default parameters ***')
            
        end
        
        function FrameCountUp(obj,~,~)
            
            obj.framecount = obj.framecount + 1;
            
            disp('*** ImagingSource camera - Picture Aqcuired ! ***')

        end
        
        function InspectVid(obj,~,~)
            
            inspect(obj.vid)
            
        end
        
        function InspectSrc(obj,~,~)
            
            inspect(obj.src)
            
        end
        
        function preview_camera2(obj,~,~)
            
           preview(obj.vid)
           obj.src.Trigger = 'Disable';
           obj.StopAcquisition()
           
        end
        


        function [] = listenFcn(obj,~,~)
            if (obj.vid.FramesAvailable == 0)
                disp('*******Frame Count Reset*******')
            else
                disp('***********Frame Get**********')
            end
            
            if(strcmp(obj.vid.Logging,'off'))
                switch obj.imagingType
                    case 'fluo_tof'
                        obj.vid.FramesPerTrigger = 2;
                    case 'fluo_1pix'
                        obj.vid.FramesPerTrigger = 1;
                    case 'clean_abs'
                        obj.vid.FramesPerTrigger = 1;%2;
                end
            else
            end
            
            
            switch obj.imagingType
                case 'fluo_tof'
                    if(obj.vid.FramesAvailable == 4)
                        obj.getImagesBool = true;
                        obj.SaveAndSend4
                    else
                        obj.getImagesBool = false;
                    end
                case 'fluo_1pix'
                    if(obj.vid.FramesAvailable == 2)
                        obj.getImagesBool = true;
                        obj.SaveAndSend2
                    else
                        obj.getImagesBool = false;
                    end
                    
                case 'clean_abs'
                    if(obj.vid.FramesAvailable == 4)
                        obj.getImagesBool = true;
                        obj.SaveAndSend4
                    else
                        obj.getImagesBool = false;
                    end
            end
                                  
            
        end

        
        
        
        
        %**********************************************************************************%
        %* These methods are 'definitions' that will be called to prepare the acquisition *%
        %**********************************************************************************%
        
        %-----InitializeImagingsource method to declare/open the camera-----%
        function [] = InitializeImagsource(obj)
            %-----Load the library defining the C methods called to control the camera-----%
            fprintf('\n');
            disp('**********Loading the library**********');
            
            
            %-----Check whether the library is loaded or not-----%
            if (~any(strcmp(obj.imaqinfo.InstalledAdaptors,'tisimaq_r2013')))
                % Make sure that the '.dll' and '.h' specified below reside in the specified folder
                imaqregister('C:\Program Files (x86)\TIS IMAQ for MATLAB R2013b\x64\TISImaq_R2013.dll');
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
            if(strcmp(obj.vid.Logging, 'off'))
                start(obj.vid)
                pause('on')
                disp('Camera is running')
                obj.isRunning        = 1;
            else
            end
  
      
            
        end
        
%         function FrameCountUp(obj)
%             obj.framecount = obj.framecount + 1;
%         end
%         

        
        
        function [] = SetTriggerMode(obj)       % Set the trigger mode to Enable
            %        if(obj.src.Trigger == 'Enable')
            %            obj.src.Trigger = 'Disable';
            %        else
            obj.src.Trigger = 'Enable';
            disp('Trigger enabled')
        end
        
%         function [] = SetRecordingState(obj)    % Set the recording state
%             if(strcmp(obj.vid.Logging,'off'))
%                 start(obj.vid);
%                 obj.isRunning        = 1;
%                 disp('vid is logging');
%             else
%                 stop(obj.vid);
%                 obj.isRunning        = 0;
%                 disp('vid is not logging')
%             end
%         end


        %-----SettingsImagingsource method to prepare the camera settings for acquisition-----%
        function [] = SettingsImagsource(obj,~,~)
            fprintf('\n');
            disp('**********Setting camera parameters**********');
            
            
            %-----Check that the camera is not recording-----%
            if(strcmp(obj.vid.Logging, 'on'))
                disp('Camera state        -> recording');
            else
                disp('Camera state        -> not recording');
            end
            
            
            %-----If the camera is recording, we turn it off-----%
            if(strcmp(obj.vid.Logging, 'on'))
                obj.recordingState = 0;
                obj.SetRecordingState();
            else
            end
            
            %-----Set defaults-----%
            obj.set_default_params;
            
        end
        
        
        
        %-----Close the camera-----%
        function CloseImagsource(obj,~,~)
            if(strcmp(obj.vid.Logging, 'on'))
                stop(obj.vid);
                flushdata(obj.vid)
                disp('Close camera        -> done');
                obj.isRunning = 0;
                obj.framecount = 0;
            else
                flushdata(obj.vid)
                disp('Close camera        -> done');
                obj.isRunning = 0;
                obj.framecount = 0;
            end
            
            
        end
        
        
        %************************************************************%
        %* These methods are the ones to be called to take pictures *%
        %************************************************************%
        
        %-----Start the camera-----%
        function [] = StartAcquisition(obj,~,~)
            
            disp('**********Start pictures acquisition**********');
            

            
            if(strcmp(obj.src.Trigger,'Disable'))
                obj.src.Trigger = 'Enable';
            else
            end

            if(strcmp(obj.vid.Logging,'off'))
                
                switch obj.imagingType
                    case 'fluo_tof'
                        obj.vid.FramesPerTrigger = 2;
                    case 'fluo_1pix'
                        obj.vid.FramesPerTrigger = 1;
                    case 'clean_abs'
                        obj.vid.FramesPerTrigger = 1;%2
                end
            
                start(obj.vid)
                
                obj.isRunning = 1;
            elseif(strcmp(obj.vid.Logging, 'on'))
                disp('Camera already open and armed !');
                
            else
                disp('Camera not loaded')
            end
            
            flushdata(obj.vid);
            obj.framecount = 0;
        end


        function SaveAndSend2(obj,~,~)
            
            B = peekdata(obj.vid,2);
            
            if ~any(any(any(B)))
                disp('No pictures acquired!');
                obj.getImagesBool = false;
            else
                disp('Image(s) waiting in Buffer ');
               
                    
                    %-----Copy the buffer data into the image stack-----%
                    obj.A = getdata(obj.vid,2);
                    
                    disp('Frames acquired');

                    %-----Save the pictures-----%
                    pic_at    = obj.A(:,:,1);
                    pic_at_bg = obj.A(:,:,2);
                    
                  
                    save(['\\E010-BEC-PC03\Data\Tmp\ImagSource\','pic_at.mat'],'pic_at');
                    save(['\\E010-BEC-PC03\Data\Tmp\ImagSource\','pic_at_bg.mat'],'pic_at_bg');
                    
                                       
                    disp('Images read and saved');
                    obj.framecount = 0;

       
            end
            
            %-----Send Network message-----%
            
            if obj.getImagesBool
                
                obj.parent.net.send_message('main',obj.current_message);
                
                disp('message sent')
            else     
            end
          
            
        end
        
        function SaveAndSend4(obj,~,~)
            B = peekdata(obj.vid,4);
            
            if ~any(any(any(B)))
                disp('No pictures acquired!');
                obj.getImagesBool = false;
            else
                disp('Image(s) waiting in Buffer');
                
                
                obj.A = getdata(obj.vid,4);
                
                pic_at     = obj.A(:,:,1);
                pic_at_bg  = obj.A(:,:,3);
                
                pic_wat    = obj.A(:,:,2);
                pic_wat_bg = obj.A(:,:,4);
                
                
                save(['\\E010-BEC-PC03\Data\Tmp\ImagSource\','pic_at.mat'],'pic_at');
                save(['\\E010-BEC-PC03\Data\Tmp\ImagSource\','pic_at_bg.mat'],'pic_at_bg');
                
                save(['\\E010-BEC-PC03\Data\Tmp\ImagSource\','pic_wat.mat'],'pic_wat');
                save(['\\E010-BEC-PC03\Data\Tmp\ImagSource\','pic_wat_bg.mat'],'pic_wat_bg');
                
                
                disp('Images read and saved');
                obj.framecount = 0;

               
            end
            if obj.getImagesBool
                
                obj.parent.net.send_message('main',obj.current_message);
                
                disp('message sent')
            else
            end
            
            disp('**********Pictures acquisition ended**********');
            
        end
        
        %-----Stop the camera-----%
        function [] = StopAcquisition(obj)
            fprintf('\n');
            disp('**********Close camera/Deallocate the memory**********');
            
            if(strcmp(obj.vid.Logging,'on'))
                
                %-----Close the camera-----%
                obj.CloseImagsource();
                
                %-----Set the running state to 0-----%
                obj.isRunning = 0;
            elseif(strcmp(obj.vid.Logging,'off'))
                %-----Set the running state to 0-----%
                obj.isRunning = 0;
                
                %-----Close the camera-----%
                obj.CloseImagsource();
                
            else
                disp('Error -> either library not loaded and/or camera is not open');
            end
        end
    end
    
    
end
