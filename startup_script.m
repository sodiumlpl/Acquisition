%% Clear Matlab

clear classes

imaqreset
close all
clc

addpath('C:\Users\BEC\Documents\MATLAB\14\09_sodium_acquisition_software\dev\C_Files');
addpath('C:\Program Files\IVI Foundation\IVI\Drivers\ww257x\examples\matlab');
addpath('C:\Users\BEC\Documents\MATLAB\20\09_SMC100A\ICT_rssmb');

%% Create Acquisition class

test_acquisition = Acquisition.Acquisition_dual;

%% start GUI

test_acquisition.acquisition_main_gui;


%%

delete(test_acquisition);
A = timerfind;
delete(A);
close all
clc
