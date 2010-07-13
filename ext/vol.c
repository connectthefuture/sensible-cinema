#include <windows.h>
    #include <mmsystem.h>
   
int main() {
    MMRESULT rc;              // Return code.
    HMIXER hMixer;            // Mixer handle used in mixer API calls.
    MIXERCONTROL mxc;         // Holds the mixer control data.
    MIXERLINE mxl;            // Holds the mixer line data.
    MIXERLINECONTROLS mxlc;   // Obtains the mixer control.

    // Open the mixer. This opens the mixer with a deviceID of 0. If you
    // have a single sound card/mixer, then this will open it. If you have
    // multiple sound cards/mixers, the deviceIDs will be 0, 1, 2, and
    // so on.
    rc = mixerOpen(&hMixer, 0,0,0,0);
    if (MMSYSERR_NOERROR != rc) {
        // Couldn't open the mixer.
      printf("bad4");
    }

    // Initialize MIXERLINE structure.
    ZeroMemory(&mxl,sizeof(mxl));
    mxl.cbStruct = sizeof(mxl);

    // Specify the line you want to get. You are getting the input line
    // here. If you want to get the output line, you need to use
    // MIXERLINE_COMPONENTTYPE_SRC_WAVEOUT.
    // MIXERLINE_COMPONENTTYPE_DST_WAVEIN
    // MIXERLINE_COMPONENTTYPE_DST_SPEAKERS
    mxl.dwComponentType = MIXERLINE_COMPONENTTYPE_SRC_WAVEOUT;

    rc = mixerGetLineInfo((HMIXEROBJ)hMixer, &mxl,
                           MIXER_GETLINEINFOF_COMPONENTTYPE);
    if (MMSYSERR_NOERROR == rc) {
        // Couldn't get the mixer line.
      printf("bad3 ok");
      

      // Get the control.
      ZeroMemory(&mxlc, sizeof(mxlc));
      mxlc.cbStruct = sizeof(mxlc);
      mxlc.dwLineID = mxl.dwLineID;
      
      // MIXERCONTROL_CONTROLTYPE_VOLUME
      // MIXERCONTROL_CONTROLTYPE_PEAKMETER
      mxlc.dwControlType = MIXERCONTROL_CONTROLTYPE_PEAKMETER;
      mxlc.cControls = 1;
      mxlc.cbmxctrl = sizeof(mxc);
      mxlc.pamxctrl = &mxc;
      ZeroMemory(&mxc, sizeof(mxc));
      mxc.cbStruct = sizeof(mxc);
      rc = mixerGetLineControls((HMIXEROBJ)hMixer,&mxlc,
      MIXER_GETLINECONTROLSF_ONEBYTYPE);
      if (MMSYSERR_NOERROR != rc) {
          // Couldn't get the control.
        printf("bad2 fatal");
        return -1;
      }
    }
   
  // After successfully getting the peakmeter control, the volume range
    // will be specified by mxc.Bounds.lMinimum to mxc.Bounds.lMaximum.

    MIXERCONTROLDETAILS mxcd;             // Gets the control values.
    MIXERCONTROLDETAILS_SIGNED volStruct; // Gets the control values.
    long volume;                          // Holds the final volume value.

    // Initialize the MIXERCONTROLDETAILS structure
    ZeroMemory(&mxcd, sizeof(mxcd));
    mxcd.cbStruct = sizeof(mxcd);
    mxcd.cbDetails = sizeof(volStruct);
    mxcd.dwControlID = mxc.dwControlID;
    mxcd.paDetails = &volStruct;
    mxcd.cChannels = 1;

    // Get the current value of the peakmeter control. Typically, you
    // would set a timer in your program to query the volume every 10th
    // of a second or so.
    rc = mixerGetControlDetails((HMIXEROBJ)hMixer, &mxcd,
                                 MIXER_GETCONTROLDETAILSF_VALUE);
    if (MMSYSERR_NOERROR == rc) {
        // Couldn't get the current volume.
      printf("bad1");
        return -1;
        
    }
    volume = volStruct.lValue;
    volume =  mxc.Bounds.lMaximum;

    // Get the absolute value of the volume.
    if (volume < 0)
        volume = -volume;
              
      //return volume;
      printf("volume is %d", volume);
      return 0;
    }