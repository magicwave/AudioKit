//
//  AKWhiteNoiseDSP.mm
//  AudioKit
//
//  Created by Aurelius Prochazka, revision history on Github.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "AKWhiteNoiseDSP.hpp"
#import "AKLinearParameterRamp.hpp"

extern "C" AKDSPRef createWhiteNoiseDSP(int nChannels, double sampleRate) {
    AKWhiteNoiseDSP *dsp = new AKWhiteNoiseDSP();
    dsp->init(nChannels, sampleRate);
    return dsp;
}

struct AKWhiteNoiseDSP::InternalData {
    sp_noise *_noise;
    AKLinearParameterRamp amplitudeRamp;
};

AKWhiteNoiseDSP::AKWhiteNoiseDSP() : data(new InternalData) {
    data->amplitudeRamp.setTarget(defaultAmplitude, true);
    data->amplitudeRamp.setDurationInSamples(defaultRampDurationSamples);
}

// Uses the ParameterAddress as a key
void AKWhiteNoiseDSP::setParameter(AUParameterAddress address, AUValue value, bool immediate) {
    switch (address) {
        case AKWhiteNoiseParameterAmplitude:
            data->amplitudeRamp.setTarget(clamp(value, amplitudeLowerBound, amplitudeUpperBound), immediate);
            break;
        case AKWhiteNoiseParameterRampDuration:
            data->amplitudeRamp.setRampDuration(value, _sampleRate);
            break;
    }
}

// Uses the ParameterAddress as a key
float AKWhiteNoiseDSP::getParameter(uint64_t address) {
    switch (address) {
        case AKWhiteNoiseParameterAmplitude:
            return data->amplitudeRamp.getTarget();
        case AKWhiteNoiseParameterRampDuration:
            return data->amplitudeRamp.getRampDuration(_sampleRate);
    }
    return 0;
}

void AKWhiteNoiseDSP::init(int _channels, double _sampleRate) {
    AKSoundpipeDSPBase::init(_channels, _sampleRate);
    sp_noise_create(&data->_noise);
    sp_noise_init(_sp, data->_noise);
    data->_noise->amp = defaultAmplitude;
}

void AKWhiteNoiseDSP::deinit() {
    sp_noise_destroy(&data->_noise);
}

void AKWhiteNoiseDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) {

    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
        int frameOffset = int(frameIndex + bufferOffset);

        // do ramping every 8 samples
        if ((frameOffset & 0x7) == 0) {
            data->amplitudeRamp.advanceTo(_now + frameOffset);
        }

        data->_noise->amp = data->amplitudeRamp.getValue();

        float temp = 0;
        for (int channel = 0; channel < _nChannels; ++channel) {
            float *out = (float *)_outBufferListPtr->mBuffers[channel].mData + frameOffset;

            if (_playing) {
                if (channel == 0) {
                    sp_noise_compute(_sp, data->_noise, nil, &temp);
                }
                *out = temp;
            } else {
                *out = 0.0;
            }
        }
    }
}
