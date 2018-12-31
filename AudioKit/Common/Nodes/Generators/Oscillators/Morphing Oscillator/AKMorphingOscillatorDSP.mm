//
//  AKMorphingOscillatorDSP.mm
//  AudioKit
//
//  Created by Aurelius Prochazka, revision history on Github.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "AKMorphingOscillatorDSP.hpp"
#import "AKLinearParameterRamp.hpp"

extern "C" AKDSPRef createMorphingOscillatorDSP(int nChannels, double sampleRate) {
    AKMorphingOscillatorDSP *dsp = new AKMorphingOscillatorDSP();
    dsp->init(nChannels, sampleRate);
    return dsp;
}

struct AKMorphingOscillatorDSP::InternalData {
    sp_oscmorph *_oscmorph;
    sp_ftbl *_ft_array[4];
    UInt32 _ftbl_size = 4096;
    AKLinearParameterRamp frequencyRamp;
    AKLinearParameterRamp amplitudeRamp;
    AKLinearParameterRamp indexRamp;
    AKLinearParameterRamp detuningOffsetRamp;
    AKLinearParameterRamp detuningMultiplierRamp;
};

AKMorphingOscillatorDSP::AKMorphingOscillatorDSP() : data(new InternalData) {
    data->frequencyRamp.setTarget(defaultFrequency, true);
    data->frequencyRamp.setDurationInSamples(defaultRampDurationSamples);
    data->amplitudeRamp.setTarget(defaultAmplitude, true);
    data->amplitudeRamp.setDurationInSamples(defaultRampDurationSamples);
    data->indexRamp.setTarget(defaultIndex, true);
    data->indexRamp.setDurationInSamples(defaultRampDurationSamples);
    data->detuningOffsetRamp.setTarget(defaultDetuningOffset, true);
    data->detuningOffsetRamp.setDurationInSamples(defaultRampDurationSamples);
    data->detuningMultiplierRamp.setTarget(defaultDetuningMultiplier, true);
    data->detuningMultiplierRamp.setDurationInSamples(defaultRampDurationSamples);
}

// Uses the ParameterAddress as a key
void AKMorphingOscillatorDSP::setParameter(AUParameterAddress address, AUValue value, bool immediate) {
    switch (address) {
        case AKMorphingOscillatorParameterFrequency:
            data->frequencyRamp.setTarget(clamp(value, frequencyLowerBound, frequencyUpperBound), immediate);
            break;
        case AKMorphingOscillatorParameterAmplitude:
            data->amplitudeRamp.setTarget(clamp(value, amplitudeLowerBound, amplitudeUpperBound), immediate);
            break;
        case AKMorphingOscillatorParameterIndex:
            data->indexRamp.setTarget(clamp(value, indexLowerBound, indexUpperBound), immediate);
            break;
        case AKMorphingOscillatorParameterDetuningOffset:
            data->detuningOffsetRamp.setTarget(clamp(value, detuningOffsetLowerBound, detuningOffsetUpperBound), immediate);
            break;
        case AKMorphingOscillatorParameterDetuningMultiplier:
            data->detuningMultiplierRamp.setTarget(clamp(value, detuningMultiplierLowerBound, detuningMultiplierUpperBound), immediate);
            break;
        case AKMorphingOscillatorParameterRampDuration:
            data->frequencyRamp.setRampDuration(value, _sampleRate);
            data->amplitudeRamp.setRampDuration(value, _sampleRate);
            data->indexRamp.setRampDuration(value, _sampleRate);
            data->detuningOffsetRamp.setRampDuration(value, _sampleRate);
            data->detuningMultiplierRamp.setRampDuration(value, _sampleRate);
            break;
    }
}

// Uses the ParameterAddress as a key
float AKMorphingOscillatorDSP::getParameter(uint64_t address) {
    switch (address) {
        case AKMorphingOscillatorParameterFrequency:
            return data->frequencyRamp.getTarget();
        case AKMorphingOscillatorParameterAmplitude:
            return data->amplitudeRamp.getTarget();
        case AKMorphingOscillatorParameterIndex:
            return data->indexRamp.getTarget();
        case AKMorphingOscillatorParameterDetuningOffset:
            return data->detuningOffsetRamp.getTarget();
        case AKMorphingOscillatorParameterDetuningMultiplier:
            return data->detuningMultiplierRamp.getTarget();
        case AKMorphingOscillatorParameterRampDuration:
            return data->frequencyRamp.getRampDuration(_sampleRate);
    }
    return 0;
}

void AKMorphingOscillatorDSP::init(int _channels, double _sampleRate) {
    AKSoundpipeDSPBase::init(_channels, _sampleRate);
    _playing = false;
    sp_oscmorph_create(&data->_oscmorph);
}

void AKMorphingOscillatorDSP::deinit() {
    sp_oscmorph_destroy(&data->_oscmorph);
}

void  AKMorphingOscillatorDSP::reset() {
    sp_oscmorph_init(_sp, data->_oscmorph, data->_ft_array, 4, 0);
    data->_oscmorph->freq = defaultFrequency;
    data->_oscmorph->amp = defaultAmplitude;
    data->_oscmorph->wtpos = defaultIndex;
    AKSoundpipeDSPBase::reset();
}

void AKMorphingOscillatorDSP::setupIndividualWaveform(uint32_t waveform, uint32_t size) {
    data->_ftbl_size = size;
    sp_ftbl_create(_sp, &data->_ft_array[waveform], data->_ftbl_size);
}

void AKMorphingOscillatorDSP::setIndividualWaveformValue(uint32_t waveform, uint32_t index, float value) {
    data->_ft_array[waveform]->tbl[index] = value;
}
void AKMorphingOscillatorDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) {

    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
        int frameOffset = int(frameIndex + bufferOffset);

        // do ramping every 8 samples
        if ((frameOffset & 0x7) == 0) {
            data->frequencyRamp.advanceTo(_now + frameOffset);
            data->amplitudeRamp.advanceTo(_now + frameOffset);
            data->indexRamp.advanceTo(_now + frameOffset);
            data->detuningOffsetRamp.advanceTo(_now + frameOffset);
            data->detuningMultiplierRamp.advanceTo(_now + frameOffset);
        }

        data->_oscmorph->freq = data->frequencyRamp.getValue() * data->detuningMultiplierRamp.getValue() + data->detuningOffsetRamp.getValue();
        data->_oscmorph->amp = data->amplitudeRamp.getValue();
        data->_oscmorph->wtpos = data->indexRamp.getValue();

        float temp = 0;
        for (int channel = 0; channel < _nChannels; ++channel) {
            float *out = (float *)_outBufferListPtr->mBuffers[channel].mData + frameOffset;

            if (_playing) {
                if (channel == 0) {
                    sp_oscmorph_compute(_sp, data->_oscmorph, nil, &temp);
                }
                *out = temp;
            } else {
                *out = 0.0;
            }
        }
    }
}
