classdef SMC100AClass < handle

    properties
        
        % Device
        
        dev
        
        % Parent class of the SMC100A Class
        
        parent
        
        % Sweep parameters
        
        start_freq
        stop_freq
        
        sweep_duration
        sweep_points
        
        level
        
    end
    
    methods
        
        function obj=SMC100AClass()
            
            % create class
            
            obj = obj@handle;
            
        end
        
        function init(obj)
            
            % create device
            
            obj.dev = icdevice('rssmb.mdd','TCPIP::192.168.137.51::INSTR');
            
            % connect to device
            
            connect(obj.dev);
            
            % set output on
            
            invoke (obj.dev, 'SetOutputState', 1)
            
            % Message
            
            disp('*** SMC100A - initialized ***')
            
        end
        
        function set_parameters(obj)
            
            invoke(obj.dev, 'SetFrequencySweepMode', 3) % External Single
            
            % set Sweep start frequency [Hz]
            
            invoke(obj.dev, 'SetFrequencySweepStartFreq', obj.start_freq)
            
            invoke(obj.dev, 'SetFrequencySweepStopFreq', obj.stop_freq)
            
            invoke(obj.dev, 'SetFrequencySweepShape', 0) % Sawtooth
            
            invoke(obj.dev, 'SetFrequencySweepSpacing', 0) % Linear
            
            invoke(obj.dev, 'SetFrequencySweepPoints', obj.sweep_points)
            
            invoke(obj.dev, 'SetFrequencySweepDwellTime', obj.sweep_duration)
            
            invoke(obj.dev, 'SetRFLevel', obj.level) % dBm
            
        end
        
        function close(obj)
            
            % set output off
            
            invoke (obj.dev, 'SetOutputState', 0)
            
            % disconnect tabor
            
            disconnect(obj.dev);
            
            % delete device
            
            delete(obj.dev);
            obj.dev = [];
            
            % message
            
            disp('*** SMC100A - closed ***')
            
        end
        
    end
end