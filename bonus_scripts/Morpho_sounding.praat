#Michel Belykm
#UCL, 2020
#OSX 10.15.1, praat v6.1.06
#CC-BY-4
#ADD segment time stamp
#WHy is there white space in my outputs?


#helper script for Morpho_*.m vocal tract tracking series if you have fairly clean in-scanner audio recordings
#This script maybe be useful in making to logfile that morpho uses to identify useful frames for analysis
#Automatically identifies sounding vs silent periods (NB. keep sounding periods >50ms or pitch measures fail)
#Silent intervals are omitted from further analysis, all others are noted in logfile
#finds the frame numbers for those boundaries (NB. makes strong assumptions that the audio is aligned to the start of the scan)
#Feel free to rename sounding intervals to any notation that us useful to your project

#in_dir: relative filepath to sound files
#out_dir: relative filepath to save directory
#format: file extension marking files to analyse. Use * for all.
#fps: sampling rate of the rtMRI data, frames per second
#label_to_analyse: the label you will give to textgrid intervals that should be analysed

#outputs a single long .csv file with the information and column headings required by morpho_subsetter.m
#also some standard acoustical measurements at each interval in case they are wanted
#will still need to be reorganised into a multisheet excel file
#the SEGMENT_LABEL column is filler, you can edit the output to something useful later if you'd like

#################
####query user###
#################
form Open all files in directory
	sentence in_dir ../vtMRI_audio_clean/
	sentence out_dir ../logs/
	positive fps 8
  	sentence format .wav
	sentence delimiter ,
	sentence missing NA
	sentence log_extension .csv
	real silence_threshold -25.0
	positive min_silent_period 0.05
	positive min_sounding_period 0.05
	positive minimum_f0 80
	positive maximum_f0 900
	#sentence label_to_analyse sounding
	sentence label_to_skip silent

endform

################
####import files###
################
#Get list of files

Create Strings as file list... list 'in_dir$'*'format$'
numberOfFiles = Get number of strings

#open all the files
for ifile to numberOfFiles
	filename$ = Get string... ifile
	Read from file... 'in_dir$''filename$'
	select Strings list
endfor

pause Are these the droids you were looking for?

select all
n = numberOfSelected ("Sound")
for i to n
	sound'i' = selected ("Sound", i)
endfor

#########################
###Loop Through Sounds###
#########################
#clear the info window

for i to n
	#get working sound file
	select Strings list
	filename$ = Get string... i
	filename_len = length(filename$)
	#remove file extension
	filename_new$ = left$(filename$, filename_len-4) 
	
	#easy to manage filename for the active sound file. inherited by derived objects
	select sound'i'
	Rename... working


	##########################
	###Print logfile header###
	##########################
	clearinfo
	print sound_name'delimiter$' SEGMENT_NUMBER 'delimiter$' SEGMENT_LABEL 'delimiter$'ONSET 'delimiter$' OFFSET 'delimiter$'
	print Intensity 'delimiter$' Duration 'delimiter$'
	print f0_mean 'delimiter$' f0_SD 'delimiter$'  f0_min  'delimiter$' f0_max 'delimiter$'
	print F1 'delimiter$' F2 'delimiter$' F3 'delimiter$'
	print 'newline$'

	################################
	###Identify Sounding Segments###
	################################

	#automatic syllable detection
	select Sound working
	To Intensity: 75, 0, "yes"
	To TextGrid (silences): -25, min_silent_period, min_sounding_period, "silent", "sounding"
	
	#user oversight
	plus Sound working
	Edit
	editor TextGrid working

	beginPause: "Add or delete texgrid intervals as needed."
		comment: "Click continue when done"
	endPause: "continue", 1

	#close the editor
	Close
 	endeditor

	###take global measurements
	select TextGrid working
	count_intervals = Get number of intervals: 1
	#count_sounding = Count intervals where: 1, "contains", "sounding"
	count_silent = Count intervals where: 1, "contains", "silent"
	count_sounding = count_intervals - count_silent

	#loop intervals
	segment=0
	for interval to count_intervals

		#identify interval
		select TextGrid working
		this_label$ = Get label of interval: 1, interval

		#only bother with sounding intervals
		#if this_label$ == label_to_analyse$
		if not this_label$ == label_to_skip$
			#keep a count of the number of times we trigger this sequence
		    segment = segment+1 

			#get interval timing
			start_time = Get start time of interval: 1, interval
			end_time = Get end time of interval: 1, interval
			duration = end_time - start_time
			midpoint = start_time + duration/2 

			#convert start time to frame number
			onset_frame = start_time * fps
			onset_frame = round(onset_frame)
			#in same cases could roudn to frame zero which is silly
			if onset_frame <1
				onset_frame = 1
			endif

			#convert end time to frame number
			offset_frame = end_time * fps
			offset_frame = round(offset_frame)

			###Measure some acoustics while we're here###
			#extract sound part
			select Sound working
			Extract part: start_time, end_time, "rectangular", 1, "yes"

			intensity = Get intensity (dB)

			#pitch and formant measurements for sufficiently long segments
			if duration > min_sounding_period
				To Pitch: 0, minimum_f0, maximum_f0
				f0_mean = Get mean: 0, 0, "Hertz"
				f0_SD = Get standard deviation: 0, 0, "Hertz"
				f0_min = Get minimum: 0, 0, "Hertz", "Parabolic"
				f0_max = Get maximum: 0, 0, "Hertz", "Parabolic"
				Remove

				select Sound working_part
				To Formant (keep all): 0, 5, 5500, 0.025, 50
				f1 = Get value at time: 1, midpoint, "hertz", "Linear"
				f2 = Get value at time: 2, midpoint, "hertz", "Linear"
				f3 = Get value at time: 3, midpoint, "hertz", "Linear"
				Remove
			endif

			#print to info window
			print 'filename$' 'delimiter$' 'segment' 'delimiter$' 'this_label$' 'delimiter$' 'onset_frame' 'delimiter$' 'offset_frame' 'delimiter$'
			print 'intensity:3' 'delimiter$' 'duration:3' 'delimiter$'
			
			if duration > min_sounding_period
				print 'f0_mean:3' 'delimiter$' 'f0_SD:3' 'delimiter$' 'f0_min:3' 'delimiter$' 'f0_max:3' 'delimiter$'
				print 'f1' 'delimiter$' 'f2' 'delimiter$' 'f3' 'delimiter$'
			else
				print 'missing$' 'delimiter$' 'missing$' 'delimiter$' 'missing$' 'delimiter$' 'missing$' 'delimiter$'
				print 'missing$' 'delimiter$' 'missing$' 'delimiter$' 'missing$' 'delimiter$'
			endif
			print 'newline$'
	
			#save output
			logfile_out$ = out_dir$ + filename_new$ + log_extension$
			fappendinfo 'logfile_out$'
			clearinfo
			
			#end of interval clean-up
			select Sound working_part
			Remove
		endif

	#end interval for
	endfor

	#end of file clean-up
	select Sound working
	plus Intensity working
	plus TextGrid working

	Remove

#end soundfile for
endfor

#final cleanup
select Strings list
Remove