#! /usr/bin/env ruby
require 'optparse'

mafftpath = "/home/patrick_bioinf/pipeline_test/conda/env-5ca2d9ea20a5d66997b910386eefd121/bin/mafft"

def cleartempfiles( filenames )
	for f in filenames
		system( "rm -rf #{f}" )
	end
end


seed = 0
scand = "50%"
npick = 500
infn = ""
reorderoption = "--reorder"
pickoptions = " --retree 1 "
coreoptions = " --globalpair --maxiterate 100 "
corelastarg = " "
addoptions = " "
directionoptions = " --retree 0 --pileup "
markcore = ""
randompickup = true
outnum = false

begin
	params = ARGV.getopts('m:s:n:p:i:C:L:A:o:MhuD:')
rescue => e
    STDERR.puts e
	STDERR.puts "See #{$0} -h"
    exit 1
end

#p params

mafftpath = params["m"]         if params["m"]
seed = params["s"].to_i         if params["s"]
scand = params["n"].to_s        if params["n"]
npick = params["p"].to_i        if params["p"]
infn = params["i"]              if params["i"]
#pickoptions += params["P"]     if params["P"]
coreoptions += params["C"]      if params["C"] # tsuikagaki!
corelastarg += params["L"]      if params["L"] # tsuikagaki!
addoptions  += params["A"]      if params["A"]
directionoptions += params["D"] if params["D"] # tsuikagaki
markcore = "*"                  if params["M"]
#randompickup = false           if params["S"]
reorderoption = ""              if params["o"] =~ /^i/
outnum = true                   if params["u"]

if params["h"] then
	STDERR.puts "Usage: #{$0} -i inputfile [options]"
	STDERR.puts "Options:"
	STDERR.puts "   -i string     Input file."
	STDERR.puts "   -m string     Mafft command.  Default: mafft"
	STDERR.puts "   -s int        Seed.  Default:0"
	STDERR.puts "   -n int        Number of candidates for core sequences.  Default: upper 50% in length"
	STDERR.puts "   -p int        Number of core sequences.  Default: 500"
#	STDERR.puts "   -P \"string\"   Mafft options for the PICKUP stage."
#	STDERR.puts "                 Default: \"--retree 1\""
#	STDERR.puts "   -S            Tree-based pickup.  Default: off"
	STDERR.puts "   -C \"string\"   Mafft options for the CORE stage."
	STDERR.puts "                 Default: \"--globalpair --maxiterate 100\""
	STDERR.puts "   -A \"string\"   Mafft options for the ADD stage."
	STDERR.puts "                 Default: \"\""
	STDERR.puts "   -D \"string\"   Mafft options for inferring the direction of nucleotide sequences."
	STDERR.puts "                 Default: \"\""
	STDERR.puts "   -o r or i     r: Reorder the sequences based on similarity.  Default"
	STDERR.puts "                 i: Same as input."
	exit 1
end

if infn == "" then
	STDERR.puts "Give input file with -i."
	exit 1
end



pid = $$.to_s
tmpdir = ENV["TMPDIR"]
tmpdir = "/tmp" if tmpdir == nil
tempfiles = []
tempfiles.push( temp_pf = tmpdir + "/_pf" + pid )
tempfiles.push( temp_nf = tmpdir + "/_nf" + pid )
tempfiles.push( temp_cf = tmpdir + "/_cf" + pid )
tempfiles.push( temp_of = tmpdir + "/_of" + pid )

Signal.trap(:INT){cleartempfiles( tempfiles ); exit 1}
at_exit{ cleartempfiles( tempfiles )}

system "#{mafftpath} --version > #{temp_of} 2>&1"

fp = File.open( temp_of, "r" )
	line = fp.gets
fp.close


versionnum = line.split(' ')[0].sub(/v/,"").to_f

if versionnum < 7.210 then
	STDERR.puts "\n"
	STDERR.puts "Please use mafft version >= 7.210\n"
	STDERR.puts "\n"
	exit
end

srand( seed )

def readfasta( fp, name, seq )
        nseq = 0
        tmpseq = ""
        while fp.gets
                if $_ =~ /^>/ then
                        name.push( $_.sub(/>/,"").chop )
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



begin
	infp = File.open( infn, "r" )
rescue => e
    STDERR.puts e
    exit 1
end
infp.close

if directionoptions =~ /--adjustdirection/ then
	system( mafftpath + "#{directionoptions} #{infn} > #{temp_of}" )
else
	system( "cp #{infn} #{temp_of}" )
end

tname = []
tseq = []
infp = File.open( temp_of, "r" )
tin = readfasta( infp, tname, tseq )
infp.close
lenhash = {}

if outnum then
	for i in 1..(tin)
		tname[i-1] = "_numo_s_0#{i}_numo_e_" + tname[i-1]
	end
end

npick = 0 if npick == 1
npick = tin if npick > tin


if scand =~ /%$/ then
	ncand = (tin * scand.to_f * 0.01 ).to_i
else
	ncand = scand.to_i
end

if ncand < 0 || ncand > tin then
	STDERR.puts "Error.  -n #{scand}?"
	exit 1
end

ncand = npick if ncand < npick
ncand = tin if ncand > tin

STDERR.puts "ncand = #{ncand}, npick = #{npick}"


sai = []
for i in 0..(tin-1)
	lenhash[i] = tseq[i].gsub(/-/,"").length
end

i = 0
sorted = lenhash.sort_by{|key, value| [-value, i+=1]}
#for i in 0..(ncand-1)
#	sai[sorted[i][0]] = 1
#end
#for i in ncand..(tin-1)
#	sai[sorted[i][0]] = 0
#end

ncandres = 0
ntsukau = 0
for i in 0..(tin-1)
	cand = sorted[i][0]
	if tname[cand] =~ /^_focus_/ then
		sai[cand] = 0
		ntsukau += 1
	elsif ncandres < ncand  then
		unless  tname[cand] =~ /^_tsukawanai_/ then
			sai[cand] = 1
			ncandres += 1
		else
			sai[cand] = 0
		end
	else
		sai[cand] = 0
	end
end

if ncandres+ntsukau < npick
	STDERR.puts "ncandres = #{ncandres}"
	STDERR.puts "ncand = #{ncand}"
	STDERR.puts "ntsukau = #{ntsukau}"
	STDERR.puts "npick = #{npick}"
	STDERR.puts "Too many _tsukawanai_ sequences."
	exit 1
end

if ntsukau > npick
	STDERR.puts "ntsukau = #{ntsukau}"
	STDERR.puts "npick = #{npick}"
	STDERR.puts "Too many _focus_ sequences."
	exit 1
end

#p sai
#for i in 0..(tin-1)
#	puts sai[i].to_s + " " + tname[i]
#end

npickrand = npick - ntsukau

if randompickup
	pick = []
	for i in 0..(npickrand-1)
		pick[i] = 1
	end
	for i in npickrand..(ncandres-1)
		pick[i] = 0
	end
	pick2 = pick.sort_by{rand}
	pick = pick2
#	p pick
#	p sai

	ipick = 0
	for i in 0..(tin-1)
		if sai[i] == 1 then
			if pick[ipick] == 0 then
				sai[i] = 0
			end
			ipick += 1
		end
	end
#	p sai

	for i in 0..(tin-1)
		if tname[i] =~ /^_focus_/ then
			sai[i] = 1
		end
	end
#	p sai

	pfp = File.open( temp_pf, 'w' )
	nfp = File.open( temp_nf, 'w' )

	i = 0
	while i < tin
		if sai[i] == 1 then
			pfp.puts ">" + i.to_s + " " + ">" + markcore + tname[i]
			pfp.puts tseq[i]
		else
			nfp.puts ">" + i.to_s + " " + ">" + tname[i]
			nfp.puts tseq[i]
		end
		i += 1
	end

	nfp.close
	pfp.close

else   # yamerukamo
	STDERR.puts "Not supported in this version"
	exit 1
end

if npick > 1 then
	if npick < tin then
		system( mafftpath + " #{coreoptions} #{temp_pf} #{corelastarg} > #{temp_cf}" ) # add de sort
	else
		system( mafftpath + " #{coreoptions} #{reorderoption} #{temp_pf} #{corelastarg} > #{temp_cf}" ) # ima sort
	end
	res = ( File::stat(temp_cf).size == 0 ) 
else
	system( "cat /dev/null > #{temp_cf}" )
	res = false
end

if res == true then
	STDERR.puts "\n\nError in the core alignment stage.\n\n"
	exit 1
end


if npick < tin 
	system( mafftpath + " #{addoptions} #{reorderoption} --add #{temp_nf} #{temp_cf} > #{temp_of}" )
	res = ( File::stat(temp_of).size == 0 )
else
	system( "cp #{temp_cf} #{temp_of}" )
	res = false
end

if res == true then
	STDERR.puts "\n\nError in the add stage.\n\n"
	exit 1
end

resname = []
resseq = []
resfp = File.open( temp_of, "r" )
nres = readfasta( resfp, resname, resseq )
resfp.close

if reorderoption =~ /--reorder/ then
	for i in 0..(nres-1)
		puts ">" + resname[i].sub(/^[0-9]* >/,"")
		puts resseq[i]
	end
else
	seqhash = {}
	namehash = {}
	seqlast = []
	namelast = []
	nlast = 0
	for i in 0..(nres-1)
		if resname[i] =~ /^[0-9]* >/
			key = resname[i].split(' ')[0]
			seqhash[key] = resseq[i]
			namehash[key] = resname[i]
		else
			seqlast.push( resseq[i] )
			namelast.push( resname[i] )
			nlast += 1
		end
	end
	for i in 0..(nlast-1)
		puts ">" + namelast[i]
		puts seqlast[i]
	end
	for i in 0..(nres-nlast-1)
		key = i.to_s
		puts ">" + namehash[key].sub(/^[0-9]* >/,"")
		puts seqhash[key]
	end
end


