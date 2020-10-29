classdef Default_parameters
    % Default_parameters class contains the value of every Network
    % parameters
    
    properties (Constant) % Defaults Panel properties

        sample_rate = 100e6;
        
        % No filter = 0
        % Filter 25 MHz = 1
        % Filter 50 MHz = 2
        % Filter 60 MHz = 3
        % Filter 120 MHz = 4
        
        filter = 0;
        
        gain = 1; % gain of arbitrary waveforms in the sequence
        
        offset = 0; % offset of arbitrary waveforms in the sequence
        
        data_root_path = '\\BEC008-T3600\Users\BEC\Documents\data\';
        
        tabor_data_path = 'C:\Users\BEC\Documents\MATLAB\20\09_tabor\';
        
    end

    
    methods
    end
    
end