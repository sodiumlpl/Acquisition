%% Clear Matlab

clear classes
close all
clc

addpath('C:\Users\BEC\Documents\MATLAB\14\09_sodium_acquisition_software\dev\C_Files');

%% Create Acquisition class
%cnt=1;
test_acquisition = Acquisition.Acquisition;

%% start GUI

test_acquisition.acquisition_main_gui;

%%

delete(test_acquisition)