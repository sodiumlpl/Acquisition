classdef TaborClass < handle
    
    %addpath('C:\Program Files\IVI Foundation\IVI\Drivers\ww107x\examples\matlab');
    properties
        
        % Device
        
        dev
        
        % Configuration Handles
        
        Ut
        Cnf
        CnfFuncArbOut
        CnfFuncArbOutArbWav
        CnfFuncArbOutArbSeq
        
        % Array of the Waves
        
        Waves=[];
        
        % Array of the wave handles and sequence handle
        
        WaveHandles
        
        seqHandle
        
        % Parent class of the Tabor Class
        
        parent
        
    end
    
    properties
        
        waves_freq
        
        waves_nbr
        
        sample_rate
        
        filter
        
        gain
        
        offset
        
    end
    
    methods
        
        function obj=TaborClass()
            
            % create class
            
            obj = obj@handle;
            
            % set sample rate to default value
            
            obj.sample_rate = Tabor.Default_parameters.sample_rate;
            
            % set filter to default value
            
            obj.filter = Tabor.Default_parameters.filter;
            
            % set gain and offset of the sequence to default value
            
            obj.gain = Tabor.Default_parameters.gain;
            
            obj.offset = Tabor.Default_parameters.offset;
            
        end
        
        function init(obj)
            
            % create device
            
            obj.dev = icdevice('ww257x_64.mdd', 'TCPIP::192.168.137.74::23::SOCKET');
            
            % connect to device
            
            connect(obj.dev);
            
            % create pointers to configuration menu
            
            obj.Ut = get(obj.dev, 'Utility');
            obj.Cnf = get(obj.dev,'Configuration');
            obj.CnfFuncArbOut = get(obj.dev, 'Configurationfunctionsarbitraryoutput');
            obj.CnfFuncArbOutArbWav = get(obj.dev, 'Configurationfunctionsarbitraryoutputarbitrarywaveform');
            obj.CnfFuncArbOutArbSeq = get(obj.dev, 'Configurationfunctionsarbitraryoutputarbitrarysequence');
            
            % reset tabor
            
            invoke(obj.Ut, 'reset')
            
            % set sample rate
            
            invoke(obj.CnfFuncArbOut,'configuresamplerate',obj.sample_rate);
            
            % set Trigger mode
            
            invoke(obj.Cnf,'ConfigureOperationMode','CHAN_A',1002);
            
            % Message
            
            disp('*** Tabor - initialized ***')
            
        end
        
        function close(obj)
            
            % disable output
            
            invoke(obj.Cnf, 'configureoutputenabled', 'CHAN_A', 0)
            
            % disconnect tabor
            
            disconnect(obj.dev);
            
            % delete device
            
            delete(obj.dev);
            obj.dev = [];
            
            % clear properties
            
            obj.Ut = [];
            obj.Cnf = [];
            obj.CnfFuncArbOut = [];
            obj.CnfFuncArbOutArbWav = [];
            obj.CnfFuncArbOutArbSeq = [];
            obj.Waves = [];
            obj.WaveHandles = [];
            obj.seqHandle = [];
            
            % message
            
            disp('*** Tabor - closed ***')
            
        end
        
        function create_waves(obj)
            
            obj.Waves = [];
            
            obj.waves_freq = [10e6,11e6,12e6,13e6,14e6,15e6,16e6,17e6,18e6,19e6,20e6,21e6];
            
            obj.waves_nbr = [80,200,100,300,100,120,100,200,100,300,200,200];
            
            for i = 1:length(obj.waves_freq)
                obj.Waves{i}=sin(2*pi*obj.waves_freq(i)/obj.sample_rate*(0:obj.waves_nbr(i)-1));
            end
        end
        
        function load_waves(obj,~,~)
            
            % Create Waves
            
            obj.create_waves;
            
            invoke(obj.CnfFuncArbOutArbSeq,'cleararbmemory')
            
            
            
            obj.WaveHandles = [];
            
            obj.seqHandle = [];
            
            
            L = cellfun(@(x) length(x) , obj.Waves);
            
            hw=waitbar(0,'Initializing...',...;
                'Name','Transmitting waves to Tabor generator','Color','w');
            
            tic;
            
            for i =1:length(obj.Waves)
                
                obj.WaveHandles(i)= invoke(obj.CnfFuncArbOutArbWav, 'createarbwaveform', length(obj.Waves{i}), obj.Waves{i});
                
                ready=sum(L(1:i))./sum(L);
                
                hw=waitbar(ready,hw,[int2str(sum(L(1:i))) ' out of ' int2str(sum(L)) ' points'],...
                    'Name','Transmitting waves to Tabor generator');
                
            end
            toc;
            
            close(hw);
            
            
            
            %%% Save data to Adwin computer
            
            tabor_waves_freq = obj.waves_freq;
            
            tabor_waves_nbr = obj.waves_nbr;
            
            sample_rate = obj.sample_rate;
            
            save([Tabor.Default_parameters.data_root_path,'tabor_waves_informations'],...
                'tabor_waves_freq','tabor_waves_nbr','sample_rate');
            
            obj.parent.net.send_message('BEC008','Tabor_Waves-changed');
            
        end
        
        function load_sequence(obj)
            
            % Clear an old sequence
            
            if not(isempty(obj.seqHandle))
                
                invoke (obj.CnfFuncArbOutArbSeq,'ClearArbSequence',obj.seqHandle)
                
                invoke(obj.Cnf, 'configureoutputmode',0 )
                
            end
            
            % Load sequence file from Adwin computer
            tic;
            load([Tabor.Default_parameters.tabor_data_path,'tabor_data'])
            
            %Use tabor_waves_index_array tabor_waves_loops_array received from Adwin computer to create the sequence
            
            obj.seqHandle = invoke(obj.CnfFuncArbOutArbSeq, 'createarbsequence', length(tabor_waves_index_array), obj.WaveHandles(tabor_waves_index_array), tabor_waves_loops_array);
            
            invoke(obj.CnfFuncArbOutArbSeq,'ConfigureArbSequence','CHAN_A',obj.seqHandle, obj.gain,obj.offset) % Gain and offset of the sequence
            
            invoke(obj.Cnf, 'configureoutputmode',2 ) % Sequence mode
            invoke(obj.Cnf, 'configurefilter', 'CHAN_A', obj.filter); % Filter (0=none, 1=25MHz, 2=50MHz, 3=60MHz, 4=120MHz)
            invoke(obj.Cnf, 'configureoutputenabled', 'CHAN_A', 1) % Output enabled
            
            toc;
            
            disp('sequence loaded')
            
        end
    end
end