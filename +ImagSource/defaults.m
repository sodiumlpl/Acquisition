%% Register dll if needed

imaqreset


imaqregister('C:\Program Files (x86)\TIS IMAQ for MATLAB R2013b\x64\TISImaq_R2013.dll')
clear all
close all

%%

vid = videoinput('tisimaq_r2013', 1, 'Y800 (1280x960)');
src = getselectedsource(vid);
src.Trigger = 'Disable';
src.ColorEnhancement = 'Disable';
src.Brightness = 0;
src.Contrast = 0;
src.Denoise = 0;
src.Exposure = 0.1;
src.ExposureAuto = 'Off';
src.Gain = 34;
src.GainAuto = 'Off';
src.Gamma = 100;
src.Highlightreduction = 'Disable';
src.Hue = 0;
src.Saturation = 0;
src.Sharpness = 0;
src.Strobe = 'Disable';
src.WhiteBalanceAuto = 'Off';
src.WhiteBalanceBlue = 64;
src.WhiteBalanceGreen = 64;
src.WhiteBalanceRed = 64;

vid.FramesPerTrigger = 1;
vid.FrameGrabInterval = 1;
vid.LoggingMode = 'memory';
vid.TimerPeriod = 0.01;
vid.TriggerRepeat = Inf;
vid.FramesAcquiredFcnCount = 1;
vid.FramesAcquiredFcn = [];
vid.ReturnedColorSpace = 'grayscale';

%% Grab a frame and call it A

 start(vid); pause('on'); pause(1); pause('off');
A = peekdata(vid,1);
stop(vid);
