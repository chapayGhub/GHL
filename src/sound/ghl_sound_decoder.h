/*
    GHL - Game Helpers Library
    Copyright (C)  Andrey Kunitsyn 2009

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

    Andrey (AndryBlack) Kunitsyn
    blackicebox (at) gmail (dot) com
*/

#ifndef GHL_SOUND_DECODER_H
#define GHL_SOUND_DECODER_H

#include <ghl_types.h>
#include <ghl_sound.h>
#include "../ghl_ref_counter_impl.h"

namespace GHL
{

	struct DataStream;

	class SoundDecoderBase : public RefCounterImpl<SoundDecoder>
	{
		protected:
			DataStream* m_ds;
			SampleType	m_type;
			UInt32		m_freq;
			UInt32		m_samples;
		public:
            explicit SoundDecoderBase(DataStream* ds);
            virtual ~SoundDecoderBase();
            /// sample type
            virtual SampleType GHL_CALL GetSampleType() const { return m_type; }
            /// samples rate
            virtual UInt32 GHL_CALL GetFrequency() const { return m_freq; } 
            /// samples amount
            virtual UInt32 GHL_CALL GetSamplesAmount() const { return m_samples; }
    };
}

#endif /*GHL_SOUND_DECODER_H*/