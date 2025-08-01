#!/usr/bin/env ruby

localdb = "sp"
# database name from which homologues are collected
# by locally installed blast. Leave this if you do
# not use the '-l' option.

mafftpath = "/home/patrick_bioinf/pipeline_test/conda/env-5ca2d9ea20a5d66997b910386eefd121/bin/mafft"   
# path of mafft. "/usr/local/bin/mafft"
# if mafft is in your command path, "mafft" is ok.

blastpath = "psiblast"
# path of blastall.
# if blastall is in your command path, "blastall" is ok.

# mafft-homologs.rb  v. 2.1 aligns sequences together with homologues
# automatically collected from SwissProt via NCBI BLAST.
#
# mafft > 5.58 is required
#
# Usage:
#   mafft-homologs.rb [options] input > output
# Options:
#   -a #      the number of collected sequences (default: 50)
#   -e #      threshold value (default: 1e-10)
#   -o "xxx"  options for mafft
#             (default: " --op 1.53 --ep 0.123 --maxiterate 1000")
#   -l        locally carries out blast searches instead of NCBI blast
#             (requires locally installed blast and a database)
#   -f        outputs collected homologues also (default: off)
#   -w        entire sequences are subjected to BLAST search
#             (default: well-aligned region only)

#require 'getopts'
require 'optparse'
require 'tempfile'

if ENV["MAFFT_BLAST"] && ENV["MAFFT_BLAST"] != "" then
	blastpath = ENV["MAFFT_BLAST"]
end

if ENV["MAFFT_HOMOLOGS_MAFFT"] && ENV["MAFFT_HOMOLOGS_MAFFT"] != "" then
	mafftpath = ENV["MAFFT_HOMOLOGS_MAFFT"]
end

# mktemp
GC.disable
temp_vf = Tempfile.new("_vf").path
temp_if = Tempfile.new("_if").path
temp_pf = Tempfile.new("_pf").path
temp_af = Tempfile.new("_af").path
temp_qf = Tempfile.new("_qf").path
temp_bf = Tempfile.new("_bf").path
temp_rid = Tempfile.new("_rid").path
temp_res = Tempfile.new("_res").path


system( mafftpath + " --help > #{temp_vf} 2>&1" )
pfp = File.open( "#{temp_vf}", 'r' )
while pfp.gets
	break if $_ =~ /MAFFT v/
end
pfp.close

if( $_ ) then
	mafftversion = $_.sub( /^\D*/, "" ).split(" ").slice(0).strip.to_s
else
	mafftversion = "0"
end
if( mafftversion < "5.58" ) then
	STDERR.puts ""
	STDERR.puts "======================================================"
	STDERR.puts "Install new mafft (v. >= 5.58)"
	STDERR.puts "======================================================"
	STDERR.puts ""
	exit
end

srand ( 0 )

def readfasta( fp, name, seq )
	nseq = 0
	tmpseq = ""
	while fp.gets
		if $_ =~ /^>/ then
			name.push( $_.sub(/>/,"").strip )
			seq.push( tmpseq ) if nseq > 0
			nseq += 1
			tmpseq = ""
		else
			tmpseq += $_.strip
		end
	end
	seq.push( tmpseq )
	return nseq
end

nadd = 600
num_alignments = 600
num_threads_blast = 4
eval = 1e-1
local = 0
fullout = 0
entiresearch = 1
corewin = 50
corethr = 0.3
#mafftopt = " --op 1.53 --ep 0.123 --localpair --maxiterate 1000 --reorder "
mafftopt = " --op 1.53 --ep 0.0 --globalpair --maxiterate 1000 --reorder "


#if getopts( "s", "f", "w", "l", "h", "e:", "a:", "o:", "c:", "d:" ) == nil ||  ARGV.length == 0 || $OPT_h then
#	puts "Usage: #{$0} [-h -l -e# -a# -o\"[options for mafft]\"] input_file"
#	exit
#end
params = ARGV.getopts( "sfwlhe:a:o:c:d:n:N:" )


#if $OPT_c then
if params["c"] != nil then
	corewin = params["c"].to_i
end

#if $OPT_d then
#if params["d"] != nil then
#	corethr = params["d"].to_f
#end
#
if params["d"] != nil then
	localdb = params["d"].to_s
end

if params["n"] != nil then
	num_alignments = params["n"].to_s
end

if params["N"] != nil then
	num_threads_blast = params["N"].to_s
end

#if $OPT_w
if params["w"] == true then
	entiresearch = 1
end

#if $OPT_f
if params["f"] == true then
	fullout = 1
end

#if $OPT_s
if params["s"] == true then
	fullout = 0
end

#if $OPT_l
if params["l"] == true then
	local = 1
end

#if $OPT_e then
if params["e"] != nil then
#	eval = $OPT_e.to_f
	eval = params["e"].to_f
end

#if $OPT_a then
if params["a"] != nil then
	nadd = params["a"].to_i
end

#if $OPT_o then
if params["o"] != nil then
	mafftopt += " " + params["o"] + " "
end

infn = ARGV[0].to_s.strip

system "cat " + infn + " > #{temp_if}"
ar = mafftopt.split(" ")
nar = ar.length
for i in 0..(nar-1)
	if ar[i] == "--seed" then
		system "cat #{ar[i+1]} >> #{temp_if}"
	end
end

if fullout == 0 then
	mafftopt += " --excludehomologs "
end

nseq = 0
ifp = File.open( "#{temp_if}", 'r' )
	while ifp.gets
		nseq += 1 if $_ =~ /^>/
	end
ifp.close

if nseq >= 10000 then
	STDERR.puts "The number of input sequences must be <10000."
	exit
elsif nseq == 1 then
	system( "cp #{temp_if}"  + " #{temp_pf}" )
else
	STDERR.puts "Performing preliminary alignment .. "
	if entiresearch == 1 then
#		system( mafftpath + " --maxiterate 1000 --localpair #{temp_if} > #{temp_pf}" )
		system( mafftpath + " --maxiterate 0 --retree 2 #{temp_if} > #{temp_pf}" )
	else
		system( mafftpath + " --maxiterate 1000 --localpair --core --coreext --corethr #{corethr.to_s} --corewin #{corewin.to_s} #{temp_if} > #{temp_pf}" )
	end
end

pfp = File.open( "#{temp_pf}", 'r' )
inname = []
inseq = []
slen = []
act = []
nin = 0
nin = readfasta( pfp, inname, inseq )
for i in 0..(nin-1)
	slen.push( inseq[i].gsub(/-/,"").length )
	act.push( 1 )
end
pfp.close

pfp = File.open( "#{temp_if}", 'r' )
orname = []
orseq = []
nin = 0
nin = readfasta( pfp, orname, orseq )
pfp.close

allen = inseq[0].length
for i in 0..(nin-2)
	for j in (i+1)..(nin-1)
		next if act[i] == 0
		next if act[j] == 0
		pid = 0.0
		total = 0
		for a in 0..(allen-1)
			next if inseq[i][a,1] == "-" || inseq[j][a,1] == "-"
			total += 1
			pid += 1.0 if inseq[i][a,1] == inseq[j][a,1]
		end
		pid /= total
#		puts "#{i.to_s}, #{j.to_s}, #{pid.to_s}"
		if pid > 0.5 then
			if slen[i] < slen[j]
				act[i] = 0
			else
				act[j] = 0
			end
		end
	end
end
#p act


afp = File.open( "#{temp_af}", 'w' )

STDERR.puts "Searching .. \n"
ids = []
add = []
sco = []
nblast = 0 # ato de tsukau kamo
for i in 0..(nin-1)
	singleids = []
	singleadd = []

	inseq[i].gsub!(/-/,"")
	afp.puts ">" + orname[i]
	afp.puts orseq[i]

#	afp.puts ">" + inname[i]
#	afp.puts inseq[i]

	STDERR.puts "Query (#{i+1}/#{nin})\n" + inname[i]
	if act[i] == 0 then
		STDERR.puts "Skip.\n\n"
		next
	end

	if local == 0 then
		command = "lynx -source 'https://www.ncbi.nlm.nih.gov/blast/Blast.cgi?QUERY=" + inseq[i] + "&DATABASE=swissprot&HITLIST_SIZE=" + nadd.to_s + "&FILTER=L&EXPECT='" + eval.to_s + "'&FORMAT_TYPE=TEXT&PROGRAM=blastp&SERVICE=plain&NCBI_GI=on&PAGE=Proteins&CMD=Put' > #{temp_rid}"
		system command

		ridp = File.open( "#{temp_rid}", 'r' )
		while ridp.gets
			break if $_ =~ / RID = (.*)/
		end
		ridp.close
		rid = $1.strip
		STDERR.puts "Submitted to NCBI. rid = " + rid

		STDERR.printf "Waiting "
		while 1
			STDERR.printf "."
			sleep 10
			command = "lynx -source 'https://www.ncbi.nlm.nih.gov/blast/Blast.cgi?RID=" + rid + "&DESCRIPTIONS=500&ALIGNMENTS=" + nadd.to_s + "&ALIGNMENT_TYPE=Pairwise&OVERVIEW=no&CMD=Get&FORMAT_TYPE=XML' > #{temp_res}"
			system command
			resp = File.open( "#{temp_res}", 'r' )
#			resp.gets
#			if $_ =~ /WAITING/ then
#				resp.close
#				next
#			end
			while( resp.gets )
				break if $_ =~ /QBlastInfoBegin/
			end
			resp.gets
			if $_ =~ /WAITING/ then
				resp.close
				next
			else
				resp.close
				break
			end
		end
	else
#		puts "Not supported"
#		exit
		qfp = File.open( "#{temp_qf}", 'w' )
			qfp.puts "> "
			qfp.puts inseq[i]
		qfp.close
		command = blastpath + " -num_iterations 2 -num_threads #{num_threads_blast} -evalue  #{eval} -num_alignments #{num_alignments} -outfmt 5 -query #{temp_qf} -db #{localdb} > #{temp_res}"
		system command
#		system "cp #{temp_res} _res"
	end
	STDERR.puts " Done.\n\n"

	resp = File.open( "#{temp_res}", 'r' )
	hitnum = 0
	lasteval = "nohit"

	while resp.gets
		break if $_ =~ /<Iteration_iter-num>2<\/Iteration_iter-num>/
	end

	if $_ == nil then
		STDERR.puts "no hit"
	else
		while 1
			while resp.gets
				break if $_ =~ /<Hit_id>(.*)<\/Hit_id>/ || $_ =~ /(<Iteration_stat>)/
			end
			id = $1
			break if $_ =~ /<Iteration_stat>/
	#		p id

			starthit = 9999999
			endhit = -1
			startquery = 9999999
			endquery = -1
			target = ""
			score = 0.0

			while line = resp.gets
				if line =~ /<Hsp_hit-from>(.*)<\/Hsp_hit-from>/
					starthitcand=$1.to_i
				elsif line =~ /<Hsp_hit-to>(.*)<\/Hsp_hit-to>/
					endhitcand=$1.to_i
				elsif line =~ /<Hsp_query-from>(.*)<\/Hsp_query-from>/
					startquerycand=$1.to_i
				elsif line =~ /<Hsp_query-to>(.*)<\/Hsp_query-to>/
					endquerycand=$1.to_i
				elsif $_ =~ /<Hsp_hseq>(.*)<\/Hsp_hseq>/
					targetcand = $1.sub( /-/, "" ).sub( /U/, "X" )
				elsif line =~ /<Hsp_bit-score>(.*)<\/Hsp_bit-score>/
					scorecand=$1.to_f
				elsif line =~ /<Hsp_evalue>(.*)<\/Hsp_evalue>/
					evalcand=$1.to_s
				elsif line =~ /<\/Hsp>/
					if endhit == -1 then
						starthit = starthitcand
						endhit= endhitcand
						startquery = startquerycand
						endquery= endquerycand
						target = targetcand
						score = scorecand
						lasteval = evalcand
					else
	#					if endhit <=   endhitcand && endquery <=   endquerycand  then
						if endhit <= starthitcand && endquery <= startquerycand  then
							endhit = endhitcand
							endquery = endquerycand
							target = target + "XX" + targetcand
							score = score + scorecand
						end
	#					if starthitcand <= starthit && startquerycand <= startquery  then
						if   endhitcand <= starthit &&   endquerycand <= startquery  then
							starthit = starthitcand
							startquery = startquerycand
							target = targetcand + "XX" + target
							score = score + scorecand
						end
					end
				elsif line =~ /<\/Hit>/
					hitnum = hitnum + 1
					break;
				end
			end

			singleids.push( id )
			singleadd.push( target )

			known = ids.index( id )
			if known != nil then
				if sco[known] >= score then
					next
				else
					ids.delete_at( known )
					add.delete_at( known )
					sco.delete_at( known )
				end
			end
			ids.push( id )
			sco.push( score )
			add.push( target )

		end
		resp.close
	end

	n = singleids.length
	outnum = 0

	totalprob = 0
	prob = []
	for m in 0..(n-1)
#		prob[m] = 1.0 / population[eclass[m]]
		prob[m] = 1.0
		totalprob += prob[m]
	end
#	puts ""
	for m in 0..(n-1)
		prob[m] /= (totalprob)
		prob[m] *= (nadd.to_f / nin.to_f)
		prob[m] = 1 if prob[m] > 1
	end


	for m in 0..(n-1)
		if rand( 1000000 ).to_f/1000000 < prob[m] then
#			STDERR.puts "hit in " + m.to_s
			afp.puts ">_addedbymaffte_" + singleids[m]
			afp.puts singleadd[m]
		end
	end
end
afp.close

STDERR.puts "Aligning .. "
system( mafftpath + mafftopt + "#{temp_af} > #{temp_bf}" )
STDERR.puts "done."

bfp = File.open( "#{temp_bf}", 'r' )
outseq = []
outnam = []
readfasta( bfp, outnam, outseq )
bfp.close

outseq2 = []
outnam2 = []

len = outseq.length
for i in 0..(len-1)
#	p outnam[i]
	if fullout == 0 && outnam[i] =~ /_addedbymaffte_/ then
		next
	end
	outseq2.push( outseq[i] )
	outnam2.push( outnam[i].sub( /_addedbymaffte_/, "_ho_" ) )
end

nout = outseq2.length
len = outseq[0].length
p = len
while p>0
	p -= 1
    allgap = 1
    for j in 0..(nout-1)
		if outseq2[j][p,1] != "-" then
			allgap = 0
			break
		end
    end
    if allgap == 1 then
        for j in 0..(nout-1)
            outseq2[j][p,1] = ""
        end
    end
end
for i in 0..(nout-1)
	puts ">" + outnam2[i]
	puts outseq2[i].gsub( /.{1,60}/, "\\0\n" )
end


system( "rm -rf #{temp_if} #{temp_vf} #{temp_af} #{temp_bf} #{temp_pf} #{temp_qf} #{temp_res} #{temp_rid}" )
#system( "cp #{temp_if} #{temp_vf} #{temp_af} #{temp_bf} #{temp_pf} #{temp_qf} #{temp_res} #{temp_rid} ." )
if File.exist?( "#{temp_af}.tree" ) then
	system( "sed 's/_addedbymaffte_/_ho_/'  #{temp_af}.tree > #{ARGV[0].to_s}.tree" )
	system( "rm #{temp_af}.tree" )
end
