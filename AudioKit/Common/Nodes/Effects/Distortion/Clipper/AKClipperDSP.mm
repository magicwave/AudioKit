//
//  AKClipperDSP.mm
//  AudioKit
//
//  Created by Aurelius Prochazka, revision history on Github.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "AKClipperDSP.hpp"
#import "AKLinearParameterRamp.hpp"

extern "C" AKDSPRef createClipperDSP(int nChannels, double sampleRate) {
    AKClipperDSP *dsp = new AKClipperDSP();
    dsp->init(nChannels, sampleRate);
    return dsp;
}

struct AKClipperDSP::InternalData {
    sp_clip *_clip0;
    sp_clip *_clip1;
    AKLinearParameterRamp limitRamp;
};

AKClipperDSP::AKClipperDSP() : data(new InternalData) {
    data->limitRamp.setTarget(defaultLimit, true);
    data->limitRamp.setDurationInSamples(defaultRampDurationSamples);
}

// Uses the ParameterAddress as a key
void AKClipperDSP::setParameter(AUParameterAddress address, AUValue value, bool immediate) {
    switch (address) {
        case AKClipperParameterLimit:
            data->limitRamp.setTarget(clamp(value, limitLowerBound, limitUpperBound), immediate);
            break;
        case AKClipperParameterRampDuration:
            data->limitRamp.setRampDuration(value, _sampleRate);
            break;
    }
}

// Uses the ParameterAddress as a key
float AKClipperDSP::getParameter(uint64_t address) {
    switch (address) {
        case AKClipperParameterLimit:
            return data->limitRamp.getTarget();
        case AKClipperParameterRampDuration:
            return data->limitRamp.getRampDuration(_sampleRate);
    }
    return 0;
}

void AKClipperDSP::init(int _channels, double _sampleRate) {
    AKSoundpipeDSPBase::init(_channels, _sampleRate);
    sp_clip_create(&data->_clip0);
    sp_clip_init(_sp, data->_clip0);
    sp_clip_create(&data->_clip1);
    sp_clip_init(_sp, data->_clip1);
    data->_clip0->lim = defaultLimit;
    data->_clip1->lim = defaultLimit;
}

void AKClipperDSP::deinit() {
    sp_clip_destroy(&data->_clip0);
    sp_clip_destroy(&data->_clip1);
}

void AKClipperDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) {

    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
        int frameOffset = int(frameIndex + bufferOffset);

        // do ramping every 8 samples
        if ((frameOffset & 0x7) == 0) {
            data->limitRamp.advanceTo(_now + frameOffset);
        }

        data->_clip0->lim = data->limitRamp.getValue();
        data->_clip1->lim = data->limitRamp.getValue();

        float *tmpin[2];
        float *tmpout[2];
        for (int channel = 0; channel < _nChannels; ++channel) {
            float *in  = (float *)_inBufferListPtr->mBuffers[channel].mData  + frameOffset;
            float *out = (float *)_outBufferListPtr->mBuffers[channel].mData + frameOffset;
            if (channel < 2) {
                tmpin[channel] = in;
                tmpout[channel] = out;
            }
            if (!_playing) {
                *out = *in;
                continue;
            }

            if (channel == 0) {
                sp_clip_compute(_sp, data->_clip0, in, out);
            } else {
                sp_clip_compute(_sp, data->_clip1, in, out);
            }
        }
    }
}
