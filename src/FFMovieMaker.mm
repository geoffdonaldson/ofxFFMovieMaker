/*
 *  FFMovieMaker.cpp
 *
 *  Created by hansi raber, 
 *  but 99% is a direct copy of "output-example.c" from the ffmpeg source distribution. 
 * 
 */

#include "FFMovieMaker.h"

// use width=0 to indicate audio-only. 
FFMovieMaker::FFMovieMaker( string filename, int width, int height, int srcWidth, int srcHeight ){
	if( width == -1 ) width = ofGetWidth(); 
	if( height == -1 ) height = ofGetHeight(); 
	
	av_register_all();
	
	// convert filename... 
//	sprintf( this->filename, "%s", filename.c_str() ); 
	sprintf( this->filename, "%s", Poco::Path( ofToDataPath( filename, false ) ).absolute().toString().c_str() ); 
	printf( "filename is: %s", this->filename ); 
	config.v_destWidth = width; 
	config.v_destHeight = height; 
	config.v_srcWidth = srcWidth; 
	config.v_srcHeight = srcHeight; 
	
	samplesIndex = 0; 
	currentBuffer = 0;
    
	floatAudioBuffer = NULL; 
	screenGrab = NULL;
    
    videoBuffers.resize(MAX_BUFFERS);
    audioBuffers.resize(MAX_BUFFERS);
    
    for (int i = 0; i < MAX_BUFFERS; i++) {
        videoBuffers[i] = new LimitedQueue(MAX_BUFFER_LEN);
        audioBuffers[i] = new LimitedQueue(MAX_BUFFER_LEN);
    }
    
    finished = false;
}

FFMovieMaker::~FFMovieMaker(){
	if( floatAudioBuffer != NULL ) delete floatAudioBuffer; 
	if( screenGrab != NULL ) delete screenGrab;
    
    waitForThread();
}

void FFMovieMaker::threadedFunction(){
    
    while (isThreadRunning()){
        
        if (finished) break;
        
        AVCodecContext *c;
        c = video_st->codec;

        AVPacket pkt;
        av_init_packet(&pkt);
        
        if (pkt.pts != AV_NOPTS_VALUE)
            pkt.pts = av_rescale_q(pkt.pts, c->time_base, video_st->time_base);
        if (pkt.dts != AV_NOPTS_VALUE)
            pkt.dts = av_rescale_q(pkt.dts, c->time_base, video_st->time_base);
        
        if (c->coded_frame->pts != AV_NOPTS_VALUE)
            pkt.pts= av_rescale_q(c->coded_frame->pts, c->time_base, video_st->time_base);
        
        if(c->coded_frame->key_frame)
            pkt.flags |= AV_PKT_FLAG_KEY;
        pkt.stream_index= video_st->index;

        
        if (currentBuffer > 0 && !videoBuffers[currentBuffer-1]->isEmpty()){
            
            node_t *vidData = videoBuffers[currentBuffer-1]->wait_to_pop_and_lock();
            
            pkt.data= vidData->data;
            pkt.size= vidData->data_len;
            
            write_video_frame(oc, pkt);
            
            videoBuffers[currentBuffer-1]->releaseLock();
            
        }else if (currentBuffer == 0 && !videoBuffers[MAX_BUFFERS-1]->isEmpty()){
            
            node_t *vidData = videoBuffers[MAX_BUFFERS-1]->wait_to_pop_and_lock();
            
            pkt.data= vidData->data;
            pkt.size= vidData->data_len;
            
            write_video_frame(oc, pkt);
            
            videoBuffers[MAX_BUFFERS-1]->releaseLock();
        }
        
    }
    bool emptyFlag = false;

    while (!emptyFlag && finished) {
        
        for (int i=0;i<MAX_BUFFERS;i++){
            if(!videoBuffers[i]->isEmpty()) emptyFlag = true;
        }
        
        AVCodecContext *c;
        c = video_st->codec;
        
        AVPacket pkt;
        av_init_packet(&pkt);
        
        if (pkt.pts != AV_NOPTS_VALUE)
            pkt.pts = av_rescale_q(pkt.pts, c->time_base, video_st->time_base);
        if (pkt.dts != AV_NOPTS_VALUE)
            pkt.dts = av_rescale_q(pkt.dts, c->time_base, video_st->time_base);
        
        if (c->coded_frame->pts != AV_NOPTS_VALUE)
            pkt.pts= av_rescale_q(c->coded_frame->pts, c->time_base, video_st->time_base);
        
        if(c->coded_frame->key_frame)
            pkt.flags |= AV_PKT_FLAG_KEY;
        pkt.stream_index= video_st->index;
        
        if (currentBuffer > 0 && !videoBuffers[currentBuffer-1]->isEmpty()) {
            
            node_t *vidData = videoBuffers[currentBuffer-1]->wait_to_pop_and_lock();
            
            pkt.data= vidData->data;
            pkt.size= vidData->data_len;
            
            write_video_frame(oc, pkt);
            
            videoBuffers[currentBuffer-1]->releaseLock();
            
        }else if (currentBuffer == 0 && !videoBuffers[MAX_BUFFERS-1]->isEmpty()){
            
            node_t *vidData = videoBuffers[MAX_BUFFERS-1]->wait_to_pop_and_lock();
            
            pkt.data= vidData->data;
            pkt.size= vidData->data_len;
            
            write_video_frame(oc, pkt);
            
            videoBuffers[MAX_BUFFERS-1]->releaseLock();
            
        }else if(!videoBuffers[currentBuffer]->isEmpty()){
            
            node_t *vidData = videoBuffers[currentBuffer]->wait_to_pop_and_lock();
            
            pkt.data= vidData->data;
            pkt.size= vidData->data_len;
            
            write_video_frame(oc, pkt);
            
            videoBuffers[currentBuffer]->releaseLock();
        }
    }
    
    int i;
	
    /* write the trailer, if any.  the trailer must be written
     * before you close the CodecContexts open when you wrote the
     * header; otherwise write_trailer may try to use memory that
     * was freed on av_codec_close() */
    av_write_trailer(oc);
	
    /* close each codec */
    if (video_st)
        close_video(oc, video_st);
    if (audio_st)
        close_audio(oc, audio_st);
	
    /* free the streams */
    for(i = 0; i < oc->nb_streams; i++) {
        av_freep(&oc->streams[i]->codec);
        av_freep(&oc->streams[i]);
    }
	
    if (!(fmt->flags & AVFMT_NOFILE)) {
        /* close the output file */
        avio_close(oc->pb);
    }
	
    /* free the stream */
    av_free(oc);
    
    stopThread();
}


void FFMovieMaker::begin(){
	#define FFMM_CONFIG(a, b) config.a = config.a == -1? config.b:config.a
	FFMM_CONFIG( a_destSampleRate, a_srcSampleRate );
	FFMM_CONFIG( v_srcWidth, v_destWidth ); 
	FFMM_CONFIG( v_srcHeight, v_destHeight ); 
	
	cout << "Starting with the following params: " << endl; 
	cout << "> src width: " << config.v_srcWidth << endl; 
	cout << "> src height: " << config.v_srcHeight << endl; 
	cout << "> dest width: " << config.v_destWidth << endl; 
	cout << "> dest height: " << config.v_destHeight << endl; 
	
	pixels = NULL; 
	fmt = av_guess_format( NULL, filename, NULL );
    if( !fmt ){
        printf( "Could not deduce output format from file extension: using MPEG.\n" );
        fmt = av_guess_format( "mp4", NULL, NULL );
    }
    if( !fmt ){
        fprintf( stderr, "Could not find suitable output format\n" );
        // exit( 1 );
		return; 
    }
	
    /* allocate the output media context */
    oc = avformat_alloc_context();
    if( !oc ){
        fprintf(stderr, "Memory error\n");
        // exit(1);
		return; 
    }
    oc->oformat = fmt;
    snprintf( oc->filename, sizeof(oc->filename), "%s", filename );
	
    /* add the audio and video streams using the default format codecs
	 and initialize the codecs */
    video_st = NULL;
    audio_st = NULL;
    if (fmt->video_codec != CODEC_ID_NONE && config.v_destWidth > 0 ){
		cout << "adding video stream" << endl; 
        video_st = add_video_stream(oc, fmt->video_codec, config.v_destWidth, config.v_destHeight );
    }
    if (fmt->audio_codec != CODEC_ID_NONE) {
		cout << "adding audio stream" << endl; 
        audio_st = add_audio_stream(oc, fmt->audio_codec);
    }
	
    /* set the output parameters (must be done even if no
	 parameters). */
//    if (av_set_parameters(oc, NULL) < 0) {
//        fprintf(stderr, "Invalid output format parameters\n");
//        exit(1);
//    }
	
    av_dump_format(oc, 0, filename, 1);
	
    /* now that all the parameters are set, we can open the audio and
	 video codecs and allocate the necessary encode buffers */
    if (video_st)
        open_video(oc, video_st);
    if (audio_st)
        open_audio(oc, audio_st);
	
    /* open the output file, if needed */
    if (!(fmt->flags & AVFMT_NOFILE)) {
        if (avio_open(&oc->pb, filename, AVIO_FLAG_WRITE) < 0) {
            fprintf(stderr, "Could not open '%s'\n", filename);
            exit(1);
        }
    }
	
    /* write the stream header, if any */
    avformat_write_header(oc, NULL);
	
	frame_count	= 0; 
	
    startThread(true, false);
}


void FFMovieMaker::addScreen(){
	if( config.v_srcFormat == PIX_FMT_RGBA ){
		cout << "FFMovieMaker: addScreen() only works with config.v_srcFormat=PIX_FMT_RGBA!" << endl; 
	}
	
	if( screenGrab == NULL ){
		screenGrab = new ofImage();
		screenGrab->allocate( config.v_srcWidth, config.v_srcHeight, OF_IMAGE_COLOR_ALPHA );
	}
	screenGrab->grabScreen( 0, 0, config.v_srcWidth, config.v_srcHeight ); 
	addPixels( (int*) screenGrab->getPixels() ); 
}


void FFMovieMaker::addPixels( int * pixels ){
	this->pixels = pixels; 
	
	/* compute current audio and video time */
	if (audio_st)
		audio_pts = (double)audio_st->pts.val * audio_st->time_base.num / audio_st->time_base.den;
	else
		audio_pts = 0.0;
	
	if (video_st)
		video_pts = (double)video_st->pts.val * video_st->time_base.num / video_st->time_base.den;
	else
		video_pts = 0.0;
	
	/*	if ((!audio_st || audio_pts >= STREAM_DURATION) &&
	 (!video_st || video_pts >= STREAM_DURATION))
	 break;*/
	
	/* write interleaved audio and video frames */
	if( video_st ){
        encode_video_frame(oc, video_st);
		//write_video_frame(oc, video_st);
	}
}

bool FFMovieMaker::wantsAudio(){
	if( !audio_st ) return false; 
	
	/* compute current audio and video time */
	if (audio_st)
		audio_pts = (double)audio_st->pts.val * audio_st->time_base.num / audio_st->time_base.den;
	else
		audio_pts = 0.0;
	
	if (video_st)
		video_pts = (double)video_st->pts.val * video_st->time_base.num / video_st->time_base.den;
	else
		video_pts = 0.0;
	
	return !video_st || (audio_st && audio_pts < video_pts); 
}

/**
 * length is the length of the samples array, the sum over all channels! 
 * 256 int16 values per channel in stereo makes len=512
 */
void FFMovieMaker::addAudio( int16_t * buffer, int len ){
	int offset = 0; // buffer internal offset in samples (two bytes each)
	
	/* compute current audio and video time */
	if (audio_st)
		audio_pts = (double)audio_st->pts.val * audio_st->time_base.num / audio_st->time_base.den;
	else
		audio_pts = 0.0;
	
	if (video_st)
		video_pts = (double)video_st->pts.val * video_st->time_base.num / video_st->time_base.den;
	else
		video_pts = 0.0;
	
	// copy as much as we can into the sample buffer
	while( len > 0 ){
		int howMany = min( audio_input_frame_size*config.a_srcChannels - samplesIndex, len ); 
		
		if( howMany < 0 ){
			cout << "FFMovieMaker: OOOOOOOOOOO, something went seriously wrong!!!" << endl; 
			cout << "              i really can't add a negative number of samples. " << endl; 
		}
		else if( howMany == 0 ){
			cout << "FFMovieMaker: Warning, 90% weirdness going on!" << endl; 
		}
		else{
			// don't think i understand memcpy, but this is what i want: 
			//for( int i = 0; i < howMany; i++ ){
			//	//samples[samplesIndex+i] = buffer[offset+i]; 
			//}
			// and this is what seems to do the trick: 
			memcpy( samples + samplesIndex, buffer+offset, howMany*2 ); 
			
			len -= howMany; 
			samplesIndex += howMany; 
			offset += howMany; 
		}
		
		if( samplesIndex == audio_input_frame_size*config.a_srcChannels ){
			if( audio_st && audio_pts >= video_pts ){
				cout << "FFMovieMaker: Warning, writing audio ahead of video. weirdness factor=7%" << endl;
				cout << "              audioT=" << audio_pts << ", videoT=" << video_pts << endl; 
			}
			write_audio_frame(oc, audio_st);
			audio_pts = (double)audio_st->pts.val * audio_st->time_base.num / audio_st->time_base.den;
			
			samplesIndex = 0; 
		}
		
		//cout << len << " left in buffer; " << samplesIndex << "/" << audio_input_frame_size << " filled in a/v buffer" << endl; 
	}
}

void FFMovieMaker::addAudio( float * buffer, int len ){
	if( floatAudioLen < len || floatAudioBuffer == NULL ){
		if( floatAudioBuffer == NULL ) delete [] floatAudioBuffer; 
		floatAudioBuffer = new short int[len]; 
	}
	for( int i = 0; i < len; i++ ){
		floatAudioBuffer[i] = buffer[i] < -1? -32767:( buffer[i] > 1? +32767:((short int)(32767*buffer[i])) ); 
	}
	
	addAudio( floatAudioBuffer, len ); 
}


void FFMovieMaker::finish(){
    finished = true;

//    waitForThread();
//    int i;
//	
//    /* write the trailer, if any.  the trailer must be written
//     * before you close the CodecContexts open when you wrote the
//     * header; otherwise write_trailer may try to use memory that
//     * was freed on av_codec_close() */
//    av_write_trailer(oc);
//	
//    /* close each codec */
//    if (video_st)
//        close_video(oc, video_st);
//    if (audio_st)
//        close_audio(oc, audio_st);
//	
//    /* free the streams */
//    for(i = 0; i < oc->nb_streams; i++) {
//        av_freep(&oc->streams[i]->codec);
//        av_freep(&oc->streams[i]);
//    }
//	
//    if (!(fmt->flags & AVFMT_NOFILE)) {
//        /* close the output file */
//        avio_close(oc->pb);
//    }
//	
//    /* free the stream */
//    av_free(oc);
}

/**************************************************************/
/* video output */

/* add a video output stream */
AVStream * FFMovieMaker::add_video_stream( AVFormatContext *oc, enum AVCodecID codec_id, int width, int height ){
    AVCodecContext *c;
    AVStream *st;
	
    st = avformat_new_stream(oc, NULL);
    if (!st) {
        fprintf(stderr, "Could not alloc stream\n");
        exit(1);
    }
	   
    c = st->codec;
    c->codec_id = codec_id;
    c->codec_type = AVMEDIA_TYPE_VIDEO;
	
    /* put sample parameters */
    c->bit_rate = 1024*1024*10; // 10 megabit
	
    /* resolution must be a multiple of two */
    c->width = width;
    c->height = height;
    /* time base: this is the fundamental unit of time (in seconds) in terms
	 of which frame timestamps are represented. for fixed-fps content,
	 timebase should be 1/framerate and timestamp increments should be
	 identically 1. */
    c->time_base.den = config.v_destFrameRate;
    c->time_base.num = 1;
    c->gop_size = 12; /* emit one intra frame every twelve frames at most */
    c->pix_fmt = config.v_destFormat;
    if (c->codec_id == CODEC_ID_MPEG2VIDEO) {
        /* just for testing, we also add B frames */
        c->max_b_frames = 2;
    }
    if (c->codec_id == CODEC_ID_MPEG1VIDEO){
        /* Needed to avoid using macroblocks in which some coeffs overflow.
		 This does not happen with normal video, it just happens here as
		 the motion of the chroma plane does not match the luma plane. */
        c->mb_decision=2;
    }
    if (c->codec_id == CODEC_ID_H264) {
        
        c->bit_rate = 500*1000;
        c->bit_rate_tolerance = 0;
        c->rc_max_rate = 0;
        c->rc_buffer_size = 0;
        c->gop_size = 40;
        c->max_b_frames = 3;
        c->b_frame_strategy = 1;
        c->coder_type = 1;
        c->me_cmp = 1;
        c->me_range = 16;
        c->qmin = 10;
        c->qmax = 51;
        c->scenechange_threshold = 40;
        c->flags |= CODEC_FLAG_LOOP_FILTER;
        c->me_method = ME_HEX;
        c->me_subpel_quality = 5;
        c->i_quant_factor = 0.71;
        c->qcompress = 0.6;
        c->max_qdiff = 4;
        
        av_opt_set(c->priv_data,"preset", "ultrafast", 0);
        av_opt_set(c->priv_data,"rc_lookahead","0",0);
        av_opt_set(c->priv_data,"sync-lookahead","0",0);
        av_opt_set(c->priv_data,"mbtree","0",0);
        av_opt_set(c->priv_data, "x264opts","no-mbtree:sliced-threads:sync-lookahead=0", 0);

//        - zerolatency:
//        --bframes 0 --force-cfr --no-mbtree
//        --sync-lookahead 0 --sliced-threads
//        --rc-lookahead 0
//        av_opt_set(c->priv_data,"bframes","0",0);
//        av_opt_set(c->priv_data,"no-mbtree","off",0);
//
//
//        av_opt_set(c->priv_data,"subq","6",0);
//        av_opt_set(c->priv_data,"crf","20.0",0);
//        av_opt_set(c->priv_data,"weighted_p_pred","0",0);
//        av_opt_set(c->priv_data,"vprofile","baseline",0);
//        av_opt_set(c->priv_data,"preset","medium",0);
        //av_opt_set(c->priv_data,"tune","zerolatency",0);
        //c->directpred = 1;
        //c->flags2 |= CODEC_FLAG2_FASTPSKIP;
        c->level = 41;
        c->profile = FF_PROFILE_H264_HIGH;
    }
	
    // some formats want stream headers to be separate
    if(oc->oformat->flags & AVFMT_GLOBALHEADER)
        c->flags |= CODEC_FLAG_GLOBAL_HEADER;
	
    return st;
}

AVFrame * FFMovieMaker::alloc_picture(enum PixelFormat pix_fmt, int width, int height){
    AVFrame *picture;
    uint8_t *picture_buf;
    int size;
	
    picture = avcodec_alloc_frame();
    if (!picture)
        return NULL;
    size = avpicture_get_size(pix_fmt, width, height);
	cout << "SIZE===" << size << endl; 
	cout << "S2=" << avpicture_get_size(pix_fmt, width, height) << endl; 
	cout << "S3=" << avpicture_get_size(pix_fmt, 1, 1) << endl; 
	cout << "S4=" << avpicture_get_size(pix_fmt, 2, 2) << endl; 
    picture_buf = (uint8_t*) av_malloc(size);
    if (!picture_buf) {
        av_free(picture);
        return NULL;
    }
    avpicture_fill((AVPicture *)picture, picture_buf,
                   pix_fmt, width, height);
    return picture;
}

void FFMovieMaker::open_video(AVFormatContext *oc, AVStream *st)
{
    AVCodec *codec;
    AVCodecContext *c;
	
    c = st->codec;
	
    /* find the video encoder */
    codec = avcodec_find_encoder(c->codec_id);
    if (!codec) {
        fprintf(stderr, "codec not found\n");
        exit(1);
    }
	
    /* open the codec */
    if (avcodec_open2(c, codec, NULL) < 0) {
        fprintf(stderr, "could not open codec\n");
        exit(1);
    }
	
    video_outbuf = NULL;
    if (!(oc->oformat->flags & AVFMT_RAWPICTURE)) {
        /* allocate output buffer */
        /* XXX: API change will be done */
        /* buffers passed into lav* can be allocated any way you prefer,
		 as long as they're aligned enough for the architecture, and
		 they're freed appropriately (such as using av_free for buffers
		 allocated with av_malloc) */
        video_outbuf_size = config.v_destWidth*config.v_destHeight*2;
        video_outbuf = (uint8_t*) av_malloc(video_outbuf_size);
    }
	
    /* allocate the encoded raw picture */
    picture = alloc_picture(c->pix_fmt, c->width, c->height);
    if (!picture) {
        fprintf(stderr, "Could not allocate picture\n");
        exit(1);
    }
	
	
	picture_rgb = alloc_picture( config.v_srcFormat, config.v_srcWidth, config.v_srcHeight ); 
	//	avpicture_alloc(picture_rgb, PIX_FMT_RGB32, srcWidth, srcHeight);
	
	img_convert_ctx_rgb = sws_alloc_context(); 
	
	av_set_int(img_convert_ctx_rgb, "sws_flags", config.v_scaling);
    av_set_int(img_convert_ctx_rgb, "srcw", config.v_srcWidth);
    av_set_int(img_convert_ctx_rgb, "srch", config.v_srcHeight);
    av_set_int(img_convert_ctx_rgb, "dstw", c->width);
    av_set_int(img_convert_ctx_rgb, "dsth", c->height);
    av_set_int(img_convert_ctx_rgb, "src_format", config.v_srcFormat);
    av_set_int(img_convert_ctx_rgb, "dst_format", c->pix_fmt);
    const int *coeff = sws_getCoefficients(SWS_CS_DEFAULT);
	int srcRange = 0; 
	int dstRange = 1; 
    sws_setColorspaceDetails(img_convert_ctx_rgb, coeff, srcRange, coeff /* FIXME*/, dstRange, 0, 1<<16, 1<<16);
	
	cout << "KKK!" << endl; 
	sws_init_context( img_convert_ctx_rgb, NULL, NULL );
	
	for( int i = 0; i < 4; i++ ){
		cout << "YUV-LS-" << i << "=" << picture->linesize[i] << endl; 
		cout << "RGB-LS-" << i << "=" << picture_rgb->linesize[i] << endl; 
	}
	//sws_getContext( config.v_srcWidth, config.v_srcWidth, config.v_srcFormat, c->width, c->height, c->pix_fmt, config.v_scaling, NULL, NULL, NULL );
	
}

/* prepare a dummy image */
void FFMovieMaker::fill_yuv_image( AVFrame *pict, int frame_index, int width, int height )
{
    int x, y, i;
	
    i = frame_index;
	
	int r = frame_index%255; 
	int g = frame_index%255; 
	int b = frame_index%255; 
	
    /* Y */
    for(y=0;y<height;y++) {
        for(x=0;x<width;x++) {
			r = (frame_count+x+y*width)%255; 
			
            //pict->data[0][y * pict->linesize[0] + x] = x + y + i * 3;
            pict->data[0][y * pict->linesize[0] + x] = (0.299*r)+(0.587*g)+(0.114*b); 
        }
    }
	
    /* Cb and Cr */
    for(y=0;y<height/2;y++ ){
        for(x=0;x<width/2;x++) {
			r = (x+frame_count+y*width)%255; 
            //pict->data[1][y * pict->linesize[1] + x] = 128 + y + i * 2;
            //pict->data[2][y * pict->linesize[2] + x] = 64 + x + i * 5;
            pict->data[1][y * pict->linesize[1] + x] = 128-(0.168736*r)-(0.331264*g)+(0.5*b); 
            pict->data[2][y * pict->linesize[2] + x] = 128+(0.5*r)-(0.418688*g)-(0.081312*b); 
        }
    }
}

void FFMovieMaker::encode_video_frame(AVFormatContext *oc, AVStream *st){
    
    int out_size, ret;
    AVCodecContext *c;
    
    AVPacket pkt;
    av_init_packet(&pkt);
    
	long a = ofGetSystemTime();
    c = st->codec;
	picture_rgb->data[0] = (uint8_t*) pixels;
	sws_scale( img_convert_ctx_rgb, picture_rgb->data, picture_rgb->linesize, 0, config.v_srcHeight, picture->data, picture->linesize );
	cout << "scale: " << ( ofGetSystemTime() - a ) << " ms" << endl;
	
    if (oc->oformat->flags & AVFMT_RAWPICTURE) {
        /* raw video case. The API will change slightly in the near
		 futur for that */
		cout << "RAW VIDEO!" << endl;
		
        pkt.flags |= AV_PKT_FLAG_KEY;
        pkt.stream_index= st->index;
        pkt.data= (uint8_t *)picture;
        pkt.size= sizeof(AVPicture);
		
        ret = av_interleaved_write_frame(oc, &pkt);
    } else {
        /* encode the image */
		cout << "OUTSIZE=" << video_outbuf_size << endl;
		a = ofGetSystemTime();
        
        picture->pts = frame_count;

        out_size = avcodec_encode_video(c, video_outbuf, video_outbuf_size, picture);
		cout << "encode: " << ( ofGetSystemTime() - a ) << " ms" << endl;
		a = ofGetSystemTime();
        /* if zero size, it means the image was buffered */
        if (out_size > 0) {
            
            if (videoBuffers[currentBuffer]->getSize() == MAX_BUFFER_LEN-1) {
                if (currentBuffer == MAX_BUFFERS-1) {
                    currentBuffer = 0;
                }else{
                    currentBuffer +=1;
                }
            }
            
            videoBuffers[currentBuffer]->push((unsigned char*) video_outbuf, out_size);
            ret = 0;
            
            /* write the compressed frame in the media file */
            //ret = av_interleaved_write_frame(oc, &pkt);
        } else {
            ret = 0;
        }
		cout << "other crazy shit: " << ( ofGetSystemTime() - a ) << " ms" << endl;
		a = ofGetSystemTime();
        
    }
    if (ret != 0) {
        fprintf(stderr, "Error while writing video frame\n");
        exit(1);
    }
	
    frame_count++;
}



void FFMovieMaker::write_video_frame(AVFormatContext *oc, AVPacket pkt){
    
    /* write the compressed frame in the media file */
    if (av_interleaved_write_frame(oc, &pkt) != 0) {
        fprintf(stderr, "Error while writing video frame\n");
        //exit(1);
    }
}


void FFMovieMaker::write_video_frame(AVFormatContext *oc, AVStream *st)
{
    int out_size, ret;
    AVCodecContext *c;
	
	long a = ofGetSystemTime(); 
    c = st->codec;
	picture_rgb->data[0] = (uint8_t*) pixels; 
	sws_scale( img_convert_ctx_rgb, picture_rgb->data, picture_rgb->linesize, 0, config.v_srcHeight, picture->data, picture->linesize ); 
	cout << "scale: " << ( ofGetSystemTime() - a ) << " ms" << endl; 
	
    if (oc->oformat->flags & AVFMT_RAWPICTURE) {
        /* raw video case. The API will change slightly in the near
		 futur for that */
		cout << "RAW VIDEO!" << endl; 
        AVPacket pkt;
        av_init_packet(&pkt);
		
        pkt.flags |= AV_PKT_FLAG_KEY;
        pkt.stream_index= st->index;
        pkt.data= (uint8_t *)picture;
        pkt.size= sizeof(AVPicture);
		
        ret = av_interleaved_write_frame(oc, &pkt);
    } else {
        /* encode the image */
		cout << "OUTSIZE=" << video_outbuf_size << endl; 
		a = ofGetSystemTime();
        
        picture->pts = frame_count;
        
        out_size = avcodec_encode_video(c, video_outbuf, video_outbuf_size, picture);
		cout << "encode: " << ( ofGetSystemTime() - a ) << " ms" << endl; 
		a = ofGetSystemTime(); 
        /* if zero size, it means the image was buffered */
        if (out_size > 0) {
            AVPacket pkt;
            av_init_packet(&pkt);
			
            if (pkt.pts != AV_NOPTS_VALUE)
                pkt.pts = av_rescale_q(pkt.pts, c->time_base, st->time_base);
            if (pkt.dts != AV_NOPTS_VALUE)
                pkt.dts = av_rescale_q(pkt.dts, c->time_base, st->time_base);
            
            if (c->coded_frame->pts != AV_NOPTS_VALUE)
                pkt.pts= av_rescale_q(c->coded_frame->pts, c->time_base, st->time_base);
			         
            if(c->coded_frame->key_frame)
                pkt.flags |= AV_PKT_FLAG_KEY;
            pkt.stream_index= st->index;
            pkt.data= video_outbuf;
            pkt.size= out_size;
			
            /* write the compressed frame in the media file */
            ret = av_interleaved_write_frame(oc, &pkt);
        } else {
            ret = 0;
        }
		cout << "other crazy shit: " << ( ofGetSystemTime() - a ) << " ms" << endl; 
		a = ofGetSystemTime(); 

    }
    if (ret != 0) {
        fprintf(stderr, "Error while writing video frame\n");
        //exit(1);
    }
	
    frame_count++;
}

void FFMovieMaker::close_video(AVFormatContext *oc, AVStream *st)
{
    avcodec_close(st->codec);
    av_free(picture->data[0]);
    av_free(picture);
    av_free(video_outbuf);
}




/**************************************************************/
/* audio output */

/*
 * add an audio output stream
 */
AVStream * FFMovieMaker::add_audio_stream(AVFormatContext *oc, enum AVCodecID codec_id)
{
    AVCodecContext *c;
    AVStream *st;
	
    st = avformat_new_stream(oc, NULL);
    if (!st) {
        fprintf(stderr, "Could not alloc stream\n");
        exit(1);
    }
	   
    c = st->codec;
    c->codec_id = codec_id;
    c->codec_type = AVMEDIA_TYPE_AUDIO;
	
    /* put sample parameters */
    c->sample_fmt = AV_SAMPLE_FMT_FLTP; //AV_SAMPLE_FMT_S16;
    c->bit_rate = config.a_destBitRate;
    c->sample_rate = config.a_destSampleRate;
    c->channels = 2;
    c->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
	
    // some formats want stream headers to be separate
    if(oc->oformat->flags & AVFMT_GLOBALHEADER)
        c->flags |= CODEC_FLAG_GLOBAL_HEADER;
	
    return st;
}

void FFMovieMaker::open_audio(AVFormatContext *oc, AVStream *st)
{
    AVCodecContext *c;
    AVCodec *codec;
	
    c = st->codec;
	
    /* find the audio encoder */
    codec = avcodec_find_encoder(c->codec_id);
    if (!codec) {
        fprintf(stderr, "codec not found\n");
        exit(1);
    }
	
    /* open it */
    if (avcodec_open2(c, codec, NULL) < 0) {
        fprintf(stderr, "could not open codec\n");
        exit(1);
    }
	
    /* init signal generator */
    t = 0;
    tincr = 2 * M_PI * 110.0 / c->sample_rate;
    /* increment frequency by 110 Hz per second */
    tincr2 = 2 * M_PI * 110.0 / c->sample_rate / c->sample_rate;
	
    audio_outbuf_size = 10000;
    audio_outbuf = (uint8_t*) av_malloc(audio_outbuf_size);
	
    /* ugly hack for PCM codecs (will be removed ASAP with new PCM
	 support to compute the input frame size in samples */
    if (c->frame_size <= 1) {
        audio_input_frame_size = audio_outbuf_size / c->channels;
        switch(st->codec->codec_id) {
			case CODEC_ID_PCM_S16LE:
			case CODEC_ID_PCM_S16BE:
			case CODEC_ID_PCM_U16LE:
			case CODEC_ID_PCM_U16BE:
				audio_input_frame_size >>= 1;
				break;
			default:
				break;
        }
    } else {
        audio_input_frame_size = c->frame_size;
    }
    samples = (int16_t*) av_malloc(audio_input_frame_size * 2 * c->channels);
	cout << "CHANNELS===" << c->channels << endl; 
	cout << "A-FRAME_SIZE===" << audio_input_frame_size << endl; 
}

/* prepare a 16 bit dummy audio frame of 'frame_size' samples and
 'nb_channels' channels */
void FFMovieMaker::get_audio_frame(int16_t *samples, int frame_size, int nb_channels)
{
    int j, i, v;
    int16_t *q;
    q = samples;
    for(j=0;j<frame_size;j++) {
        v = (int)(sin(t) * 10000);
        for(i = 0; i < nb_channels; i++)
            *q++ = v;
        t += tincr;
        tincr += tincr2;
    }
}

void FFMovieMaker::encode_audio_frame(AVFormatContext *oc, AVStream *st)
{
    AVCodecContext *c;
    AVPacket pkt;
    av_init_packet(&pkt);
	
    c = st->codec;
	
    //get_audio_frame(samples, audio_input_frame_size, c->channels);
	
    pkt.size= avcodec_encode_audio(c, audio_outbuf, audio_outbuf_size, samples);
	
    if (c->coded_frame && c->coded_frame->pts != AV_NOPTS_VALUE)
        pkt.pts= av_rescale_q(c->coded_frame->pts, c->time_base, st->time_base);
    pkt.flags |= AV_PKT_FLAG_KEY;
    pkt.stream_index= st->index;
    pkt.data= audio_outbuf;
    
    if (audioBuffers[currentBuffer]->getSize() == MAX_BUFFER_LEN) {
        if (currentBuffer == MAX_BUFFERS-1) {
            currentBuffer = 0;
        }else{
            currentBuffer +=1;
        }
    }
    
    audioBuffers[currentBuffer]->push((unsigned char*) &pkt, sizeof(pkt));
}

void FFMovieMaker::write_audio_frame(AVFormatContext *oc, AVPacket pkt){
    
    /* write the compressed frame in the media file */
    if (av_interleaved_write_frame(oc, &pkt) != 0) {
        fprintf(stderr, "Error while writing audio frame\n");
        exit(1);
    }
}


void FFMovieMaker::write_audio_frame(AVFormatContext *oc, AVStream *st)
{
    AVCodecContext *c;
    AVPacket pkt;
    av_init_packet(&pkt);
	
    c = st->codec;
	
    //get_audio_frame(samples, audio_input_frame_size, c->channels);
	
    pkt.size= avcodec_encode_audio(c, audio_outbuf, audio_outbuf_size, samples);
	
    if (c->coded_frame && c->coded_frame->pts != AV_NOPTS_VALUE)
        pkt.pts= av_rescale_q(c->coded_frame->pts, c->time_base, st->time_base);
    pkt.flags |= AV_PKT_FLAG_KEY;
    pkt.stream_index= st->index;
    pkt.data= audio_outbuf;
	
    /* write the compressed frame in the media file */
    if (av_interleaved_write_frame(oc, &pkt) != 0) {
        fprintf(stderr, "Error while writing audio frame\n");
        exit(1);
    }
}

void FFMovieMaker::close_audio(AVFormatContext *oc, AVStream *st)
{
    avcodec_close(st->codec);
	
    av_free(samples);
    av_free(audio_outbuf);
}

