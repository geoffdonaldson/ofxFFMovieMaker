/*
 *  FFMovieMaker.h
 *  ffmpegTest
 *
 *  Is a simple movie maker based on FFMPEG. 
 *  It allows you to create either 
 *  Created by hansi on 20.11.10.
 *  Copyright 2010 __MyCompanyName__. All rights reserved.
 *
 */


#ifndef __FF_MOVIE_MAKER__
#define __FF_MOVIE_MAKER__

namespace ffmpeg{
extern "C"{
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavutil/log.h"
#include "libavutil/opt.h"
}
}

#include <string>
#include <iostream>
#include "ofMain.h"
#include <Poco/Path.h>

#include "LimitedQueue.h"

#define MAX_BUFFERS 4
#define MAX_BUFFER_LEN 100

using namespace std; 
using namespace ffmpeg; 

struct FFMovieMakerConfig {
	FFMovieMakerConfig():
	a_srcChannels(2), // stereo
	a_srcSampleRate(44100), // 44.1khz
	a_destSampleRate(-1), // defaults to src sample rate
	a_destBitRate(192000), // default to 192kBit/s
	v_srcWidth(-1), // defaults to dest width
	v_srcHeight(-1), // defaults to dest height
	v_destWidth(-1), // specified in constructor
	v_destHeight(-1),  // specified in constructor
	v_destFrameRate(25),  // 25 fps
	v_scaling(SWS_BICUBIC), // use "pretty" scaling if src and dest size don't match
	
	a_srcFormat(AV_SAMPLE_FMT_S16), // 16 bit sound
	v_srcFormat(PIX_FMT_RGBA), // what it says! 
	v_destFormat(PIX_FMT_YUV420P) // codec wants yuv420p pixel format
	{}; 
	
	int a_srcSampleRate; 
	int a_destSampleRate; 
	int a_destBitRate; 
	int a_srcChannels; 
	int v_srcWidth; 
	int v_srcHeight; 
	int v_destWidth; 
	int v_destHeight; 
	int v_destFrameRate; 
	int v_scaling; 
	
	AVSampleFormat a_srcFormat; 	
	PixelFormat v_srcFormat; 
	PixelFormat v_destFormat; 
}; 


class FFMovieMaker : public ofThread {
	
public: 
	FFMovieMaker( string filename, int width = -1, int height = -1, int srcWidth = -1, int srcHeight = -1 ); 
	~FFMovieMaker(); 
	FFMovieMakerConfig config;
	
	void begin(); 
	void addScreen(); // takes a screen grab and adds the output
	void addPixels( int * pixels ); // always call addframe and add audio
	void addAudio( int16_t * buffer, int len ); // from the same thread or things might get messy
	void addAudio( float * buffer, int len ); 
	bool wantsAudio(); 
	void finish(); 
	
    void threadedFunction();

private: 
	bool initialized;
	char filename[512]; 
	
	// we likey pixie!
	int * pixels;
	AVFrame *picture_rgb;
	int samplesIndex;
    struct SwsContext *img_convert_ctx_rgb;
	short int * floatAudioBuffer; 
	int floatAudioLen; 
	ofImage * screenGrab; 
	
	// whatever this is, it's important! 
    AVOutputFormat *fmt;
	AVFormatContext *oc;
    AVStream *audio_st, *video_st;
    double audio_pts, video_pts;
	
	// for audio output
	float t, tincr, tincr2;
	int16_t *samples;
	uint8_t *audio_outbuf;
	int audio_outbuf_size;
	int audio_input_frame_size;
	AVStream * add_audio_stream(AVFormatContext *oc, enum AVCodecID codec_id);
	void open_audio(AVFormatContext *oc, AVStream *st); 
public:
	void get_audio_frame(int16_t *samples, int frame_size, int nb_channels); 
private:
    void encode_audio_frame(AVFormatContext *oc, AVStream *st);
    void write_audio_frame(AVFormatContext *oc, AVPacket pkt);
	void write_audio_frame(AVFormatContext *oc, AVStream *st); 
	void close_audio(AVFormatContext *oc, AVStream *st); 
	
	
	// for video output
	AVFrame *picture;
	uint8_t *video_outbuf;
	int frame_count, video_outbuf_size;
	AVStream * add_video_stream( AVFormatContext *oc, enum AVCodecID codec_id, int width, int height );
	AVFrame * alloc_picture(enum PixelFormat pix_fmt, int width, int height); 
	void open_video(AVFormatContext *oc, AVStream *st); 
	void fill_yuv_image( AVFrame *pict, int frame_index, int width, int height );
    void encode_video_frame(AVFormatContext *oc, AVStream *st);
    void write_video_frame(AVFormatContext *oc, AVPacket pkt);
	void write_video_frame(AVFormatContext *oc, AVStream *st);
	void close_video(AVFormatContext *oc, AVStream *st); 
	
    int currentBuffer;
    vector<LimitedQueue *> videoBuffers;
    vector<LimitedQueue *> audioBuffers;
    
    vector<deque<AVPacket> > videoQueue;
    vector<deque<AVPacket> > audioQueue;
    
    bool finished;
    
};


#endif